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
    p_updates jsonb
  ) AS $$
  BEGIN
    IF jsonb_typeof(p_updates) <> 'array' THEN
      RAISE EXCEPTION 'Input must be a JSON array';
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM jsonb_array_elements(p_updates) elem 
        WHERE NOT (
          elem ? 'id' 
          AND elem ? 'event_group' 
          AND jsonb_typeof(elem->'id') = 'number' 
          AND jsonb_typeof(elem->'event_group') = 'string'
        )
    ) THEN
        RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "event_group" (string)';
    END IF;

    UPDATE event e
    SET event_group = updates.event_group
    FROM (
      SELECT 
        (record->>'id')::INTEGER AS id, 
        (record->>'event_group')::VARCHAR AS event_group
      FROM jsonb_array_elements(p_updates) AS record
    ) AS updates
    WHERE e.id = updates.id;
  END;
  $$ LANGUAGE plpgsql;
`.execute(db);


await sql`
    CREATE OR REPLACE PROCEDURE update_direct_durations(
      p_direct_durations jsonb
    ) AS $$
    BEGIN
      IF jsonb_typeof(p_direct_durations) <> 'array' THEN
        RAISE EXCEPTION 'Input must be a JSON array';
      END IF;

      IF EXISTS (
        SELECT 1 
        FROM jsonb_array_elements(p_direct_durations) elem 
        WHERE NOT (
          elem ? 'id' 
          AND elem ? 'direct' 
          AND jsonb_typeof(elem->'id') = 'number' 
          AND jsonb_typeof(elem->'direct') = 'number'
        )
      ) THEN
        RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "direct" (integer)';
      END IF;

      UPDATE event e
      SET direct_driving_duration = updates.direct
      FROM (
        SELECT 
          (record->>'id')::INTEGER AS id, 
          (record->>'direct')::INTEGER AS direct
        FROM jsonb_array_elements(p_direct_durations) AS record
      ) AS updates
      WHERE e.id = updates.id;
    END;
    $$ LANGUAGE plpgsql;
  `.execute(db);


  await sql`
  CREATE OR REPLACE PROCEDURE update_return_durations(
    p_return_durations jsonb
  ) AS $$
  BEGIN
    IF jsonb_typeof(p_return_durations) <> 'array' THEN
      RAISE EXCEPTION 'Input must be a JSON array';
    END IF;

    IF EXISTS (
      SELECT 1 
      FROM jsonb_array_elements(p_return_durations) elem 
      WHERE NOT (
        elem ? 'id' 
        AND elem ? 'return_duration' 
        AND jsonb_typeof(elem->'id') = 'number' 
        AND jsonb_typeof(elem->'return_duration') = 'number'
      )
    ) THEN
      RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "return_duration" (integer)';
    END IF;

    UPDATE event e
    SET return_duration = updates.return_duration
    FROM (
      SELECT 
        (record->>'id')::INTEGER AS id, 
        (record->>'return_duration')::INTEGER AS return_duration
      FROM jsonb_array_elements(p_return_durations) AS record
    ) AS updates
    WHERE e.id = updates.id;
  END;
  $$ LANGUAGE plpgsql;
`.execute(db);


await sql`
    CREATE OR REPLACE PROCEDURE update_approach_durations(
      p_approach_durations jsonb
    ) AS $$
    BEGIN
      IF jsonb_typeof(p_approach_durations) <> 'array' THEN
        RAISE EXCEPTION 'Input must be a JSON array';
      END IF;

      IF EXISTS (
        SELECT 1 
        FROM jsonb_array_elements(p_approach_durations) elem 
        WHERE NOT (
          elem ? 'id' 
          AND elem ? 'approach_duration' 
          AND jsonb_typeof(elem->'id') = 'number' 
          AND jsonb_typeof(elem->'approach_duration') = 'number'
        )
      ) THEN
        RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "approach_duration" (integer)';
      END IF;

      UPDATE event e
      SET approach_duration = updates.approach_duration
      FROM (
        SELECT 
          (record->>'id')::INTEGER AS id, 
          (record->>'approach_duration')::INTEGER AS approach_duration
        FROM jsonb_array_elements(p_approach_durations) AS record
      ) AS updates
      WHERE e.id = updates.id;
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
      p_tour tour_type,
      p_update_event_groups jsonb,
      p_update_return_durations jsonb,
      p_update_approach_durations jsonb,
      p_update_direct_durations jsonb
    ) AS $$
    DECLARE
      v_request_id INTEGER;
      v_tour_id INTEGER;
    BEGIN
      CALL update_event_groups(p_update_event_groups);
      CALL update_direct_durations(p_update_direct_durations);
      CALL update_return_durations(p_update_return_durations);
      CALL update_approach_durations(p_update_approach_durations);
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
	await sql`DROP PROCEDURE IF EXISTS insert_request(request_type, INTEGER, OUT INTEGER)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_event(event_type, INTEGER, INTEGER)`.execute(
		db
	);
	await sql`DROP PROCEDURE IF EXISTS merge_tours(INTEGER[], INTEGER, TIMESTAMP, TIMESTAMP)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS insert_tour(tour_type, OUT INTEGER)`.execute(db);
  await sql`DROP PROCEDURE IF EXISTS update_direct_durations(jsonb)`.execute(db);
  await sql`DROP PROCEDURE IF EXISTS update_return_durations(jsonb)`.execute(db);
  await sql`DROP PROCEDURE IF EXISTS update_approach_durations(jsonb)`.execute(db);
  await sql`DROP PROCEDURE IF EXISTS update_event_groups(jsonb)`.execute(db);
	await sql`DROP PROCEDURE IF EXISTS create_and_merge_tours(
      request_type,
      event_type,
      event_type,
      INTEGER[],
      tour_type,
      jsonb,
      jsonb,
      jsonb,
      jsonb)`.execute(db);
}
