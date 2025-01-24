import { sql } from 'kysely';

export async function up(db) {	
  await sql`
  CREATE TYPE request_type AS (
      passengers INTEGER,
      wheelchairs INTEGER,
      bikes INTEGER,
      luggage INTEGER
  );`.execute(db);

  await sql`
  CREATE TYPE tour_type AS (
      departure TIMESTAMP,
      arrival TIMESTAMP,
      vehicle INTEGER,
      id INTEGER
  );`.execute(db);

	await sql`
  CREATE TYPE event_type AS ( 
    is_pickup boolean,
    latitude float,
    longitude float,
    scheduled_time TIMESTAMP,
    communicated_time TIMESTAMP,
    customer text,
    approach_duration integer,
    return_duration integer,
    direct_driving_duration integer,
    address TEXT,
    grp TEXT
  );`.execute(db);

  await sql`
    CREATE OR REPLACE PROCEDURE update_event_groups(
      p_ids_list INTEGER[],
      p_event_groups varchar[]
    ) AS $$
    DECLARE
      idx INTEGER;
    BEGIN
      IF array_length(p_ids_list,1) <> array_length(p_event_groups,1) THEN
          RAISE EXCEPTION 'In update_event_groups, number of ids must match number of update values.';
      END IF;

      FOR idx IN 1..COALESCE(array_length(p_ids_list, 1), 0) LOOP
        UPDATE event
        SET event_group = p_event_groups[idx]
        WHERE id = p_ids_list[idx];
      END LOOP;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

  await sql`
    CREATE OR REPLACE PROCEDURE update_event_direct_durations(
      p_ids_list INTEGER[],
      p_direct_durations INTEGER[]
    ) AS $$
    DECLARE
      idx INTEGER;
    BEGIN
      IF array_length(p_ids_list,1) <> array_length(p_direct_durations,1) THEN
          RAISE EXCEPTION 'In update_event_direct_durations, number of ids must match number of update values.';
      END IF;

      FOR idx IN 1..COALESCE(array_length(p_ids_list, 1), 0) LOOP
        UPDATE event
        SET direct_driving_duration = p_direct_durations[idx]
        WHERE id = p_ids_list[idx];
      END LOOP;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

  await sql`
    CREATE OR REPLACE PROCEDURE update_event_return_durations(
      p_prev_pickup_id INTEGER,
      p_prev_pickup_duration INTEGER,
      p_prev_dropoff_id INTEGER,
      p_prev_dropoff_duration INTEGER
    ) AS $$
    DECLARE
      idx INTEGER;
      v_prev_id1 INTEGER := p_prev_pickup_id;
      v_next_id1 INTEGER := p_prev_dropoff_id;
    BEGIN
      IF v_prev_id1 IS NOT NULL THEN
        UPDATE event
        SET return_duration = p_prev_pickup_duration
        WHERE id = v_prev_id1;
      END IF;

      IF v_next_id1 IS NOT NULL THEN
        UPDATE event
        SET return_duration = p_prev_dropoff_duration
        WHERE id = v_next_id1;
      END IF;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

  await sql`
    CREATE OR REPLACE PROCEDURE update_event_approach_durations(
      p_after_pickup_id INTEGER,
      p_after_pickup_duration INTEGER,
      p_after_dropoff_id INTEGER,
      p_after_dropoff_duration INTEGER
    ) AS $$
    DECLARE
      idx INTEGER;
      v_prev_id2 INTEGER := p_after_pickup_id;
      v_next_id2 INTEGER := p_after_dropoff_id;
    BEGIN
      IF v_prev_id2 IS NOT NULL THEN
        UPDATE event
        SET approach_duration = p_after_pickup_duration
        WHERE id = v_prev_id2;
      END IF;

      IF v_next_id2 IS NOT NULL THEN
        UPDATE event
        SET approach_duration = p_after_dropoff_duration
        WHERE id = v_next_id2;
      END IF;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

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
    CREATE OR REPLACE PROCEDURE insert_event(
      p_event event_type,
      p_request_id INTEGER,
      p_tour_id INTEGER
    ) AS $$
      BEGIN
        INSERT INTO event (
          is_pickup, latitude, longitude, scheduled_time, communicated_time,
          address, tour, customer, request, approach_duration, return_duration, event_group, direct_driving_duration
        )
      VALUES (
        p_event.is_pickup, p_event.latitude, p_event.longitude, p_event.scheduled_time,
        p_event.communicated_time, p_event.address, p_tour_id, p_event.customer,
        p_request_id, p_event.approach_duration, p_event.return_duration, p_event.grp, p_event.direct_driving_duration
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
      SET 
          arrival = CASE WHEN p_arrival IS NOT NULL THEN p_arrival ELSE arrival END,
          departure = CASE WHEN p_departure IS NOT NULL THEN p_departure ELSE departure END
      WHERE id = p_target_tour_id;


      DELETE FROM tour
      WHERE id = ANY(p_merge_tour_list);
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE insert_tour(
      p_tour tour_type,
      OUT v_tour_id INTEGER
    ) AS $$
    BEGIN
      INSERT INTO tour (departure, arrival, vehicle, fare)
      VALUES (p_tour.departure, p_tour.arrival, p_tour.vehicle, NULL)
      RETURNING id INTO v_tour_id;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);

	await sql`
    CREATE OR REPLACE PROCEDURE create_and_merge_tours(
      p_request request_type,
      p_event1 event_type,
      p_event2 event_type,
      p_merge_tour_list INTEGER[],
      p_update_event_group_ids INTEGER[],
      p_update_event_group_updates varchar[],
      p_tour tour_type,
      p_prev_pickup_id INTEGER,
      p_prev_pickup_return_duration INTEGER,
      p_after_pickup_id INTEGER,
      p_after_pickup_approach_duration INTEGER,
      p_prev_dropoff_id INTEGER,
      p_prev_dropoff_return_duration INTEGER,
      p_after_dropoff_id INTEGER,
      p_after_dropoff_approach_duration INTEGER,
      p_update_duration_ids INTEGER[],
      p_update_direct_durations INTEGER[]
    ) AS $$
    DECLARE
      v_request_id INTEGER;
      v_tour_id INTEGER;
    BEGIN
      CALL update_event_groups(p_update_event_group_ids, p_update_event_group_updates);
      CALL update_event_direct_durations(p_update_duration_ids, p_update_direct_durations);
      CALL update_event_return_durations(p_prev_pickup_id, p_prev_pickup_return_duration, p_prev_dropoff_id, p_prev_dropoff_return_duration);
      CALL update_event_approach_durations(p_after_pickup_id, p_after_pickup_approach_duration, p_after_dropoff_id, p_after_dropoff_approach_duration);
      IF p_tour.id IS NULL THEN
          CALL insert_tour(p_tour, v_tour_id);
      ELSE
        v_tour_id := p_tour.id;
        CALL merge_tours(p_merge_tour_list, v_tour_id, p_tour.arrival, p_tour.departure);
      END IF;
      CALL insert_request(p_request, v_tour_id, v_request_id);
      CALL insert_event(p_event1, v_request_id, v_tour_id);
      CALL insert_event(p_event2, v_request_id, v_tour_id);
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);
}

export async function down(db) {
	await sql`DROP PROCEDURE IF EXISTS insert_request(request_type, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_event(event_type, INTEGER, INTEGER)`.execute(
		db
	);
	await sql`DROP PROCEDURE IF EXISTS merge_tours(INTEGER[], INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_tour(tour_type, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS create_and_merge_tours(request_type, event_type, event_type, INTEGER[], tour_type)`.execute(
		db
	);
}
