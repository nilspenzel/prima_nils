import { sql } from 'kysely';

export async function up(db) {
    await db.schema
        .createTable('ride_share_tour')
        .addColumn('id', 'serial', (col) => col.primaryKey())
        .addColumn('passengers', 'integer')
        .addColumn('luggage', 'integer')
        .addColumn('scheduled_start_time', 'bigint')
        .addColumn('scheduled_end_time', 'bigint')
        .addColumn('communicated_start_time', 'bigint')
        .addColumn('communicated_end_time', 'bigint')
        .addColumn('fare', 'integer')
        .addColumn('cancelled', 'boolean', (col) => col.notNull())
        .addColumn('message', 'varchar')
        .addColumn('provider', 'integer', (col) => col.references('user.id').notNull())
        .execute();

    await db.schema
        .alterTable('request')
        .alterColumn('tour', (col) => col.dropNotNull())
        .addColumn('ride_share_tour', 'integer', (col) => col.references('ride_share_tour.id'))
        .execute();

        await sql`
    CREATE OR REPLACE PROCEDURE insert_request_rs(
        p_request request_type,
        p_tour_id INTEGER,
        OUT v_request_id INTEGER
    ) AS $$
    BEGIN
        INSERT INTO request (passengers, wheelchairs, bikes, luggage, customer, ride_share_tour, ticket_code, ticket_checked, cancelled, kids_zero_to_two, kids_three_to_four, kids_five_to_six)
        VALUES (p_request.passengers, p_request.wheelchairs, p_request.bikes, p_request.luggage, p_request.customer, p_tour_id, md5(random()::text), FALSE, FALSE, p_request.kids_zero_to_two, p_request.kids_three_to_four, p_request.kids_five_to_six)
        RETURNING id INTO v_request_id;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);

    await sql`
    CREATE OR REPLACE FUNCTION add_ride_share_request(
        p_request request_type,
        p_event1 event_type,
        p_event2 event_type,
        p_tour_id integer,
        p_update_prev_leg_durations jsonb,
        p_update_next_leg_durations jsonb,
        p_update_scheduled_times jsonb
    ) RETURNS INTEGER AS $$
    DECLARE
        v_request_id INTEGER;
    BEGIN
        CALL insert_request_rs(p_request, p_tour_id, v_request_id);
        CALL insert_event(p_event1, v_request_id);
        CALL insert_event(p_event2, v_request_id);
        CALL update_prev_leg_durations(p_update_prev_leg_durations);
        CALL update_next_leg_durations(p_update_next_leg_durations);
        CALL update_scheduled_times(p_update_scheduled_times);
    
        RETURN v_request_id;
    END;
    $$ LANGUAGE plpgsql;
    `.execute(db);
}

export async function down() { }
