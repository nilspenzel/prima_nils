import csv
import json
import random
import socket
import sys
import time
import math
import psycopg2
from urllib.parse import urlparse

def parse_env_file(file_path='.env'):
    env_vars = {}
    try:
        with open(file_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split('=', 1)
                    if len(parts) == 2:
                        key = parts[0].strip()
                        value = parts[1].strip().strip('"\'')
                        env_vars[key] = value
        return env_vars
    except FileNotFoundError:
        print(f"Error: .env file not found at {file_path}")
        return {}
    except Exception as e:
        print(f"Error reading .env file: {e}")
        return {}

def create_database_connection(env_vars):
    try:
        if 'DATABASE_URL' in env_vars:
            parsed_url = urlparse(env_vars['DATABASE_URL'])
            host = parsed_url.hostname
            port = parsed_url.port or 5432
            database = parsed_url.path.lstrip('/')
            user = parsed_url.username
            password = parsed_url.password
        else:
            host = env_vars.get('DB_HOST', 'localhost')
            port = env_vars.get('DB_PORT', '5432')
            database = env_vars.get('DB_NAME', 'prima')
            user = env_vars.get('POSTGRES_USER', 'postgres')
            password = env_vars.get('POSTGRES_PASSWORD', '')
        
        connection = psycopg2.connect(
            host=host,
            port=port,
            database=database,
            user=user,
            password=password
        )
        connection.autocommit = True
        return connection
    
    except psycopg2.Error as e:
        print(f"PostgreSQL Error connecting to the database: {e}")
        return None
    except Exception as e:
        print(f"Unexpected error parsing database connection: {e}")
        return None

def get_uncancelled_tour_id(connection):
    if connection:
        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT tour.id as tour_id, tour.vehicle as vehicle_id
                    FROM tour 
                    WHERE cancelled = false 
                    LIMIT 1
                """)
                result = cursor.fetchone()
                return result if result else None
        except psycopg2.Error as e:
            print(f"Error executing tour ID query: {e}")
            return None
    return None

def get_other_vehicle(connection, blocked_id):
    if connection:
        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT id
                    FROM vehicle 
                    WHERE id != %s
                    LIMIT 1
                """, (blocked_id,))
                result = cursor.fetchone()
                return result if result else None
        except psycopg2.Error as e:
            print(f"Error executing tour ID query: {e}")
            return None
    return None

def send_request(endpoint, payload, session_token="dbxjvyuujwk3fr6sh7ofe25cbbxfephz"):
    try:
        json_payload = json.dumps(payload).encode('utf-8')
        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(30)
        sock.connect(('localhost', 5173))
        
        request_str = (
            f"POST {endpoint} HTTP/1.1\r\n"
            f"Host: localhost:5173\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(json_payload)}\r\n"
            f"Cookie: session = {session_token}\r\n"
            f"Connection: close\r\n\r\n"
        )
        request = request_str.encode('utf-8')
        sock.sendall(request + json_payload)
        response = sock.recv(4096).decode('utf-8')
        sock.close()
        if "HTTP/1.1 200" not in response and "HTTP/1.1 400" not in response:
            print(f"Error sending request to {endpoint}. Response: {response}")
            return None
        
        return response
    
    except socket.timeout:
        print(f"Timeout error: The request to {endpoint} timed out.")
        return None
    except socket.error as e:
        print(f"Socket error sending request to {endpoint}: {e}")
        return None
    except Exception as e:
        print(f"Unexpected error sending request to {endpoint}: {e}")
        return None

def parse_endpoint_probabilities(args):
    probabilities = {
        '/api/booking': 0.9,
        '/api/cancelTour': 0.02,
        'taxi/availability/api/tour': 0.08
    }
    
    for arg in args:
        if arg.startswith('--prob-booking='):
            prob = float(arg.split('=')[1])
            probabilities['/api/booking'] = prob
        
        elif arg.startswith('--prob-cancel='):
            prob = float(arg.split('=')[1])
            probabilities['/api/cancelTour'] = prob
        
        elif arg.startswith('--prob-cancel='):
            prob = float(arg.split('=')[1])
            probabilities['taxi/availability/api/tour'] = prob
    
    return probabilities

def choose_endpoint(probabilities):
    return random.choices(
        list(probabilities.keys()), 
        weights=list(probabilities.values())
    )[0]

def read_coordinates(filepath):
    coordinates = []
    with open(filepath, 'r') as csvfile:
        reader = csv.reader(csvfile)
        next(reader, None)
        
        for row in reader:
            if len(row) >= 2:
                try:
                    lng = float(row[0])
                    lat = float(row[1])
                    coordinates.append({
                        'lng': lng,
                        'lat': lat
                    })
                except (ValueError, IndexError) as e:
                    print(f"Skipping row due to conversion error: {row}")
    
    if not coordinates:
        raise ValueError("No valid coordinates found in the CSV file")
    
    return coordinates

def generate_random_coordinate(min_lat, max_lat, min_lng, max_lng):
    lat = random.uniform(min_lat, max_lat)
    lng = random.uniform(min_lng, max_lng)
    
    return {
        'lat': lat,
        'lng': lng
    }

def generate_coordinates_pair(min_lat, max_lat, min_lng, max_lng, min_distance=500):
    coord1 = generate_random_coordinate(min_lat, max_lat, min_lng, max_lng)
    coord2 = generate_random_coordinate(min_lat, max_lat, min_lng, max_lng)
    
    return coord1, coord2

def create_location(coord, address="Generated Address"):
    return {
        'lat': coord['lat'],
        'lng': coord['lng'],
        'address': address
    }

def generate_booking_request(coordinates=None, min_lat=None, max_lat=None, min_lng=None, max_lng=None, include_second_connection=True):
    current_time = int(time.time() * 1000)

    start_time_range = current_time - (3 * 24 * 60 * 60 * 1000)
    end_time_range = current_time + (21 * 24 * 60 * 60 * 1000)
    
    if coordinates:
        if len(coordinates) < 2:
            raise ValueError("Not enough coordinates to create a booking request")
        
        start_coord = random.choice(coordinates)
        target_coord = random.choice([c for c in coordinates if c != start_coord])
    else:
        if not all([min_lat, max_lat, min_lng, max_lng]):
            raise ValueError("Bounding box coordinates must be provided for random generation")
        
        start_coord, target_coord = generate_coordinates_pair(
            min_lat, max_lat, min_lng, max_lng
        )

    booking_request = {
        'capacities': {
            'passengers': random.randint(1, 2),
            'wheelchairs': random.randint(0, 0),
            'bikes': random.randint(0, 0),
            'luggage': random.randint(0, 0)
        }
    }
    
    first_start_time = random.randint(start_time_range, end_time_range - 14400000)
    first_target_time = first_start_time + random.randint(1800000, 14400000)
    
    booking_request['connection1'] = {
        'start': create_location(start_coord),
        'target': create_location(target_coord),
        'startTime': first_start_time,
        'targetTime': first_target_time
    }
    
    if include_second_connection:
        if coordinates:
            another_start = random.choice([c for c in coordinates if c not in [start_coord, target_coord]])
            another_target = random.choice([c for c in coordinates if c not in [start_coord, target_coord, another_start]])
        else:
            another_start, another_target = generate_coordinates_pair(
                min_lat, max_lat, min_lng, max_lng
            )
        
        second_start_time = random.randint(start_time_range, end_time_range)
        second_target_time = first_start_time + random.randint(1800000, 14400000)
        
        booking_request['connection2'] = {
            'start': create_location(another_start),
            'target': create_location(another_target),
            'startTime': second_start_time,
            'targetTime': second_target_time
        }
    else:
        booking_request['connection2'] = None

    booking_request['test'] = True
    return booking_request

def main(filepath=None, min_lat=None, max_lat=None, min_lng=None, max_lng=None, 
         num_requests=1, include_second_connection=True, endpoint_probabilities=None):
    probabilities = endpoint_probabilities
    
    cancellation_counter = 0
    
    env_vars = parse_env_file()
    connection = create_database_connection(env_vars)
    
    try:
        coordinates = read_coordinates(filepath) if filepath else None
        
        for i in range(num_requests):
            chosen_endpoint = choose_endpoint(probabilities)
            print("starting request nr: ", i, ", chosen endpoint: ", chosen_endpoint)
            
            if chosen_endpoint == '/api/booking':
                booking_request = generate_booking_request(
                    coordinates=coordinates,
                    min_lat=min_lat, max_lat=max_lat,
                    min_lng=min_lng, max_lng=max_lng,
                    include_second_connection=include_second_connection
                )
                send_request('/api/booking', booking_request)
            
            elif chosen_endpoint == '/api/cancelTour':
                tour_id = get_uncancelled_tour_id(connection)
                if tour_id:
                    cancel_tour = {
                        'tourId': tour_id[0],
                        'message': str(cancellation_counter)
                    }
                    send_request('/api/cancelTour', cancel_tour)
                    cancellation_counter += 1
                else:
                    print("No uncancelled tours found. Skipping cancellation.")

            elif chosen_endpoint == 'taxi/availability/api/tour':
                tour_and_vehicle = get_uncancelled_tour_id(connection)
                if tour_and_vehicle:
                    vehicle = get_other_vehicle(connection, tour_and_vehicle[1])
                    if vehicle:
                        move_tour = {
                            'tourId': tour_and_vehicle[0],
                            'vehicleId': vehicle[0]
                        }
                        send_request('/taxi/availability/api/tour', move_tour)
                        print(f"moved tour {tour_and_vehicle[0]} to vehicle {vehicle} from {tour_and_vehicle[1]}")
                    else:
                        print("No vehicle to move the chosen tour to.")
                else:
                    print("No uncancelled tours found. Skipping moving tour.")

    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    
    finally:
        if connection:
            connection.close()

if __name__ == "__main__":
    filepath = None
    min_lat = 51.299482657433586
    max_lat = 51.597147209063884
    min_lng = 14.439685057885825
    max_lng = 14.974246307684922
    num_requests = 1
    include_second_connection = True
    
    endpoint_probabilities = parse_endpoint_probabilities(sys.argv[1:])
    
    for arg in sys.argv[1:]:
        if arg in ['--no-c2', '--no-connection2', '--no-connection']:
            include_second_connection = False
        elif arg.startswith('--requests='):
            num_requests = int(arg.split('=')[1])
        elif arg.startswith('--file='):
            filepath = arg.split('=')[1]
        elif arg.startswith('--min-lat='):
            min_lat = float(arg.split('=')[1])
        elif arg.startswith('--max-lat='):
            max_lat = float(arg.split('=')[1])
        elif arg.startswith('--min-lng='):
            min_lng = float(arg.split('=')[1])
        elif arg.startswith('--max-lng='):
            max_lng = float(arg.split('=')[1])
    
    main(
        filepath=filepath,
        min_lat=min_lat, max_lat=max_lat,
        min_lng=min_lng, max_lng=max_lng,
        num_requests=num_requests, 
        include_second_connection=include_second_connection,
        endpoint_probabilities=endpoint_probabilities
    )