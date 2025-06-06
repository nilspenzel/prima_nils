import { sql } from 'kysely';

export async function up(db) {
    await sql`
        CREATE OR REPLACE PROCEDURE update_scheduled_times(
            p_update_scheduled_times jsonb
        ) AS $$
        DECLARE
            record jsonb;
            v_event_id INTEGER;
            v_time BIGINT;
            v_start BOOLEAN;
        BEGIN
            FOR record IN SELECT * FROM jsonb_array_elements(p_update_scheduled_times)
            LOOP
                v_event_id := (record->>'event_id')::INTEGER;
                v_time := (record->>'time')::BIGINT;
                v_start := (record->>'start')::BOOLEAN;

                IF v_start THEN
                    UPDATE event
                    SET scheduled_time_start = v_time
                    WHERE id = v_event_id;
                ELSE
                    UPDATE event
                    SET scheduled_time_end = v_time
                    WHERE id = v_event_id;
                END IF;
            END LOOP;
        END;
        $$ LANGUAGE plpgsql;
        `.execute(db);

    await sql`
        DROP FUNCTION public.create_and_merge_tours(
            request_type,
            event_type,
            event_type,
            integer[],
            tour_type,
            jsonb,
            jsonb,
            jsonb,
            direct_duration_type,
            direct_duration_type
        );
    `.execute(db);

    await sql`
        CREATE OR REPLACE FUNCTION create_and_merge_tours(
            p_request request_type,
            p_event1 event_type,
            p_event2 event_type,
            p_merge_tour_list INTEGER[],
            p_tour tour_type,
            p_update_event_groups jsonb,
            p_update_next_leg_durations jsonb,
            p_update_prev_leg_durations jsonb,
            p_update_direct_duration_dropoff direct_duration_type,
            p_update_direct_duration_pickup direct_duration_type,
            p_update_scheduled_times jsonb
        ) RETURNS INTEGER AS $$
        DECLARE
            v_request_id INTEGER;
            v_tour_id INTEGER;
        BEGIN
            CALL update_event_groups(p_update_event_groups);
            CALL update_direct_duration(p_update_direct_duration_dropoff);
            CALL update_next_leg_durations(p_update_next_leg_durations);
            CALL update_prev_leg_durations(p_update_prev_leg_durations);
            IF p_tour.id IS NULL THEN
                    CALL insert_tour(p_tour, v_tour_id);
            ELSE
                v_tour_id := p_tour.id;
                CALL merge_tours(p_merge_tour_list, v_tour_id, p_tour.arrival, p_tour.departure);
                CALL update_direct_duration(p_update_direct_duration_pickup);
            END IF;
            CALL insert_request(p_request, v_tour_id, v_request_id);
            CALL insert_event(p_event1, v_request_id);
            CALL insert_event(p_event2, v_request_id);
            CALL update_scheduled_times(p_update_scheduled_times);

            RETURN v_request_id;
        END;
        $$ LANGUAGE plpgsql;
        `.execute(db);
}
