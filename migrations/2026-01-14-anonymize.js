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
    input_json jsonb
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
            IF leg->>'mode' = 'ODM' THEN
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
    DECLARE
        j RECORD;
    BEGIN
        -- Anonymize event table
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

        -- Anonymize journey table
        FOR j IN
            SELECT journey.id, journey.json
            FROM journey
            LEFT JOIN request r1 ON journey.request1 = r1.id
            LEFT JOIN request r2 ON journey.request2 = r2.id
            LEFT JOIN tour tour1 ON r1.tour = tour1.id
            LEFT JOIN tour tour2 ON r2.tour = tour2.id
            WHERE
                (r1.customer is not null
                AND tour1 is not null
                AND tour1.arrival > t1
                AND tour1.arrival < t2)
                OR (r2.customer is not null
                AND tour2 is not null
                AND tour2.arrival > t1
                AND tour2.arrival < t2)
        LOOP
            UPDATE journey SET
                "user" = NULL,
                json = anonymize_journey_json(j.json)
            WHERE id = j.id;
        END LOOP;

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
    DECLARE
        j RECORD;
    BEGIN
        -- Anonymize ride_share_tour table
        UPDATE ride_share_tour
        SET vehicle = NULL
        WHERE ride_share_tour.latest_end > t1
          AND ride_share_tour.latest_end < t2
          AND vehicle is not null;

        -- Anonymize event table
        UPDATE event_group
        SET lat = round_to_step(event_group.lat::double precision, anonymization_lat_step()),
            lng = round_to_step(event_group.lng::double precision, anonymization_lng_step()),
            address = 'anonymer Ort'
        FROM event
        INNER JOIN request ON request.id = event.request
        INNER JOIN ride_share_tour ON request.ride_share_tour = ride_share_tour.id
        WHERE event.event_group_id = event_group.id
          AND request.customer is not null
          AND ride_share_tour.latest_end > t1
          AND ride_share_tour.latest_end < t2;

        -- Anonymize journey table
        FOR j IN
            SELECT journey.id, journey.json
            FROM journey
            LEFT JOIN request r1 ON journey.request1 = r1.id
            LEFT JOIN request r2 ON journey.request2 = r2.id
            LEFT JOIN ride_share_tour rst1 ON r1.ride_share_tour = rst1.id
            LEFT JOIN ride_share_tour rst2 ON r2.ride_share_tour = rst2.id
            WHERE
                (rst1 IS NOT NULL
                AND r1.customer is not null
                AND rst1.latest_end > t1
                AND rst1.latest_end < t2)
                OR (rst2 IS NOT NULL
                AND r2.customer is not null
                AND rst2.latest_end > t1
                AND rst2.latest_end < t2)
        LOOP
            UPDATE journey SET
                "user" = NULL,
                json = anonymize_journey_json(j.json)
            WHERE id = j.id;
        END LOOP;

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
}

export async function down() { }