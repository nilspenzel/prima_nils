import csv
import json
import random
import socket
import sys
import time
import math
import psycopg2
from urllib.parse import urlparse

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

def send_request(endpoint, payload, session_token="opnrjn3u3axvgupvdgftsc2y5bg43xty"):
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

def main():    
    cancellation_counter = 0
    
    env_vars = parse_env_file()
    connection = create_database_connection(env_vars)
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

if __name__ == "__main__":
    main()