import { sql } from 'kysely';

export async function up(db) {
	await db.schema
		.alterTable('event')
		.addColumn('approach_duration', 'integer', (col) => col.notNull())
		.addColumn('return_duration', 'integer', (col) => col.notNull())
		.execute();

	await sql`
      CREATE TYPE request_type AS (
          passengers INTEGER,
          wheelchairs INTEGER,
          bikes INTEGER,
          luggage INTEGER
      );
  `.execute(db);

	await sql`
    CREATE TYPE address_type AS (
      city TEXT,
      postal_code TEXT,
      house_number TEXT,
      street TEXT
    );`.execute(db);

	await sql`CREATE TYPE event_type AS ( 
    is_pickup boolean,
    latitude float,
    longitude float,
    scheduled_time TIMESTAMP,
    communicated_time TIMESTAMP,
    customer text,
    approach_duration integer,
    return_duration integer
  );`.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE insert_request(
      p_request request_type,
      p_tour_id INTEGER,
      OUT v_request_id INTEGER
    ) AS $$
    BEGIN
      INSERT INTO request (passengers, wheelchairs, bikes, luggage, tour)
      VALUES (p_request.passengers, p_request.wheelchairs, p_request.bikes, p_request.luggage, p_tour_id)
      RETURNING id INTO v_request_id;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE get_or_insert_address(
      p_address address_type,
      OUT v_address_id INTEGER
    ) AS $$
    BEGIN
      SELECT id INTO v_address_id
      FROM address
      WHERE street = p_address.street
        AND house_number = p_address.house_number
        AND postal_code = p_address.postal_code
        AND city = p_address.city;

      IF v_address_id IS NULL THEN
        INSERT INTO address (street, house_number, postal_code, city)
        VALUES (p_address.street, p_address.house_number, p_address.postal_code, p_address.city)
        RETURNING id INTO v_address_id;
      END IF;
    END;
    $$ LANGUAGE plpgsql`.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE insert_event(
      p_event event_type,
      p_address address_type,
      p_request_id INTEGER,
      p_tour_id INTEGER
    ) AS $$
    DECLARE
      v_address_id INTEGER;
      BEGIN
        CALL get_or_insert_address(p_address, v_address_id);
        INSERT INTO event (
          is_pickup, latitude, longitude, scheduled_time, communicated_time,
          address, tour, customer, request, approach_duration, return_duration
        )
      VALUES (
        p_event.is_pickup, p_event.latitude, p_event.longitude, p_event.scheduled_time,
        p_event.communicated_time, v_address_id, p_tour_id, p_event.customer,
        p_request_id, p_event.approach_duration, p_event.return_duration
      );
    END;
    $$ LANGUAGE plpgsql;`.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE merge_tours(p_merge_tour_list INTEGER[], p_target_tour_id INTEGER, p_arrival TIMESTAMP, p_departure TIMESTAMP) AS $$
    BEGIN
      UPDATE request
      SET tour = p_target_tour_id
      WHERE tour = ANY(p_merge_tour_list);

      UPDATE event
      SET tour = p_target_tour_id
      WHERE tour = ANY(p_merge_tour_list);

      UPDATE tour
      SET arrival = p_arrival, departure = p_departure
      WHERE id = p_target_tour_id;

      DELETE FROM tour
      WHERE id = ANY(p_merge_tour_list);
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE insert_tour(
      p_departure TIMESTAMP,
      p_arrival TIMESTAMP,
      p_vehicle_id INTEGER,
      OUT v_tour_id INTEGER
    ) AS $$
    BEGIN
      INSERT INTO tour (departure, arrival, vehicle, fare, fare_route)
      VALUES (p_departure, p_arrival, p_vehicle_id, NULL, NULL)
      RETURNING id INTO v_tour_id;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE create_and_merge_tours(
      p_request request_type,
      p_event1 event_type,
      p_address1 address_type,
      p_event2 event_type,
      p_address2 address_type,
      p_merge_tour_list INTEGER[],
      p_departure TIMESTAMP,
      p_arrival TIMESTAMP,
      p_tour_id INTEGER,
      p_vehicle_id INTEGER
    ) AS $$
    DECLARE
      v_request_id INTEGER;
      v_tour_id INTEGER;
    BEGIN
      IF p_tour_id IS NULL THEN
          CALL insert_tour(p_departure, p_arrival, p_vehicle_id, v_tour_id);
      ELSE
        v_tour_id := p_tour_id;
      END IF;
      CALL insert_request(p_request, v_tour_id, v_request_id);
      CALL insert_event(p_event1, p_address1, v_request_id, v_tour_id);
      CALL insert_event(p_event2, p_address2, v_request_id, v_tour_id);
      CALL merge_tours(p_merge_tour_list, v_tour_id, p_arrival, p_departure);
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);
}

export async function down(db) {
	await sql`DROP PROCEDURE IF EXISTS insert_request(request_type, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS get_or_insert_address(address_type, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_event(event_type, address_type, INTEGER, INTEGER)`.execute(
		db
	);
	await sql`DROP PROCEDURE IF EXISTS merge_tours(INTEGER[], INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_tour(TIMESTAMT, TIMESTAMP, INTEGER, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS create_and_merge_tours(request_type, event_type, address_type, event_type, address_type, INTEGER[], INTEGER, tour_type DEFAULT NULL)`.execute(
		db
	);
}
