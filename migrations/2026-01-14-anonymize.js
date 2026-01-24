import { sql } from 'kysely';

export async function up(db) {
await sql`
    CREATE OR REPLACE FUNCTION anonymization_lat_step()
    RETURNS double precision
    AS $$
    BEGIN
        RETURN 0.003;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE FUNCTION anonymization_lng_step()
    RETURNS double precision
    AS $$
    BEGIN
        RETURN 0.003;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE FUNCTION round_to_step(
        value double precision,
        step  double precision
    )
    RETURNS double precision
    AS $$
    BEGIN
        IF step <= 0 THEN
            RAISE EXCEPTION 'step must be > 0 (got %)', step;
        END IF;

        RETURN ROUND(value / step) * step;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE FUNCTION anonymize_journey_json(
    input_json jsonb,
    mode varchar
    )
    RETURNS jsonb
    AS $$
    DECLARE
        legs jsonb;
        leg jsonb;
        leg_index int := 0;
        result jsonb := input_json;
    BEGIN
        legs := input_json->'legs';
        FOR leg IN
            SELECT * FROM jsonb_array_elements(legs)
        LOOP
            IF leg->>'mode' = mode THEN
                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'from', 'lat'],
                    round_to_step((leg->'from'->>'lat')::double precision, anonymization_lat_step())::text::jsonb
                );

                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'from', 'lon'],
                    round_to_step((leg->'from'->>'lon')::double precision, anonymization_lng_step())::text::jsonb
                );

                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'from', 'name'],
                    '"anonymer Ort"'::jsonb
                );

                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'to', 'lat'],
                    round_to_step((leg->'to'->>'lat')::double precision, anonymization_lat_step())::text::jsonb
                );

                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'to', 'lon'],
                    round_to_step((leg->'to'->>'lon')::double precision, anonymization_lng_step())::text::jsonb
                );

                result := jsonb_set(
                    result,
                    ARRAY['legs', leg_index::text, 'to', 'name'],
                    '"anonymer Ort"'::jsonb
                );
            END IF;

            leg_index := leg_index + 1;
        END LOOP;

        RETURN result;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);


    await sql`
    CREATE OR REPLACE PROCEDURE anonymize_taxi(
        t1 BIGINT,
        t2 BIGINT
    )
    AS $$
    BEGIN
        -- Anonymize event_group table
        UPDATE event_group
        SET lat = round_to_step(event_group.lat::double precision, anonymization_lat_step()),
            lng = round_to_step(event_group.lng::double precision, anonymization_lng_step()),
            address = 'anonymer Ort'
        FROM event
        INNER JOIN request ON request.id = event.request
        INNER JOIN tour ON request.tour = tour.id
        WHERE event.event_group_id = event_group.id
          AND request.customer is not null
          AND tour.arrival > t1
          AND tour.arrival < t2;

        -- Update journeys for request1
        UPDATE journey j
        SET "user" = NULL,
            json = anonymize_journey_json(j.json, 'ODM')
        FROM request r
        JOIN tour t ON r.tour = t.id
        WHERE j.request1 = r.id
          AND r.customer IS NOT NULL
          AND t.arrival > t1
          AND t.arrival < t2;

        -- Update journeys for request2
        UPDATE journey j
        SET "user" = NULL,
            json = anonymize_journey_json(j.json, 'ODM')
        FROM request r
        JOIN tour t ON r.tour = t.id
        WHERE j.request2 = r.id
          AND r.customer IS NOT NULL
          AND t.arrival > t1
          AND t.arrival < t2;

        -- Anonymize request table
        UPDATE request
        SET customer = NULL
        FROM tour
        WHERE tour.id = request.tour
          AND tour.arrival > t1
          AND tour.arrival < t2
          AND customer is not null;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE PROCEDURE anonymize_rs(
        t1 BIGINT,
        t2 BIGINT
    )
    AS $$
    BEGIN
        -- Anonymize ride_share_tour table
        UPDATE ride_share_tour
        SET vehicle = NULL
        WHERE ride_share_tour.latest_end > t1
          AND ride_share_tour.latest_end < t2
          AND vehicle is not null;

        -- Anonymize event_group table
        UPDATE event_group
        SET lat = round_to_step(event_group.lat::double precision, anonymization_lat_step()),
            lng = round_to_step(event_group.lng::double precision, anonymization_lng_step()),
            address = 'anonymer Ort'
        FROM event
        INNER JOIN request ON request.id = event.request
        INNER JOIN ride_share_tour ON request.ride_share_tour = ride_share_tour.id
        WHERE event.event_group_id = event_group.id;

        -- Update journeys for request1
        UPDATE journey j
        SET "user" = NULL,
            json = anonymize_journey_json(j.json, 'RIDE_SHARING')
        FROM request r
        JOIN ride_share_tour rst ON r.ride_share_tour = rst.id
        WHERE j.request1 = r.id
          AND r.customer IS NOT NULL
          AND rst.latest_end > t1
          AND rst.latest_end < t2;

        -- Update journeys for request2
        UPDATE journey j
        SET "user" = NULL,
            json = anonymize_journey_json(j.json, 'RIDE_SHARING')
        FROM request r
        JOIN ride_share_tour rst ON r.ride_share_tour = rst.id
        WHERE j.request2 = r.id
          AND r.customer IS NOT NULL
          AND rst.latest_end > t1
          AND rst.latest_end < t2;

        -- Anonymize request table
        UPDATE request
        SET customer = NULL
        FROM ride_share_tour
        WHERE ride_share_tour.id = request.ride_share_tour
          AND ride_share_tour.latest_end > t1
          AND ride_share_tour.latest_end < t2
          AND customer is not null;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE PROCEDURE delete_unused_events()
    AS $$
    BEGIN
        DELETE FROM event_group
        WHERE NOT EXISTS (
            SELECT 1
            FROM event
            WHERE event.event_group_id = event_group.id
        );
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);
}

export async function down() { }