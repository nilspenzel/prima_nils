import csv
import json
import random
import socket
import sys
import time
import math

def read_coordinates(filepath):
    """
    Read coordinates from a CSV file.
    Assumes the file is comma-separated with a header row.
    Reads longitude and latitude values.
    """
    coordinates = []
    with open(filepath, 'r') as csvfile:
        # Use csv.reader to handle potential quotes or escaping
        reader = csv.reader(csvfile)
        
        # Skip the header row
        next(reader, None)
        
        for row in reader:
            # Check if row has at least two elements
            if len(row) >= 2:
                try:
                    # Convert first two elements to float (longitude, latitude)
                    lng = float(row[0])
                    lat = float(row[1])
                    coordinates.append({
                        'lng': lng,
                        'lat': lat
                    })
                except (ValueError, IndexError) as e:
                    # Skip rows that can't be converted
                    print(f"Skipping row due to conversion error: {row}")
    
    # Raise an error if no valid coordinates were found
    if not coordinates:
        raise ValueError("No valid coordinates found in the CSV file")
    
    return coordinates

def generate_random_coordinate(min_lat, max_lat, min_lng, max_lng):
    """
    Generate a random coordinate within the specified bounding box.
    
    :param min_lat: Minimum latitude
    :param max_lat: Maximum latitude
    :param min_lng: Minimum longitude
    :param max_lng: Maximum longitude
    :return: Dictionary with 'lat' and 'lng' keys
    """
    lat = random.uniform(min_lat, max_lat)
    lng = random.uniform(min_lng, max_lng)
    
    return {
        'lat': lat,
        'lng': lng
    }

def haversine_distance(coord1, coord2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees) using Haversine formula.
    
    :param coord1: First coordinate dictionary with 'lat' and 'lng'
    :param coord2: Second coordinate dictionary with 'lat' and 'lng'
    :return: Distance in meters
    """
    
    R = 6371.0
    
    lat1 = math.radians(coord1['lat'])
    lon1 = math.radians(coord1['lng'])
    lat2 = math.radians(coord2['lat'])
    lon2 = math.radians(coord2['lng'])
    
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    distance = R * c * 1000
    
    return distance

def generate_coordinates_pair(min_lat, max_lat, min_lng, max_lng, min_distance=500):
    """
    Generate two coordinates that are at least min_distance apart.
    
    :param min_lat: Minimum latitude
    :param max_lat: Maximum latitude
    :param min_lng: Minimum longitude
    :param max_lng: Maximum longitude
    :param min_distance: Minimum distance between coordinates in meters
    :return: Tuple of two coordinate dictionaries
    """
    max_attempts = 100
    for _ in range(max_attempts):
        coord1 = generate_random_coordinate(min_lat, max_lat, min_lng, max_lng)
        coord2 = generate_random_coordinate(min_lat, max_lat, min_lng, max_lng)
        
        if haversine_distance(coord1, coord2) >= min_distance:
            return coord1, coord2
    
    return coord1, coord2

def create_location(coord, address="Generated Address"):
    """
    Create a location dictionary based on coordinates.
    """
    return {
        'lat': coord['lat'],
        'lng': coord['lng'],
        'address': address
    }

def generate_booking_request(coordinates=None, min_lat=None, max_lat=None, min_lng=None, max_lng=None, include_second_connection=True):
    """
    Generate a booking request based on either predefined coordinates or bounding box.
    
    :param coordinates: List of coordinate dictionaries (optional)
    :param min_lat: Minimum latitude for random coordinate generation (optional)
    :param max_lat: Maximum latitude for random coordinate generation (optional)
    :param min_lng: Minimum longitude for random coordinate generation (optional)
    :param max_lng: Maximum longitude for random coordinate generation (optional)
    :param include_second_connection: Flag to include or exclude second connection
    """
    current_time = int(time.time() * 1000)

    start_time_range = current_time - (3 * 24 * 60 * 60 * 1000)  # 3 days ago
    end_time_range = current_time + (21 * 24 * 60 * 60 * 1000)  # 3 weeks in the future
    
    if coordinates:
        # Use provided coordinates
        if len(coordinates) < 2:
            raise ValueError("Not enough coordinates to create a booking request")
        
        start_coord = random.choice(coordinates)
        target_coord = random.choice([c for c in coordinates if c != start_coord])
    else:
        # Generate random coordinates within bounding box
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
    first_target_time = first_start_time + random.randint(1800000, 14400000)  # 30-240 minutes later in ms
    
    booking_request['connection1'] = {
        'start': create_location(start_coord),
        'target': create_location(target_coord),
        'startTime': first_start_time,
        'targetTime': first_target_time
    }
    
    # Second connection based on flag
    if include_second_connection:
        if coordinates:
            # Select different coordinates for second connection
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

def send_booking_request(booking_data):
    """
    Send booking request to the specified endpoint using raw socket communication.
    """
    try:
        # Prepare the JSON payload
        payload = json.dumps(booking_data).encode('utf-8')
        
        # Create a socket connection
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect(('localhost', 5173))
        
        session_token = "65g77aqgzo7b5u66ltkk5hfvt67unxos"
        request_str = (
            f"POST /api/booking HTTP/1.1\r\n"
            f"Host: localhost:5173\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(payload)}\r\n"
            f"Cookie: session = {session_token}\r\n"
            f"Connection: close\r\n\r\n"
        )
        request = request_str.encode('utf-8')
        
        sock.sendall(request + payload)
        
        response = sock.recv(4096).decode('utf-8')
        
        sock.close()
        
    except Exception as e:
        print(f"Error sending request: {e}")

def main(filepath=None, min_lat=None, max_lat=None, min_lng=None, max_lng=None, num_requests=1, include_second_connection=True):
    """
    Main function to process coordinates and send multiple booking requests.
    
    :param filepath: Path to the CSV file with coordinates (optional)
    :param min_lat: Minimum latitude for random coordinate generation (optional)
    :param max_lat: Maximum latitude for random coordinate generation (optional)
    :param min_lng: Minimum longitude for random coordinate generation (optional)
    :param max_lng: Maximum longitude for random coordinate generation (optional)
    :param num_requests: Number of requests to send
    :param include_second_connection: Flag to include or exclude second connection
    """
    try:
        # Read coordinates from file if filepath is provided
        coordinates = read_coordinates(filepath) if filepath else None
        
        for i in range(num_requests):        
            booking_request = generate_booking_request(
                coordinates=coordinates,
                min_lat=min_lat, max_lat=max_lat,
                min_lng=min_lng, max_lng=max_lng,
                include_second_connection=include_second_connection
            )
                      
            send_booking_request(booking_request)
    
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    # Default values
    filepath = None
    min_lat = 51.299482657433586
    max_lat = 51.597147209063884
    min_lng = 14.439685057885825
    max_lng = 14.974246307684922
    num_requests = 1
    include_second_connection = True
    
    # Parse command-line arguments
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
    
    # Run the main function
    main(
        filepath=filepath,
        min_lat=min_lat, max_lat=max_lat,
        min_lng=min_lng, max_lng=max_lng,
        num_requests=num_requests, 
        include_second_connection=include_second_connection
    )