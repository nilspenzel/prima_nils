--
-- PostgreSQL database dump
--

\restrict NnSfHSVmjTbhQn7Kd3daxrbgChG97ht0SGTgRJJVcLkYeOEQQT5iUJoS4jCGwhz

-- Dumped from database version 16.4 (Debian 16.4-1.pgdg110+2)
-- Dumped by pg_dump version 16.11 (Ubuntu 16.11-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: direct_duration_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.direct_duration_type AS (
	tour_id integer,
	duration integer
);


ALTER TYPE public.direct_duration_type OWNER TO postgres;

--
-- Name: event_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.event_type AS (
	is_pickup boolean,
	lat double precision,
	lng double precision,
	scheduled_time_start bigint,
	scheduled_time_end bigint,
	communicated_time bigint,
	prev_leg_duration integer,
	next_leg_duration integer,
	address text,
	grp integer
);


ALTER TYPE public.event_type OWNER TO postgres;

--
-- Name: request_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.request_type AS (
	passengers integer,
	kids_zero_to_two integer,
	kids_three_to_four integer,
	kids_five_to_six integer,
	wheelchairs integer,
	bikes integer,
	luggage integer,
	customer integer,
	ticket_price integer,
	ticket_code character varying
);


ALTER TYPE public.request_type OWNER TO postgres;

--
-- Name: ride_share_request_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.ride_share_request_type AS (
	passengers integer,
	luggage integer,
	customer integer,
	bus_stop_time bigint,
	requested_time bigint,
	start_fixed boolean
);


ALTER TYPE public.ride_share_request_type OWNER TO postgres;

--
-- Name: tour_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tour_type AS (
	departure bigint,
	arrival bigint,
	vehicle integer,
	direct_duration integer,
	id integer
);


ALTER TYPE public.tour_type OWNER TO postgres;

--
-- Name: accept_ride_share_request(integer, public.event_type, public.event_type, integer, integer, jsonb, jsonb, jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.accept_ride_share_request(IN p_request_id integer, IN p_event1 public.event_type, IN p_event2 public.event_type, IN p_event_id1 integer, IN p_event_id2 integer, IN p_update_scheduled_times jsonb, IN p_prev_leg_updates jsonb, IN p_next_leg_updates jsonb)
    LANGUAGE plpgsql
    AS $$
    BEGIN
    	CALL update_next_leg_durations(p_next_leg_updates);
    	CALL update_prev_leg_durations(p_prev_leg_updates);
        CALL update_scheduled_times(p_update_scheduled_times);

        CALL update_event(p_event_id1, p_event1);
        CALL update_event(p_event_id2, p_event2);

    	UPDATE request r
    	SET pending = false
    	WHERE r.id = p_request_id;
    END;
    $$;


ALTER PROCEDURE public.accept_ride_share_request(IN p_request_id integer, IN p_event1 public.event_type, IN p_event2 public.event_type, IN p_event_id1 integer, IN p_event_id2 integer, IN p_update_scheduled_times jsonb, IN p_prev_leg_updates jsonb, IN p_next_leg_updates jsonb) OWNER TO postgres;

--
-- Name: add_ride_share_request(public.ride_share_request_type, public.event_type, public.event_type, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_ride_share_request(p_request public.ride_share_request_type, p_event1 public.event_type, p_event2 public.event_type, p_tour_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
    	v_request_id INTEGER;
        v_event_group_id_1 INTEGER;
        v_event_group_id_2 INTEGER;
    BEGIN
    	CALL insert_request_ride_share(p_request, p_tour_id, v_request_id);
        CALL create_event_group(p_event1, v_event_group_id_1);
        CALL create_event_group(p_event2, v_event_group_id_2);
    	CALL insert_event(p_event1, v_request_id, v_event_group_id_1);
    	CALL insert_event(p_event2, v_request_id, v_event_group_id_2);
    	RETURN v_request_id;
    END;
    $$;


ALTER FUNCTION public.add_ride_share_request(p_request public.ride_share_request_type, p_event1 public.event_type, p_event2 public.event_type, p_tour_id integer) OWNER TO postgres;

--
-- Name: cancel_request(integer, integer, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancel_request(p_request_id integer, p_user_id integer, p_now bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    DECLARE
    	v_tour_id INTEGER;
    	v_all_requests_cancelled BOOLEAN;
    BEGIN
    	IF NOT EXISTS (
    	    SELECT 1
    			FROM request r
    	    WHERE r.customer = p_user_id
    			AND r.id = p_request_id
    	) THEN
    	    RETURN FALSE;
    	END IF;

    	IF (
    		SELECT communicated_time
    		FROM request r
    		JOIN event e ON r.id = e.request
    		WHERE r.id = p_request_id
    		ORDER BY e.communicated_time ASC
    		LIMIT 1
    	) <= p_now THEN
    		RETURN FALSE;
    	END IF;

    	UPDATE request r
    	SET cancelled = true
    	WHERE r.id = p_request_id;

    	SELECT tour INTO v_tour_id
    	FROM request
    	WHERE id = p_request_id;

    	SELECT bool_and(cancelled) INTO v_all_requests_cancelled
    	FROM request
    	WHERE tour = v_tour_id;

    	IF v_all_requests_cancelled THEN
    		UPDATE tour
    		SET cancelled = TRUE
    		WHERE id = v_tour_id;
    	END IF;

    	UPDATE event e
    	SET cancelled = TRUE
    	WHERE e.request = p_request_id;

    	RETURN v_all_requests_cancelled;
    END;
    $$;


ALTER FUNCTION public.cancel_request(p_request_id integer, p_user_id integer, p_now bigint) OWNER TO postgres;

--
-- Name: cancel_ride_share_request(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_ride_share_request(IN p_request_id integer, IN p_user_id integer)
    LANGUAGE plpgsql
    AS $$
    DECLARE
    	v_tour_id INTEGER;
    BEGIN
    	IF NOT EXISTS (
    	    SELECT 1
    			FROM request r
    	    WHERE r.customer = p_user_id
    			AND r.id = p_request_id
    	) THEN
    	    RETURN;
    	END IF;

    	UPDATE request r
    	SET cancelled = true
    	WHERE r.id = p_request_id;

    	UPDATE event e
    	SET cancelled = TRUE
    	WHERE e.request = p_request_id;
    END;
    $$;


ALTER PROCEDURE public.cancel_ride_share_request(IN p_request_id integer, IN p_user_id integer) OWNER TO postgres;

--
-- Name: cancel_ride_share_tour(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_ride_share_tour(IN p_tour_id integer, IN p_user_id integer)
    LANGUAGE plpgsql
    AS $$
        BEGIN
        	IF NOT EXISTS (
        	    SELECT 1
        	    FROM ride_share_tour t
        	    JOIN ride_share_vehicle v ON v.id = t.vehicle
        	    WHERE t.id = p_tour_id
        	    AND v.owner = p_user_id
        	) THEN
        	    RETURN;
        	END IF;

        	UPDATE ride_share_tour t
        	SET cancelled = TRUE
        	WHERE t.id = p_tour_id;

        	UPDATE request r
        	SET cancelled = TRUE
        	WHERE r.ride_share_tour = p_tour_id;

        	UPDATE event e
        	SET cancelled = TRUE
        	WHERE e.request IN (SELECT id FROM request WHERE ride_share_tour = p_tour_id);
        END;
        $$;


ALTER PROCEDURE public.cancel_ride_share_tour(IN p_tour_id integer, IN p_user_id integer) OWNER TO postgres;

--
-- Name: cancel_tour(integer, integer, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_tour(IN p_tour_id integer, IN p_company_id integer, IN p_message character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF NOT EXISTS (
	    SELECT 1
	    FROM tour t
	    JOIN vehicle v ON v.id = t.vehicle
	    WHERE t.id = p_tour_id
	    AND v.company = p_company_id
	) THEN
	    RETURN;
	END IF;

	UPDATE tour t
	SET cancelled = TRUE,
		message = p_message
	WHERE t.id = p_tour_id;

	UPDATE request r
	SET cancelled = TRUE
	WHERE r.tour = p_tour_id;

	UPDATE event e
	SET cancelled = TRUE
	WHERE e.request IN (SELECT id FROM request WHERE tour = p_tour_id);
END;
$$;


ALTER PROCEDURE public.cancel_tour(IN p_tour_id integer, IN p_company_id integer, IN p_message character varying) OWNER TO postgres;

--
-- Name: create_and_merge_tours(public.request_type, public.event_type, public.event_type, integer[], public.tour_type, public.direct_duration_type, public.direct_duration_type, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_and_merge_tours(p_request public.request_type, p_event1 public.event_type, p_event2 public.event_type, p_merge_tour_list integer[], p_tour public.tour_type, p_update_direct_duration_dropoff public.direct_duration_type, p_update_direct_duration_pickup public.direct_duration_type, p_update_scheduled_times jsonb, p_prev_leg_updates jsonb, p_next_leg_updates jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
    	v_request_id INTEGER;
    	v_tour_id INTEGER;
        v_event_group_id_1 INTEGER;
        v_event_group_id_2 INTEGER;
    BEGIN
    	CALL update_direct_duration(p_update_direct_duration_dropoff);
    	CALL update_next_leg_durations(p_next_leg_updates);
    	CALL update_prev_leg_durations(p_prev_leg_updates);
    	IF p_tour.id IS NULL THEN
    		CALL insert_tour(p_tour, v_tour_id);
    	ELSE
    		v_tour_id := p_tour.id;
    		CALL merge_tours(p_merge_tour_list, v_tour_id, p_tour.arrival, p_tour.departure);
    		CALL update_direct_duration(p_update_direct_duration_pickup);
    	END IF;
    	CALL insert_request(p_request, v_tour_id, v_request_id);
        
        IF p_event1.grp IS NULL THEN
            CALL create_event_group(p_event1, v_event_group_id_1);
        ELSE
            CALL update_event_group(p_event1);
            v_event_group_id_1 := p_event1.grp;
        END IF;
        IF p_event2.grp IS NULL THEN
            CALL create_event_group(p_event2, v_event_group_id_2);
        ELSE
            CALL update_event_group(p_event2);
            v_event_group_id_2 := p_event2.grp;
        END IF;
    	CALL insert_event(p_event1, v_request_id, v_event_group_id_1);
    	CALL insert_event(p_event2, v_request_id, v_event_group_id_2);

        CALL update_scheduled_times(p_update_scheduled_times);
    	RETURN v_request_id;
    END;
    $$;


ALTER FUNCTION public.create_and_merge_tours(p_request public.request_type, p_event1 public.event_type, p_event2 public.event_type, p_merge_tour_list integer[], p_tour public.tour_type, p_update_direct_duration_dropoff public.direct_duration_type, p_update_direct_duration_pickup public.direct_duration_type, p_update_scheduled_times jsonb, p_prev_leg_updates jsonb, p_next_leg_updates jsonb) OWNER TO postgres;

--
-- Name: create_event_group(public.event_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_event_group(IN p_event public.event_type, OUT v_event_group_id integer)
    LANGUAGE plpgsql
    AS $$
    BEGIN
        INSERT INTO event_group (
            lat, lng, scheduled_time_start, scheduled_time_end,
            address, prev_leg_duration, next_leg_duration
        )
        VALUES (
            p_event.lat, p_event.lng, p_event.scheduled_time_start, p_event.scheduled_time_end,
            p_event.address, p_event.prev_leg_duration, p_event.next_leg_duration
        )
        RETURNING id INTO v_event_group_id;
    END;
    $$;


ALTER PROCEDURE public.create_event_group(IN p_event public.event_type, OUT v_event_group_id integer) OWNER TO postgres;

--
-- Name: insert_event(public.event_type, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_event(IN p_event public.event_type, IN p_request_id integer, IN p_event_group integer)
    LANGUAGE plpgsql
    AS $$
    BEGIN
        INSERT INTO event (
            is_pickup, request, event_group_id, cancelled, communicated_time
        )
        VALUES (
            p_event.is_pickup, p_request_id, p_event_group, FALSE, p_event.communicated_time
        );
    END;
    $$;


ALTER PROCEDURE public.insert_event(IN p_event public.event_type, IN p_request_id integer, IN p_event_group integer) OWNER TO postgres;

--
-- Name: insert_request(public.request_type, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_request(IN p_request public.request_type, IN p_tour_id integer, OUT v_request_id integer)
    LANGUAGE plpgsql
    AS $$
                BEGIN
                    INSERT INTO request (passengers, wheelchairs, bikes, luggage, customer, tour, ticket_code, ticket_checked, ticket_price, cancelled, kids_zero_to_two, kids_three_to_four, kids_five_to_six, pending)
                    VALUES (p_request.passengers, p_request.wheelchairs, p_request.bikes, p_request.luggage, p_request.customer, p_tour_id, p_request.ticket_code, FALSE, p_request.ticket_price, FALSE, p_request.kids_zero_to_two, p_request.kids_three_to_four, p_request.kids_five_to_six, false)
                    RETURNING id INTO v_request_id;
                END;
                $$;


ALTER PROCEDURE public.insert_request(IN p_request public.request_type, IN p_tour_id integer, OUT v_request_id integer) OWNER TO postgres;

--
-- Name: insert_request_ride_share(public.ride_share_request_type, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_request_ride_share(IN p_request public.ride_share_request_type, IN p_tour_id integer, OUT v_request_id integer)
    LANGUAGE plpgsql
    AS $$
                BEGIN
                    INSERT INTO request (passengers, wheelchairs, bikes, luggage, customer, ride_share_tour, ticket_checked, cancelled, kids_zero_to_two, kids_three_to_four, kids_five_to_six, pending, bus_stop_time, requested_time, start_fixed, ticket_code)
                    VALUES (p_request.passengers, 0, 0, p_request.luggage, p_request.customer, p_tour_id, FALSE, FALSE, 0, 0, 0, true, p_request.bus_stop_time, p_request.requested_time, p_request.start_fixed, '')
                    RETURNING id INTO v_request_id;
                END;
                $$;


ALTER PROCEDURE public.insert_request_ride_share(IN p_request public.ride_share_request_type, IN p_tour_id integer, OUT v_request_id integer) OWNER TO postgres;

--
-- Name: insert_tour(public.tour_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_tour(IN p_tour public.tour_type, OUT v_tour_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
	INSERT INTO tour (departure, arrival, vehicle, fare, direct_duration, cancelled)
	VALUES (p_tour.departure, p_tour.arrival, p_tour.vehicle, NULL, p_tour.direct_duration, FALSE)
	RETURNING id INTO v_tour_id;
END;
$$;


ALTER PROCEDURE public.insert_tour(IN p_tour public.tour_type, OUT v_tour_id integer) OWNER TO postgres;

--
-- Name: merge_tours(integer[], integer, bigint, bigint); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.merge_tours(IN p_merge_tour_list integer[], IN p_target_tour_id integer, IN p_arrival bigint, IN p_departure bigint)
    LANGUAGE plpgsql
    AS $$
        BEGIN
        	UPDATE request
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
        $$;


ALTER PROCEDURE public.merge_tours(IN p_merge_tour_list integer[], IN p_target_tour_id integer, IN p_arrival bigint, IN p_departure bigint) OWNER TO postgres;

--
-- Name: update_direct_duration(public.direct_duration_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_direct_duration(IN p_direct_duration public.direct_duration_type)
    LANGUAGE plpgsql
    AS $$
		BEGIN
			UPDATE tour t
			SET direct_duration = p_direct_duration.duration
			WHERE t.id = p_direct_duration.tour_id;
		END;
		$$;


ALTER PROCEDURE public.update_direct_duration(IN p_direct_duration public.direct_duration_type) OWNER TO postgres;

--
-- Name: update_event(integer, public.event_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_event(IN p_id integer, IN p_event public.event_type)
    LANGUAGE plpgsql
    AS $$
     DECLARE
        grp integer;
        old_grp integer;
     BEGIN
        IF p_event.grp IS NOT NULL THEN
            grp := p_event.grp;
            old_grp := (
                SELECT event_group_id
                FROM event
                WHERE id = p_id
            );

            UPDATE event e
            SET event_group_id = grp
            WHERE e.id = p_id;

            UPDATE event_group eg
            SET prev_leg_duration = (
                SELECT prev_leg_duration
                FROM event_group
                WHERE id = old_grp
            )
            WHERE id = grp;

            UPDATE event_group eg
            SET next_leg_duration = (
                SELECT next_leg_duration
                FROM event_group
                WHERE id = old_grp
            )
            WHERE id = grp;

        ELSE
            SELECT event_group_id INTO grp
            FROM event
            WHERE id = p_id;
        END IF;

        UPDATE event_group eg
        SET scheduled_time_start = p_event.scheduled_time_start
        WHERE id = grp;

        UPDATE event_group eg
        SET scheduled_time_end = p_event.scheduled_time_end
        WHERE id = grp;
    END;
    $$;


ALTER PROCEDURE public.update_event(IN p_id integer, IN p_event public.event_type) OWNER TO postgres;

--
-- Name: update_event_group(public.event_type); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_event_group(IN p_event public.event_type)
    LANGUAGE plpgsql
    AS $$
    BEGIN
        UPDATE event_group e
        SET
            scheduled_time_start = p_event.scheduled_time_start,
            scheduled_time_end = p_event.scheduled_time_end
        WHERE e.id = p_event.grp;
    END;
    $$;


ALTER PROCEDURE public.update_event_group(IN p_event public.event_type) OWNER TO postgres;

--
-- Name: update_event_groups(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_event_groups(IN p_updates jsonb)
    LANGUAGE plpgsql
    AS $$
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
		$$;


ALTER PROCEDURE public.update_event_groups(IN p_updates jsonb) OWNER TO postgres;

--
-- Name: update_next_leg_durations(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_next_leg_durations(IN p_next_leg_durations jsonb)
    LANGUAGE plpgsql
    AS $$
        DECLARE
            v_duration BIGINT;
            v_item jsonb;
            v_event_id INTEGER;
        BEGIN
            IF jsonb_typeof(p_next_leg_durations) <> 'array' THEN
				RAISE EXCEPTION 'Input must be a JSON array';
			END IF;

			IF EXISTS (
				SELECT 1 
				FROM jsonb_array_elements(p_next_leg_durations) elem 
				WHERE NOT (
					elem ? 'event' 
					AND elem ? 'duration' 
					AND jsonb_typeof(elem->'event') = 'number' 
					AND jsonb_typeof(elem->'duration') = 'number'
				)
			) THEN
				RAISE EXCEPTION 'Each JSON object must contain "event" (integer) and "duration" (integer)';
			END IF;
            FOR v_item IN SELECT * FROM jsonb_array_elements(p_next_leg_durations)
            LOOP
                v_event_id := (v_item ->> 'event')::INTEGER;
                v_duration := (v_item ->> 'duration')::BIGINT;

                UPDATE event_group e
                SET next_leg_duration = v_duration
                WHERE id = (
                    SELECT event_group_id
                    FROM event
                    WHERE id = v_event_id
                );
            END LOOP;
        END;
        $$;


ALTER PROCEDURE public.update_next_leg_durations(IN p_next_leg_durations jsonb) OWNER TO postgres;

--
-- Name: update_prev_leg_durations(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_prev_leg_durations(IN p_prev_leg_durations jsonb)
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_duration BIGINT;
        v_item jsonb;
        v_event_id INTEGER;
    BEGIN
        IF jsonb_typeof(p_prev_leg_durations) <> 'array' THEN
			RAISE EXCEPTION 'Input must be a JSON array';
		END IF;

		IF EXISTS (
			SELECT 1 
			FROM jsonb_array_elements(p_prev_leg_durations) elem 
			WHERE NOT (
				elem ? 'event' 
				AND elem ? 'duration' 
				AND jsonb_typeof(elem->'event') = 'number' 
				AND jsonb_typeof(elem->'duration') = 'number'
			)
		) THEN
			RAISE EXCEPTION 'Each JSON object must contain "event" (integer) and "duration" (integer)';
		END IF;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_prev_leg_durations)
        LOOP
            v_event_id := (v_item ->> 'event')::INTEGER;
            v_duration := (v_item ->> 'duration')::BIGINT;
            UPDATE event_group e
            SET prev_leg_duration = v_duration
            WHERE id = (
                SELECT event_group_id
                FROM event
                WHERE id = v_event_id
            );
        END LOOP;
    END;
    $$;


ALTER PROCEDURE public.update_prev_leg_durations(IN p_prev_leg_durations jsonb) OWNER TO postgres;

--
-- Name: update_scheduled_times(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_scheduled_times(IN p_update_scheduled_times jsonb)
    LANGUAGE plpgsql
    AS $$
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
                    UPDATE event_group e
                    SET scheduled_time_start = v_time
                    WHERE id = (
                        SELECT event_group_id
                        FROM event
                        WHERE id = v_event_id
                    );
                ELSE
                    UPDATE event_group e
                    SET scheduled_time_end = v_time
                    WHERE id = (
                        SELECT event_group_id
                        FROM event
                        WHERE id = v_event_id
                    );
                END IF;
            END LOOP;
        END;
        $$;


ALTER PROCEDURE public.update_scheduled_times(IN p_update_scheduled_times jsonb) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: availability; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.availability (
    id integer NOT NULL,
    start_time bigint NOT NULL,
    end_time bigint NOT NULL,
    vehicle integer NOT NULL
);


ALTER TABLE public.availability OWNER TO postgres;

--
-- Name: availability_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.availability_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.availability_id_seq OWNER TO postgres;

--
-- Name: availability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.availability_id_seq OWNED BY public.availability.id;


--
-- Name: company; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company (
    id integer NOT NULL,
    lat real,
    lng real,
    name character varying,
    address character varying,
    zone integer,
    phone character varying
);


ALTER TABLE public.company OWNER TO postgres;

--
-- Name: company_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.company_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.company_id_seq OWNER TO postgres;

--
-- Name: company_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.company_id_seq OWNED BY public.company.id;


--
-- Name: event; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event (
    id integer NOT NULL,
    is_pickup boolean NOT NULL,
    communicated_time bigint NOT NULL,
    request integer NOT NULL,
    cancelled boolean NOT NULL,
    event_group_id integer NOT NULL
);


ALTER TABLE public.event OWNER TO postgres;

--
-- Name: event_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.event_group (
    id integer NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    scheduled_time_start bigint NOT NULL,
    scheduled_time_end bigint NOT NULL,
    prev_leg_duration integer NOT NULL,
    next_leg_duration integer NOT NULL,
    address character varying NOT NULL
);


ALTER TABLE public.event_group OWNER TO postgres;

--
-- Name: event_group_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.event_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.event_group_id_seq OWNER TO postgres;

--
-- Name: event_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.event_group_id_seq OWNED BY public.event_group.id;


--
-- Name: event_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.event_id_seq OWNER TO postgres;

--
-- Name: event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.event_id_seq OWNED BY public.event.id;


--
-- Name: fcm_token; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fcm_token (
    device_id character varying NOT NULL,
    company integer NOT NULL,
    fcm_token character varying NOT NULL
);


ALTER TABLE public.fcm_token OWNER TO postgres;

--
-- Name: journey; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.journey (
    id integer NOT NULL,
    json jsonb NOT NULL,
    "user" integer NOT NULL,
    request1 integer,
    request2 integer,
    rating integer,
    comment character varying,
    rating_booking integer,
    reason character varying
);


ALTER TABLE public.journey OWNER TO postgres;

--
-- Name: journey_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.journey_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.journey_id_seq OWNER TO postgres;

--
-- Name: journey_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.journey_id_seq OWNED BY public.journey.id;


--
-- Name: kysely_migration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kysely_migration (
    name character varying(255) NOT NULL,
    "timestamp" character varying(255) NOT NULL
);


ALTER TABLE public.kysely_migration OWNER TO postgres;

--
-- Name: kysely_migration_lock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kysely_migration_lock (
    id character varying(255) NOT NULL,
    is_locked integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.kysely_migration_lock OWNER TO postgres;

--
-- Name: request; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.request (
    id integer NOT NULL,
    passengers integer NOT NULL,
    kids_zero_to_two integer NOT NULL,
    kids_three_to_four integer NOT NULL,
    kids_five_to_six integer NOT NULL,
    wheelchairs integer NOT NULL,
    bikes integer NOT NULL,
    luggage integer NOT NULL,
    tour integer,
    customer integer NOT NULL,
    ticket_code character varying NOT NULL,
    ticket_checked boolean NOT NULL,
    cancelled boolean NOT NULL,
    ticket_price integer DEFAULT 0 NOT NULL,
    license_plate_updated_at bigint,
    created_at timestamp without time zone DEFAULT now(),
    ride_share_tour integer,
    start_fixed boolean,
    bus_stop_time bigint,
    requested_time bigint,
    pending boolean DEFAULT false NOT NULL
);


ALTER TABLE public.request OWNER TO postgres;

--
-- Name: request_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.request_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.request_id_seq OWNER TO postgres;

--
-- Name: request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.request_id_seq OWNED BY public.request.id;


--
-- Name: ride_share_rating; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_share_rating (
    id integer NOT NULL,
    rating integer NOT NULL,
    request integer NOT NULL,
    rated_is_customer boolean NOT NULL
);


ALTER TABLE public.ride_share_rating OWNER TO postgres;

--
-- Name: ride_share_rating_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_share_rating_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_share_rating_id_seq OWNER TO postgres;

--
-- Name: ride_share_rating_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_share_rating_id_seq OWNED BY public.ride_share_rating.id;


--
-- Name: ride_share_tour; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_share_tour (
    id integer NOT NULL,
    passengers integer,
    luggage integer,
    cancelled boolean NOT NULL,
    communicated_start bigint NOT NULL,
    communicated_end bigint NOT NULL,
    earliest_start bigint NOT NULL,
    latest_end bigint NOT NULL,
    vehicle integer NOT NULL
);


ALTER TABLE public.ride_share_tour OWNER TO postgres;

--
-- Name: ride_share_tour_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_share_tour_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_share_tour_id_seq OWNER TO postgres;

--
-- Name: ride_share_tour_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_share_tour_id_seq OWNED BY public.ride_share_tour.id;


--
-- Name: ride_share_vehicle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_share_vehicle (
    id integer NOT NULL,
    passengers integer NOT NULL,
    luggage integer NOT NULL,
    color character varying,
    model character varying,
    smoking_allowed boolean NOT NULL,
    license_plate character varying,
    owner integer NOT NULL,
    picture character varying
);


ALTER TABLE public.ride_share_vehicle OWNER TO postgres;

--
-- Name: ride_share_vehicle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_share_vehicle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_share_vehicle_id_seq OWNER TO postgres;

--
-- Name: ride_share_vehicle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_share_vehicle_id_seq OWNED BY public.ride_share_vehicle.id;


--
-- Name: ride_share_zone; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_share_zone (
    id integer NOT NULL,
    area public.geography(MultiPolygon,4326) NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.ride_share_zone OWNER TO postgres;

--
-- Name: ride_share_zone_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_share_zone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_share_zone_id_seq OWNER TO postgres;

--
-- Name: ride_share_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_share_zone_id_seq OWNED BY public.ride_share_zone.id;


--
-- Name: session; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.session (
    id character varying NOT NULL,
    expires_at bigint NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.session OWNER TO postgres;

--
-- Name: tour; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tour (
    id integer NOT NULL,
    departure bigint NOT NULL,
    arrival bigint NOT NULL,
    direct_duration integer,
    vehicle integer NOT NULL,
    fare integer,
    cancelled boolean NOT NULL,
    message character varying
);


ALTER TABLE public.tour OWNER TO postgres;

--
-- Name: tour_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tour_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tour_id_seq OWNER TO postgres;

--
-- Name: tour_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tour_id_seq OWNED BY public.tour.id;


--
-- Name: user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."user" (
    id integer NOT NULL,
    name character varying NOT NULL,
    email character varying,
    password_hash character varying NOT NULL,
    is_taxi_owner boolean NOT NULL,
    is_admin boolean NOT NULL,
    is_email_verified boolean DEFAULT false NOT NULL,
    email_verification_code character varying,
    email_verification_expires_at bigint,
    password_reset_code character varying,
    password_reset_expires_at bigint,
    phone character varying,
    company_id integer,
    is_service boolean DEFAULT false NOT NULL,
    first_name character varying DEFAULT ''::character varying NOT NULL,
    gender character varying,
    zip_code character varying DEFAULT ''::character varying NOT NULL,
    city character varying DEFAULT ''::character varying NOT NULL,
    region character varying DEFAULT ''::character varying NOT NULL,
    profile_picture character varying
);


ALTER TABLE public."user" OWNER TO postgres;

--
-- Name: user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_id_seq OWNER TO postgres;

--
-- Name: user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_id_seq OWNED BY public."user".id;


--
-- Name: vehicle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicle (
    id integer NOT NULL,
    license_plate character varying NOT NULL,
    company integer NOT NULL,
    passengers integer NOT NULL,
    wheelchairs integer NOT NULL,
    bikes integer NOT NULL,
    luggage integer NOT NULL
);


ALTER TABLE public.vehicle OWNER TO postgres;

--
-- Name: vehicle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vehicle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vehicle_id_seq OWNER TO postgres;

--
-- Name: vehicle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vehicle_id_seq OWNED BY public.vehicle.id;


--
-- Name: zone; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.zone (
    id integer NOT NULL,
    area public.geography(MultiPolygon,4326) NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.zone OWNER TO postgres;

--
-- Name: zone_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.zone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.zone_id_seq OWNER TO postgres;

--
-- Name: zone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.zone_id_seq OWNED BY public.zone.id;


--
-- Name: availability id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability ALTER COLUMN id SET DEFAULT nextval('public.availability_id_seq'::regclass);


--
-- Name: company id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company ALTER COLUMN id SET DEFAULT nextval('public.company_id_seq'::regclass);


--
-- Name: event id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event ALTER COLUMN id SET DEFAULT nextval('public.event_id_seq'::regclass);


--
-- Name: event_group id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_group ALTER COLUMN id SET DEFAULT nextval('public.event_group_id_seq'::regclass);


--
-- Name: journey id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey ALTER COLUMN id SET DEFAULT nextval('public.journey_id_seq'::regclass);


--
-- Name: request id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request ALTER COLUMN id SET DEFAULT nextval('public.request_id_seq'::regclass);


--
-- Name: ride_share_rating id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_rating ALTER COLUMN id SET DEFAULT nextval('public.ride_share_rating_id_seq'::regclass);


--
-- Name: ride_share_tour id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_tour ALTER COLUMN id SET DEFAULT nextval('public.ride_share_tour_id_seq'::regclass);


--
-- Name: ride_share_vehicle id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_vehicle ALTER COLUMN id SET DEFAULT nextval('public.ride_share_vehicle_id_seq'::regclass);


--
-- Name: ride_share_zone id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_zone ALTER COLUMN id SET DEFAULT nextval('public.ride_share_zone_id_seq'::regclass);


--
-- Name: tour id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tour ALTER COLUMN id SET DEFAULT nextval('public.tour_id_seq'::regclass);


--
-- Name: user id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user" ALTER COLUMN id SET DEFAULT nextval('public.user_id_seq'::regclass);


--
-- Name: vehicle id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle ALTER COLUMN id SET DEFAULT nextval('public.vehicle_id_seq'::regclass);


--
-- Name: zone id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zone ALTER COLUMN id SET DEFAULT nextval('public.zone_id_seq'::regclass);


--
-- Data for Name: availability; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.availability (id, start_time, end_time, vehicle) FROM stdin;
1	1770775200000	1770850800000	1
2	1770720300000	1770764400000	1
3	1770861600000	1770937200000	1
5	1771034400000	1771110000000	1
4	1771120800000	1771196400000	1
6	1771293600000	1771369200000	1
7	1770948000000	1771023600000	1
8	1771207200000	1771282800000	1
9	1771380000000	1771455600000	1
10	1771466400000	1771542000000	1
11	1771552800000	1771628400000	1
12	1771639200000	1771714800000	1
13	1771725600000	1771801200000	1
14	1771812000000	1771887600000	1
15	1771898400000	1771925744818	1
\.


--
-- Data for Name: company; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.company (id, lat, lng, name, address, zone, phone) FROM stdin;
1	51.493713	14.625855	Taxi Weißwasser	Werner-Seelenbinder-Straße 70A, 02943 Weißwasser/Oberlausitz	2	555-2342
2	51.532974	14.660599	Taxi Gablenz	Schulstraße 21, 02953 Gablenz	2	555-2342
3	51.38096	14.666578	Taxi Reichwalde	Robert-Koch-Straße 45, 02943 Boxberg/Oberlausitz	1	555-2342
4	51.30576	14.782109	Taxi Moholz	Postweg 10, 02906 Niesky	1	555-2342
5	51.302185	14.834551	Taxi Niesky	Trebuser Str. 4, 02906 Niesky	1	555-2342
6	51.321884	14.944467	Taxi Rothenburg	Zur Wasserscheide 37, 02929 Rothenburg/Oberlausitz	1	555-2342
7	51.166775	14.934901	Taxi Schöpstal	Ebersbacher Str. 43, 02829 Schöpstal	3	555-2342
8	51.129536	14.941331	Taxi Görlitz	Plantagenweg 3, 02827 Görlitz	3	555-2342
\.


--
-- Data for Name: event; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event (id, is_pickup, communicated_time, request, cancelled, event_group_id) FROM stdin;
19	t	1770911880000	10	t	19
20	f	1770914033850	10	t	20
17	t	1771188000000	9	t	17
18	f	1771188564899	9	t	18
7	t	1770865714000	4	t	7
8	f	1770866486800	4	t	8
21	t	1771597527900	11	t	21
22	f	1771600080000	11	t	22
29	t	1771450464419	15	t	29
30	f	1771453012419	15	t	30
15	t	1771702800000	8	t	15
16	f	1771705038900	8	t	16
25	t	1771666800000	13	t	25
26	f	1771667391900	13	t	26
55	t	1771592460000	28	t	55
56	f	1771593096450	28	t	56
11	t	1771236151616	6	t	11
12	f	1771238435066	6	t	12
69	t	1771826335190	35	t	69
70	f	1771828613240	35	t	70
61	t	1771647300000	31	t	61
62	f	1771651239899	31	t	62
33	t	1771011000000	17	t	33
34	f	1771011447450	17	t	34
75	t	1771061700000	38	t	75
76	f	1771062472800	38	t	76
9	t	1771847640000	5	t	9
10	f	1771848342600	5	t	10
43	t	1771576800000	22	t	43
44	f	1771577800949	22	t	44
65	t	1771727617818	33	t	65
66	f	1771728887418	33	t	66
91	t	1770930576750	46	t	91
92	f	1770930900000	46	t	92
95	t	1771104300000	48	f	95
96	f	1771105981000	48	f	96
51	t	1771424754301	26	t	51
52	f	1771425060000	26	t	52
23	t	1771048200000	12	t	23
24	f	1771048983600	12	t	24
101	t	1771134000000	51	f	101
102	f	1771134965849	51	f	102
103	t	1771214940000	52	t	103
104	f	1771216125900	52	t	104
77	t	1771186967251	39	t	77
78	f	1771187819701	39	t	78
39	t	1771130100000	20	t	39
40	f	1771131832650	20	t	40
31	t	1771200994649	16	t	31
32	f	1771203252449	16	t	32
107	t	1771439400000	54	f	107
108	f	1771441135350	54	f	108
49	t	1771903609000	25	t	49
50	f	1771905515000	25	t	50
13	t	1770954822300	7	t	13
14	f	1770956100000	7	t	14
109	t	1771573800000	55	t	109
110	f	1771577032500	55	t	110
71	t	1771335660000	36	t	71
57	t	1771663089328	29	t	57
58	f	1771665552328	29	t	58
35	t	1770872342251	18	t	35
36	f	1770873300000	18	t	36
63	t	1771332718051	32	t	63
64	f	1771333260000	32	t	64
113	t	1771318572150	57	t	113
114	f	1771319700000	57	t	114
89	t	1771912380000	45	t	89
90	f	1771912996200	45	t	90
59	t	1771088490781	30	t	59
60	f	1771089019230	30	t	60
5	t	1771445040000	3	t	5
6	f	1771445356500	3	t	6
1	t	1771739400000	1	t	1
2	f	1771741023300	1	t	2
97	t	1771412272248	49	t	97
67	t	1771740327240	34	t	67
68	f	1771743120240	34	t	68
87	t	1771039059000	44	t	87
88	f	1771041015000	44	t	88
81	t	1771532506950	41	t	81
82	f	1771532760000	41	t	82
117	t	1770879180000	59	t	117
85	t	1770840900000	43	t	85
86	f	1770842060250	43	t	86
115	t	1770906989537	58	t	115
116	f	1770910184537	58	t	116
41	t	1771161600000	21	t	41
42	f	1771164013050	21	t	42
37	t	1771560000000	19	t	37
38	f	1771560822750	19	t	38
47	t	1771206586871	24	t	47
93	t	1771766700000	47	t	93
94	f	1771768654049	47	t	94
99	t	1770782400000	50	t	99
100	f	1770783294300	50	t	100
3	t	1770964045200	2	t	3
4	f	1770964440000	2	t	4
53	t	1771270500000	27	t	53
54	f	1771272819900	27	t	54
83	t	1770747900000	42	t	83
84	f	1770748482450	42	t	84
79	t	1771152600000	40	t	79
80	f	1771155080550	40	t	80
105	t	1770870540000	53	t	105
106	f	1770870863250	53	t	106
45	t	1771690320000	23	t	45
111	t	1771387800000	56	t	111
112	f	1771390190100	56	t	112
27	t	1770907726650	14	t	27
28	f	1770908220000	14	t	28
73	t	1771396489050	37	t	73
74	f	1771397760000	37	t	74
123	t	1771340221501	62	f	123
124	f	1771341240000	62	f	124
129	t	1771875000000	65	f	129
130	f	1771877642550	65	f	130
72	f	1771336120950	36	t	72
139	t	1771216867651	70	f	139
140	f	1771218900000	70	f	140
141	t	1771622400000	71	f	141
142	f	1771624107000	71	f	142
143	t	1771095300000	72	f	143
144	f	1771097264849	72	f	144
159	t	1771602990900	80	f	159
160	f	1771603680000	80	f	160
167	t	1771181100000	84	f	167
168	f	1771182865050	84	f	168
145	t	1771185840000	73	t	145
146	f	1771186325250	73	t	146
98	f	1771414172297	49	t	98
165	t	1770742140000	83	t	165
166	f	1770743853750	83	t	166
183	t	1771838597250	92	f	183
184	f	1771839960000	92	f	184
179	t	1771741554240	90	t	179
180	f	1771743015240	90	t	180
155	t	1771653939756	78	t	155
156	f	1771656897756	78	t	156
161	t	1771471158749	81	t	161
162	f	1771473332849	81	t	162
163	t	1771400531101	82	t	163
164	f	1771402500000	82	t	164
118	f	1770880028400	59	t	118
147	t	1770882540000	74	t	147
148	f	1770884731650	74	t	148
215	t	1771243200000	108	f	215
216	f	1771245293100	108	f	216
213	t	1771211739000	107	t	213
214	f	1771213779651	107	t	214
177	t	1771669095175	89	t	177
178	f	1771671057324	89	t	178
175	t	1771107299073	88	t	175
176	f	1771107668223	88	t	176
189	t	1771732362297	95	t	189
190	f	1771734703797	95	t	190
225	t	1771843740000	113	f	225
226	f	1771845359250	113	f	226
131	t	1771008300000	66	t	131
132	f	1771011076200	66	t	132
207	t	1771169100000	104	t	207
208	f	1771170214350	104	t	208
171	t	1771516200000	86	t	171
172	f	1771517137500	86	t	172
229	t	1771173900000	115	f	229
230	f	1771174662000	115	f	230
127	t	1771793100000	64	t	127
128	f	1771794636900	64	t	128
231	t	1771823240400	116	t	231
203	t	1771791300000	102	t	203
204	f	1771792984000	102	t	204
133	t	1771358400000	67	t	133
134	f	1771360675350	67	t	134
195	t	1770792900000	98	t	195
205	t	1771485600000	103	t	205
206	f	1771486059600	103	t	206
181	t	1770927300000	91	t	181
182	f	1770929879100	91	t	182
223	t	1771237936300	112	t	223
224	f	1771240388500	112	t	224
209	t	1770756922000	105	t	209
210	f	1770760440000	105	t	210
173	t	1771621700857	87	t	173
174	f	1771623569856	87	t	174
121	t	1771881300000	61	t	121
122	f	1771882909800	61	t	122
227	t	1771056600000	114	t	227
199	t	1771189118125	100	t	199
200	f	1771190250025	100	t	200
149	t	1770750748000	75	t	149
150	f	1770753160000	75	t	150
201	t	1771664160000	101	t	201
202	f	1771664673599	101	t	202
221	t	1771273784000	111	t	221
222	f	1771275613000	111	t	222
211	t	1771652400000	106	t	211
212	f	1771652697599	106	t	212
193	t	1771304949600	97	t	193
194	f	1771308120000	97	t	194
217	t	1770977040000	109	t	217
218	f	1770978196200	109	t	218
191	t	1771419780000	96	t	191
192	f	1771420439400	96	t	192
153	t	1771460528376	77	t	153
151	t	1771045200000	76	t	151
152	f	1771047669750	76	t	152
125	t	1771594042500	63	t	125
126	f	1771595520000	63	t	126
187	t	1770843040000	94	t	187
188	f	1770844267750	94	t	188
185	t	1771577580000	93	t	185
186	f	1771578964350	93	t	186
157	t	1771590420000	79	t	157
158	f	1771590821550	79	t	158
119	t	1771746960000	60	t	119
120	f	1771747784100	60	t	120
137	t	1771128600000	69	t	137
138	f	1771131068400	69	t	138
197	t	1771702141000	99	t	197
198	f	1771704146349	99	t	198
169	t	1771702440000	85	t	169
135	t	1771566540000	68	t	135
136	f	1771569209550	68	t	136
241	t	1771188000000	121	f	241
242	f	1771190626350	121	f	242
243	t	1770839711400	122	f	243
244	f	1770840900000	122	f	244
247	t	1771605833900	124	f	247
248	f	1771606620000	124	f	248
232	f	1771824780000	116	t	232
239	t	1771562618000	120	t	239
240	f	1771563381000	120	t	240
196	f	1770793663350	98	t	196
259	t	1771700100000	130	f	259
260	f	1771700990250	130	f	260
48	f	1771209242921	24	t	48
261	t	1771689000000	131	f	261
262	f	1771689334050	131	f	262
255	t	1771233373451	128	t	255
256	f	1771235539000	128	t	256
265	t	1771137673000	133	f	265
266	f	1771139799000	133	f	266
269	t	1770961332600	135	f	269
270	f	1770962640000	135	f	270
271	t	1771562520000	136	t	271
272	f	1771562908050	136	t	272
257	t	1771823293504	129	t	257
258	f	1771824511804	129	t	258
235	t	1771430100016	118	t	235
236	f	1771433094016	118	t	236
233	t	1771347600000	117	t	233
234	f	1771348470000	117	t	234
277	t	1771840897250	139	f	277
278	f	1771842158750	139	f	278
281	t	1771740000000	141	f	281
282	f	1771742556150	141	f	282
263	t	1771489231393	132	t	263
264	f	1771490706193	132	t	264
285	t	1770953097000	143	f	285
286	f	1770954835000	143	f	286
289	t	1771156800000	145	f	289
290	f	1771158641999	145	f	290
228	f	1771058224650	114	t	228
291	t	1771298184000	146	f	291
292	f	1771299700000	146	f	292
293	t	1770928560000	147	f	293
294	f	1770929963250	147	f	294
295	t	1771586400000	148	f	295
296	f	1771588057000	148	f	296
299	t	1771566310650	150	f	299
300	f	1771568100000	150	f	300
237	t	1770918900000	119	t	237
238	f	1770920146650	119	t	238
287	t	1771409693909	144	t	287
288	f	1771412999309	144	t	288
311	t	1771524360000	156	f	311
312	f	1771524978900	156	f	312
275	t	1771560964992	138	t	275
276	f	1771562657142	138	t	276
317	t	1771363068600	159	f	317
318	f	1771365240000	159	f	318
319	t	1771511400000	160	f	319
320	f	1771515330449	160	f	320
321	t	1771391582000	161	f	321
322	f	1771393403000	161	f	322
323	t	1771817014000	162	f	323
324	f	1771818743000	162	f	324
327	t	1771867800000	164	f	327
328	f	1771871511749	164	f	328
329	t	1771617900000	165	f	329
330	f	1771618896899	165	f	330
154	f	1771461775026	77	t	154
283	t	1771654007015	142	t	283
284	f	1771656245915	142	t	284
309	t	1771683000000	155	t	309
310	f	1771683724200	155	t	310
301	t	1770945075276	151	t	301
302	f	1770948125526	151	t	302
331	t	1771234809392	166	t	331
332	f	1771239033392	166	t	332
303	t	1771899327224	152	t	303
304	f	1771900297123	152	t	304
339	t	1771497900000	170	f	339
340	f	1771498667400	170	f	340
341	t	1771696875000	171	f	341
342	f	1771698515000	171	f	342
325	t	1771268732400	163	t	325
307	t	1771822380000	154	t	307
308	f	1771823389049	154	t	308
267	t	1771695240000	134	t	267
268	f	1771696744500	134	t	268
333	t	1770989400000	167	t	333
249	t	1771879164000	125	t	249
250	f	1771880220000	125	t	250
279	t	1771829100000	140	t	279
280	f	1771829457000	140	t	280
315	t	1771001062051	158	t	315
316	f	1771002900000	158	t	316
305	t	1771038939000	153	t	305
306	f	1771039629450	153	t	306
245	t	1771846790000	123	t	245
246	f	1771848110000	123	t	246
273	t	1770983940000	137	t	273
274	f	1770984723600	137	t	274
297	t	1770782400000	149	t	297
298	f	1770782757000	149	t	298
337	t	1771906500000	169	t	337
338	f	1771907460449	169	t	338
253	t	1771230366451	127	t	253
254	f	1771230660000	127	t	254
251	t	1771390759000	126	t	251
252	f	1771391989000	126	t	252
335	t	1771918659750	168	t	335
336	f	1771920900000	168	t	336
343	t	1771850535827	172	t	343
344	f	1771852942127	172	t	344
355	t	1770818424600	178	f	355
356	f	1770819300000	178	f	356
357	t	1771732200000	179	f	357
358	f	1771734301200	179	f	358
363	t	1771343178501	182	f	363
364	f	1771346128000	182	f	364
326	f	1771269300000	163	t	326
347	t	1771448336851	174	t	347
348	f	1771449300000	174	t	348
371	t	1771356600000	186	f	371
372	f	1771357704900	186	f	372
361	t	1771200792008	181	t	361
362	f	1771204170008	181	t	362
373	t	1771674900000	187	f	373
374	f	1771675315050	187	f	374
377	t	1771062480000	189	f	377
378	f	1771063239300	189	f	378
379	t	1771447500000	190	f	379
380	f	1771449940050	190	f	380
383	t	1771573510650	192	f	383
384	f	1771575300000	192	f	384
353	t	1771003849051	177	t	353
354	f	1771005647000	177	t	354
387	t	1771760433000	194	f	387
388	f	1771760910150	194	f	388
389	t	1771007100000	195	f	389
390	f	1771007930850	195	f	390
395	t	1770929907000	198	f	395
396	f	1770931801000	198	f	396
219	t	1771581851250	110	t	219
220	f	1771582080000	110	t	220
401	t	1770958620000	201	f	401
402	f	1770959821600	201	f	402
407	t	1770782911000	204	f	407
408	f	1770784896000	204	f	408
405	t	1770777890289	203	t	405
406	f	1770779649939	203	t	406
385	t	1770933509759	193	t	385
386	f	1770935372008	193	t	386
411	t	1771141740000	206	f	411
412	f	1771143657599	206	f	412
413	t	1770891159450	207	f	413
414	f	1770892560000	207	f	414
415	t	1770993600000	208	f	415
416	f	1770996318150	208	f	416
391	t	1770888952658	196	t	391
392	f	1770890064308	196	t	392
421	t	1770751500000	211	f	421
422	f	1770753130050	211	f	422
423	t	1771187100000	212	f	423
424	f	1771187788000	212	f	424
367	t	1771902540072	184	t	367
368	f	1771904326722	184	t	368
425	t	1770866177000	213	f	425
426	f	1770867770000	213	f	426
334	f	1770989724600	167	t	334
419	t	1770959805715	210	t	419
420	f	1770961599115	210	t	420
429	t	1771767600000	215	f	429
430	f	1771770139950	215	f	430
439	t	1771220340000	220	f	439
440	f	1771220694300	220	f	440
403	t	1770878400000	202	t	403
404	f	1770879457649	202	t	404
451	t	1771506060000	226	f	451
452	f	1771507540200	226	f	452
433	t	1771098383000	217	t	433
437	t	1770962980865	219	t	437
438	f	1770963412115	219	t	438
449	t	1770897981325	225	t	449
450	f	1770900946525	225	t	450
365	t	1771147500000	183	t	365
366	f	1771148433450	183	t	366
375	t	1771278680558	188	t	375
376	f	1771281087558	188	t	376
409	t	1771523063454	205	t	409
410	f	1771524264204	205	t	410
457	t	1771889259863	229	t	457
445	t	1771548551193	223	t	445
446	f	1771549931493	223	t	446
359	t	1770968100000	180	t	359
360	f	1770968843100	180	t	360
435	t	1771431300000	218	t	435
399	t	1771304400000	200	t	399
400	f	1771305989550	200	t	400
351	t	1771536600000	176	t	351
352	f	1771537638749	176	t	352
427	t	1771752840000	214	t	427
428	f	1771754193300	214	t	428
345	t	1771905300000	173	t	345
346	f	1771906308000	173	t	346
443	t	1771178100000	222	t	443
444	f	1771179492450	222	t	444
397	t	1770822900000	199	t	397
398	f	1770823416299	199	t	398
381	t	1771758600000	191	t	381
382	f	1771760759250	191	t	382
417	t	1771086600000	209	t	417
393	t	1771779354300	197	t	393
394	f	1771780200000	197	t	394
441	t	1771579200000	221	t	441
442	f	1771580623500	221	t	442
455	t	1771709100000	228	t	455
456	f	1771709855250	228	t	456
349	t	1770904140000	175	t	349
350	f	1770905616650	175	t	350
453	t	1771235340000	227	t	453
454	f	1771237484400	227	t	454
369	t	1771016400000	185	t	369
370	f	1771018019250	185	t	370
447	t	1771331184055	224	t	447
448	f	1771333594405	224	t	448
465	t	1770987510000	233	f	465
466	f	1770989499000	233	f	466
434	f	1771100702000	217	t	434
467	t	1771610100000	234	f	467
468	f	1771612665600	234	f	468
469	t	1771531680000	235	f	469
470	f	1771532054550	235	f	470
471	t	1770799740000	236	f	471
472	f	1770801726449	236	f	472
475	t	1770791836651	238	f	475
476	f	1770793680000	238	f	476
479	t	1771851000000	240	f	479
480	f	1771853716800	240	f	480
483	t	1771656000000	242	f	483
484	f	1771656717450	242	f	484
485	t	1771470950000	243	f	485
486	f	1771473298000	243	f	486
489	t	1771735800000	245	t	489
490	f	1771737920000	245	t	490
493	t	1771861038000	247	f	493
494	f	1771861612350	247	f	494
495	t	1771425600000	248	f	495
496	f	1771427408250	248	f	496
499	t	1771764960000	250	f	499
500	f	1771765812450	250	f	500
458	f	1771891033013	229	t	458
473	t	1770895800000	237	t	473
474	f	1770897203250	237	t	474
503	t	1771790400000	252	f	503
504	f	1771793844450	252	f	504
487	t	1771627196000	244	t	487
488	f	1771629627000	244	t	488
507	t	1771828800000	254	f	507
508	f	1771831221150	254	f	508
313	t	1771039883000	157	t	313
314	f	1771042050000	157	t	314
511	t	1770789480000	256	f	511
512	f	1770789934200	256	f	512
509	t	1771265793760	255	t	509
510	f	1771267068760	255	t	510
459	t	1771254900000	230	t	459
460	f	1771255828050	230	t	460
519	t	1770912300000	260	f	519
520	f	1770914727900	260	f	520
523	t	1771001575050	262	f	523
524	f	1771002900000	262	f	524
525	t	1770746760000	263	f	525
526	f	1770748414350	263	f	526
501	t	1771155184333	251	t	501
502	f	1771157548783	251	t	502
436	f	1771432742400	218	t	436
481	t	1771512881417	241	t	481
482	f	1771514971817	241	t	482
527	t	1771872952803	264	t	527
528	f	1771874624703	264	t	528
531	t	1771491300000	266	f	531
532	f	1771493120400	266	f	532
515	t	1770997691484	258	t	515
516	f	1770999985734	258	t	516
517	t	1771755768000	259	t	517
518	f	1771756860000	259	t	518
535	t	1771514616000	268	f	535
536	f	1771516384000	268	f	536
537	t	1770754690000	269	f	537
538	f	1770757293000	269	f	538
543	t	1771514221789	272	t	543
544	f	1771515437389	272	t	544
539	t	1771863204000	270	f	539
540	f	1771864828000	270	f	540
497	t	1771575966451	249	t	497
498	f	1771576260000	249	t	498
545	t	1770997979000	273	f	545
546	f	1770999560000	273	f	546
463	t	1771860420000	232	t	463
464	f	1771860855300	232	t	464
541	t	1771811442922	271	t	541
542	f	1771812694972	271	t	542
553	t	1771665960000	277	f	553
554	f	1771666323750	277	f	554
555	t	1771568478650	278	f	555
556	f	1771570009000	278	f	556
557	t	1771683060000	279	f	557
558	f	1771684804800	279	f	558
513	t	1771204302819	257	t	513
514	f	1771207313819	257	t	514
529	t	1771745899050	265	t	529
530	f	1771746360000	265	t	530
505	t	1771749086000	253	t	505
506	f	1771751473000	253	t	506
477	t	1771907750000	239	t	477
478	f	1771908148850	239	t	478
559	t	1771643868000	280	f	559
560	f	1771645707000	280	f	560
561	t	1771041600000	281	f	561
562	f	1771044432900	281	f	562
563	t	1771330200000	282	f	563
564	f	1771330740599	282	f	564
547	t	1771101779143	274	t	547
548	f	1771103884393	274	t	548
567	t	1771249260000	284	f	567
568	f	1771250090850	284	f	568
533	t	1771610647000	267	t	533
534	f	1771612215000	267	t	534
491	t	1771580592000	246	t	491
492	f	1771583047000	246	t	492
549	t	1771708500000	275	t	549
550	f	1771708910000	275	t	550
565	t	1771582476428	283	t	565
566	f	1771584626228	283	t	566
521	t	1771913400000	261	t	521
522	f	1771915961550	261	t	522
571	t	1770842502400	286	f	571
572	f	1770844414000	286	f	572
569	t	1771134598390	285	t	569
570	f	1771136044840	285	t	570
575	t	1771178476500	288	f	575
576	f	1771178820000	288	f	576
577	t	1771148400000	289	f	577
578	f	1771149519750	289	f	578
46	f	1771691167050	23	t	46
573	t	1771419720283	287	t	573
574	f	1771420753632	287	t	574
461	t	1771529143029	231	t	461
462	f	1771529444678	231	t	462
418	f	1771088617499	209	t	418
581	t	1771488486300	291	f	581
582	f	1771488900000	291	f	582
585	t	1771441865000	293	f	585
586	f	1771442694000	293	f	586
587	t	1771849464450	294	f	587
588	f	1771849920000	294	f	588
593	t	1771048800000	297	f	593
594	f	1771049682150	297	f	594
583	t	1771067347878	292	t	583
584	f	1771069742878	292	t	584
595	t	1771146632400	298	f	595
596	f	1771147740000	298	f	596
597	t	1771052400000	299	f	597
598	f	1771056239999	299	f	598
599	t	1770922680000	300	f	599
600	f	1770924833850	300	f	600
551	t	1771706700000	276	t	551
552	f	1771707966000	276	t	552
591	t	1771052463094	296	t	591
592	f	1771053535594	296	t	592
605	t	1771167300000	303	f	605
606	f	1771168724850	303	f	606
607	t	1771499432000	304	f	607
608	f	1771501455000	304	f	608
609	t	1770893020450	305	f	609
610	f	1770894480000	305	f	610
617	t	1770780191000	309	f	617
618	f	1770781560000	309	f	618
619	t	1770882540000	310	f	619
620	f	1770884716800	310	f	620
621	t	1771601400000	311	f	621
622	f	1771602162900	311	f	622
623	t	1771332981450	312	f	623
624	f	1771333680000	312	f	624
601	t	1771571516509	301	t	601
602	f	1771573466508	301	t	602
625	t	1771310100000	313	f	625
626	f	1771311564000	313	f	626
615	t	1771560300000	308	t	615
616	f	1771562210000	308	t	616
589	t	1771294952848	295	t	589
590	f	1771297380748	295	t	590
629	t	1771475091000	315	f	629
630	f	1771476426750	315	f	630
631	t	1771407900000	316	f	631
632	f	1771409100750	316	f	632
635	t	1771245082000	318	f	635
636	f	1771247044000	318	f	636
637	t	1771825859701	319	f	637
638	f	1771826160000	319	f	638
603	t	1771414594798	302	t	603
604	f	1771414861348	302	t	604
633	t	1771133411363	317	t	633
634	f	1771135454512	317	t	634
643	t	1770826200000	322	f	643
644	f	1770828083849	322	f	644
611	t	1771367609793	306	t	611
612	f	1771369837893	306	t	612
431	t	1770901260000	216	t	431
432	f	1770901648050	216	t	432
645	t	1771336287000	323	f	645
646	f	1771337400000	323	f	646
649	t	1770956904200	325	f	649
650	f	1770959240300	325	f	650
651	t	1771086000000	326	f	651
652	f	1771088345550	326	f	652
613	t	1771899433953	307	t	613
614	f	1771900632003	307	t	614
653	t	1770896329450	327	f	653
654	f	1770898057000	327	f	654
639	t	1770870661489	320	t	639
640	f	1770872076889	320	t	640
657	t	1771821121000	329	f	657
658	f	1771823280000	329	f	658
647	t	1771650510253	324	t	647
648	f	1771651562502	324	t	648
641	t	1771785413226	321	t	641
642	f	1771785767526	321	t	642
579	t	1771667672000	290	t	579
580	f	1771668045200	290	t	580
170	f	1771703704200	85	t	170
661	t	1771879200000	331	f	661
662	f	1771879995750	331	f	662
663	t	1771240700250	332	f	663
664	f	1771242360000	332	f	664
665	t	1771903343000	333	f	665
666	f	1771904958000	333	f	666
667	t	1770968580000	334	f	667
668	f	1770970049400	334	f	668
669	t	1771432800000	335	f	669
670	f	1771433416200	335	f	670
671	t	1770918540000	336	f	671
672	f	1770919979700	336	f	672
675	t	1770971122650	338	f	675
676	f	1770971400000	338	f	676
655	t	1770973509193	328	t	655
627	t	1771631624683	314	t	627
628	f	1771633728583	314	t	628
673	t	1771798599443	337	t	673
674	f	1771799558542	337	t	674
659	t	1771401296129	330	t	659
660	f	1771404404429	330	t	660
656	f	1770975287743	328	t	656
679	t	1771519560000	340	f	679
680	f	1771521025350	340	f	680
681	t	1771150628081	341	f	681
682	f	1771152356681	341	f	682
683	t	1771651500000	342	f	683
684	f	1771653246150	342	f	684
685	t	1771322514900	343	f	685
686	f	1771322880000	343	f	686
677	t	1771854402922	339	t	677
678	f	1771855794022	339	t	678
687	t	1770972960000	344	f	687
688	f	1770975610650	344	f	688
689	t	1770726730200	345	f	689
690	f	1770728880000	345	f	690
691	t	1770803880000	346	f	691
692	f	1770804493500	346	f	692
693	t	1771523176000	347	f	693
694	f	1771525980000	347	f	694
695	t	1771917600000	348	f	695
696	f	1771918472700	348	f	696
697	t	1771581466950	349	f	697
698	f	1771582800000	349	f	698
699	t	1771353360000	350	f	699
700	f	1771354618800	350	f	700
701	t	1771777200000	351	f	701
702	f	1771778549250	351	f	702
703	t	1771584338950	352	f	703
704	f	1771584900000	352	f	704
\.


--
-- Data for Name: event_group; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event_group (id, lat, lng, scheduled_time_start, scheduled_time_end, prev_leg_duration, next_leg_duration, address) FROM stdin;
1	51.5298098	14.6666151	1771739400000	1771739460000	539000	1158000	Krauschwitzer Weg 20
2	51.5405733	14.520827	1771740618000	1771741023300	1158000	1117000	Thälmann-Siedlung 25
4	51.348580999999996	14.590756	1770964353200	1770964440000	248000	1496000	Klitten Bahnhof
5	51.362845	14.509056000000001	1771445040000	1771445100000	1328000	190000	Uhyst (Spree) Bahnhof
6	51.3514095	14.5160213	1771445290000	1771445356500	190000	1518000	Spreeteich Uhyst
7	51.5296686	14.5991695	1770865714000	1770865774000	514000	528000	Halbendorfer Weg 60
8	51.533173	14.529221	1770866302000	1770866486800	528000	1013000	Mühlroser Straße 8a
9	51.506547	14.628111999999998	1771847640000	1771847700000	254000	476000	Weißwasser Mühlenstraße
10	51.4760082	14.6481188	1771848176000	1771848342600	476000	265000	Jagenstein 88+89+104+105
11	51.5341111	14.5351491	1771236151616	1771236211616	0	1647000	Schleifer Straße 3
12	51.3455839	14.6431287	1771237858616	1771238435066	1647000	0	Neudorfer Weg 1
13	51.4753327	14.7051496	1770954822300	1770954882300	789000	902000	Bresina - Brězyna
14	51.505442	14.638026999999997	1770955784300	1770956100000	902000	313000	Weißwasser Bahnhof
15	51.5342031	14.5217853	1771702800000	1771702860000	949000	1614000	Neustädter Straße 10
16	51.4021021	14.6410198	1771704474000	1771705038900	1614000	1097000	Schadendorf - Pakosnica
17	51.505442	14.638026999999997	1771188000000	1771188060000	292000	374000	Weißwasser Bahnhof
18	51.5090476	14.6057218	1771188434000	1771188564899	374000	431000	Tiergartenstraße 52
19	51.52533000000001	14.727186999999999	1770911880000	1770911940000	709000	1551000	Krauschwitz Obermühle
20	51.4226514	14.933801	1770913491000	1770914033850	1551000	1985000	Tränkeberg
21	51.3269674	14.6348337	1771597527900	1771597587900	2005000	1846000	Heuhotel Ferienhof Erlengrund
22	51.505888	14.479387000000001	1771599433900	1771600080000	1846000	1274000	Mulkwitz Außenkippe
23	51.5405556	14.5920921	1771048200000	1771048260000	599000	536000	Halbendorf (b Weißwasser) Bahnhofstraße
24	51.5305303	14.5320261	1771048796000	1771048983600	536000	949000	Rohner Weg 10
25	51.505442	14.638026999999997	1771666800000	1771666860000	292000	394000	Weißwasser Bahnhof
26	51.5175914	14.6370604	1771667254000	1771667391900	394000	581000	Qualisch Ost 17
27	51.5392554	14.6923251	1770907726650	1770907786650	692000	321000	Richard-Wagner-Straße 124
28	51.53425	14.663793	1770908107650	1770908220000	321000	581000	Gablenz Feuerwehr
29	51.5292289	14.5391334	1771450464419	1771450524419	0	1888000	Rohner Weg 3
30	51.3740326	14.6050458	1771452412419	1771453012419	1888000	0	Teichweg 4
31	51.5292355	14.5213952	1771200994649	1771201054649	0	1628000	Gefallenendenkmale Rohne
32	51.3269569	14.4965347	1771202682649	1771203252449	1628000	0	Grenzstein 91 KS/KP
33	51.5417264	14.5348536	1771011000000	1771011060000	923000	287000	Gemeindeamt
34	51.5394742	14.5159274	1771011347000	1771011447450	287000	1113000	Hoyerswerdaer Straße 94
35	51.4477017	14.6874532	1770872342251	1770872402251	408000	665000	Jungfernberge
36	51.505442	14.638026999999997	1770873067251	1770873300000	665000	313000	Weißwasser Bahnhof
37	51.5364085	14.524572	1771560000000	1771560060000	1023000	565000	Jahnring 5b
39	51.5357022	14.6852047	1771130100000	1771130160000	721000	1239000	Seeteich
40	51.5292289	14.5391334	1771131399000	1771131832650	1239000	895000	Rohner Weg 3
41	51.3451099	14.5934969	1771161600000	1771161660000	1510000	1743000	Halbendorfer Straße 221b
42	51.5305303	14.5320261	1771163403000	1771164013050	1743000	949000	Rohner Weg 10
43	51.505442	14.638026999999997	1771576800000	1771576860000	292000	697000	Weißwasser Bahnhof
44	51.5054342	14.7259846	1771577557000	1771577800949	697000	679000	Hammerstraße 23
46	51.508491	14.6746671	1771690963000	1771691167050	583000	579000	Am Braunsteich 6
47	51.3720677	14.5175614	1771206586871	1771206646871	0	1923000	2.3
48	51.5400866	14.5128586	1771208569871	1771209242921	1923000	0	Hoyerswerdaer Straße 98
49	51.3478918	14.5760464	1771903609000	1771903669000	1609000	1715000	Heidestraße 380
50	51.5342031	14.5217853	1771905384000	1771905515000	1715000	1009000	Neustädter Straße 10
51	51.5292355	14.5213952	1771424754301	1771424814301	1019000	182000	Gefallenendenkmale Rohne
52	51.53534500000001	14.530609	1771424996301	1771425060000	182000	964000	Schleife Bahnhof
53	51.5292355	14.5213952	1771270500000	1771270560000	1019000	1674000	Gefallenendenkmale Rohne
54	51.4853134	14.6120677	1771272234000	1771272819900	1674000	695000	Weißwasser Schwerer Berg
55	51.365159000000006	14.509355	1771592460000	1771592520000	1372000	427000	Uhyst (Spree) Gaststätte
56	51.3699395	14.5123155	1771592947000	1771593096450	427000	1686000	Volkspark Uhyst
57	51.5106667	14.7023512	1771663089328	1771663149328	0	1803000	Sanddeponie Keulahütte
58	51.5433114	14.5309437	1771664952328	1771665552328	1803000	0	Hoyerswerdaer Straße 33
59	51.5571805	14.5512115	1771088490781	1771088550781	0	347000	Groß-Dübener Weg 16
60	51.5345327	14.5239956	1771088897781	1771089019230	347000	0	Neustädter Straße 7
61	51.4496704	14.7311198	1771647300000	1771647360000	1850000	2874000	Goldberge
62	51.5295517	14.5240575	1771650234000	1771651239899	2874000	1147000	Tischlereiweg 115a
63	51.5067774	14.67079	1771332718051	1771332778051	533000	357000	Waldhaus
64	51.505798000000006	14.642610999999999	1771333135051	1771333260000	357000	296000	Weißwasser Stadtzentrum
65	51.508427	14.6401472	1771727617818	1771727677818	0	896000	Jahnstraße 5
66	51.5342031	14.5217853	1771728573818	1771728887418	896000	0	Neustädter Straße 10
69	51.5418744	14.537528	1771826335190	1771826395190	0	1643000	Friedensstraße 77a
70	51.3843827	14.6822273	1771828038190	1771828613240	1643000	0	Reichwalde Ausbau
71	51.535121000000004	14.529001	1771335660000	1771335720000	948000	297000	Schleife Busbahnhof
72	51.5343123	14.5136158	1771336017000	1771336120950	297000	1183000	Forstweg 78a
73	51.5456749	14.5346691	1771396489050	1771396549050	914000	897000	Spremberger Straße 17
74	51.505396000000005	14.639304999999998	1771397446050	1771397760000	897000	303000	Weißwasser Bahnhof
75	51.5232172	14.5984696	1771061700000	1771061760000	521000	528000	Feuerlöschwasser.
76	51.5393992	14.5316092	1771062288000	1771062472800	528000	985000	Strugaaue 2
38	51.5435	14.5619892	1771560625000	1771560625000	565000	1993000	Station 15
3	51.3325791	14.5518154	1770964105000	1770964105200	1465000	248000	Grenzstein 79 KP
77	51.5330493	14.6119875	1771186967251	1771187027251	0	587000	Katzenberg
78	51.5388861	14.5189616	1771187614251	1771187819701	587000	0	Zum Sportplatz 5
79	51.5301599	14.5247083	1771152600000	1771152660000	1097000	1793000	Tischlereiweg 113b
80	51.3807459	14.6547693	1771154453000	1771155080550	1793000	1579000	Mittelweg 22
81	51.5338793	14.5202632	1771532506950	1771532566950	957000	143000	Grenzweg 106c
82	51.53543200000001	14.532100999999999	1771532709950	1771532760000	143000	1020000	Schleife Bahnhof
83	51.541743	14.5826338	1770747900000	1770747960000	644000	387000	Halbendorfer See
84	51.5416387	14.5289058	1770748347000	1770748482450	387000	1032000	Lindenweg 20
85	51.4372936	14.5272309	1770840900000	1770840960000	1042000	815000	Hundewiese
86	51.528762	14.5279248	1770841775000	1770842060250	815000	973000	Trebendorfer Weg 116c
87	51.5399955	14.5160315	1771039059000	1771039119000	1059000	1815000	Hoyerswerdaer Straße 90
88	51.5011183	14.7601445	1771040934000	1771041015000	1815000	884000	Brandstraße 10
89	51.545089	14.577663	1771912380000	1771912440000	704000	412000	Halbendorf (b Weißwasser) Mitte
90	51.5292355	14.5213952	1771912852000	1771912996200	412000	1079000	Gefallenendenkmale Rohne
91	51.5015741	14.6486838	1770930576750	1770930636750	321000	195000	Görlitzer Straße 40
92	51.505442	14.638026999999997	1770930831750	1770930900000	195000	313000	Weißwasser Bahnhof
93	51.5431772	14.7102351	1771766700000	1771766760000	857000	1403000	Richard-Wagner-Straße 19a
94	51.5446031	14.5355952	1771768163000	1771768654049	1403000	1038000	Schleife - Slepo
95	51.5433114	14.5309437	1771104300000	1771104360000	958000	1296000	Hoyerswerdaer Straße 33
96	51.4884283	14.6723274	1771105656000	1771105981000	1296000	419000	Pumpstation
97	51.5393992	14.5316092	1771412272248	1771412332248	0	1363000	Strugaaue 2
98	51.3569031	14.6075622	1771413695248	1771414172297	1363000	0	Zum Jahnsportplatz 82d
99	51.5689853	14.554928	1770782400000	1770782460000	1066000	618000	Schützenverein Groß Düben
100	51.5353088	14.5289849	1770783078000	1770783294300	618000	999000	Siedlung - Sydlišćo
101	51.5506831	14.5893889	1771134000000	1771134060000	802000	671000	Edelstraße 73
102	51.5343123	14.5136158	1771134731000	1771134965849	671000	1183000	Forstweg 78a
103	51.508303000000005	14.644146999999998	1771214940000	1771215000000	278000	834000	Weißwasser Straße des Friedens
104	51.516883	14.7498293	1771215834000	1771216125900	834000	795000	Hüttenstraße 1
105	51.53537800000001	14.530662999999999	1770870540000	1770870600000	904000	195000	Schleife Bahnhof
106	51.5426918	14.5308026	1770870795000	1770870863250	195000	1059000	Hoyerswerdaer Straße 37
107	51.5435594	14.5297765	1771439400000	1771439460000	996000	1241000	Alter Postweg 11
108	51.473238	14.6478236	1771440701000	1771441135350	1241000	284000	Jagenstein 88+89+104+105
109	51.5296246	14.5237337	1771573800000	1771573860000	1075000	2350000	Tischlereiweg 115a
110	51.4802166	14.9049549	1771576210000	1771577032500	2350000	1398000	Königshügel 36
111	51.3687208	14.5188148	1771387800000	1771387860000	1605000	1726000	2.3
113	51.5213658	14.7562811	1771318572150	1771318632150	678000	791000	Unterdorf 98
114	51.505442	14.638026999999997	1771319423150	1771319700000	791000	313000	Weißwasser Bahnhof
115	51.4408653	14.9645881	1770906989537	1770907049537	0	2535000	Schimpelberg
116	51.5394742	14.5159274	1770909584537	1770910184537	2535000	0	Hoyerswerdaer Straße 94
117	51.365159000000006	14.509355	1770879180000	1770879240000	1372000	584000	Uhyst (Spree) Gaststätte
121	51.5158294	14.6053879	1771881300000	1771881360000	780000	1148000	Halbendorfer Weg 25
122	51.5435594	14.5297765	1771882508000	1771882909800	1148000	1057000	Alter Postweg 11
123	51.3509265	14.6252181	1771340221501	1771340281501	1671000	710000	Ernst-Thälmann-Straße 98
124	51.384587999999994	14.617674	1771340991501	1771341240000	710000	1210000	Kringelsdorf Waage
125	51.4486748	14.7390955	1771594042500	1771594102500	968000	1050000	Goldberge
126	51.507358	14.644218999999998	1771595152500	1771595520000	1050000	321000	Weißwasser Muskauer Straße
128	51.5182948	14.6529272	1771794254000	1771794636900	1094000	455000	Landzunge
129	51.3618776	14.5700344	1771875000000	1771875060000	1706000	1913000	3.2
130	51.5290227	14.5298561	1771876973000	1771877642550	1913000	956000	Rohner Weg 17
131	51.5418744	14.537528	1771008300000	1771008360000	911000	2012000	Friedensstraße 77a
132	51.3178498	14.5917742	1771010372000	1771011076200	2012000	1867000	Grenzstein 76 KS/KP
133	51.3596579	14.4729124	1771358400000	1771358460000	1599000	1641000	Untere Drehnaer Teiche
134	51.5312432	14.5115818	1771360101000	1771360675350	1641000	1086000	Mühlweg 5b
135	51.505849	14.479243	1771566540000	1771566600000	1215000	1933000	Mulkwitz Außenkippe
136	51.3438222	14.4817038	1771568533000	1771569209550	1933000	2213000	Rokotschin
137	51.3562189	14.4742495	1771128600000	1771128660000	1657000	1784000	Untere Drehnaer Teiche
138	51.5347542	14.5339465	1771130444000	1771131068400	1784000	940000	Tiefbau-Service-Berton
139	51.4822181	14.7648734	1771216867651	1771216927651	1348000	1461000	Feuerlöschteich 4
140	51.505442	14.638026999999997	1771218388651	1771218900000	1461000	313000	Weißwasser Bahnhof
141	51.5305303	14.5320261	1771622400000	1771622460000	889000	1292000	Rohner Weg 10
142	51.519796	14.686649	1771623752000	1771624107000	1292000	693000	Heideweg 49
143	51.5305303	14.5320261	1771095300000	1771095360000	889000	1411000	Rohner Weg 10
144	51.5085074	14.6846339	1771096771000	1771097264849	1411000	645000	Große Modzidla
145	51.348580999999996	14.590756	1771185840000	1771185900000	1435000	315000	Klitten Bahnhof
146	51.3596395	14.5755402	1771186215000	1771186325250	315000	1673000	Syterteich
118	51.3718586	14.510638	1770879824000	1770880028400	584000	1563000	Seeperle
147	51.505849	14.479243	1770882540000	1770882600000	1563000	1579000	Mulkwitz Außenkippe
148	51.3212968	14.6305692	1770884179000	1770884731650	1579000	1800000	Förstgener Straße 14
149	51.4866023	14.8545185	1770750748000	1770750808000	1369000	2260000	Schlauchboothafen
150	51.5279047	14.5229428	1770753068000	1770753160000	2260000	1014000	Trebendorfer Weg 81
151	51.5456749	14.5346691	1771045200000	1771045260000	914000	1785000	Spremberger Straße 17
152	51.3428674	14.4903266	1771047045000	1771047669750	1785000	1642000	Rokotschin
120	51.387624	14.6256044	1771747586000	1771747586000	566000	1485000	Schadendorfer Straße 12
119	51.348580999999996	14.590756	1771746970000	1771747020000	610000	566000	Klitten Bahnhof
153	51.5424728	14.6389564	1771460528376	1771460588376	0	879000	Jämlitzer Weg 57
154	51.538412	14.5250691	1771461467376	1771461775026	879000	0	Jahnring 21
155	51.5433114	14.5309437	1771653939756	1771653999756	0	2298000	Hoyerswerdaer Straße 33
156	51.4218271	14.5659111	1771656297756	1771656897756	2298000	0	Werk 2
157	51.53537800000001	14.530662999999999	1771590420000	1771590480000	904000	253000	Schleife Bahnhof
158	51.5301599	14.5247083	1771590733000	1771590821550	253000	1157000	Tischlereiweg 113b
160	51.505888	14.479387000000001	1771603516900	1771603680000	466000	1274000	Mulkwitz Außenkippe
161	51.3717575	14.6044841	1771471158749	1771471218749	0	1566000	Am Forsthaus 1
162	51.5292355	14.5213952	1771472784749	1771473332849	1566000	0	Gefallenendenkmale Rohne
163	51.4734329	14.7981781	1771400531101	1771400591101	1301000	1414000	ehem. Ort Neudorf
164	51.505442	14.638026999999997	1771402005101	1771402500000	1414000	313000	Weißwasser Bahnhof
165	51.505849	14.479243	1770742140000	1770742200000	1215000	1225000	Mulkwitz Außenkippe
166	51.4259483	14.5836186	1770743425000	1770743853750	1225000	1252000	Findlingsparkblick
167	51.5103208	14.6646048	1771181100000	1771181160000	468000	1263000	Waldhausstraße 100a
168	51.5400192	14.5240712	1771182423000	1771182865050	1263000	1116000	Thälmann-Siedlung 8
171	51.5400192	14.5240712	1771516200000	1771516260000	1055000	650000	Thälmann-Siedlung 8
172	51.4778763	14.480276	1771516910000	1771517137500	650000	1337000	Campingplatz Ruhlmühle
173	51.5020684	14.7121191	1771621700857	1771621760857	0	1340000	Görlitzer Straße 5
174	51.5292355	14.5213952	1771623100857	1771623569856	1340000	0	Gefallenendenkmale Rohne
175	51.5536653	14.5338599	1771107299073	1771107359073	0	229000	Dorfgemeinschaftshaus Mühlrose - Wjesny dom Miłoraz
176	51.5393992	14.5316092	1771107588073	1771107668223	229000	0	Strugaaue 2
177	51.5292355	14.5213952	1771669095175	1771669155175	0	1409000	Gefallenendenkmale Rohne
178	51.5025897	14.7281736	1771670564175	1771671057324	1409000	0	Ringweg 2
181	51.41521	14.6158004	1770927300000	1770927360000	1369000	1866000	Buttermilchberge
182	51.5296246	14.5237337	1770929226000	1770929879100	1866000	1135000	Tischlereiweg 115a
67	51.4796153	14.9070791	1771740327240	1771740327240	0	1227000	Königshügel 16
68	51.5353088	14.5289849	1771743120240	1771743120240	105000	0	Siedlung - Sydlišćo
207	51.5801126	14.5732073	1771169100000	1771169160000	1045000	781000	Am Grenzgraben 1
179	51.4770182	14.6503931	1771741554240	1771741614240	1227000	1145000	Jagenstein 88+89+104+105
208	51.5343123	14.5136158	1771169941000	1771170214350	781000	1183000	Forstweg 78a
180	51.5393992	14.5316092	1771742759240	1771743015240	1145000	105000	Strugaaue 2
183	51.3656465	14.6394813	1771838597250	1771838657250	1907000	965000	Schäferei 14
185	51.365159000000006	14.509355	1771577580000	1771577640000	1372000	981000	Uhyst (Spree) Gaststätte
187	51.505442	14.638026999999997	1770843040000	1770843100000	292000	865000	Weißwasser Bahnhof
188	51.5453912	14.7253948	1770843965000	1770844267750	865000	1048000	Töpferei Gordon Gran
189	51.5279047	14.5229428	1771732362297	1771732422297	0	1690000	Trebendorfer Weg 81
190	51.4702653	14.7045228	1771734112297	1771734703797	1690000	0	Heideweg 7
191	51.50463	14.634229999999999	1771419780000	1771419840000	248000	444000	Weißwasser Landau-Gymnasium
192	51.475876	14.655712	1771420284000	1771420439400	444000	274000	Hermannsdorfer See (in Flutung)
193	51.5027772	14.8300298	1771304949600	1771305009600	2242000	2304000	Mosty (Wendisch Musta)
194	51.504378	14.635010999999999	1771307313600	1771308120000	2304000	301000	Weißwasser Landau-Gymnasium
195	51.519859	14.715311999999999	1770792900000	1770792960000	613000	521000	Krauschwitz Wilhelmstraße
196	51.4832703	14.732597	1770793481000	1770793663350	521000	790000	Kiefernweg 3
209	51.4303197	14.7258133	1770756922000	1770756922000	2840000	2953000	Löschteich 45
210	51.505442	14.638026999999997	1770759875000	1770760440000	2953000	313000	Weißwasser Bahnhof
169	51.508303000000005	14.644146999999998	1771702500000	1771702500000	299000	892000	Weißwasser Straße des Friedens
170	51.5443525	14.5405083	1771703392000	1771703392000	892000	250000	Friedensstraße 62
199	51.5405733	14.520827	1771189118125	1771189178125	0	794000	Thälmann-Siedlung 25
200	51.441774	14.5218499	1771189972125	1771190250025	794000	0	Alter Spreeverlauf
201	51.516359	14.718338999999999	1771664160000	1771664220000	573000	336000	Krauschwitz Keulahütte
202	51.4944518	14.7167733	1771664556000	1771664673599	336000	645000	An der Schmiede 6
203	51.353354	14.5969374	1771791300000	1771791360000	1456000	1604000	Platz der MTS 348
127	51.5433114	14.5309437	1771793160000	1771793160000	176000	1094000	Hoyerswerdaer Straße 33
205	51.5359089	14.5038922	1771485600000	1771485660000	1130000	296000	Forstweg 77a
206	51.5393992	14.5316092	1771485956000	1771486059600	296000	985000	Strugaaue 2
211	51.505442	14.638026999999997	1771652400000	1771652460000	292000	176000	Weißwasser Bahnhof
212	51.5040503	14.6440753	1771652636000	1771652697599	176000	392000	Kleingärtnerverein "Reichsbahn"
213	51.5353088	14.5289849	1771211739000	1771211799000	939000	1899000	Siedlung - Sydlišćo
214	51.3399908	14.6096626	1771213698000	1771213779651	1899000	1800000	Schuberts Berge 3
217	51.362845	14.509056000000001	1770977040000	1770977100000	1328000	812000	Uhyst (Spree) Bahnhof
218	51.3481505	14.4770138	1770977912000	1770978196200	812000	1832000	Sarkassenteich
197	51.4931288	14.6280856	1771702141000	1771702201000	39000	1117000	Weißwasser/O.L.
219	51.3727022	14.6762974	1771581851250	1771581911250	1056000	125000	Amselweg 8
220	51.377765	14.669138	1771582036250	1771582080000	125000	1484000	Reichwalde Mühlenstraße
221	51.4636975	14.7415012	1771273784000	1771273800000	855000	1813000	Kommandantur
222	51.5364085	14.524572	1771275613000	1771275613000	1813000	1066000	Jahnring 5b
223	51.5388861	14.5189616	1771237936300	1771237996300	0	1772000	Zum Sportplatz 5
224	51.41521	14.6158004	1771239768300	1771240388500	1772000	0	Buttermilchberge
186	51.3229189	14.6391744	1771578621000	1771578964350	981000	1910000	Im Erlengrund 1
215	51.362845	14.509056000000001	1771243200000	1771243260000	610000	1506000	Uhyst (Spree) Bahnhof
184	51.348580999999996	14.590756	1771839622250	1771839622250	965000	1275000	Klitten Bahnhof
159	51.4372936	14.5272309	1771603050900	1771603050900	888000	466000	Hundewiese
216	51.5397943	14.5386138	1771244766000	1771244766000	1506000	316000	Schleife Bahnhof
226	51.3620805	14.6141723	1771844955000	1771845359250	1155000	1376000	Am Waldessaum 11
227	51.517561	14.6426068	1771056600000	1771056660000	560000	1159000	Schulze-Delitzsch-Straße 25
228	51.5312531	14.516953	1771057819000	1771058224650	1159000	1037000	Rohne Ausbau
229	51.5446031	14.5355952	1771173900000	1771173960000	977000	520000	Schleife - Slepo
230	51.5085094	14.4856332	1771174480000	1771174662000	520000	1249000	Neustädter Straße 48
231	51.5301599	14.5247083	1771823240400	1771823300400	1097000	1096000	Tischlereiweg 113b
232	51.505424	14.639178999999999	1771824396400	1771824780000	1096000	304000	Weißwasser Bahnhof
233	51.5152804	14.5871743	1771347600000	1771347660000	467000	600000	Grundwasser Meßstation.
234	51.5338793	14.5202632	1771348260000	1771348470000	600000	1017000	Grenzweg 106c
235	51.4574695	14.9471773	1771430100016	1771430160016	0	2334000	Vaterunser Berg
236	51.5286634	14.5366817	1771432494016	1771433094016	2334000	0	Rohner Weg 6
204	51.5344465	14.5268116	1771792964000	1771792984000	1604000	1001000	Mulkwitzer Weg 2a
237	51.5186029	14.6042589	1770918900000	1770918960000	534000	879000	Halbendorfer Weg 52
238	51.5286634	14.5366817	1770919839000	1770920146650	879000	1038000	Rohner Weg 6
239	51.348580999999996	14.590756	1771562618000	1771562678000	1993000	621000	Klitten Bahnhof
240	51.3717575	14.6044841	1771563299000	1771563381000	621000	1539000	Am Forsthaus 1
242	51.4904843	14.8022204	1771189961000	1771190626350	1901000	1064000	Zur Tanne 63
243	51.4835968	14.7318838	1770839711400	1770839771400	723000	836000	Kiefernweg 3
244	51.505442	14.638026999999997	1770840607400	1770840900000	836000	313000	Weißwasser Bahnhof
245	51.500706	14.7174395	1771846790000	1771846800000	459000	1310000	Am Hammerlugk 1a
246	51.5393992	14.5316092	1771848110000	1771848110000	1310000	985000	Strugaaue 2
247	51.5537951	14.7018176	1771605833900	1771605833900	1043000	636000	Drosselweg 27
248	51.53425	14.663793	1771606469900	1771606620000	636000	581000	Gablenz Feuerwehr
249	51.4833121	14.69376	1771879164000	1771879164000	823000	936000	Waldweg 5
250	51.505442	14.638026999999997	1771880100000	1771880220000	936000	313000	Weißwasser Bahnhof
251	51.5506571	14.6283915	1771390759000	1771390800000	1173000	1189000	Jämlitzer Weg 60
252	51.5312531	14.516953	1771391989000	1771391989000	1189000	1037000	Rohne Ausbau
253	51.5388861	14.5189616	1771230366451	1771230426451	1028000	173000	Zum Sportplatz 5
254	51.535267	14.529270999999998	1771230599451	1771230660000	173000	984000	Schleife Busbahnhof
255	51.321187	14.4797212	1771233373451	1771233433451	1790000	1939000	Grenzstein 93 KS/KP
256	51.5443525	14.5405083	1771235372451	1771235539000	1939000	938000	Friedensstraße 62
257	51.4377781	14.5270747	1771823293504	1771823353504	0	858000	Hundewiese
258	51.5302251	14.5252029	1771824211504	1771824511804	858000	0	Tischlereiweg 113b
260	51.56622	14.5815125	1771700775000	1771700990250	615000	1077000	Klein Dübener Weg 5
261	51.563862	14.569973	1771689000000	1771689060000	902000	203000	Groß Düben Dorf
45	51.505396000000005	14.639304999999998	1771690361050	1771690380000	1027000	583000	Weißwasser Bahnhof
263	51.4047924	14.5235396	1771489231393	1771489291393	0	1048000	Krümme
264	51.5417264	14.5348536	1771490339393	1771490706193	1048000	0	Gemeindeamt
265	51.3637213	14.471371	1771137673000	1771137733000	1759000	1899000	Rotdornallee 32
267	51.508303000000005	14.644146999999998	1771695240000	1771695300000	278000	1070000	Weißwasser Straße des Friedens
112	51.5342917	14.5338773	1771389586000	1771389586000	1726000	934000	Schleifer Straße 2
198	51.5394742	14.5159274	1771703642000	1771704146349	1117000	1113000	Hoyerswerdaer Straße 94
272	51.5331022	14.5468938	1771562823000	1771562908050	243000	1020000	Schleifer Straße 27a
273	51.538033000000006	14.629809999999999	1770983940000	1770984000000	727000	536000	Kromlau
274	51.5314351	14.6315313	1770984536000	1770984723600	536000	1252000	Nixenteiche
275	51.5296246	14.5237337	1771560964992	1771561024992	0	1209000	Tischlereiweg 115a
276	51.4141183	14.5456677	1771562233992	1771562657142	1209000	0	An der Binnenfischerei 1
225	51.505849	14.479243	1771843740000	1771843800000	890000	1155000	Mulkwitz Außenkippe
277	51.505849	14.479243	1771840897250	1771840957250	1275000	890000	Mulkwitz Außenkippe
278	51.38401	14.607085	1771841847250	1771842158750	890000	890000	Teichweg 3a
279	51.525850000000005	14.565868	1771829100000	1771829160000	613000	220000	Trebendorf Vereinshaus
280	51.5107127	14.5830002	1771829380000	1771829457000	220000	513000	Grundwasser Meßstation.
282	51.3310895	14.5203713	1771741909000	1771742556150	1849000	1675000	Zigeunerweg
283	51.489472	14.728663	1771654007015	1771654067015	0	1614000	Pappelweg 3
284	51.5364085	14.524572	1771655681015	1771656245915	1614000	0	Jahnring 5b
285	51.3807243	14.655446	1770953097000	1770953100000	1497000	1735000	Mittelweg 22
286	51.5397943	14.5386138	1770954835000	1770954835000	1735000	1004000	Schleife Bahnhof
287	51.44258	14.9581073	1771409693909	1771409753909	0	2404000	Schimpelberg
288	51.5279047	14.5229428	1771412157909	1771412999309	2404000	0	Trebendorfer Weg 81
289	51.5214164	14.6999751	1771156800000	1771156860000	656000	1320000	Waldweg 11
290	51.5290227	14.5298561	1771158180000	1771158641999	1320000	956000	Rohner Weg 17
291	51.5357337	14.5192924	1771298184000	1771298244000	984000	1300000	Jahnring 13
292	51.3690022	14.6101025	1771299544000	1771299700000	1300000	1220000	Am Forsthaus 2
293	51.505563	14.638612999999998	1770928560000	1770928620000	291000	995000	Weißwasser Bahnhof
270	51.505888	14.479387000000001	1770962316600	1770962640000	924000	1274000	Mulkwitz Außenkippe
295	51.5338793	14.5202632	1771586400000	1771586460000	957000	1502000	Grenzweg 106c
296	51.3470723	14.5078271	1771587962000	1771588057000	1502000	1519000	Ferienwohnung im Alten Forsthaus
297	51.5338793	14.5202632	1770782400000	1770782460000	957000	220000	Grenzweg 106c
266	51.5417264	14.5348536	1771139632000	1771139799000	1899000	466000	Gemeindeamt
294	51.5417871	14.524831	1770929615000	1770929615000	995000	292000	Hoyerswerdaer Straße 50
269	51.3804046	14.6156514	1770961392600	1770961392600	1571000	924000	Klittener Straße 14
281	51.5302251	14.5252029	1771740060000	1771740060000	354000	1849000	Tischlereiweg 113b
241	51.5417264	14.5348536	1771188060000	1771188060000	272000	1901000	Gemeindeamt
262	51.5679086	14.5583588	1771689263000	1771689334050	203000	1105000	Horlitzaweg 13f
271	51.530573000000004	14.543670999999998	1771562580000	1771562580000	370000	243000	Klein Trebendorf
299	51.5755325	14.7032459	1771566310650	1771566370650	1418000	1281000	Zschorno 33
301	51.3438785	14.5523294	1770945075276	1770945135276	0	2215000	ehem. Kleiner Kascheler Teich
302	51.5343123	14.5136158	1770947350276	1770948125526	2215000	0	Forstweg 78a
303	51.5338793	14.5202632	1771899327224	1771899387224	0	674000	Grenzweg 106c
304	51.5416568	14.6174096	1771900061224	1771900297123	674000	0	Am Lieskauer Weg 13
305	51.5353088	14.5289849	1771038939000	1771038999000	939000	467000	Siedlung - Sydlišćo
307	51.365159000000006	14.509355	1771822380000	1771822440000	1372000	703000	Uhyst (Spree) Gaststätte
308	51.3408812	14.4856542	1771823143000	1771823389049	703000	1962000	Rokotschin
309	51.5295517	14.5240575	1771683000000	1771683060000	1087000	492000	Tischlereiweg 115a
310	51.5509673	14.5369265	1771683552000	1771683724200	492000	1143000	Mühlrose (b Schleife) Dorfgemeinschaftshaus
361	51.5400866	14.5128586	1771200792008	1771200852008	0	2718000	Hoyerswerdaer Straße 98
313	51.5305303	14.5320261	1771039883000	1771039943000	417000	1950000	Rohner Weg 10
314	51.3278581	14.5808466	1771041893000	1771042050000	1950000	1778000	Neubauernstraße 442
306	51.5252081	14.5591373	1771039466000	1771039466000	467000	417000	Waldweg 12
315	51.4762335	14.8273233	1771001062051	1771001122051	1204000	1317000	ehem. Ablage 66
316	51.505442	14.638026999999997	1771002439051	1771002900000	1317000	313000	Weißwasser Bahnhof
317	51.4618679	14.9408598	1771363068600	1771363128600	1451000	1564000	Vaterunser Berg
318	51.505442	14.638026999999997	1771364692600	1771365240000	1564000	313000	Weißwasser Bahnhof
321	51.5163639	14.6869969	1771391582000	1771391642000	1062000	1703000	Drachenberg
322	51.5393992	14.5316092	1771393345000	1771393403000	1703000	985000	Strugaaue 2
323	51.3794044	14.6685639	1771817014000	1771817074000	1414000	1643000	Sportverein 48 Reichwalde
325	51.5278027	14.6648215	1771268732400	1771268792400	513000	376000	Wiesengrund 3b
326	51.505442	14.638026999999997	1771269168400	1771269300000	376000	313000	Weißwasser Bahnhof
327	51.4620402	14.953355	1771867800000	1771867860000	1652000	2705000	Am Damm 35
328	51.5302251	14.5252029	1771870565000	1771871511749	2705000	1176000	Tischlereiweg 113b
329	51.45005	14.5156383	1771617900000	1771617960000	1106000	694000	Feuerlöschwasser
330	51.5279047	14.5229428	1771618654000	1771618896899	694000	1014000	Trebendorfer Weg 81
331	51.5443525	14.5405083	1771234809392	1771234869392	0	3564000	Friedensstraße 62
332	51.4193333	14.9249616	1771238433392	1771239033392	3564000	0	Tränkeberg
333	51.5296246	14.5237337	1770989400000	1770989460000	1075000	196000	Tischlereiweg 115a
334	51.5344465	14.5268116	1770989656000	1770989724600	196000	1001000	Mulkwitzer Weg 2a
335	51.4730461	14.928933	1771918659750	1771918719750	1502000	1615000	Flußkilometer 100,0
336	51.505442	14.638026999999997	1771920334750	1771920900000	1615000	313000	Weißwasser Bahnhof
339	51.525850000000005	14.565868	1771497900000	1771497960000	613000	524000	Trebendorf Vereinshaus
342	51.3613133	14.4751126	1771698279000	1771698515000	1344000	1645000	Rotdornallee 11
268	51.5400192	14.5240712	1771696370000	1771696370000	1070000	505000	Thälmann-Siedlung 8
259	51.5357337	14.5192924	1771700160000	1771700160000	1645000	615000	Jahnring 13
343	51.5433114	14.5309437	1771850535827	1771850595827	0	1738000	Hoyerswerdaer Straße 33
344	51.5201476	14.729807	1771852333827	1771852942127	1738000	0	Grüner Teich
362	51.4357858	14.5753052	1771203570008	1771204170008	2718000	0	Dr. Karl Preußner Stein
345	51.4246473	14.5455887	1771905300000	1771905360000	944000	809000	Ltg MN und MP Boxberg - Bärwalde
346	51.5329343	14.5196775	1771906169000	1771906308000	809000	252000	Rohne Ausbau
337	51.5400866	14.5128586	1771906560000	1771906560000	252000	667000	Hoyerswerdaer Straße 98
347	51.5135576	14.7139933	1771448336851	1771448396851	561000	669000	Carolinenweg 10
348	51.505442	14.638026999999997	1771449065851	1771449300000	669000	313000	Weißwasser Bahnhof
350	51.3611789	14.5322164	1770905398000	1770905616650	1198000	1478000	Bärwalder See
351	51.5443525	14.5405083	1771536600000	1771536660000	877000	725000	Friedensstraße 62
352	51.5064998	14.6184196	1771537385000	1771537638749	725000	361000	August-Bebel-Straße 26
353	51.5301599	14.5247083	1771003849051	1771003909051	1097000	1547000	Tischlereiweg 113b
354	51.5483484	14.7058353	1771005456051	1771005647000	1547000	946000	Feldstraße 43
355	51.5278006	14.6388402	1770818424600	1770818484600	741000	604000	Fichte 4
356	51.505442	14.638026999999997	1770819088600	1770819300000	604000	313000	Weißwasser Bahnhof
357	51.5095717	14.6790692	1771732200000	1771732260000	549000	1512000	Keulaer Tiergarten
359	51.5342031	14.5217853	1770968100000	1770968160000	949000	506000	Neustädter Straße 10
360	51.5154956	14.570317	1770968666000	1770968843100	506000	575000	Löschwasserentnahmestelle
363	51.5446031	14.5355952	1771343178501	1771343238501	977000	2728000	Schleife - Slepo
364	51.3230963	14.6482674	1771345966501	1771346128000	2728000	2463000	Kiesgrube Tauer
365	51.5397943	14.5386138	1771147500000	1771147560000	943000	647000	Schleife Bahnhof
366	51.5290766	14.5685306	1771148207000	1771148433450	647000	837000	Kranichweg 19
367	51.4868554	14.6208881	1771902540072	1771902600072	0	1279000	Aussichtsturm am Schweren Berg
368	51.5342031	14.5217853	1771903879072	1771904326722	1279000	0	Neustädter Straße 10
369	51.4775411	14.6605439	1771016400000	1771016460000	212000	1155000	Hermannsdorfer See (in Flutung)
370	51.5417264	14.5348536	1771017615000	1771018019250	1155000	1030000	Gemeindeamt
341	51.505849	14.479243	1771696875000	1771696935000	1215000	1344000	Mulkwitz Außenkippe
349	51.505849	14.479243	1770904140000	1770904200000	1222000	1198000	Mulkwitz Außenkippe
319	51.375179	14.5586787	1771511400000	1771511460000	1853000	2867000	A13
371	51.5344271	14.5295784	1771356600000	1771356660000	170000	774000	Mühlroser Straße 3
358	51.5312432	14.5115818	1771733772000	1771734301200	1512000	354000	Mühlweg 5b
320	51.5400866	14.5128586	1771514327000	1771514327000	2867000	289000	Hoyerswerdaer Straße 98
300	51.505442	14.638026999999997	1771567651650	1771567651650	1281000	827000	Weißwasser Bahnhof
340	51.5184	14.5825106	1771498484000	1771498484000	524000	948000	Zum Pechofen 7
324	51.5360245	14.5286573	1771818717000	1771818717000	1643000	2404000	Neustädter Straße 18
372	51.5418058	14.634916	1771357434000	1771357704900	774000	924000	Jämlitzer Weg 59
373	51.5433114	14.5309437	1771674900000	1771674960000	958000	263000	Hoyerswerdaer Straße 33
374	51.5255841	14.5093906	1771675223000	1771675315050	263000	1088000	Rohne Am Njepila-Hof
375	51.5002382	14.7670861	1771278680558	1771278740558	0	1747000	Neudorfer Straße 42
376	51.5292355	14.5213952	1771280487558	1771281087558	1747000	0	Gefallenendenkmale Rohne
377	51.377333	14.668932	1771062480000	1771062540000	1425000	518000	Reichwalde Mühlenstraße
378	51.3509004	14.6367873	1771063058000	1771063239300	518000	1575000	Lichtenteich
379	51.3413029	14.5648792	1771447500000	1771447560000	1614000	1763000	Neudorfer Straße 427
380	51.5279047	14.5229428	1771449323000	1771449940050	1763000	1014000	Trebendorfer Weg 81
381	51.3579025	14.5155841	1771758600000	1771758660000	1448000	1555000	Spreegasse 11
383	51.4794916	14.7967237	1771573510650	1771573570650	1168000	1281000	Ehem. gEHÖFT jAINSCH
385	51.4119206	14.5887514	1770933509759	1770933569759	0	1335000	EPT
386	51.5357337	14.5192924	1770934904759	1770935372008	1335000	0	Jahnring 13
437	51.5357337	14.5192924	1770962980865	1770963040865	0	275000	Jahnring 13
388	51.5456749	14.5346691	1771760802000	1771760910150	309000	975000	Spremberger Straße 17
382	51.5350649	14.5289157	1771760215000	1771760215000	1555000	218000	Schleife Busbahnhof
389	51.5526044	14.5357171	1771007100000	1771007160000	1139000	571000	Dorfgemeinschaftshaus Mühlrose - Wjesny dom Miłoraz
390	51.5388861	14.5189616	1771007731000	1771007930850	571000	1083000	Zum Sportplatz 5
391	51.5201959	14.6184255	1770888952658	1770889012658	0	779000	Kromlauer Weg 54
392	51.528762	14.5279248	1770889791658	1770890064308	779000	0	Trebendorfer Weg 116c
393	51.5040543	14.5159002	1771779354300	1771779414300	1672000	582000	Am Damm
394	51.510713	14.493634000000002	1771779996300	1771780200000	582000	1212000	Mulkwitz Abzw Mühlrose
395	51.5332486	14.5141138	1770929907000	1770929967000	292000	1801000	Mühlweg 5b
396	51.4838092	14.6957805	1770931768000	1770931801000	1801000	881000	Waldweg 6
397	51.5397943	14.5386138	1770822900000	1770822960000	943000	338000	Schleife Bahnhof
398	51.5554519	14.512657	1770823298000	1770823416299	338000	1132000	Spremberger Straße 45
399	51.5417871	14.524831	1771304400000	1771304460000	1014000	1133000	Hoyerswerdaer Straße 50
400	51.5338079	14.6232905	1771305593000	1771305989550	1133000	1235000	Ziegelei 8
401	51.505798000000006	14.642610999999999	1770958620000	1770958680000	236000	891000	Weißwasser Stadtzentrum
402	51.4708892	14.7207669	1770959571000	1770959821600	891000	1571000	Dorfstraße 29
403	51.505442	14.638026999999997	1770878400000	1770878460000	292000	739000	Weißwasser Bahnhof
404	51.5202428	14.7571597	1770879199000	1770879457649	739000	725000	Skerbersdorfer Straße 31
405	51.5397943	14.5386138	1770777890289	1770777950289	0	1259000	Schleife Bahnhof
406	51.4933823	14.6218366	1770779209289	1770779649939	1259000	0	Schwerer Berg 1
408	51.5133134	14.7903182	1770784867000	1770784896000	1896000	965000	Bienengartenweg 16
298	51.5435594	14.5297765	1770782680000	1770782680000	220000	231000	Alter Postweg 11
409	51.408276	14.5518224	1771523063454	1771523123454	0	845000	Ltg MQ und MR Boxberg - Bärwalde
410	51.5312432	14.5115818	1771523968454	1771524264204	845000	0	Mühlweg 5b
411	51.505849	14.479243	1771141740000	1771141800000	466000	1376000	Mulkwitz Außenkippe
412	51.3580048	14.5856831	1771143176000	1771143657599	1376000	1597000	Dürrbacher Straße 356
413	51.5417264	14.5348536	1770891159450	1770891219450	923000	993000	Gemeindeamt
415	51.505442	14.638026999999997	1770993600000	1770993660000	292000	1969000	Weißwasser Bahnhof
416	51.4388838	14.5822273	1770995629000	1770996318150	1969000	1794000	Dr. Karl Preußner Stein
417	51.5388861	14.5189616	1771086600000	1771086660000	1028000	1450000	Zum Sportplatz 5
418	51.5380302	14.7081058	1771088110000	1771088617499	1450000	832000	Weinbergweg 100
419	51.5290227	14.5298561	1770959805715	1770959865715	0	1284000	Rohner Weg 17
420	51.5034168	14.6867627	1770961149715	1770961599115	1284000	0	Große Modzidla
421	51.5397309	14.5335292	1770751500000	1770751560000	974000	1163000	Norma
422	51.4052563	14.5762255	1770752723000	1770753130050	1163000	899000	Alte Bautzener Straße 47
423	51.5286293	14.5701245	1771187100000	1771187160000	744000	600000	Kranichweg 19
424	51.5277052	14.5242631	1771187760000	1771187788000	600000	272000	Trebendorfer Weg 116b
425	51.5312531	14.516953	1770866177000	1770866237000	977000	1370000	Rohne Ausbau
426	51.3628562	14.5105966	1770867607000	1770867770000	1370000	1413000	Lange Straße 21
428	51.5397943	14.5386138	1771753858000	1771754193300	958000	1004000	Schleife Bahnhof
430	51.5386074	14.5148166	1771769497000	1771770139950	1837000	1123000	Hoyerswerdaer Straße 91
431	51.365159000000006	14.509355	1770901260000	1770901320000	1372000	243000	Uhyst (Spree) Gaststätte
432	51.3520812	14.5251619	1770901563000	1770901648050	243000	1222000	Neuteich Uhyst
433	51.5277052	14.5242631	1771098383000	1771098443000	967000	2102000	Trebendorfer Weg 116b
434	51.3545262	14.4878931	1771100545000	1771100702000	2102000	2040000	Großer Drehnaer Teich
435	51.4985181	14.6186071	1771431300000	1771431360000	125000	1024000	Sternenbäck
436	51.5296246	14.5237337	1771432384000	1771432742400	1024000	1135000	Tischlereiweg 115a
438	51.5085094	14.4856332	1770963315865	1770963412115	275000	0	Neustädter Straße 48
439	51.38720099999999	14.607899999999999	1771220340000	1771220400000	1077000	218000	Kringelsdorf Denkmal
440	51.3685444	14.6080397	1771220618000	1771220694300	218000	1224000	Am Forsthaus 2
441	51.424386999999996	14.537185	1771579200000	1771579260000	985000	1010000	Sprey
443	51.4393197	14.5152418	1771178100000	1771178160000	1242000	987000	Alter Spreeverlauf
444	51.5290227	14.5298561	1771179147000	1771179492450	987000	956000	Rohner Weg 17
445	51.4873517	14.6319813	1771548551193	1771548611193	0	978000	Professor-Wagenfeld-Ring 133
446	51.536356	14.5290886	1771549589193	1771549931493	978000	0	Friedensstraße 1
429	51.4708892	14.7207669	1771767600000	1771767660000	580000	1837000	Dorfstraße 29
407	51.5399955	14.5160315	1770782911000	1770782971000	1059000	1896000	Hoyerswerdaer Straße 90
387	51.5358982	14.5420901	1771760433000	1771760493000	940000	309000	Werksweg 10
414	51.417514	14.549752	1770892212450	1770892212450	993000	808000	Boxberg Warmwasseranlage
447	51.5418744	14.537528	1771331184055	1771331244055	0	1741000	Friedensstraße 77a
448	51.3389863	14.556837	1771332985055	1771333594405	1741000	0	Neudorfer Straße 428
449	51.4589948	14.7260245	1770897981325	1770898041325	0	2152000	Dorfstraße 6
450	51.5342031	14.5217853	1770900193325	1770900946525	2152000	0	Neustädter Straße 10
451	51.365159000000006	14.509355	1771506060000	1771506120000	1372000	1052000	Uhyst (Spree) Gaststätte
452	51.3256004	14.5699871	1771507172000	1771507540200	1052000	1853000	Neubauernstraße 441
453	51.505849	14.479243	1771235340000	1771235400000	1215000	1544000	Mulkwitz Außenkippe
454	51.3904767	14.6671335	1771236944000	1771237484400	1544000	1765000	Rodelberg Reichwalde
456	51.5548403	14.5734843	1771709675000	1771709855250	515000	925000	Edelstraße 50
457	51.4016117	14.5860009	1771889259863	1771889319863	0	1269000	Straße der Freundschaft 26
458	51.5305303	14.5320261	1771890588863	1771891033013	1269000	0	Rohner Weg 10
459	51.5397943	14.5386138	1771254900000	1771254960000	943000	643000	Schleife Bahnhof
460	51.5465954	14.6130163	1771255603000	1771255828050	643000	1006000	AV Schleife e.V.
461	51.5400192	14.5240712	1771529143029	1771529203029	0	179000	Thälmann-Siedlung 8
462	51.5443525	14.5405083	1771529382029	1771529444678	179000	0	Friedensstraße 62
463	51.543759	14.537974999999998	1771860420000	1771860480000	886000	278000	Schleife Kirche
465	51.3530726	14.5652193	1770987510000	1770987570000	1722000	1899000	Jasua
466	51.5347542	14.5339465	1770989469000	1770989499000	1899000	940000	Tiefbau-Service-Berton
469	51.362845	14.509056000000001	1771531680000	1771531740000	1328000	233000	Uhyst (Spree) Bahnhof
470	51.3481897	14.4900933	1771531973000	1771532054550	233000	1561000	Sarkassenteich
471	51.505849	14.479243	1770799740000	1770799800000	1215000	1427000	Mulkwitz Außenkippe
472	51.4227498	14.5796147	1770801227000	1770801726449	1427000	1454000	Block R
473	51.5279047	14.5229428	1770895800000	1770895860000	954000	995000	Trebendorfer Weg 81
474	51.5262124	14.6166727	1770896855000	1770897203250	995000	621000	Kromlauer Weg 73a
476	51.505888	14.479387000000001	1770793217651	1770793680000	1321000	1274000	Mulkwitz Außenkippe
477	51.53537800000001	14.530662999999999	1771907750000	1771907810000	523000	251000	Schleife Bahnhof
478	51.5400866	14.5128586	1771908061000	1771908148850	251000	1150000	Hoyerswerdaer Straße 98
338	51.569467	14.5688701	1771907227000	1771907227000	667000	523000	Dorfladen - Doreen Thumann
480	51.4299222	14.7311601	1771853028000	1771853716800	1968000	1223000	Löschteich 45
481	51.5302251	14.5252029	1771512881417	1771512941417	0	1504000	Tischlereiweg 113b
482	51.5034168	14.6867627	1771514445417	1771514971817	1504000	0	Große Modzidla
483	51.5388861	14.5189616	1771656000000	1771656060000	1028000	487000	Zum Sportplatz 5
484	51.5610558	14.5479444	1771656547000	1771656717450	487000	1188000	Groß-Dübener Weg 16
485	51.5340052	14.5217744	1771470950000	1771471010000	950000	2098000	Grenzweg 107a
486	51.4190355	14.5720943	1771473108000	1771473298000	2098000	1858000	Boxberg Block P
487	51.5295517	14.5240575	1771627196000	1771627256000	0	1771000	Tischlereiweg 115a
488	51.3472613	14.6580256	1771629027000	1771629627000	1771000	0	Dreiecksteich
489	51.5405733	14.520827	1771735800000	1771735849000	292000	2071000	Thälmann-Siedlung 25
490	51.4864915	14.7960662	1771737920000	1771737920000	2071000	2140000	Aussiedlung von sechs Familien
491	51.5279047	14.5229428	1771580592000	1771580652000	322000	2347000	Trebendorfer Weg 81
492	51.4592847	14.7310216	1771582999000	1771583047000	2347000	1516000	Kommandantur Haide
442	51.5456749	14.5346691	1771580270000	1771580270000	1010000	322000	Spremberger Straße 17
509	51.5350649	14.5289157	1771265793760	1771265853760	0	900000	Schleife Busbahnhof
494	51.5359089	14.5038922	1771861479000	1771861612350	381000	1190000	Forstweg 77a
464	51.5296246	14.5237337	1771860758000	1771860758000	278000	280000	Tischlereiweg 115a
495	51.505442	14.638026999999997	1771425600000	1771425660000	292000	1295000	Weißwasser Bahnhof
496	51.4656101	14.7088101	1771426955000	1771427408250	1295000	1281000	Dorfstraße 1
497	51.5397943	14.5386138	1771575966451	1771576026451	928000	173000	Schleife Bahnhof
498	51.53534500000001	14.530609	1771576199451	1771576260000	173000	964000	Schleife Bahnhof
499	51.516359	14.718338999999999	1771764960000	1771765020000	573000	587000	Krauschwitz Keulahütte
500	51.4753327	14.7051496	1771765607000	1771765812450	587000	580000	Bresina - Brězyna
501	51.3388087	14.602484	1771155184333	1771155244333	0	1707000	Heuteich
502	51.5456749	14.5346691	1771156951333	1771157548783	1707000	0	Spremberger Straße 17
503	51.5397943	14.5386138	1771790400000	1771790460000	943000	2507000	Schleife Bahnhof
504	51.3255531	14.5576061	1771792967000	1771793844450	2507000	2330000	Weizenberg
505	51.5386074	14.5148166	1771749086000	1771749145000	1500000	2328000	Hoyerswerdaer Straße 91
506	51.4841055	14.76693	1771751473000	1771751473000	2328000	1427000	Feuerlöschteich 4
507	51.3269569	14.4965347	1771828800000	1771828860000	1600000	1749000	Grenzstein 91 KS/KP
508	51.5443525	14.5405083	1771830609000	1771831221150	1749000	938000	Friedensstraße 62
510	51.508827	14.6421237	1771266753760	1771267068760	900000	0	Jahnstraße 8
475	51.3398427	14.5088677	1770791836651	1770791896651	1865000	1321000	Eichenallee 16
511	51.52533000000001	14.727186999999999	1770789480000	1770789540000	709000	292000	Krauschwitz Obermühle
512	51.5192568	14.7617199	1770789832000	1770789934200	292000	1865000	Unterdorf 61
513	51.4649548	14.7008748	1771204302819	1771204362819	0	2351000	Schranke 214
514	51.5286634	14.5366817	1771206713819	1771207313819	2351000	0	Rohner Weg 6
515	51.5122227	14.7069889	1770997691484	1770997751484	0	1655000	Randsiedlung 53
516	51.5360245	14.5286573	1770999406484	1770999985734	1655000	0	Neustädter Straße 18
517	51.5145285	14.7948255	1771755768000	1771755768000	906000	988000	Bienengartenweg 14
518	51.507358	14.644218999999998	1771756756000	1771756860000	988000	321000	Weißwasser Muskauer Straße
427	51.508303000000005	14.644146999999998	1771752900000	1771752900000	1485000	958000	Weißwasser Straße des Friedens
384	51.505442	14.638026999999997	1771574851650	1771575038451	1281000	313000	Weißwasser Bahnhof
493	51.5417264	14.5348536	1771861038000	1771861098000	923000	381000	Gemeindeamt
455	51.5394742	14.5159274	1771709160000	1771709160000	250000	515000	Hoyerswerdaer Straße 94
479	51.5443525	14.5405083	1771851000000	1771851060000	68000	1968000	Friedensstraße 62
519	51.5386074	14.5148166	1770912300000	1770912360000	1068000	1754000	Hoyerswerdaer Straße 91
520	51.4238172	14.5804052	1770914114000	1770914727900	1754000	1362000	Block R
521	51.3509265	14.6252181	1771913400000	1771913460000	1671000	1853000	Ernst-Thälmann-Straße 98
522	51.5277052	14.5242631	1771915313000	1771915961550	1853000	1027000	Trebendorfer Weg 116b
523	51.5011183	14.7601445	1771001575050	1771001635050	824000	937000	Brandstraße 10
524	51.505442	14.638026999999997	1771002572050	1771002900000	937000	313000	Weißwasser Bahnhof
525	51.529751000000005	14.659086000000002	1770746760000	1770746820000	467000	1181000	Gablenz Friedhof
526	51.5089519	14.6952169	1770748001000	1770748414350	1181000	1254000	Sanddeponie Keulahütte
527	51.535357	14.5350536	1771872952803	1771873012803	0	1194000	Werksweg 12
528	51.4974095	14.6869049	1771874206803	1771874624703	1194000	0	Am Braunsteich 1
529	51.3379649	14.4933158	1771745899050	1771745959050	1565000	297000	Kosmače
530	51.362845	14.509056000000001	1771746256050	1771746360000	297000	610000	Uhyst (Spree) Bahnhof
532	51.5292289	14.5391334	1771492664000	1771493120400	1304000	895000	Rohner Weg 3
533	51.4915553	14.7143354	1771610647000	1771610700000	547000	1515000	Zum Floßgraben 10D
534	51.5338793	14.5202632	1771612215000	1771612215000	1515000	256000	Grenzweg 106c
531	51.56125	14.5438998	1771491300000	1771491360000	1168000	1304000	Groß Dübener Weg 4
581	51.5295517	14.5240575	1771488486300	1771488546300	1087000	262000	Tischlereiweg 115a
535	51.5397309	14.5335292	1771514616000	1771514676000	289000	1684000	Norma
537	51.5386074	14.5148166	1770754690000	1770754750000	1068000	2493000	Hoyerswerdaer Straße 91
538	51.3464563	14.48255	1770757243000	1770757293000	2493000	2354000	Sarkassenteich
539	51.5056849	14.68697	1771863204000	1771863264000	535000	1528000	Große Modzidla
540	51.5394742	14.5159274	1771864792000	1771864828000	1528000	1113000	Hoyerswerdaer Straße 94
541	51.4276651	14.5366857	1771811442922	1771811502922	0	883000	Dorfstraße 14b
542	51.5295517	14.5240575	1771812385922	1771812694972	883000	0	Tischlereiweg 115a
543	51.5426918	14.5308026	1771514221789	1771514281789	0	856000	Hoyerswerdaer Straße 37
544	51.5069572	14.6307982	1771515137789	1771515437389	856000	0	Forster Straße 26
545	51.5080288	14.6813943	1770997979000	1770998039000	556000	1460000	Keulaer Tiergarten
546	51.5277052	14.5242631	1770999499000	1770999560000	1460000	1027000	Trebendorfer Weg 116b
547	51.3477422	14.6026836	1771101779143	1771101839143	0	1515000	Ernst-Thälmann-Straße 21
548	51.5343123	14.5136158	1771103354143	1771103884393	1515000	0	Forstweg 78a
550	51.5443525	14.5405083	1771708910000	1771708910000	392000	250000	Friedensstraße 62
582	51.532663	14.519262999999999	1771488808300	1771488900000	262000	1168000	Rohne Ausbau
551	51.525705	14.658208	1771706700000	1771706760000	446000	1119000	Große Karoline
552	51.5388861	14.5189616	1771707879000	1771707966000	1119000	552000	Zum Sportplatz 5
549	51.5348316	14.593757	1771708518000	1771708518000	552000	392000	Garten Eden
553	51.535267	14.529270999999998	1771665960000	1771666020000	924000	225000	Schleife Busbahnhof
554	51.5296246	14.5237337	1771666245000	1771666323750	225000	1135000	Tischlereiweg 115a
555	51.548994	14.717790999999998	1771568478650	1771568538650	827000	1429000	Bad Muskau Maßmannplatz
556	51.5388861	14.5189616	1771569967650	1771570009000	1429000	1083000	Zum Sportplatz 5
557	51.508303000000005	14.644146999999998	1771683060000	1771683120000	278000	1248000	Weißwasser Straße des Friedens
558	51.4836416	14.7881383	1771684368000	1771684804800	1248000	1209000	Zur Tanne 86
559	51.5386074	14.5148166	1771643868000	1771643928000	1068000	1707000	Hoyerswerdaer Straße 91
560	51.3470286	14.621655	1771645635000	1771645707000	1707000	1509000	Ernst-Thälmann-Straße 98
561	51.5302251	14.5252029	1771041600000	1771041660000	1116000	2054000	Tischlereiweg 113b
562	51.3697393	14.6281118	1771043714000	1771044432900	2054000	1821000	Schäferei 11
563	51.5347542	14.5339465	1771330200000	1771330260000	880000	356000	Tiefbau-Service-Berton
564	51.5242018	14.5633604	1771330616000	1771330740599	356000	644000	Tiergartenstraße 34
565	51.5295517	14.5240575	1771582476428	1771582536428	0	1548000	Tischlereiweg 115a
566	51.3552702	14.5952281	1771584084428	1771584626228	1548000	0	Dürrbacher Straße 353a
568	51.3754913	14.6097765	1771249891000	1771250090850	571000	1577000	Teichweg 4
569	51.5456749	14.5346691	1771134598390	1771134658390	0	1027000	Spremberger Straße 17
570	51.5145512	14.5339857	1771135685390	1771136044840	1027000	0	Schäferstraße 89a
571	51.3428674	14.4903266	1770842502400	1770842562400	1582000	1714000	Rokotschin
572	51.5341111	14.5351491	1770844276400	1770844414000	1714000	924000	Schleifer Straße 3
573	51.4993125	14.5159216	1771419720283	1771419780283	0	721000	Am Damm 111
574	51.5400866	14.5128586	1771420501283	1771420753632	721000	0	Hoyerswerdaer Straße 98
575	51.3817282	14.6899855	1771178476500	1771178536500	1525000	210000	Reichwalde Ziegelei
576	51.377765	14.669138	1771178746500	1771178820000	210000	1484000	Reichwalde Mühlenstraße
578	51.5319259	14.52021	1771149245000	1771149519750	785000	1080000	Rohne Ausbau
467	51.5005361	14.7603157	1771610100000	1771610100000	832000	1856000	Brandstraße 12
468	51.5295517	14.5240575	1771612471000	1771612665600	1856000	1147000	Tischlereiweg 115a
579	51.505442	14.638026999999997	1771667672000	1771667732000	292000	232000	Weißwasser Bahnhof
580	51.5036597	14.633142	1771667964000	1771668045200	232000	372000	Astrid-Lindgren-Schule
583	51.5066853	14.7943525	1771067347878	1771067407878	0	1735000	Skerbersdorf Bienengarten
584	51.5301599	14.5247083	1771069142878	1771069742878	1735000	0	Tischlereiweg 113b
585	51.5347542	14.5339465	1771441865000	1771441925000	880000	594000	Tiefbau-Service-Berton
586	51.5320382	14.5684693	1771442519000	1771442694000	594000	885000	Kranichweg 15
587	51.5295517	14.5240575	1771849464450	1771849524450	1087000	293000	Tischlereiweg 115a
588	51.543881999999996	14.538559	1771849817450	1771849920000	293000	68000	Schleife Kirche
589	51.5394742	14.5159274	1771294952848	1771295012848	0	1754000	Hoyerswerdaer Straße 94
590	51.3341511	14.4869987	1771296766848	1771297380748	1754000	0	Milkler Straße 14a
591	51.5357337	14.5192924	1771052463094	1771052523094	0	750000	Jahnring 13
592	51.4265192	14.5270988	1771053273094	1771053535594	750000	0	Sprey
567	51.38720099999999	14.607899999999999	1771249260000	1771249320000	949000	571000	Kringelsdorf Denkmal
536	51.4076382	14.5034534	1771516360000	1771516384000	1684000	786000	Ltg 551 und 552 Bärwalde - Schmölln
593	51.5290766	14.5685306	1771048800000	1771048860000	777000	609000	Kranichweg 19
594	51.5417264	14.5348536	1771049469000	1771049682150	609000	1030000	Gemeindeamt
595	51.5352741	14.635998	1771146632400	1771146692400	726000	776000	Azaleenschlucht
596	51.535267	14.529270999999998	1771147468400	1771147740000	776000	690000	Schleife Busbahnhof
577	51.5755532	14.5654744	1771148430000	1771148460000	690000	785000	Dorfstraße 69
597	51.536356	14.5290886	1771052400000	1771052460000	920000	2800000	Friedensstraße 1
598	51.5485412	14.4962388	1771055260000	1771056239999	2800000	3591000	Spremberger Straße 47
599	51.52533000000001	14.727186999999999	1770922680000	1770922740000	709000	1551000	Krauschwitz Obermühle
600	51.4226514	14.933801	1770924291000	1770924833850	1551000	1985000	Tränkeberg
601	51.5158335	14.7097515	1771571516509	1771571576509	0	1400000	Randsiedlung 22
602	51.5393992	14.5316092	1771572976509	1771573466508	1400000	0	Strugaaue 2
603	51.5456749	14.5346691	1771414594798	1771414654798	0	153000	Spremberger Straße 17
604	51.538412	14.5250691	1771414807798	1771414861348	153000	0	Jahnring 21
605	51.5426918	14.5308026	1771167300000	1771167360000	998000	1011000	Hoyerswerdaer Straße 37
606	51.5032265	14.6276629	1771168371000	1771168724850	1011000	287000	Sandstraße 2
607	51.5397943	14.5386138	1771499432000	1771499492000	948000	1755000	Schleife Bahnhof
608	51.3914062	14.5651047	1771501247000	1771501455000	1755000	1563000	B1
609	51.4238172	14.5804052	1770893020450	1770893020450	808000	1335000	Block R
610	51.505888	14.479387000000001	1770894355450	1770894480000	1335000	1274000	Mulkwitz Außenkippe
611	51.3487339	14.5164789	1771367609793	1771367669793	0	1606000	Kleiner Winkelteich
612	51.5296246	14.5237337	1771369275793	1771369837893	1606000	0	Tischlereiweg 115a
613	51.5345327	14.5239956	1771899433953	1771899493953	0	843000	Neustädter Straße 7
614	51.5105621	14.6342527	1771900336953	1771900632003	843000	0	Bennett-Kängurus
615	51.5361935	14.7240704	1771560300000	1771560360000	798000	1632000	Bautzener Straße 15
616	51.5295517	14.5240575	1771561992000	1771562210000	1632000	370000	Tischlereiweg 115a
617	51.5669207	14.7071289	1770780191000	1770780191000	1391000	1267000	Dubrauer Weg 2
618	51.505373000000006	14.639413	1770781458000	1770781560000	1267000	334000	Weißwasser Bahnhof
619	51.505849	14.479243	1770882540000	1770882600000	1215000	1568000	Mulkwitz Außenkippe
620	51.3708642	14.5081998	1770884168000	1770884716800	1568000	1848000	Schloßstraße 25
621	51.5075364	14.6192409	1771601400000	1771601445900	289000	717000	Berliner Straße 107
622	51.5456749	14.5346691	1771602162900	1771602162900	717000	888000	Spremberger Straße 17
623	51.3460419	14.6446321	1771332981450	1771333041450	1518000	473000	Neudorfer Weg 1
624	51.377765	14.669138	1771333514450	1771333680000	473000	1484000	Reichwalde Mühlenstraße
625	51.409541	14.529995	1771310100000	1771310160000	998000	1040000	Merzdorfer Straße 1
626	51.5312432	14.5115818	1771311200000	1771311564000	1040000	1086000	Mühlweg 5b
627	51.360214	14.5035957	1771631624683	1771631684683	0	1514000	Straße des Friedens 7a
628	51.5340052	14.5217744	1771633198683	1771633728583	1514000	0	Grenzweg 107a
629	51.499228	14.625229	1771475091000	1771475151000	125000	945000	Weißwasser Sachsendamm
630	51.5329343	14.5196775	1771476096000	1771476426750	945000	1021000	Rohne Ausbau
631	51.4421732	14.5161153	1771407900000	1771407960000	1073000	845000	Alter Spreeverlauf
632	51.5386074	14.5148166	1771408805000	1771409100750	845000	1123000	Hoyerswerdaer Straße 91
633	51.5319259	14.52021	1771133411363	1771133471363	0	1469000	Rohne Ausbau
634	51.5441549	14.707984	1771134940363	1771135454512	1469000	0	Mozartweg 13
635	51.5400866	14.5128586	1771245082000	1771245142000	316000	1744000	Hoyerswerdaer Straße 98
636	51.3396439	14.5062725	1771246886000	1771247044000	1744000	949000	Eichenallee 16
638	51.554568999999994	14.543554	1771826097701	1771826160000	178000	1070000	Schleife Milchviehanlage
639	51.4953694	14.6226751	1770870661489	1770870721489	0	1004000	Werner-Seelenbinder-Straße 54a
640	51.5399955	14.5160315	1770871725489	1770872076889	1004000	0	Hoyerswerdaer Straße 90
641	51.5344465	14.5268116	1771785413226	1771785473226	0	218000	Mulkwitzer Weg 2a
642	51.5280081	14.4982534	1771785691226	1771785767526	218000	0	Spremberger Weg 71
643	51.505396000000005	14.639304999999998	1770826200000	1770826260000	295000	1351000	Weißwasser Bahnhof
644	51.4746781	14.8988675	1770827611000	1770828083849	1351000	1347000	Lager Werdeck
645	51.5294693	14.625319	1771336287000	1771336347000	1258000	780000	Kromlau Waldeisenbahn
646	51.533747	14.595647000000001	1771337127000	1771337400000	780000	598000	Halbendorf (b Weißwasser) Gewerbegebiet
647	51.4990486	14.5249564	1771650510253	1771650570253	0	735000	Schutzpflanzung
648	51.5343123	14.5136158	1771651305253	1771651562502	735000	0	Forstweg 78a
649	51.3409271	14.5852008	1770956904200	1770956964200	0	1686000	Winterteich 1
650	51.5405733	14.520827	1770958650200	1770959240300	1686000	0	Thälmann-Siedlung 25
651	51.5417264	14.5348536	1771086000000	1771086060000	923000	1693000	Gemeindeamt
652	51.3438513	14.5414283	1771087753000	1771088345550	1693000	1567000	ehem. Großer Kascheler Teich
653	51.5167167	14.753935	1770896329450	1770896389450	700000	1657000	Hüttenstraße 1
654	51.5319259	14.52021	1770898046450	1770898057000	1657000	1080000	Rohne Ausbau
655	51.5147037	14.6237708	1770973509193	1770973569193	0	1273000	Gablenzer Weg 31
656	51.5329343	14.5196775	1770974842193	1770975287743	1273000	0	Rohne Ausbau
637	51.5610558	14.5479444	1771825859701	1771825919701	695000	178000	Groß-Dübener Weg 16
657	51.3304167	14.634597	1771821121000	1771821121000	2404000	2016000	Kreuzberge
658	51.505888	14.479387000000001	1771823137000	1771823280000	2016000	695000	Mulkwitz Außenkippe
659	51.5402438	14.4640151	1771401296129	1771401356129	0	2258000	Graustein Süd
660	51.5345327	14.5239956	1771403614129	1771404404429	2258000	0	Neustädter Straße 7
661	51.505442	14.638026999999997	1771879200000	1771879260000	292000	545000	Weißwasser Bahnhof
662	51.5151769	14.6656976	1771879805000	1771879995750	545000	744000	Seerosenteich
663	51.3173833	14.5666723	1771240700250	1771240760250	2499000	1185000	Läuferstein 77-14 KS/KP
664	51.348580999999996	14.590756	1771241945250	1771242360000	1185000	610000	Klitten Bahnhof
665	51.3552702	14.5952281	1771903343000	1771903403000	1343000	1458000	Dürrbacher Straße 353a
666	51.5345327	14.5239956	1771904861000	1771904958000	1458000	1002000	Neustädter Straße 7
667	51.543881999999996	14.538559	1770968580000	1770968640000	884000	1044000	Schleife Kirche
669	51.505442	14.638026999999997	1771432800000	1771432860000	292000	412000	Weißwasser Bahnhof
670	51.4856166	14.6618971	1771433272000	1771433416200	412000	302000	Industriestraße Ost 8
671	51.505849	14.479243	1770918540000	1770918600000	1215000	1022000	Mulkwitz Außenkippe
672	51.3657075	14.5017085	1770919622000	1770919979700	1022000	1302000	Agrarhandel Uhyst
673	51.5196746	14.575182	1771798599443	1771798659443	0	666000	Zum Pechofen 8
674	51.5322939	14.5345323	1771799325443	1771799558542	666000	0	Reinert Ranch
668	51.4107278	14.5707563	1770969684000	1770970049400	1044000	1052000	Ltg MN und MP sowie MQ und MR Boxberg - Bärwalde
675	51.5443525	14.5405083	1770971122650	1770971182650	1052000	161000	Friedensstraße 62
676	51.535121000000004	14.528802999999998	1770971343650	1770971400000	161000	1007000	Schleife Busbahnhof
677	51.5290227	14.5298561	1771854402922	1771854462922	0	986000	Rohner Weg 17
678	51.5034748	14.6563233	1771855448922	1771855794022	986000	0	Telux
679	51.417514	14.549752	1771519560000	1771519620000	786000	1041000	Boxberg Warmwasseranlage
681	51.5342031	14.5217853	1771150628081	1771150688081	0	1236000	Neustädter Straße 10
682	51.5057379	14.6603813	1771151924081	1771152356681	1236000	0	Sägewerk und Holzhandel Kopte
683	51.3825141	14.6013787	1771651500000	1771651560000	1062000	1249000	Teichweg 3a
684	51.5347542	14.5339465	1771652809000	1771653246150	1249000	940000	Tiefbau-Service-Berton
685	51.3599108	14.6637444	1771322514900	1771322574900	1589000	226000	Niederteich
686	51.377765	14.669138	1771322800900	1771322880000	226000	1484000	Reichwalde Mühlenstraße
687	51.50463	14.634229999999999	1770972960000	1770973020000	248000	1919000	Weißwasser Landau-Gymnasium
688	51.4496704	14.7311198	1770974939000	1770975610650	1919000	1910000	Goldberge
689	51.3210427	14.6275272	1770726730200	1770726790200	1707000	1548000	Förstgener Straße 6
690	51.505888	14.479387000000001	1770728338200	1770728880000	1548000	1274000	Mulkwitz Außenkippe
691	51.52533000000001	14.727186999999999	1770803880000	1770803940000	709000	410000	Krauschwitz Obermühle
692	51.5042624	14.7978543	1770804350000	1770804493500	410000	844000	Skerbersdorf Bienengarten
680	51.5302251	14.5252029	1771520661000	1771521025350	1041000	2027000	Tischlereiweg 113b
693	51.5763797	14.7157985	1771523176000	1771523236000	2027000	1184000	Schulstraße 7a
694	51.498825000000004	14.714700999999998	1771525300000	1771525980000	466000	544000	Weißkeißel Straße der Freundschaft
311	51.529751000000005	14.659086000000002	1771524420000	1771524420000	1184000	414000	Gablenz Friedhof
312	51.5267372	14.7081132	1771524834000	1771524834000	414000	466000	Lange Straße 19
695	51.5241709	14.5748701	1771917600000	1771917660000	667000	602000	Grüne Aue 11
696	51.5292355	14.5213952	1771918262000	1771918472700	602000	1079000	Gefallenendenkmale Rohne
697	51.3431256	14.5113489	1771581466950	1771581526950	1590000	943000	Truhenteich
698	51.407126	14.574806	1771582469950	1771582800000	943000	882000	Boxberg Am Schöps
699	51.505563	14.638612999999998	1771353360000	1771353420000	291000	888000	Weißwasser Bahnhof
700	51.5305303	14.5320261	1771354308000	1771354618800	888000	170000	Rohner Weg 10
701	51.5400866	14.5128586	1771777200000	1771777260000	1095000	955000	Hoyerswerdaer Straße 98
702	51.4360232	14.5371601	1771778215000	1771778549250	955000	1113000	Spreyer Höhe
703	51.5525502	14.7129388	1771584338950	1771584338950	987000	580000	Köbelner Straße 19
704	51.53425	14.663793	1771584918950	1771584900000	580000	581000	Gablenz Feuerwehr
\.


--
-- Data for Name: fcm_token; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fcm_token (device_id, company, fcm_token) FROM stdin;
\.


--
-- Data for Name: journey; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.journey (id, json, "user", request1, request2, rating, comment, rating_booking, reason) FROM stdin;
\.


--
-- Data for Name: kysely_migration; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.kysely_migration (name, "timestamp") FROM stdin;
2024-07-01	2026-02-10T09:32:27.365Z
2025-04-07	2026-02-10T09:32:27.367Z
2025-04-24-json-and-latlng-precision	2026-02-10T09:32:27.380Z
2025-04-30	2026-02-10T09:32:27.420Z
2025-05-21	2026-02-10T09:32:27.421Z
2025-08-06-feedback	2026-02-10T09:32:27.421Z
2025-08-21-company-phone	2026-02-10T09:32:27.422Z
2025-08-22	2026-02-10T09:32:27.423Z
2025-08-23-concatenation-updates	2026-02-10T09:32:27.425Z
2025-08-24-event-groups	2026-02-10T09:32:27.444Z
2025-09-11-service-acc	2026-02-10T09:32:27.445Z
2025-09-12-license-plate-updates	2026-02-10T09:32:27.446Z
2025-09-18-metadata	2026-02-10T09:32:27.447Z
2025-09-30-ride-share-backend	2026-02-10T09:32:27.470Z
2025-10-07-ride-share-picutures	2026-02-10T09:32:27.470Z
2025-10-08-ride-share-rating	2026-02-10T09:32:27.478Z
2025-10-12-cancel-ride-share-tour	2026-02-10T09:32:27.478Z
2025-10-23-merge-event-groups	2026-02-10T09:32:27.479Z
2025-10-30-unique	2026-02-10T09:32:27.486Z
2025-11-12-ride-share-zone	2026-02-10T09:32:27.499Z
2025-11-28-default-vehicle	2026-02-10T09:32:27.500Z
\.


--
-- Data for Name: kysely_migration_lock; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.kysely_migration_lock (id, is_locked) FROM stdin;
migration_lock	0
\.


--
-- Data for Name: request; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.request (id, passengers, kids_zero_to_two, kids_three_to_four, kids_five_to_six, wheelchairs, bikes, luggage, tour, customer, ticket_code, ticket_checked, cancelled, ticket_price, license_plate_updated_at, created_at, ride_share_tour, start_fixed, bus_stop_time, requested_time, pending) FROM stdin;
10	2	0	0	0	0	0	0	9	1	4902e749588eb8d76137d94ef95272db	f	t	1000	\N	2026-02-10 09:36:19.452711	\N	\N	\N	\N	f
9	1	0	0	0	0	0	0	8	1	ecf51d29780634ac05fc0a7ca12e60e2	f	t	500	\N	2026-02-10 09:36:17.661967	\N	\N	\N	\N	f
4	2	0	0	0	0	0	0	4	1	18559efd6df0cb2bc490c106e6abb501	f	t	1000	\N	2026-02-10 09:36:03.193776	\N	\N	\N	\N	f
11	2	0	0	0	0	0	0	10	1	ecfbfb31670eec4a2f8d7efab4e53fa9	f	t	1000	\N	2026-02-10 09:36:25.889376	\N	\N	\N	\N	f
15	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:36:40.385648	2	\N	\N	\N	f
8	1	0	0	0	0	0	0	7	1	8573cdfaa31c5274f10bf4605d744583	f	t	500	\N	2026-02-10 09:36:16.426093	\N	\N	\N	\N	f
13	1	0	0	0	0	0	0	12	1	2565e3fd2046b4d89fc1d74beab0863d	f	t	500	\N	2026-02-10 09:36:30.941318	\N	\N	\N	\N	f
28	2	0	0	0	0	0	0	24	1	75735f702ffdb4ffdbbc50817a295153	f	t	1000	\N	2026-02-10 09:37:23.346217	\N	\N	\N	\N	f
6	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:36:07.95135	1	\N	\N	\N	f
35	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:36.797903	9	\N	\N	\N	f
31	1	0	0	0	0	0	0	25	1	b102d99f4873b040aef315821f0ebe36	f	t	500	\N	2026-02-10 09:37:30.528956	\N	\N	\N	\N	f
17	2	0	0	0	0	0	0	14	1	376abf19729e328d4da1ef0d49b2224d	f	t	1000	\N	2026-02-10 09:36:46.203073	\N	\N	\N	\N	f
38	2	0	0	0	0	0	0	29	1	6d120a6aeb8727a1c47d97fad8498f37	f	t	1000	\N	2026-02-10 09:37:50.570156	\N	\N	\N	\N	f
5	1	0	0	0	0	0	0	5	1	d227c870bf96b39c7879c635b0f38040	f	t	500	\N	2026-02-10 09:36:05.206962	\N	\N	\N	\N	f
22	2	0	0	0	0	0	0	19	1	cf9d1ffe8dd6ee17c8a803204a805951	f	t	1000	\N	2026-02-10 09:37:01.026572	\N	\N	\N	\N	f
33	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:34.142809	7	\N	\N	\N	f
46	2	0	0	0	0	0	0	36	1	7077f86b7c257aa1bd0fbd5b9d8a848f	f	t	1000	\N	2026-02-10 09:38:34.505291	\N	\N	\N	\N	f
48	1	0	0	0	0	0	0	38	1	8bde4404fa6c9fddaefa4fefe86eb9a0	f	f	500	\N	2026-02-10 09:38:47.386984	\N	\N	\N	\N	f
26	1	0	0	0	0	0	0	22	1	b8448a001638cab280aa100146fb4917	f	t	500	\N	2026-02-10 09:37:13.633313	\N	\N	\N	\N	f
12	1	0	0	0	0	0	0	11	1	b2611744a4e374ddea17565e7a289202	f	t	500	\N	2026-02-10 09:36:28.457551	\N	\N	\N	\N	f
51	1	0	0	0	0	0	0	40	1	017ade33a064f3b03c8b25461a20df54	f	f	500	\N	2026-02-10 09:38:58.516734	\N	\N	\N	\N	f
52	1	0	0	0	0	0	0	41	1	6913535aed6df73c1b0c3239254e1b6e	f	t	500	\N	2026-02-10 09:39:02.854383	\N	\N	\N	\N	f
39	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:57.838514	10	\N	\N	\N	f
20	1	0	0	0	0	0	0	17	1	85db1f0bbd965b6636b94d28f6197ee9	f	t	500	\N	2026-02-10 09:36:55.175886	\N	\N	\N	\N	f
16	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:36:42.316588	3	\N	\N	\N	f
54	1	0	0	0	0	0	0	43	1	7d10f0ee8dd403fcd93b7ff01c66b5ca	f	f	500	\N	2026-02-10 09:39:20.044913	\N	\N	\N	\N	f
25	1	0	0	0	0	0	0	21	1	a4e3ec0f7e3b62d6ebbe2600e602fb95	f	t	500	\N	2026-02-10 09:37:12.133843	\N	\N	\N	\N	f
7	2	0	0	0	0	0	0	6	1	faa74f878228a87c899ebaf114e0b0f1	f	t	1000	\N	2026-02-10 09:36:13.298113	\N	\N	\N	\N	f
37	1	0	0	0	0	0	0	28	1	13a8a6f610e78a69ab3efea1af7e8fe8	f	t	500	\N	2026-02-10 09:37:46.88024	\N	\N	\N	\N	f
62	2	0	0	0	0	0	0	50	1	b0da02f781e58cb0408f6774b7bfea9d	f	f	1000	\N	2026-02-10 09:39:51.768574	\N	\N	\N	\N	f
55	1	0	0	0	0	0	0	44	1	1e7ddbc71b10d00b40697d12866ea536	f	t	500	\N	2026-02-10 09:39:24.533721	\N	\N	\N	\N	f
29	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:25.843182	5	\N	\N	\N	f
18	1	0	0	0	0	0	0	15	1	41a54a8ac36da97aa5be22808d177ad7	f	t	500	\N	2026-02-10 09:36:49.781895	\N	\N	\N	\N	f
32	2	0	0	0	0	0	0	26	1	5260062392f8a211a4037ab2f4fa1353	f	t	1000	\N	2026-02-10 09:37:33.165564	\N	\N	\N	\N	f
57	2	0	0	0	0	0	0	46	1	7e689df786e0964d3dc1736cc49985c5	f	t	1000	\N	2026-02-10 09:39:33.694318	\N	\N	\N	\N	f
45	2	0	0	0	0	0	0	35	1	b979e8c0147c91bc5fb9eac2570f0493	f	t	1000	\N	2026-02-10 09:38:29.5501	\N	\N	\N	\N	f
30	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:27.414158	6	\N	\N	\N	f
3	2	0	0	0	0	0	0	3	1	766407f432f720131689059d8f19390a	f	t	1000	\N	2026-02-10 09:36:01.946862	\N	\N	\N	\N	f
1	2	0	0	0	0	0	0	1	1	de8e2b15b9ac2630d50c7e8f316c5bc6	f	t	1000	\N	2026-02-10 09:35:57.016858	\N	\N	\N	\N	f
49	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:38:49.078259	11	\N	\N	\N	f
34	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:34.653001	8	\N	\N	\N	f
44	2	0	0	0	0	0	0	34	1	41d41dc0581d6ce9e2470ae85982fd84	f	t	1000	\N	2026-02-10 09:38:24.238132	\N	\N	\N	\N	f
41	1	0	0	0	0	0	0	31	1	20303a0a02a6d1d18798d6a2a7183dbb	f	t	500	\N	2026-02-10 09:38:15.171108	\N	\N	\N	\N	f
59	1	0	0	0	0	0	0	47	1	d2756649b79c42c813a1665e38f8d900	f	t	500	\N	2026-02-10 09:39:39.129915	\N	\N	\N	\N	f
43	2	0	0	0	0	0	0	33	1	98e786ea8ba2d4723d6540835ca9aa05	f	t	1000	\N	2026-02-10 09:38:21.597728	\N	\N	\N	\N	f
58	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:39:37.108376	12	\N	\N	\N	f
21	2	0	0	0	0	0	0	18	1	ad04168814d7e4cb0f1a7f44337a7f61	f	t	1000	\N	2026-02-10 09:36:57.682443	\N	\N	\N	\N	f
19	2	0	0	0	0	0	0	16	1	fbc8a8ff39d71ddb87890ccbb2ff746e	f	t	1000	\N	2026-02-10 09:36:52.557595	\N	\N	\N	\N	f
24	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:37:10.6899	4	\N	\N	\N	f
47	2	0	0	0	0	0	0	37	1	3adc0af917598101a5b205fdaae5e5b4	f	t	1000	\N	2026-02-10 09:38:42.672899	\N	\N	\N	\N	f
50	1	0	0	0	0	0	0	39	1	5f4e8839d966c06f7ac9f4aa199507fd	f	t	500	\N	2026-02-10 09:38:54.10565	\N	\N	\N	\N	f
61	1	0	0	0	0	0	0	49	1	864cec0163ec5d5ebbd91b791f866a48	f	t	500	\N	2026-02-10 09:39:48.118384	\N	\N	\N	\N	f
2	1	0	0	0	0	0	0	2	1	8fec4a1e24aed1c2f464be464d1f15bd	f	t	500	\N	2026-02-10 09:35:59.302717	\N	\N	\N	\N	f
27	2	0	0	0	0	0	0	23	1	69a6a71d9e35fb1ce3550f78a8c5198c	f	t	1000	\N	2026-02-10 09:37:21.206501	\N	\N	\N	\N	f
42	2	0	0	0	0	0	0	32	1	fc0f47a5bfd18defda2e68038aa252f9	f	t	1000	\N	2026-02-10 09:38:16.454884	\N	\N	\N	\N	f
63	1	0	0	0	0	0	0	51	1	a2d1a7ed922ae8095aff6f2ec74e2e31	f	t	500	\N	2026-02-10 09:39:59.565796	\N	\N	\N	\N	f
40	2	0	0	0	0	0	0	30	1	b164413a9133f46d0b10c925c1776b3b	f	t	1000	\N	2026-02-10 09:37:59.956493	\N	\N	\N	\N	f
229	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:55:12.979019	44	\N	\N	\N	f
53	1	0	0	0	0	0	0	42	1	957ca3cdc53107c345c4d9ff8d42a862	f	t	500	\N	2026-02-10 09:39:15.247735	\N	\N	\N	\N	f
23	1	0	0	0	0	0	0	20	1	76793b27b4aaf03cdeb81b20c3e28a77	f	t	500	\N	2026-02-10 09:37:06.945838	\N	\N	\N	\N	f
56	1	0	0	0	0	0	0	45	1	debdf755f8418fffeb083953bf31777d	f	t	500	\N	2026-02-10 09:39:26.527823	\N	\N	\N	\N	f
14	1	0	0	0	0	0	0	13	1	6d3500fd2330d65d625bbf3faf26f270	f	t	500	\N	2026-02-10 09:36:33.107384	\N	\N	\N	\N	f
65	2	0	0	0	0	0	0	53	1	8da21eb4c2b55b42f3de9296ce0950c9	f	f	1000	\N	2026-02-10 09:40:06.681092	\N	\N	\N	\N	f
36	2	0	0	0	0	0	0	27	1	793552607622a6ac88cbc2ec2bf1743b	f	t	1000	\N	2026-02-10 09:37:41.137363	\N	\N	\N	\N	f
70	1	0	0	0	0	0	0	58	1	3b2fa9ddfbf43d48191cdaca4434b85d	f	f	500	\N	2026-02-10 09:40:29.056877	\N	\N	\N	\N	f
71	2	0	0	0	0	0	0	59	1	19319939214728dbf3168c52f6be49fd	f	f	1000	\N	2026-02-10 09:40:36.633234	\N	\N	\N	\N	f
72	1	0	0	0	0	0	0	60	1	335b50a3e3a11c2ba0b2d67c1a9d539c	f	f	500	\N	2026-02-10 09:40:39.059127	\N	\N	\N	\N	f
80	1	0	0	0	0	0	0	65	1	ee9a4c39f73734ee6cfeb95ce3e93443	f	f	500	\N	2026-02-10 09:41:05.181765	\N	\N	\N	\N	f
84	2	0	0	0	0	0	0	68	1	bddb2e766e604120095c8314c14e3f70	f	f	1000	\N	2026-02-10 09:41:23.79899	\N	\N	\N	\N	f
73	2	0	0	0	0	0	0	61	1	d31e88915d268982ed5f4751a7d53442	f	t	1000	\N	2026-02-10 09:40:43.922404	\N	\N	\N	\N	f
83	2	0	0	0	0	0	0	67	1	a1687d9f74964e2df1002913eb465445	f	t	1000	\N	2026-02-10 09:41:19.819076	\N	\N	\N	\N	f
90	1	0	0	0	0	0	0	\N	1		f	t	0	\N	2026-02-10 09:41:45.440853	8	t	1771741500000	1771741500000	f
78	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:40:59.53574	14	\N	\N	\N	f
81	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:41:07.917671	15	\N	\N	\N	f
82	2	0	0	0	0	0	0	66	1	b238bfd6d5f033a073f3a50c7cdfe6ba	f	t	1000	\N	2026-02-10 09:41:16.833915	\N	\N	\N	\N	f
74	2	0	0	0	0	0	0	47	1	06213c61f13e1eb2c1d45118e509208f	f	t	1000	\N	2026-02-10 09:40:48.918756	\N	\N	\N	\N	f
107	2	0	0	0	0	0	0	83	1	a40d0df6667952cea008d312228f3c0b	f	t	1000	\N	2026-02-10 09:42:57.826798	\N	\N	\N	\N	f
89	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:41:34.931194	18	\N	\N	\N	f
88	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:41:32.389588	17	\N	\N	\N	f
95	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:42:06.987468	19	\N	\N	\N	f
113	2	0	0	0	0	0	0	87	1	2a2a7dbecb008f9ff61c316a997f1831	f	f	1000	\N	2026-02-10 09:43:30.424987	\N	\N	\N	\N	f
66	1	0	0	0	0	0	0	54	1	cde06998f0eb117e82793672b216a228	f	t	500	\N	2026-02-10 09:40:09.157518	\N	\N	\N	\N	f
104	2	0	0	0	0	0	0	80	1	d19721c7830d88a64e4a84b31c48ee45	f	t	1000	\N	2026-02-10 09:42:48.953973	\N	\N	\N	\N	f
86	2	0	0	0	0	0	0	70	1	892ca7d13d9d74b0b9375bbac1b5d3be	f	t	1000	\N	2026-02-10 09:41:28.695935	\N	\N	\N	\N	f
115	1	0	0	0	0	0	0	89	1	06b811959c4df3fb7b84b64d53b24084	f	f	500	\N	2026-02-10 09:43:50.161768	\N	\N	\N	\N	f
68	2	0	0	0	0	0	0	56	1	72f559451a286e335e1acdc9300f3f4d	f	t	1000	\N	2026-02-10 09:40:22.698934	\N	\N	\N	\N	f
64	2	0	0	0	0	0	0	52	1	7287df1d41f1f750195d17603ddf1767	f	t	1000	\N	2026-02-10 09:40:01.773939	\N	\N	\N	\N	f
121	2	0	0	0	0	0	0	93	1	be8ee66ab533346e8c224b1a58c80288	f	f	1000	\N	2026-02-10 09:44:18.814156	\N	\N	\N	\N	f
122	2	0	0	0	0	0	0	94	1	e1a816b35ba3cc0f7cfdd106b39b83c9	f	f	1000	\N	2026-02-10 09:44:25.568497	\N	\N	\N	\N	f
124	2	0	0	0	0	0	0	96	1	921f390199ed7f7191faa38a63491c8e	f	f	1000	\N	2026-02-10 09:44:33.428876	\N	\N	\N	\N	f
120	1	0	0	0	0	0	0	16	1	7f3fac479ce0b852c1bd961f4b5a2be1	f	t	500	\N	2026-02-10 09:44:14.924653	\N	\N	\N	\N	f
102	1	0	0	0	0	0	0	52	1	f0da616cceaf7d587a8a8af0e1694693	f	t	500	\N	2026-02-10 09:42:38.828203	\N	\N	\N	\N	f
67	2	0	0	0	0	0	0	55	1	568029f2323154d4a9f23cdb0c9ca8a3	f	t	1000	\N	2026-02-10 09:40:11.686677	\N	\N	\N	\N	f
98	1	0	0	0	0	0	0	77	1	3f069a0562e646ec8403d73b1075dd5a	f	t	500	\N	2026-02-10 09:42:21.790207	\N	\N	\N	\N	f
125	2	0	0	0	0	0	0	97	1	2c0e137f16e99e22e5767b6d98a5e3db	f	t	1000	\N	2026-02-10 09:44:36.767541	\N	\N	\N	\N	f
91	2	0	0	0	0	0	0	71	1	a4160f1865b6bcd2a31c42d2836e64b0	f	t	1000	\N	2026-02-10 09:41:46.496523	\N	\N	\N	\N	f
118	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:44:06.395888	22	\N	\N	\N	f
112	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:43:25.966999	21	\N	\N	\N	f
117	2	0	0	0	0	0	0	91	1	932e75719414b49cfd2d8f26bf7f2589	f	t	1000	\N	2026-02-10 09:44:02.872513	\N	\N	\N	\N	f
105	1	0	0	0	0	0	0	81	1	9a27bf4a2b4100b18437db31124ab688	f	t	500	\N	2026-02-10 09:42:53.496466	\N	\N	\N	\N	f
92	2	0	0	0	0	0	0	87	1	3732001d2a3d96893b79eac7d5638186	f	f	1000	\N	2026-02-10 09:41:53.985924	\N	\N	\N	\N	f
87	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:41:30.210979	16	\N	\N	\N	f
114	2	0	0	0	0	0	0	88	1	e9a4e9b5e532d231f19ba1890eb08920	f	t	1000	\N	2026-02-10 09:43:47.520839	\N	\N	\N	\N	f
100	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:42:34.516392	20	\N	\N	\N	f
75	2	0	0	0	0	0	0	62	1	61d63f323baa40c3b61f477345daf808	f	t	1000	\N	2026-02-10 09:40:51.273194	\N	\N	\N	\N	f
101	1	0	0	0	0	0	0	78	1	ceb85fd6feadd923124544791f6313a2	f	t	500	\N	2026-02-10 09:42:35.420642	\N	\N	\N	\N	f
119	2	0	0	0	0	0	0	92	1	eabcf15b021f542025da3fef71c5ce83	f	t	1000	\N	2026-02-10 09:44:12.485431	\N	\N	\N	\N	f
111	1	0	0	0	0	0	0	86	1	4839977f5cb02951e22419f09c8fd3b9	f	t	500	\N	2026-02-10 09:43:24.079745	\N	\N	\N	\N	f
106	1	0	0	0	0	0	0	82	1	4997c4f9ccf921a325aab4a3169a400e	f	t	500	\N	2026-02-10 09:42:55.212842	\N	\N	\N	\N	f
97	1	0	0	0	0	0	0	76	1	5ee285aef12f35c256310651a5c3d906	f	t	500	\N	2026-02-10 09:42:14.952656	\N	\N	\N	\N	f
109	1	0	0	0	0	0	0	85	1	2edf7c5fa02a4383e19c7216e52f78a6	f	t	500	\N	2026-02-10 09:43:04.203701	\N	\N	\N	\N	f
96	2	0	0	0	0	0	0	75	1	85952f2f88d59375d9b1dbcbffbc3adc	f	t	1000	\N	2026-02-10 09:42:09.120737	\N	\N	\N	\N	f
77	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:40:58.538609	13	\N	\N	\N	f
76	2	0	0	0	0	0	0	63	1	daaeebd3fb473ded6a597681419102f0	f	t	1000	\N	2026-02-10 09:40:54.645215	\N	\N	\N	\N	f
94	1	0	0	0	0	0	0	74	1	906e1dfeb1d2bc6353543956d26ea28c	f	t	500	\N	2026-02-10 09:42:01.284366	\N	\N	\N	\N	f
93	1	0	0	0	0	0	0	73	1	ef8a491272bc3123b93cad6b3c6578d4	f	t	500	\N	2026-02-10 09:41:57.498507	\N	\N	\N	\N	f
103	2	0	0	0	0	0	0	79	1	214b214ba52903f25a15a1c7a0d036e2	f	t	1000	\N	2026-02-10 09:42:44.15876	\N	\N	\N	\N	f
79	2	0	0	0	0	0	0	64	1	ac7a8d999ac6a7fd3bfa6863da3d2fe5	f	t	1000	\N	2026-02-10 09:41:00.829577	\N	\N	\N	\N	f
252	2	0	0	0	0	0	0	177	1	0f9bfd034ce838b36040f782ea5931c8	f	f	1000	\N	2026-02-10 09:57:52.225498	\N	\N	\N	\N	f
251	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:57:50.864115	48	\N	\N	\N	f
108	1	0	0	0	0	0	0	193	1	7ce7d109c044a43bd308241c558e1766	f	f	500	\N	2026-02-10 09:43:01.478093	\N	\N	\N	\N	f
69	1	0	0	0	0	0	0	57	1	5301c6d7b824432d62098102e1e56716	f	t	500	\N	2026-02-10 09:40:25.190591	\N	\N	\N	\N	f
99	1	0	0	0	0	0	0	69	1	40f18fe2794498910d9b69192f944574	f	t	500	\N	2026-02-10 09:42:32.988901	\N	\N	\N	\N	f
116	1	0	0	0	0	0	0	90	1	a778d46b434365f234a0414200689568	f	t	500	\N	2026-02-10 09:43:56.703497	\N	\N	\N	\N	f
130	2	0	0	0	0	0	0	100	1	b0fb6778742783314ae79d0ec33a146a	f	f	1000	\N	2026-02-10 09:45:11.348397	\N	\N	\N	\N	f
131	1	0	0	0	0	0	0	20	1	e1ee648049f69ac6ae35dff205ec9ec1	f	f	500	\N	2026-02-10 09:45:18.038868	\N	\N	\N	\N	f
128	2	0	0	0	0	0	0	99	1	e378a51586e2a13edd44d2914e5f26f4	f	t	1000	\N	2026-02-10 09:44:48.843806	\N	\N	\N	\N	f
133	2	0	0	0	0	0	0	101	1	4991496cda57049bcfcb961a56ccf7c4	f	f	1000	\N	2026-02-10 09:45:29.810002	\N	\N	\N	\N	f
135	1	0	0	0	0	0	0	2	1	f5e25f86b63da4f1a79e42a15559f505	f	f	500	\N	2026-02-10 09:45:47.611284	\N	\N	\N	\N	f
136	1	0	0	0	0	0	0	103	1	f84743829ceec62132f62ec9442932a9	f	t	500	\N	2026-02-10 09:46:07.697289	\N	\N	\N	\N	f
129	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:45:08.560382	23	\N	\N	\N	f
139	2	0	0	0	0	0	0	87	1	9a3a2aa6f822d9885b0f731088255ce2	f	f	1000	\N	2026-02-10 09:46:19.267287	\N	\N	\N	\N	f
141	2	0	0	0	0	0	0	106	1	f5bb066c73ca531e1e2673db424cef52	f	f	1000	\N	2026-02-10 09:46:39.941549	\N	\N	\N	\N	f
132	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:45:23.097641	24	\N	\N	\N	f
143	2	0	0	0	0	0	0	107	1	e7574fae6a00427fa6d42674cc221596	f	f	1000	\N	2026-02-10 09:46:48.841457	\N	\N	\N	\N	f
145	2	0	0	0	0	0	0	108	1	e7f2f8b6c8bd3dd39e7b2840c047fbcf	f	f	1000	\N	2026-02-10 09:46:53.41369	\N	\N	\N	\N	f
146	1	0	0	0	0	0	0	109	1	0b682d0f91858d3cf4eef38d4567ee07	f	f	500	\N	2026-02-10 09:47:05.113185	\N	\N	\N	\N	f
147	1	0	0	0	0	0	0	110	1	71d99100d2e9a4e84f6321b8b5946a77	f	f	500	\N	2026-02-10 09:47:16.884544	\N	\N	\N	\N	f
148	1	0	0	0	0	0	0	111	1	df271ef0378597d52f4bfdaffa129cf8	f	f	500	\N	2026-02-10 09:47:21.880429	\N	\N	\N	\N	f
150	1	0	0	0	0	0	0	113	1	1e4645bec5a4b9106821c15589d8841c	f	f	500	\N	2026-02-10 09:47:32.16896	\N	\N	\N	\N	f
144	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:46:51.671377	27	\N	\N	\N	f
156	2	0	0	0	0	0	0	117	1	041d966cc85504c14eb6c8cd31795f72	f	f	1000	\N	2026-02-10 09:48:07.05809	\N	\N	\N	\N	f
138	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:46:17.589373	25	\N	\N	\N	f
159	1	0	0	0	0	0	0	119	1	2b62616e33cdc49ca8403011acb3f5a0	f	f	500	\N	2026-02-10 09:48:28.951843	\N	\N	\N	\N	f
161	2	0	0	0	0	0	0	121	1	24c0971c180c46a40b0a96cc0cf39a23	f	f	1000	\N	2026-02-10 09:48:38.23548	\N	\N	\N	\N	f
164	1	0	0	0	0	0	0	124	1	b7bee24b9a073deb3ad531e6b3f1dbfb	f	f	500	\N	2026-02-10 09:48:49.547705	\N	\N	\N	\N	f
165	1	0	0	0	0	0	0	125	1	44fa06874b536079a8fe04f0702dd838	f	f	500	\N	2026-02-10 09:48:54.862095	\N	\N	\N	\N	f
142	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:46:47.654919	26	\N	\N	\N	f
155	2	0	0	0	0	0	0	116	1	e1f9e9a3b68bd915685a5541b1ae70be	f	t	1000	\N	2026-02-10 09:48:03.916914	\N	\N	\N	\N	f
151	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:47:39.895162	28	\N	\N	\N	f
166	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:49:00.984389	30	\N	\N	\N	f
152	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:47:42.868226	29	\N	\N	\N	f
170	1	0	0	0	0	0	0	129	1	418fedd13d2494cf6c9000c8bd68ece7	f	f	500	\N	2026-02-10 09:49:42.602807	\N	\N	\N	\N	f
184	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:50:37.490774	33	\N	\N	\N	f
171	2	0	0	0	0	0	0	100	1	eecef5ea6aa40004b6a14a8e44958eda	f	f	1000	\N	2026-02-10 09:49:47.943755	\N	\N	\N	\N	f
172	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:49:52.52743	31	\N	\N	\N	f
178	1	0	0	0	0	0	0	134	1	5fe2af06d0fd4d8d399196a393c2209a	f	f	500	\N	2026-02-10 09:50:20.00068	\N	\N	\N	\N	f
182	1	0	0	0	0	0	0	137	1	5be19c2caa015ac0f8e6cc7cb08ac1c3	f	f	500	\N	2026-02-10 09:50:30.315216	\N	\N	\N	\N	f
163	1	0	0	0	0	0	0	123	1	3c182e19e02f0853cd56c7700a1a29f0	f	t	500	\N	2026-02-10 09:48:46.561563	\N	\N	\N	\N	f
174	2	0	0	0	0	0	0	130	1	46b737696777c9c0007fc04063e9c2a4	f	t	1000	\N	2026-02-10 09:49:56.238187	\N	\N	\N	\N	f
186	1	0	0	0	0	0	0	140	1	7a8d7b884998040107470a9bfaeef371	f	f	500	\N	2026-02-10 09:50:48.042111	\N	\N	\N	\N	f
181	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:50:27.889102	32	\N	\N	\N	f
187	2	0	0	0	0	0	0	141	1	aadaeda756dc4aa11795f91f4d4568fc	f	f	1000	\N	2026-02-10 09:50:55.318361	\N	\N	\N	\N	f
154	2	0	0	0	0	0	0	115	1	9b2d515d247f44787940a8ebe7a8faaf	f	t	1000	\N	2026-02-10 09:47:56.208085	\N	\N	\N	\N	f
134	2	0	0	0	0	0	0	100	1	3bf0efeb0b800fca7420f5e20d4776d0	f	t	1000	\N	2026-02-10 09:45:42.991119	\N	\N	\N	\N	f
167	1	0	0	0	0	0	0	126	1	0cf88f4b46c1f8a890393cb66f52b9e5	f	t	500	\N	2026-02-10 09:49:02.564798	\N	\N	\N	\N	f
140	2	0	0	0	0	0	0	105	1	28c139e8b9acd509d7c3ebfbfd3605a0	f	t	1000	\N	2026-02-10 09:46:27.289051	\N	\N	\N	\N	f
179	2	0	0	0	0	0	0	106	1	fe54ffb02ed5a067fd0ad93f54ec1766	f	f	1000	\N	2026-02-10 09:50:22.211881	\N	\N	\N	\N	f
183	2	0	0	0	0	0	0	138	1	f40c2d36757b228e4d725c5fdbb231e3	f	t	1000	\N	2026-02-10 09:50:34.012511	\N	\N	\N	\N	f
158	1	0	0	0	0	0	0	118	1	917cfd172493a495a51409c02771755b	f	t	500	\N	2026-02-10 09:48:19.883844	\N	\N	\N	\N	f
188	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:50:59.905063	34	\N	\N	\N	f
153	2	0	0	0	0	0	0	114	1	1390d94cd569160e486115940ed1b618	f	t	1000	\N	2026-02-10 09:47:48.382566	\N	\N	\N	\N	f
180	2	0	0	0	0	0	0	136	1	c50ec4754f6bed5cbc11acd2197d8b22	f	t	1000	\N	2026-02-10 09:50:24.911378	\N	\N	\N	\N	f
137	1	0	0	0	0	0	0	104	1	65add2408be600bb7f7a839a5a320013	f	t	500	\N	2026-02-10 09:46:11.772199	\N	\N	\N	\N	f
176	1	0	0	0	0	0	0	132	1	e8006b2648b081072d0fd1fb1d152fbb	f	t	500	\N	2026-02-10 09:50:12.554515	\N	\N	\N	\N	f
149	2	0	0	0	0	0	0	112	1	ee20e42edc9b2623bac4d94bc0318c39	f	t	1000	\N	2026-02-10 09:47:26.915981	\N	\N	\N	\N	f
169	2	0	0	0	0	0	0	128	1	e003ed83bad3422a0bd447fbde6c1a4d	f	t	1000	\N	2026-02-10 09:49:36.1545	\N	\N	\N	\N	f
127	1	0	0	0	0	0	0	98	1	0d80b264fcc63da6153dc15ed95e0fb8	f	t	500	\N	2026-02-10 09:44:45.079256	\N	\N	\N	\N	f
126	1	0	0	0	0	0	0	45	1	827476c235b9d471557281009e77aecf	f	t	500	\N	2026-02-10 09:44:40.105708	\N	\N	\N	\N	f
168	2	0	0	0	0	0	0	127	1	0c3cc79ae50602b9e0e61c8347dfeacf	f	t	1000	\N	2026-02-10 09:49:10.829542	\N	\N	\N	\N	f
175	2	0	0	0	0	0	0	131	1	7e38bb5523a3f3a920d2363a90935a73	f	t	1000	\N	2026-02-10 09:50:04.968052	\N	\N	\N	\N	f
162	2	0	0	0	0	0	0	209	1	721f32991f6063a9b950339bdec7a90c	f	f	1000	\N	2026-02-10 09:48:41.745783	\N	\N	\N	\N	f
185	2	0	0	0	0	0	0	139	1	ee7574bd66da9483a534abebea5f6fc3	f	t	1000	\N	2026-02-10 09:50:40.761241	\N	\N	\N	\N	f
160	2	0	0	0	0	0	0	117	1	4cd0b6a65c8d98f059a9b5da5e45d827	f	f	1000	\N	2026-02-10 09:48:35.806337	\N	\N	\N	\N	f
189	1	0	0	0	0	0	0	142	1	bf4be022bf511fc352cd4d432098d6ac	f	f	500	\N	2026-02-10 09:51:01.00138	\N	\N	\N	\N	f
190	2	0	0	0	0	0	0	143	1	3113126b35a6e715439af229adfbdf45	f	f	1000	\N	2026-02-10 09:51:04.022477	\N	\N	\N	\N	f
192	1	0	0	0	0	0	0	145	1	a7856b7b23b0e56178e78c27e947f239	f	f	500	\N	2026-02-10 09:51:10.306159	\N	\N	\N	\N	f
177	2	0	0	0	0	0	0	133	1	0813aab40fd599d5e48d26e5dde7fb6f	f	t	1000	\N	2026-02-10 09:50:15.155708	\N	\N	\N	\N	f
194	2	0	0	0	0	0	0	144	1	c6f7db515cf7eef131e04053b43c7f4d	f	f	1000	\N	2026-02-10 09:51:25.510544	\N	\N	\N	\N	f
195	2	0	0	0	0	0	0	146	1	8b9609c88f09893c44af7da38498ed63	f	f	1000	\N	2026-02-10 09:51:28.707587	\N	\N	\N	\N	f
198	1	0	0	0	0	0	0	110	1	be74e81aae54af31c30fa456b6d7fb63	f	f	500	\N	2026-02-10 09:51:46.610472	\N	\N	\N	\N	f
110	1	0	0	0	0	0	0	73	1	cebfba85067b1d060e30acbc05409176	f	t	500	\N	2026-02-10 09:43:11.176841	\N	\N	\N	\N	f
201	1	0	0	0	0	0	0	2	1	74e6a2bc6653b7727a7666ec51b7a8fd	f	f	500	\N	2026-02-10 09:52:07.866712	\N	\N	\N	\N	f
204	2	0	0	0	0	0	0	112	1	32b2eced3d190cfa94c5469f8108992e	f	f	1000	\N	2026-02-10 09:52:24.410691	\N	\N	\N	\N	f
203	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:52:21.968648	37	\N	\N	\N	f
193	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:51:19.977097	35	\N	\N	\N	f
206	1	0	0	0	0	0	0	101	1	68edd042bc950d53bb1e38c243198655	f	f	500	\N	2026-02-10 09:52:38.014899	\N	\N	\N	\N	f
207	2	0	0	0	0	0	0	151	1	f8f5790a028f615e3c851a2235e45492	f	f	1000	\N	2026-02-10 09:52:44.795337	\N	\N	\N	\N	f
208	1	0	0	0	0	0	0	152	1	d50de994a5c6328d891a24d1e22b48c6	f	f	500	\N	2026-02-10 09:52:52.728546	\N	\N	\N	\N	f
196	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:51:38.939439	36	\N	\N	\N	f
211	2	0	0	0	0	0	0	154	1	7bef5ca3782557a65b2d7e8d71263273	f	f	1000	\N	2026-02-10 09:53:14.227667	\N	\N	\N	\N	f
212	1	0	0	0	0	0	0	93	1	b65e54a1238e987f6a709ae3aac28efb	f	f	500	\N	2026-02-10 09:53:21.968041	\N	\N	\N	\N	f
213	1	0	0	0	0	0	0	155	1	7fbc996f28670e14e570f95fe0050f8b	f	f	500	\N	2026-02-10 09:53:27.196718	\N	\N	\N	\N	f
210	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:53:09.262092	39	\N	\N	\N	f
215	2	0	0	0	0	0	0	157	1	4f05595c875f0209a29bfc685b2b2309	f	f	1000	\N	2026-02-10 09:53:56.804675	\N	\N	\N	\N	f
220	2	0	0	0	0	0	0	160	1	193e422a095c5430fcfbd7422d392e07	f	f	1000	\N	2026-02-10 09:54:24.974339	\N	\N	\N	\N	f
202	2	0	0	0	0	0	0	150	1	40639a88fa6e908f29aad26cdfcc3623	f	t	1000	\N	2026-02-10 09:52:19.850293	\N	\N	\N	\N	f
224	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:54:40.793199	42	\N	\N	\N	f
233	2	0	0	0	0	0	0	167	1	f98bfe6fe007c8552ace9eba69dde085	f	f	1000	\N	2026-02-10 09:55:34.673827	\N	\N	\N	\N	f
217	1	0	0	0	0	0	0	158	1	c1e368707028add9f57bfdc0f6be105a	f	t	500	\N	2026-02-10 09:54:13.626394	\N	\N	\N	\N	f
219	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:54:24.010493	40	\N	\N	\N	f
234	1	0	0	0	0	0	0	168	1	1e5a594e3741b5ad0c0665a1cce75313	f	f	500	\N	2026-02-10 09:55:53.180288	\N	\N	\N	\N	f
235	1	0	0	0	0	0	0	169	1	a7753cf15406caf071479d189941db7c	f	f	500	\N	2026-02-10 09:56:02.424925	\N	\N	\N	\N	f
236	2	0	0	0	0	0	0	170	1	1a722e08134e97240901d239dbb761b4	f	f	1000	\N	2026-02-10 09:56:05.60644	\N	\N	\N	\N	f
238	1	0	0	0	0	0	0	172	1	260114a52b8c4c4c8ccd174c5a2293c4	f	f	500	\N	2026-02-10 09:56:17.347911	\N	\N	\N	\N	f
240	1	0	0	0	0	0	0	173	1	f38620ee1ffd11345baa860218e14740	f	f	500	\N	2026-02-10 09:56:27.40773	\N	\N	\N	\N	f
242	1	0	0	0	0	0	0	174	1	caa61cf440a19be55cb7ce1a2d819683	f	f	500	\N	2026-02-10 09:56:31.174072	\N	\N	\N	\N	f
243	1	0	0	0	0	0	0	175	1	d46561daea53dcc1e53af79eb5e839d1	f	f	500	\N	2026-02-10 09:56:39.136724	\N	\N	\N	\N	f
225	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:54:45.295265	43	\N	\N	\N	f
205	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:52:36.59614	38	\N	\N	\N	f
245	2	0	0	0	0	0	0	106	1	fe769a6c11737b37ec7eab4ae7ae9635	f	t	1000	\N	2026-02-10 09:56:43.708506	\N	\N	\N	\N	f
247	2	0	0	0	0	0	0	166	1	c1541b89b440d2a26ad2a34ef5694219	f	f	1000	\N	2026-02-10 09:57:16.141097	\N	\N	\N	\N	f
248	1	0	0	0	0	0	0	176	1	d57129bcdb133ee8c048f7b9058420bf	f	f	500	\N	2026-02-10 09:57:21.466678	\N	\N	\N	\N	f
250	2	0	0	0	0	0	0	157	1	612c66f1d007921f103bb4fff9cc0e44	f	f	1000	\N	2026-02-10 09:57:30.655232	\N	\N	\N	\N	f
237	2	0	0	0	0	0	0	171	1	2df00d8f27a953bd92e66e37c6c84b8d	f	t	1000	\N	2026-02-10 09:56:10.631134	\N	\N	\N	\N	f
223	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:54:39.668159	41	\N	\N	\N	f
244	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:56:42.823817	47	\N	\N	\N	f
230	2	0	0	0	0	0	0	165	1	8de1cabef1c4f2f384b480af277462cb	f	t	1000	\N	2026-02-10 09:55:19.092579	\N	\N	\N	\N	f
218	2	0	0	0	0	0	0	159	1	d1e91b7eaa8b81beaad304531f6d6375	f	t	1000	\N	2026-02-10 09:54:17.53042	\N	\N	\N	\N	f
241	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:56:30.321044	46	\N	\N	\N	f
200	2	0	0	0	0	0	0	149	1	fb84d85b2c140ce560f1084fc8e86967	f	t	1000	\N	2026-02-10 09:52:04.412149	\N	\N	\N	\N	f
249	2	0	0	0	0	0	0	145	1	34c58842616532b9f621c45f4fa76698	f	t	1000	\N	2026-02-10 09:57:26.416121	\N	\N	\N	\N	f
232	1	0	0	0	0	0	0	166	1	02b1c356a8c2600a8c37473c6c26297b	f	t	500	\N	2026-02-10 09:55:27.515547	\N	\N	\N	\N	f
214	2	0	0	0	0	0	0	156	1	33a28354eebe1b6d3a0ff6bca04c9504	f	t	1000	\N	2026-02-10 09:53:53.456986	\N	\N	\N	\N	f
239	2	0	0	0	0	0	0	128	1	b047ecd9216ab5d256b766ab7ac69815	f	t	1000	\N	2026-02-10 09:56:25.208124	\N	\N	\N	\N	f
222	1	0	0	0	0	0	0	162	1	9a9b2562cd8ea98a0a23ccc212e9182a	f	t	500	\N	2026-02-10 09:54:36.055696	\N	\N	\N	\N	f
199	2	0	0	0	0	0	0	148	1	a18956235796e8be4d10b02cf349d657	f	t	1000	\N	2026-02-10 09:52:00.818591	\N	\N	\N	\N	f
191	1	0	0	0	0	0	0	144	1	0282d00d0cfb0df4869e4ca058e0ffcc	f	t	500	\N	2026-02-10 09:51:07.092926	\N	\N	\N	\N	f
231	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:55:26.431675	45	\N	\N	\N	f
197	2	0	0	0	0	0	0	147	1	e749afde3cb4af210a47a84c61d6f757	f	t	1000	\N	2026-02-10 09:51:40.952039	\N	\N	\N	\N	f
221	2	0	0	0	0	0	0	161	1	afb573f98463fa55ef4bde105b7c6aaa	f	t	1000	\N	2026-02-10 09:54:31.802013	\N	\N	\N	\N	f
228	2	0	0	0	0	0	0	164	1	920396ed6fb32fa218fc505eb240c164	f	t	1000	\N	2026-02-10 09:55:04.438916	\N	\N	\N	\N	f
216	1	0	0	0	0	0	0	131	1	81a0e095d77f2b2c77d511d5e9c68190	f	t	500	\N	2026-02-10 09:54:04.423145	\N	\N	\N	\N	f
227	2	0	0	0	0	0	0	163	1	bc77422e02bc69b49ccc067b6a416a3b	f	t	1000	\N	2026-02-10 09:54:58.341783	\N	\N	\N	\N	f
226	1	0	0	0	0	0	0	117	1	b6ef5b98719a82f93413875622263de5	f	f	500	\N	2026-02-10 09:54:51.721052	\N	\N	\N	\N	f
254	1	0	0	0	0	0	0	178	1	320bc3a86b60e163819162c91ed22986	f	f	500	\N	2026-02-10 09:58:07.209614	\N	\N	\N	\N	f
157	1	0	0	0	0	0	0	114	1	ec373c41226c6e0d729b9a36842381a1	f	t	500	\N	2026-02-10 09:48:14.644158	\N	\N	\N	\N	f
123	1	0	0	0	0	0	0	95	1	25559e50fc4cd3e2868f824cd6962c8c	f	t	500	\N	2026-02-10 09:44:30.133571	\N	\N	\N	\N	f
256	1	0	0	0	0	0	0	172	1	6bb3fb9ee75114741c2612f5604ca16e	f	f	500	\N	2026-02-10 09:58:25.84497	\N	\N	\N	\N	f
255	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:58:12.897025	49	\N	\N	\N	f
260	1	0	0	0	0	0	0	180	1	a76a868e73041fdd68905753d0cdd1f4	f	f	500	\N	2026-02-10 09:58:56.733177	\N	\N	\N	\N	f
262	1	0	0	0	0	0	0	182	1	fc9394c35c778a6aca7cc7051f7d9900	f	f	500	\N	2026-02-10 09:59:04.119998	\N	\N	\N	\N	f
263	1	0	0	0	0	0	0	183	1	a3c042140898605501a902307f271405	f	f	500	\N	2026-02-10 09:59:08.320565	\N	\N	\N	\N	f
264	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:59:12.535443	52	\N	\N	\N	f
266	2	0	0	0	0	0	0	184	1	689fd65f4f431df786abefd8444e54dc	f	f	1000	\N	2026-02-10 09:59:38.068484	\N	\N	\N	\N	f
258	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:58:34.476927	51	\N	\N	\N	f
259	1	0	0	0	0	0	0	179	1	2e4ec313c74101a587724f221dc19565	f	t	500	\N	2026-02-10 09:58:41.190884	\N	\N	\N	\N	f
269	2	0	0	0	0	0	0	185	1	e088aa59eedf5446776ab9f77f3bf025	f	f	1000	\N	2026-02-10 10:00:12.11619	\N	\N	\N	\N	f
293	1	0	0	0	0	0	0	198	1	ae76558e3eff04359211c650b9bb9cc1	f	f	500	\N	2026-02-10 10:03:12.297456	\N	\N	\N	\N	f
270	2	0	0	0	0	0	0	186	1	abb02df61bb138bca6196ddd0244e6c3	f	f	1000	\N	2026-02-10 10:00:25.324917	\N	\N	\N	\N	f
273	2	0	0	0	0	0	0	187	1	2c85ea34dfd24ab9a2a2a1d36d8b8424	f	f	1000	\N	2026-02-10 10:00:33.946531	\N	\N	\N	\N	f
271	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:00:32.419265	53	\N	\N	\N	f
277	2	0	0	0	0	0	0	188	1	d7f43098e4f75dc43ea760516a568903	f	f	1000	\N	2026-02-10 10:00:59.286209	\N	\N	\N	\N	f
278	1	0	0	0	0	0	0	113	1	6c42119984e92c098d52fd0ea7194f9f	f	f	500	\N	2026-02-10 10:01:02.855653	\N	\N	\N	\N	f
279	2	0	0	0	0	0	0	189	1	d661ceef799f1a42d8e9a60a78dbb654	f	f	1000	\N	2026-02-10 10:01:09.379677	\N	\N	\N	\N	f
257	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 09:58:33.919545	50	\N	\N	\N	f
60	2	0	0	0	0	0	0	156	1	f974eabc8c4c75d21b3a1016b553b9b2	f	t	1000	\N	2026-02-10 09:39:44.729781	\N	\N	\N	\N	f
265	2	0	0	0	0	0	0	156	1	c9178d63ab52ace17225bb114f42a791	f	t	1000	\N	2026-02-10 09:59:26.425003	\N	\N	\N	\N	f
253	1	0	0	0	0	0	0	156	1	b8313f8cfa048eb4f55f5475ae7d9dd1	f	t	500	\N	2026-02-10 09:57:59.962943	\N	\N	\N	\N	f
272	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:00:32.929136	54	\N	\N	\N	f
173	1	0	0	0	0	0	0	128	1	b316978cf7ae95f37e63de856522438b	f	t	500	\N	2026-02-10 09:49:53.489959	\N	\N	\N	\N	f
280	1	0	0	0	0	0	0	190	1	f3be32d3050798da5f14f57bd115f21a	f	f	500	\N	2026-02-10 10:01:25.542852	\N	\N	\N	\N	f
281	1	0	0	0	0	0	0	191	1	da7711168f226a66e997844a0586ff30	f	f	500	\N	2026-02-10 10:01:32.81079	\N	\N	\N	\N	f
282	2	0	0	0	0	0	0	192	1	d380b8ae6a6169420a617b31bdfd1e6c	f	f	1000	\N	2026-02-10 10:01:36.312255	\N	\N	\N	\N	f
274	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:00:38.069604	55	\N	\N	\N	f
284	1	0	0	0	0	0	0	193	1	b41991d44755327815e78a9408a5c6fd	f	f	500	\N	2026-02-10 10:01:45.466911	\N	\N	\N	\N	f
286	1	0	0	0	0	0	0	194	1	2618e8500f1a3a4e7475f392e6ada5a2	f	f	500	\N	2026-02-10 10:01:51.94402	\N	\N	\N	\N	f
285	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:01:49.961287	57	\N	\N	\N	f
288	2	0	0	0	0	0	0	195	1	f108f5f2232ccf5faf87cf0c3ab3f32a	f	f	1000	\N	2026-02-10 10:02:14.130665	\N	\N	\N	\N	f
289	1	0	0	0	0	0	0	196	1	a57558dadffaa462db73c142203ca5b2	f	f	500	\N	2026-02-10 10:02:19.511985	\N	\N	\N	\N	f
287	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:02:07.993327	58	\N	\N	\N	f
209	1	0	0	0	0	0	0	153	1	3fbb0dd5a8af04503e1065d37107ff36	f	t	500	\N	2026-02-10 09:53:07.114235	\N	\N	\N	\N	f
267	1	0	0	0	0	0	0	168	1	3e7f497f20e42cce27dc96560866ebd5	f	t	500	\N	2026-02-10 09:59:55.513743	\N	\N	\N	\N	f
291	1	0	0	0	0	0	0	184	1	00d63f30796d02356500ecacc0cda284	f	f	500	\N	2026-02-10 10:03:02.638531	\N	\N	\N	\N	f
246	2	0	0	0	0	0	0	161	1	2ecf148eefb3d3c96240b6fcaa99946d	f	t	1000	\N	2026-02-10 09:56:57.059363	\N	\N	\N	\N	f
294	1	0	0	0	0	0	0	173	1	6a085beb98d881216996c0d45f74fa96	f	f	500	\N	2026-02-10 10:03:16.864921	\N	\N	\N	\N	f
297	1	0	0	0	0	0	0	199	1	49b7b9a88e92e926d3a52e9023070024	f	f	500	\N	2026-02-10 10:03:24.969149	\N	\N	\N	\N	f
292	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:03:06.064882	59	\N	\N	\N	f
298	2	0	0	0	0	0	0	196	1	baa479086a15552183c7f421fbbde4d1	f	f	1000	\N	2026-02-10 10:03:30.820973	\N	\N	\N	\N	f
299	1	0	0	0	0	0	0	200	1	c0b5d08727c0d33138896f1508057a6b	f	f	500	\N	2026-02-10 10:03:37.481708	\N	\N	\N	\N	f
300	1	0	0	0	0	0	0	201	1	fbafa738f627cc14f209a4e8a66ae585	f	f	500	\N	2026-02-10 10:03:43.167891	\N	\N	\N	\N	f
275	1	0	0	0	0	0	0	164	1	341952c5338248546f1d86b8a96900bc	f	t	500	\N	2026-02-10 10:00:39.465513	\N	\N	\N	\N	f
276	2	0	0	0	0	0	0	164	1	9f2c4443e97fbb7b704c3612e772a3d4	f	t	1000	\N	2026-02-10 10:00:54.259314	\N	\N	\N	\N	f
296	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:03:24.232928	61	\N	\N	\N	f
303	2	0	0	0	0	0	0	202	1	baacc5e0dbb49ae5e231a1bd8cb630ff	f	f	1000	\N	2026-02-10 10:04:04.622204	\N	\N	\N	\N	f
304	1	0	0	0	0	0	0	129	1	5b6cb56112381fef9813413ea5f0f459	f	f	500	\N	2026-02-10 10:04:16.655877	\N	\N	\N	\N	f
305	1	0	0	0	0	0	0	151	1	8041ad4c97ca78ef3682208de356adf0	f	f	500	\N	2026-02-10 10:04:25.667782	\N	\N	\N	\N	f
283	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:01:43.876811	56	\N	\N	\N	f
309	2	0	0	0	0	0	0	203	1	e1e2b8db9a36fc422d531339d75d9a6b	f	f	1000	\N	2026-02-10 10:04:42.215101	\N	\N	\N	\N	f
310	1	0	0	0	0	0	0	204	1	190992c2a65aa2cb612134cfe18bc3d7	f	f	500	\N	2026-02-10 10:04:46.622584	\N	\N	\N	\N	f
311	2	0	0	0	0	0	0	65	1	602461c9cf18640e37dd907cf54f4750	f	f	1000	\N	2026-02-10 10:04:51.112956	\N	\N	\N	\N	f
308	1	0	0	0	0	0	0	103	1	a4c614797bc66f14d6b6a82181b64e18	f	t	500	\N	2026-02-10 10:04:32.72427	\N	\N	\N	\N	f
295	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:03:23.697301	60	\N	\N	\N	f
302	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:03:55.987129	63	\N	\N	\N	f
306	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:04:31.314574	64	\N	\N	\N	f
307	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:04:31.788802	65	\N	\N	\N	f
290	1	0	0	0	0	0	0	197	1	93eb6a989516ee11939b08435b5b6832	f	t	500	\N	2026-02-10 10:02:54.882802	\N	\N	\N	\N	f
268	2	0	0	0	0	0	0	117	1	54e3aca3059219e154b67360ee806a8a	f	f	1000	\N	2026-02-10 10:00:05.762667	\N	\N	\N	\N	f
312	2	0	0	0	0	0	0	205	1	0cb4e65e435a5e79469b85f77970033d	f	f	1000	\N	2026-02-10 10:04:55.490588	\N	\N	\N	\N	f
301	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:03:55.356643	62	\N	\N	\N	f
313	2	0	0	0	0	0	0	206	1	f6e5e61e0bc2b3797b35b4f127613c28	f	f	1000	\N	2026-02-10 10:05:01.905712	\N	\N	\N	\N	f
315	1	0	0	0	0	0	0	207	1	774cd0cef239c7170abc95237aedf257	f	f	500	\N	2026-02-10 10:05:12.582069	\N	\N	\N	\N	f
316	1	0	0	0	0	0	0	208	1	f4cc9ad74bf895a458434667dc9f083e	f	f	500	\N	2026-02-10 10:05:16.607764	\N	\N	\N	\N	f
318	1	0	0	0	0	0	0	193	1	cd4849e13f817dc39e2a84c8665e6560	f	f	500	\N	2026-02-10 10:05:32.009746	\N	\N	\N	\N	f
319	2	0	0	0	0	0	0	209	1	15e6caadcafdb9685ba6423e211f1742	f	f	1000	\N	2026-02-10 10:05:34.821096	\N	\N	\N	\N	f
317	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:05:20.455722	67	\N	\N	\N	f
322	1	0	0	0	0	0	0	210	1	e73f6e964275336c4aeb4f00d4bcfdd4	f	f	500	\N	2026-02-10 10:05:53.887994	\N	\N	\N	\N	f
323	2	0	0	0	0	0	0	211	1	5054bf0bfc287d87352eff131b4867f2	f	f	1000	\N	2026-02-10 10:06:09.778662	\N	\N	\N	\N	f
325	0	0	0	0	0	0	0	\N	1		f	f	300	\N	2026-02-10 10:06:23.102644	71	\N	\N	\N	f
326	2	0	0	0	0	0	0	212	1	aa4c5a723960e418b74d38c9d19e3aad	f	f	1000	\N	2026-02-10 10:06:28.911085	\N	\N	\N	\N	f
327	2	0	0	0	0	0	0	213	1	24f35d9a99504fcc121644a6078bd8e6	f	f	1000	\N	2026-02-10 10:06:38.99459	\N	\N	\N	\N	f
320	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:05:47.095257	68	\N	\N	\N	f
329	1	0	0	0	0	0	0	209	1	32ad29061c6040efbbb5404376bf3b5a	f	f	500	\N	2026-02-10 10:06:48.374238	\N	\N	\N	\N	f
324	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:06:16.280664	70	\N	\N	\N	f
321	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:05:47.552267	69	\N	\N	\N	f
85	2	0	0	0	0	0	0	69	1	855a29127bccaab45152df4ffcd859c1	f	t	1000	\N	2026-02-10 09:41:27.062443	\N	\N	\N	\N	f
331	2	0	0	0	0	0	0	214	1	99173a1857143acbfff8b362c32d0efc	f	f	1000	\N	2026-02-10 10:07:16.74495	\N	\N	\N	\N	f
261	1	0	0	0	0	0	0	181	1	39f31acd9408d128408de077a264b42a	f	t	500	\N	2026-02-10 09:59:00.116913	\N	\N	\N	\N	f
332	2	0	0	0	0	0	0	193	1	9b6200721533d575bb79bce9d36f32a2	f	f	1000	\N	2026-02-10 10:07:23.900087	\N	\N	\N	\N	f
333	2	0	0	0	0	0	0	215	1	16ed0490c2bd8e2cdc00f1e3d3981b40	f	f	1000	\N	2026-02-10 10:07:26.376833	\N	\N	\N	\N	f
334	1	0	0	0	0	0	0	216	1	115c844b9178aae00d7cb22c8b2c1f24	f	f	500	\N	2026-02-10 10:07:29.315632	\N	\N	\N	\N	f
335	2	0	0	0	0	0	0	217	1	9a143d9ee5ecab4af8cc9a0de3124d4b	f	f	1000	\N	2026-02-10 10:07:33.190188	\N	\N	\N	\N	f
336	2	0	0	0	0	0	0	218	1	39bd47fd802e953de5c3b3890fda3d48	f	f	1000	\N	2026-02-10 10:07:37.125965	\N	\N	\N	\N	f
338	2	0	0	0	0	0	0	216	1	bfe7406be195766201e7cbc1cca6cbae	f	f	1000	\N	2026-02-10 10:07:41.949868	\N	\N	\N	\N	f
328	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:06:46.80188	72	\N	\N	\N	f
341	0	0	0	0	0	0	0	\N	1		f	f	300	\N	2026-02-10 10:07:55.79571	76	\N	\N	\N	f
342	2	0	0	0	0	0	0	219	1	ae4d405bded2f07d5e141d5bdda7670d	f	f	1000	\N	2026-02-10 10:07:57.585247	\N	\N	\N	\N	f
343	1	0	0	0	0	0	0	220	1	10507e7ca5239a5e6f70cb24be6be59f	f	f	500	\N	2026-02-10 10:08:04.651747	\N	\N	\N	\N	f
314	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:05:11.261197	66	\N	\N	\N	f
337	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:07:40.54103	74	\N	\N	\N	f
339	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:07:49.327028	75	\N	\N	\N	f
344	1	0	0	0	0	0	0	221	1	5b8e0e56d155ae1a0a7909adbf32beda	f	f	500	\N	2026-02-10 10:08:29.308044	\N	\N	\N	\N	f
345	2	0	0	0	0	0	0	222	1	a28b7d4ae5503fe99dfeed4c3b37713b	f	f	1000	\N	2026-02-10 10:08:33.515883	\N	\N	\N	\N	f
346	1	0	0	0	0	0	0	223	1	2833df8e6b502ec64ee5ecd1c1f1e1db	f	f	500	\N	2026-02-10 10:08:39.299303	\N	\N	\N	\N	f
330	0	0	0	0	0	0	0	\N	1		f	t	300	\N	2026-02-10 10:06:58.755538	73	\N	\N	\N	f
340	2	0	0	0	0	0	0	117	1	867f5095469633038baaee5f118fd535	f	f	1000	\N	2026-02-10 10:07:51.203077	\N	\N	\N	\N	f
347	1	0	0	0	0	0	0	117	1	868e6b647fe39e9e3efb8c5a26088061	f	f	500	\N	2026-02-10 10:08:52.862151	\N	\N	\N	\N	f
348	1	0	0	0	0	0	0	224	1	744497b51f4dfb642d6124401b6c5ab2	f	f	500	\N	2026-02-10 10:09:00.031089	\N	\N	\N	\N	f
349	2	0	0	0	0	0	0	225	1	80008fbe08878992e40956d6d9793458	f	f	1000	\N	2026-02-10 10:09:06.310069	\N	\N	\N	\N	f
350	2	0	0	0	0	0	0	140	1	8ae5f647e8cf082286ea40d168aa212f	f	f	1000	\N	2026-02-10 10:09:10.799204	\N	\N	\N	\N	f
351	1	0	0	0	0	0	0	226	1	20be802f5558009d6ee23a4e7da84021	f	f	500	\N	2026-02-10 10:09:16.118984	\N	\N	\N	\N	f
352	2	0	0	0	0	0	0	227	1	5dd9785f378406329d910e7a14ca160a	f	f	1000	\N	2026-02-10 10:09:23.219433	\N	\N	\N	\N	f
\.


--
-- Data for Name: ride_share_rating; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_share_rating (id, rating, request, rated_is_customer) FROM stdin;
\.


--
-- Data for Name: ride_share_tour; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_share_tour (id, passengers, luggage, cancelled, communicated_start, communicated_end, earliest_start, latest_end, vehicle) FROM stdin;
2	2	0	t	1771450464419	1771453012419	1771450464419	1771453012419	1
1	2	0	t	1771236151616	1771238435066	1771236151616	1771238435066	1
9	1	0	t	1771826335190	1771828613240	1771826335190	1771828613240	1
7	1	0	t	1771727617818	1771728887418	1771727617818	1771728887418	1
10	2	0	t	1771186967251	1771187819701	1771186967251	1771187819701	1
3	2	0	t	1771200994649	1771203252449	1771200994649	1771203252449	1
5	1	0	t	1771663089328	1771665552328	1771663089328	1771665552328	1
6	1	0	t	1771088490781	1771089019230	1771088490781	1771089019230	1
11	1	0	t	1771412272248	1771414172297	1771412272248	1771414172297	1
8	2	0	t	1771740327240	1771743120240	1771740327240	1771743120240	1
14	2	0	t	1771653939756	1771656897756	1771653939756	1771656897756	1
15	1	0	t	1771471158749	1771473332849	1771471158749	1771473332849	1
18	1	0	t	1771669095175	1771671057324	1771669095175	1771671057324	1
17	2	0	t	1771107299073	1771107668223	1771107299073	1771107668223	1
19	1	0	t	1771732362297	1771734703797	1771732362297	1771734703797	1
12	2	0	t	1770906989537	1770910184537	1770906989537	1770910184537	1
4	2	0	t	1771206586871	1771209242921	1771206586871	1771209242921	1
23	2	0	t	1771823293504	1771824511804	1771823293504	1771824511804	1
22	1	0	t	1771430100016	1771433094016	1771430100016	1771433094016	1
21	1	0	t	1771237936300	1771240388500	1771237936300	1771240388500	1
16	2	0	t	1771621700857	1771623569856	1771621700857	1771623569856	1
24	2	0	t	1771489231393	1771490706193	1771489231393	1771490706193	1
20	1	0	t	1771189118125	1771190250025	1771189118125	1771190250025	1
27	2	0	t	1771409693909	1771412999309	1771409693909	1771412999309	1
25	1	0	t	1771560964992	1771562657142	1771560964992	1771562657142	1
13	2	0	t	1771460528376	1771461775026	1771460528376	1771461775026	1
26	2	0	t	1771654007015	1771656245915	1771654007015	1771656245915	1
28	1	0	t	1770945075276	1770948125526	1770945075276	1770948125526	1
30	1	0	t	1771234809392	1771239033392	1771234809392	1771239033392	1
29	1	0	t	1771899327224	1771900297123	1771899327224	1771900297123	1
31	2	0	t	1771850535827	1771852942127	1771850535827	1771852942127	1
32	1	0	t	1771200792008	1771204170008	1771200792008	1771204170008	1
37	1	0	t	1770777890289	1770779649939	1770777890289	1770779649939	1
35	2	0	t	1770933509759	1770935372008	1770933509759	1770935372008	1
36	2	0	t	1770888952658	1770890064308	1770888952658	1770890064308	1
33	2	0	t	1771902540072	1771904326722	1771902540072	1771904326722	1
39	2	0	t	1770959805715	1770961599115	1770959805715	1770961599115	1
42	2	0	t	1771331184055	1771333594405	1771331184055	1771333594405	1
40	2	0	t	1770962980865	1770963412115	1770962980865	1770963412115	1
43	1	0	t	1770897981325	1770900946525	1770897981325	1770900946525	1
34	1	0	t	1771278680558	1771281087558	1771278680558	1771281087558	1
38	2	0	t	1771523063454	1771524264204	1771523063454	1771524264204	1
44	1	0	t	1771889259863	1771891033013	1771889259863	1771891033013	1
41	2	0	t	1771548551193	1771549931493	1771548551193	1771549931493	1
47	2	0	t	1771627196000	1771629627000	1771627196000	1771629627000	1
49	2	0	t	1771265793760	1771267068760	1771265793760	1771267068760	1
48	1	0	t	1771155184333	1771157548783	1771155184333	1771157548783	1
46	1	0	t	1771512881417	1771514971817	1771512881417	1771514971817	1
52	2	0	t	1771872952803	1771874624703	1771872952803	1771874624703	1
51	2	0	t	1770997691484	1770999985734	1770997691484	1770999985734	1
53	1	0	t	1771811442922	1771812694972	1771811442922	1771812694972	1
50	2	0	t	1771204302819	1771207313819	1771204302819	1771207313819	1
54	1	0	t	1771514221789	1771515437389	1771514221789	1771515437389	1
55	2	0	t	1771101779143	1771103884393	1771101779143	1771103884393	1
57	2	0	t	1771134598390	1771136044840	1771134598390	1771136044840	1
58	1	0	t	1771419720283	1771420753632	1771419720283	1771420753632	1
45	1	0	t	1771529143029	1771529444678	1771529143029	1771529444678	1
59	1	0	t	1771067347878	1771069742878	1771067347878	1771069742878	1
61	2	0	t	1771052463094	1771053535594	1771052463094	1771053535594	1
56	1	0	t	1771582476428	1771584626228	1771582476428	1771584626228	1
62	1	0	t	1771571516509	1771573466508	1771571516509	1771573466508	1
60	2	0	t	1771294952848	1771297380748	1771294952848	1771297380748	1
63	2	0	t	1771414594798	1771414861348	1771414594798	1771414861348	1
67	1	0	t	1771133411363	1771135454512	1771133411363	1771135454512	1
64	1	0	t	1771367609793	1771369837893	1771367609793	1771369837893	1
71	2	0	f	1770956904200	1770959240300	1770956904200	1770959240300	1
65	2	0	t	1771899433953	1771900632003	1771899433953	1771900632003	1
68	1	0	t	1770870661489	1770872076889	1770870661489	1770872076889	1
70	2	0	t	1771650510253	1771651562502	1771650510253	1771651562502	1
69	1	0	t	1771785413226	1771785767526	1771785413226	1771785767526	1
72	2	0	t	1770973509193	1770975287743	1770973509193	1770975287743	1
76	1	0	f	1771150628081	1771152356681	1771150628081	1771152356681	1
66	2	0	t	1771631624683	1771633728583	1771631624683	1771633728583	1
74	2	0	t	1771798599443	1771799558542	1771798599443	1771799558542	1
75	1	0	t	1771854402922	1771855794022	1771854402922	1771855794022	1
73	2	0	t	1771401296129	1771404404429	1771401296129	1771404404429	1
\.


--
-- Data for Name: ride_share_vehicle; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_share_vehicle (id, passengers, luggage, color, model, smoking_allowed, license_plate, owner, picture) FROM stdin;
1	3	0	blue	Smart	f	WSW-AB-123	1	\N
2	1	0	\N	\N	f	\N	1	\N
3	1	0	\N	\N	f	\N	2	\N
4	1	0	\N	\N	f	\N	3	\N
5	1	0	\N	\N	f	\N	4	\N
6	1	0	\N	\N	f	\N	5	\N
7	1	0	\N	\N	f	\N	6	\N
8	1	0	\N	\N	f	\N	7	\N
9	1	0	\N	\N	f	\N	8	\N
10	1	0	\N	\N	f	\N	9	\N
11	1	0	\N	\N	f	\N	10	\N
12	1	0	\N	\N	f	\N	11	\N
13	1	0	\N	\N	f	\N	12	\N
\.


--
-- Data for Name: ride_share_zone; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_share_zone (id, area, name) FROM stdin;
1	0106000020E61000000100000001030000000100000005000000702A2BF716412E40C08E5023285D4940702A2BF716412E400CA7A0F189E6494020700A90660B2B400CA7A0F189E6494020700A90660B2B40C08E5023285D4940702A2BF716412E40C08E5023285D4940	
\.


--
-- Data for Name: session; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.session (id, expires_at, user_id) FROM stdin;
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: tour; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tour (id, departure, arrival, direct_duration, vehicle, fare, cancelled, message) FROM stdin;
47	1770877868000	1770885979000	1572000	1	\N	t	message
39	1770781394000	1770784077000	1051000	1	\N	t	message
21	1771902060000	1771906393000	1935000	1	\N	t	\N
9	1770911231000	1770915476000	1599000	1	\N	t	\N
3	1771443772000	1771446808000	1255000	1	\N	t	\N
42	1770869696000	1770871854000	1444000	1	\N	t	\N
8	1771187768000	1771188865000	886000	1	\N	t	message
6	1770954093300	1770956097300	1107000	1	\N	t	message
4	1770865260000	1770867315000	\N	1	\N	t	message
87	1771836750250	1771846331000	2116000	1	\N	f	\N
10	1771595582900	1771600707900	1085000	1	\N	t	\N
7	1771701911000	1771705571000	1039000	1	\N	t	message
71	1770925991000	1770930361000	1982000	1	\N	t	\N
37	1771765903000	1771769201000	1995000	1	\N	t	\N
12	1771666568000	1771667835000	1883000	1	\N	t	\N
28	1771395635050	1771397749050	228000	1	\N	t	message
24	1771591148000	1771594633000	1645000	1	\N	t	\N
1	1771738921000	1771741735000	879000	1	\N	t	\N
44	1771572785000	1771577608000	638000	1	\N	t	message
25	1771645510000	1771651381000	1652000	1	\N	t	\N
14	1771010137000	1771012460000	1635000	1	\N	t	message
29	1771061239000	1771063273000	647000	1	\N	t	message
58	1771215579651	1771218701651	424000	1	\N	f	\N
56	1771565385000	1771570746000	778000	1	\N	t	\N
52	1771789904000	1771793965000	1782000	1	\N	t	\N
63	1771044346000	1771048687000	1980000	1	\N	t	message
5	1771847446000	1771848441000	957000	1	\N	t	\N
19	1771576568000	1771578236000	1040000	1	\N	t	message
33	1770839918000	1770842748000	1426000	1	\N	t	\N
36	1770930315750	1770931144750	405000	1	\N	t	\N
69	1771702162000	1771704755000	1076000	1	\N	t	message
22	1771423795301	1771425960301	1022000	1	\N	t	\N
61	1771184465000	1771187888000	1720000	1	\N	t	message
11	1771047661000	1771049745000	1350000	1	\N	t	\N
105	1771828547000	1771829893000	544000	1	\N	t	message
41	1771214722000	1771216629000	924000	1	\N	t	message
99	1771231643451	1771236310451	1875000	1	\N	t	\N
17	1771129439000	1771132294000	929000	1	\N	t	\N
67	1770740985000	1770744677000	\N	1	\N	t	\N
27	1771334772000	1771337200000	991000	1	\N	t	\N
51	1771593134500	1771595473500	2002000	1	\N	t	message
50	1771338610501	1771342201501	2218000	1	\N	f	\N
62	1770749439000	1770754082000	2268000	1	\N	t	\N
15	1770871994251	1770873380251	1427000	1	\N	t	message
23	1771269541000	1771272929000	269000	1	\N	t	\N
104	1770983273000	1770985788000	915000	1	\N	t	message
26	1771332245051	1771333431051	394000	1	\N	t	\N
46	1771317954150	1771319736150	1227000	1	\N	t	message
35	1771911736000	1771913931000	353000	1	\N	t	\N
108	1771156204000	1771159136000	1424000	1	\N	f	\N
16	1771559037000	1771564838000	167000	1	\N	t	message
30	1771151563000	1771156032000	727000	1	\N	t	\N
43	1771438464000	1771440985000	1238000	1	\N	f	\N
98	1771229398451	1771231583451	1382000	1	\N	t	\N
34	1771038060000	1771041818000	2056000	1	\N	t	\N
31	1771531609950	1771533729950	468000	1	\N	t	message
18	1771160150000	1771164352000	918000	1	\N	t	message
54	1771007449000	1771012239000	1918000	1	\N	t	message
66	1771399290101	1771402318101	2112000	1	\N	t	\N
38	1771103402000	1771106075000	1470000	1	\N	f	\N
73	1771576268000	1771580531000	1607000	1	\N	t	message
81	1770754082000	1770760188000	\N	1	\N	t	message
92	1770918426000	1770920877000	795000	1	\N	t	message
88	1771056100000	1771058856000	2107000	1	\N	t	message
83	1771210860000	1771215498000	229000	1	\N	t	message
80	1771168115000	1771171124000	671000	1	\N	t	\N
97	1771878341000	1771880413000	1656000	1	\N	t	\N
70	1771515205000	1771518247000	192000	1	\N	t	message
90	1771822203400	1771824700400	218000	1	\N	t	\N
53	1771873354000	1771877929000	2000000	1	\N	f	\N
13	1770907094650	1770908688650	2075000	1	\N	t	message
76	1771302767600	1771307614600	3056000	1	\N	t	message
110	1770928329000	1770932649000	2037000	1	\N	f	\N
85	1770975772000	1770979744000	1109000	1	\N	t	message
75	1771419592000	1771420558000	885000	1	\N	t	\N
96	1771604790900	1771607050900	1601000	1	\N	f	\N
55	1771356861000	1771361187000	1642000	1	\N	t	message
77	1770792347000	1770794271000	1456000	1	\N	t	\N
95	1771846341000	1771849095000	1429000	1	\N	t	message
64	1771589576000	1771591890000	1550000	1	\N	t	\N
91	1771347193000	1771349277000	1637000	1	\N	t	\N
107	1770951603000	1770955839000	1972000	1	\N	f	\N
78	1771663647000	1771665201000	726000	1	\N	t	message
49	1771880580000	1771883565000	768000	1	\N	t	message
32	1770747316000	1770749379000	\N	1	\N	t	message
74	1770842808000	1770845013000	120000	1	\N	t	message
59	1771621571000	1771624445000	165000	1	\N	f	\N
57	1771127003000	1771131384000	1670000	1	\N	t	\N
89	1771172983000	1771175729000	989000	1	\N	f	\N
101	1771135974000	1771144773000	1885000	1	\N	f	\N
82	1771652168000	1771653028000	496000	1	\N	t	message
94	1770839048400	1770840920400	1104000	1	\N	f	\N
68	1771180692000	1771183539000	1857000	1	\N	f	\N
79	1771484530000	1771486941000	373000	1	\N	t	\N
2	1770958444000	1770963590600	954000	1	\N	f	\N
60	1771094471000	1771097416000	1680000	1	\N	f	\N
111	1771585503000	1771589481000	1021000	1	\N	f	\N
93	1771186416000	1771191025000	697000	1	\N	f	\N
103	1771559562000	1771563843000	1991000	1	\N	t	message
40	1771133258000	1771135914000	1116000	1	\N	f	\N
45	1771386255000	1771390520000	1840000	1	\N	t	message
109	1771297260000	1771300764000	1657000	1	\N	f	\N
65	1771601156900	1771604790900	1768000	1	\N	f	\N
106	1771731711000	1771743584000	1493000	1	\N	f	\N
86	1771272945000	1771276679000	1726000	1	\N	t	\N
152	1770993368000	1770997423000	877000	1	\N	f	\N
158	1771097476000	1771102585000	1489000	1	\N	t	message
155	1770865260000	1770869020000	174000	1	\N	f	\N
116	1771681973000	1771684695000	1467000	1	\N	t	message
125	1771616854000	1771619668000	810000	1	\N	f	\N
194	1770840980400	1770845200400	1817000	1	\N	f	\N
169	1771530412000	1771533534000	1466000	1	\N	f	\N
137	1771342261501	1771348429501	1475000	1	\N	f	\N
123	1771268279400	1771269481400	1078000	1	\N	t	\N
165	1771254017000	1771256609000	120000	1	\N	t	message
130	1771447835851	1771449378851	488000	1	\N	t	\N
119	1771361677600	1771365005600	2149000	1	\N	f	\N
162	1771176918000	1771180103000	645000	1	\N	t	\N
133	1771002812051	1771006402051	1100000	1	\N	t	\N
170	1770798585000	1770802681000	61000	1	\N	f	\N
178	1771827260000	1771831547000	1898000	1	\N	f	\N
115	1771821068000	1771825105000	1541000	1	\N	t	\N
146	1771006021000	1771008814000	1124000	1	\N	f	\N
166	1771860175000	1771862669000	2013000	1	\N	f	\N
126	1770988385000	1770990657000	1240000	1	\N	t	message
154	1770750586000	1770753622000	2095000	1	\N	f	\N
161	1771578275000	1771584515000	1220000	1	\N	t	message
136	1770967211000	1770969241000	325000	1	\N	t	\N
160	1771219323000	1771221842000	1312000	1	\N	f	\N
150	1770878168000	1770879924000	978000	1	\N	t	message
205	1771331523450	1771334998450	1989000	1	\N	f	\N
143	1771445946000	1771450337000	2323000	1	\N	f	\N
148	1770822017000	1770824430000	928000	1	\N	t	message
159	1771431235000	1771433519000	1366000	1	\N	t	message
167	1770985848000	1770990409000	3226000	1	\N	f	\N
188	1771665096000	1771667380000	405000	1	\N	f	\N
175	1771470060000	1771474966000	230000	1	\N	f	\N
138	1771146617000	1771149044000	1774000	1	\N	t	\N
118	1770999918051	1771002752051	2592000	1	\N	t	message
145	1771572402650	1771575164650	2128000	1	\N	f	\N
195	1771177011500	1771180230500	1390000	1	\N	f	\N
157	1771764447000	1771770620000	1415000	1	\N	f	\N
171	1770894906000	1770897476000	896000	1	\N	t	message
206	1771309162000	1771312286000	575000	1	\N	f	\N
197	1771667440000	1771668336000	1072000	1	\N	t	message
198	1771441045000	1771443404000	1124000	1	\N	f	\N
189	1771682842000	1771685577000	1063000	1	\N	f	\N
114	1771038060000	1771043671000	190000	1	\N	t	message
164	1771706314000	1771710600000	1150000	1	\N	t	message
172	1770788831000	1770794491651	531000	1	\N	f	\N
217	1771432568000	1771433574000	1334000	1	\N	f	\N
149	1771303446000	1771306828000	1403000	1	\N	t	\N
179	1771754862000	1771757077000	1777000	1	\N	t	message
144	1771759553000	1771761777000	1822000	1	\N	f	\N
168	1771609268000	1771613618000	1087000	1	\N	f	\N
132	1771535783000	1771537746000	1650000	1	\N	t	message
174	1771655032000	1771657735000	220000	1	\N	f	\N
185	1770753682000	1770759597000	1212000	1	\N	f	\N
113	1771564952650	1771571050650	2884000	1	\N	f	\N
124	1771866208000	1771871741000	2642000	1	\N	f	\N
186	1771862729000	1771865905000	1602000	1	\N	f	\N
121	1771390580000	1771394330000	923000	1	\N	f	\N
182	1771000811050	1771002885050	1728000	1	\N	f	\N
187	1770997483000	1771000526000	1944000	1	\N	f	\N
156	1771744394050	1771754862000	252000	1	\N	t	message
173	1771848437450	1771854251000	1580000	1	\N	f	\N
128	1771904416000	1771909211000	922000	1	\N	t	message
181	1771911789000	1771916340000	2337000	1	\N	t	message
192	1771329380000	1771331260000	1610000	1	\N	f	\N
190	1771642860000	1771647144000	1426000	1	\N	f	\N
202	1771166362000	1771168658000	295000	1	\N	f	\N
100	1771695720000	1771701852000	873000	1	\N	f	\N
20	1771688158000	1771690368000	1903000	1	\N	f	\N
153	1771085632000	1771088942000	1733000	1	\N	t	\N
147	1771777742300	1771781208300	936000	1	\N	t	message
139	1771016248000	1771018645000	1255000	1	\N	t	message
127	1771917217750	1771920647750	2406000	1	\N	t	\N
219	1771650498000	1771653749000	480000	1	\N	f	\N
199	1771048083000	1771050499000	2385000	1	\N	f	\N
196	1771145966400	1771150325000	2228000	1	\N	f	\N
142	1771061115000	1771064633000	\N	1	\N	f	\N
200	1771051540000	1771058851000	167000	1	\N	f	\N
129	1771497347000	1771502810000	340000	1	\N	f	\N
211	1771335089000	1771337725000	2650000	1	\N	f	\N
112	1770781912000	1770785832000	1097000	1	\N	f	\N
203	1770778800000	1770781792000	3356000	1	\N	f	\N
151	1770890296450	1770895629450	1928000	1	\N	f	\N
204	1770881385000	1770886016000	1133000	1	\N	f	\N
184	1771487459300	1771493559000	260000	1	\N	f	\N
207	1771475026000	1771477117000	1934000	1	\N	f	\N
176	1771425368000	1771428236000	1056000	1	\N	f	\N
208	1771406887000	1771409928000	747000	1	\N	f	\N
141	1771674002000	1771676311000	310000	1	\N	f	\N
212	1771085137000	1771089320000	1714000	1	\N	f	\N
210	1770825965000	1770828958000	72000	1	\N	f	\N
131	1770899948000	1770906876000	1153000	1	\N	t	message
163	1771234185000	1771238709000	1003000	1	\N	t	\N
180	1770911292000	1770915476000	284000	1	\N	f	\N
213	1770895689450	1770899126450	1777000	1	\N	f	\N
215	1771902060000	1771905863000	2009000	1	\N	f	\N
209	1771815660000	1771827167701	1573000	1	\N	f	\N
191	1771040544000	1771045535000	365000	1	\N	f	\N
214	1771878968000	1771880549000	893000	1	\N	f	\N
193	1771238261250	1771251468000	1459000	1	\N	f	\N
201	1770922031000	1770926276000	1605000	1	\N	f	\N
218	1770917385000	1770920924000	1334000	1	\N	f	\N
183	1770746353000	1770749255000	1305000	1	\N	f	\N
216	1770967756000	1770972350650	420000	1	\N	f	\N
220	1771320985900	1771324284900	1691000	1	\N	f	\N
134	1770817743600	1770819401600	1235000	1	\N	f	\N
140	1771353129000	1771358358000	2659000	1	\N	f	\N
177	1771789517000	1771795297000	907000	1	\N	f	\N
221	1770972772000	1770976849000	917000	1	\N	f	\N
222	1770725083200	1770729612200	\N	1	\N	f	\N
223	1770803231000	1770805194000	1757000	1	\N	f	\N
117	1771504748000	1771525844000	1292000	1	\N	f	\N
224	1771916993000	1771919341000	525000	1	\N	f	\N
225	1771579936950	1771583351950	1825000	1	\N	f	\N
226	1771776165000	1771779328000	91000	1	\N	f	\N
227	1771583351950	1771585499950	1476000	1	\N	f	\N
\.


--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."user" (id, name, email, password_hash, is_taxi_owner, is_admin, is_email_verified, email_verification_code, email_verification_expires_at, password_reset_code, password_reset_expires_at, phone, company_id, is_service, first_name, gender, zip_code, city, region, profile_picture) FROM stdin;
1	Alice	alice@example.com	$argon2id$v=19$m=19456,t=2,p=1$9fW6tfdNBJHtNC/RgNpMgg$z+hlFH7KXxKbIyt1q4fTK134FYcF8y10ZjSslzyqmFc	f	f	t	\N	\N	\N	\N	0815-1231234	\N	f		\N				\N
2	Bob	bob@example.com	$argon2id$v=19$m=19456,t=2,p=1$9fW6tfdNBJHtNC/RgNpMgg$z+hlFH7KXxKbIyt1q4fTK134FYcF8y10ZjSslzyqmFc	f	f	t	\N	\N	\N	\N	\N	\N	f		\N				\N
3	John	maintainer@example.com	$argon2id$v=19$m=19456,t=2,p=1$ZtuiFUoQYRyXUQRduYBkfQ$E+aREm5wKl8Ldn5ASP3wZnPf/jRriMIQmR3L3BhDaSA	f	t	t	\N	\N	\N	\N	\N	\N	f		\N				\N
4	John	weisswasser@example.com	$argon2id$v=19$m=19456,t=2,p=1$BoC0z8dXsKPZmUMvpnRXPw$Hc6rK5wlUNizsw5GQFjJ9oQ9uMhgWln42Ak4J2rO8yc	t	f	t	\N	\N	\N	\N	\N	1	f		\N				\N
5	John	gablenz@example.com	$argon2id$v=19$m=19456,t=2,p=1$3/CML3alHoFB7kYR3Fz9Hw$qQ7MYo7N6NO0SeCKXFs4VrPdiwGAT0FhE5KmwC0fv8U	t	f	t	\N	\N	\N	\N	\N	2	f		\N				\N
6	John	reichwalde@example.com	$argon2id$v=19$m=19456,t=2,p=1$UCIZz8oGzu9kCDOpmWXxYQ$amyxen1cjPmi/TwetOz7I/f+neLvlx6eQxM6OTvIzx0	t	f	t	\N	\N	\N	\N	\N	3	f		\N				\N
7	John	moholz@example.com	$argon2id$v=19$m=19456,t=2,p=1$TCAyMLkDNz0F7nceulTs4A$+dCc3qIYwS362mcrSH/Z7hmXx2KW5Ow5NLhZH0XpPEI	t	f	t	\N	\N	\N	\N	\N	4	f		\N				\N
8	John	niesky@example.com	$argon2id$v=19$m=19456,t=2,p=1$jxW4oxa3l0tg+OG3+4lllw$l5TN76xuwWqc01KNBHB37WukqjmqjKsm/ZBF2y+NvPY	t	f	t	\N	\N	\N	\N	\N	5	f		\N				\N
9	John	rothenburg@example.com	$argon2id$v=19$m=19456,t=2,p=1$dviKXplqYeVGdRA+UztyDg$/rQUv5OVgKufsy6VqYtFhXfE6jaHOCV6oE+3aDZVGMo	t	f	t	\N	\N	\N	\N	\N	6	f		\N				\N
10	John	schoepstal@example.com	$argon2id$v=19$m=19456,t=2,p=1$B7mjUX8IFZv+1G/jiu2dSQ$xGhHcG8PKvDYLwydw2aVVqaaovdjFanlIrBjF0TgDkI	t	f	t	\N	\N	\N	\N	\N	7	f		\N				\N
11	John	goerlitz@example.com	$argon2id$v=19$m=19456,t=2,p=1$6zvrI5rYSzw+NP8hRZ1Yxg$pAY9o3o3rhlCNGo2zVwP/Kq5YVOrm6yvLrqaSDeWxpw	t	f	t	\N	\N	\N	\N	\N	8	f		\N				\N
12	John	fahrer@example.com	$argon2id$v=19$m=19456,t=2,p=1$6zvrI5rYSzw+NP8hRZ1Yxg$pAY9o3o3rhlCNGo2zVwP/Kq5YVOrm6yvLrqaSDeWxpw	f	f	t	\N	\N	\N	\N	\N	1	f		\N				\N
\.


--
-- Data for Name: vehicle; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vehicle (id, license_plate, company, passengers, wheelchairs, bikes, luggage) FROM stdin;
1	GR-TU-11	1	3	0	0	0
2	GR-TU-12	1	3	0	0	0
3	GR-TU-21	2	3	0	0	0
4	GR-TU-22	2	3	0	0	0
5	GR-TU-31	3	3	0	0	0
6	GR-TU-32	3	3	0	0	0
7	GR-TU-41	4	3	0	0	0
8	GR-TU-42	4	3	0	0	0
9	GR-TU-51	5	3	0	0	0
10	GR-TU-52	5	3	0	0	0
11	GR-TU-61	6	3	0	0	0
12	GR-TU-62	6	3	0	0	0
13	GR-TU-71	7	3	0	0	0
14	GR-TU-72	7	3	0	0	0
15	GR-TU-81	8	3	0	0	0
16	GR-TU-82	8	3	0	0	0
\.


--
-- Data for Name: zone; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.zone (id, area, name) FROM stdin;
1	0106000020E610000001000000010300000001000000D5000000E7948C60FB0E2E40EE9B2ACAFBA5494047608795550F2E4013A8C107AFA549407F5C76880F112E407C63E8FDA6A54940D59D01EE67102E400D3C316CC9A44940106AD4D494102E40B7338ED378A44940B342FD1810122E40CABE047844A4494076ED1E9791112E40102DA3AE85A349406E50099773152E40BE21674DF4A24940443D1903E3122E404D930EA1A0A24940AA162B9894132E40095900A62CA249400BC66E647B122E404EC638F680A149406FE668F57E132E40C5C2FAF40CA14940F7FF9BD65F102E40F0BD2DEEF0A04940FF83D5B5640F2E408FF9ADB995A049407603CF57CE0C2E409E1F2ABD7FA04940DA85F6A8E60B2E400C57D98C0CA04940D4624953890D2E40EB3ADC3BDF9F4940231B6534370E2E40F2EEC1342BA0494006D21FE8510F2E40ABE73F4028A04940FAFDCA2B2D102E401EEC556AC09F49408104EED964132E407EDF80FA389F49409BA4E1B972102E40C925381FCC9E4940524F7A04AB0E2E40E831ABA1F19E4940F4CFDC2FB80D2E40CDE39381A69E4940C7CB3294CF0E2E4030E9DAED5C9E4940F9316493090C2E402491C2971C9E4940B85F3E73C40D2E404AD97356EE9D49409736E7523C0D2E4000FE1391AC9D4940075DB6EAEF0A2E40209B5AF1449D49406506AB434D082E40F58BD7751F9D494073EF943432092E40C9ECBC9B329C49404ADE1106A9022E4011C47B97979C49402F304F30B9F72D407E0E8383CC9C49400554A6EA31F32D40D012977A209D494031CD08A470F22D40DAAD3460AB9C494087C59D1B42E82D409DBA8681399C4940E12C8ACD98E72D40818D9A31919C49403B965A8D76E32D409971817B219D49400BBE6A1ADADE2D40923D587DA29D49401EF51FCCBBDA2D403E8FB806859D4940853A954041D82D4042D0EEB30A9C4940D27D518721D82D40D2D10E58189B4940B85608C428D42D40E7A8520E429B49409EE78EB807D32D40643B2366D89A49409199EAC988D42D400E9073E8B29A4940F633B7EA40D22D40FBCF13A1D199494019ADCBDDC2CC2D40FCA4D98F149A4940C4444ACF5EC72D4084BC27FCDF9949409B2147AC95C42D40D821C3A587994940C99CBCBB29C32D40A953BF85D09949403B19F0929EBE2D40207D8A97D69949408D965BE14FBC2D40B5F1DF252E9A4940C81BC89F66B82D40879D1639429A4940897A6B65BFB72D4063C4BA437C9A4940ECEF129A11B42D40E7F43A4C969A4940411E324FE7AC2D407F43F47A1B9A494095F52957C4AC2D40DEBB1EC797994940DCD2EFF0D0AA2D40B73D0B3EB7994940232882A993A92D400FFEEF358F9949407AE7B6DF1AAA2D40231534733A994940D11FCAA675A72D40F564F2679E984940EFDECBD525A52D406B110D76979849400E1711FC4EA42D40950C6575F99849408B55C70FE2A12D40BF928603219949407402F403FEA02D402D341988DD994940ACF6C628AD9E2D40DB07AD572C9A4940D7F5F971299C2D403EFD4108EF9A4940D3D822FD4D892D401AD19EF10B9A4940406E38E357872D400543AAEC189A494093C9FAFF66872D406633CE1C549A49406AF7B4506D842D4042DEDBAD469A4940B3CC8A8F32762D4066C4A848219B494026E632AD68762D40EA925D64719B4940181CBCCB857A2D40937C15A6CD9B4940E42A64C6D87A2D4005E81109209C494047F4C9F66E762D402A1926895D9D49403F5A78D2D4732D40DE4C6842C99D4940DDEA0EEF4B712D408B7EF7FDCF9D4940D007C5ED6A6E2D4093F41667BE9D4940BC9153DCCB6C2D40341306F4569D49403BDD4ABD0D6A2D40CA87DAA52B9D4940F24DA4EC97652D400A75AF79D79B49400607A326C55E2D4032456931089B49402EFAF4EA8C592D40C58CA011019B4940917AD648B9592D40900AA8CD2C9B4940A936461E77582D40BA8872163D9B4940E3F64B7124582D40D052321EFE9A49407D23E7D261542D4042F8B9A0F89A49409013BDA7DE502D40AC4824FB459B4940C200843948512D4098A65EBB6B9B4940CF91CD779F4E2D40EFC11A17999B494078CC6CCCE94D2D4083589FA6E09B4940F03B026CDE4B2D404363573EDE9B49403E30510CCE4C2D40F99F1E9AAB9C49404BE723775E4E2D400FCACBDBE39C4940F8488C2B514C2D402F6DC32B829D49408F1E68FA714A2D406905F2F1769D4940B017DA28A1472D401C1CBEF9EE9C4940D106835BE0462D403EE4AE2A679C4940126D7F2A4E452D409035A6666A9C4940C549DCCB14452D409352AEC8409C4940E7B4ED14B0412D40CE9E2306319D4940E2947AADB13D2D40D2EFB4FC499D494050868C5AD3412D40BD146219A39E4940EE6D1D55F9432D40550B954DF09E4940B11D4A825C452D40DC5B2D57E79E49407F49A4C0D7452D40D0040575D69F4940F67466C70C412D40E162B37512A14940E8C340DAEF392D408835D2DF43A1494089815BF6D93C2D40E3EF523A19A249406703E89DFB3E2D4059FB7190C0A3494032E34A78B5392D40C0B01BEFC9A34940DDBF243763382D40595E205E74A44940546B61C63E332D40628E1386F1A449400D2D0D476F322D40AF9A0BF5C6A549402030AF7280352D40CBC9C7F8A6A6494059B079BB32382D40BEB29D7255A64940FE3573AE4B3B2D40FE9C08E87FA649400DCEC54CAF3C2D40CFE2B59D08A74940D35CA291A9402D40377ED9B40DA74940CDBA4AA7C1412D40CA7D03D0E5A64940C528E22DC4432D4030EB558B0BA749407B6EFA8FDF432D4077EB899F58A74940802AA5972E462D40E31E8D7AD0A64940F158AD3C59492D40747B01E018A749401CDA500270482D40D618179CEDA74940F41FE573DA452D40F43886BD33A849401A9F0BEB81502D40C471F07A7EA849408D4F6DBE2B4F2D401C0B4D26F4A94940926A20CD92522D4043C6DA33DEA94940197460A7E5532D4028A7D59E27AA49404EBE79AEEB522D402E0CC62B6AAA49402063A1FFAC512D40CCECA9D05CAA494070E32E625F4F2D4065BACDC0A3AA4940DD64A573D84D2D40DA14735264AA494054D55CD7344A2D401FEF0958CDAA49403B895F11514C2D403135665E1DAB494058C6CD9C9C4F2D4080D2716206AB49402099E814D6522D40C2DA517DB8AB494026E05A0F38542D40F18D9F3537AC4940CA0AFA7C4F532D40D423B1B954AC49407DC7AAE791542D407700F6D4C3AC494073582D93B7542D40F57F00ABFFAD4940905107FEBA562D4000DDC83E64AE49406220011D31562D4002DCF1B9FBAE4940FE73C4B8CD5B2D409948D245E1AF4940998FB4A55F602D40342F41D0FFAF494022F6AF7FE5632D40B0970E7951B1494010FC118EDC612D40C4A72B770FB249405A8CF012C9652D4008A7E7E839B34940E72262099B6A2D40CC68BB95D2B34940533D2A310C662D406A6EFC9DB5B449409CDD6F25FA672D40C79718A367B4494093B5E3534E682D40365EA6CABCB449406E1CE2E40A6C2D4000F26B0870B449406AFDFB783D6C2D40CCEB809217B4494028D3F0E88D712D40BAEEC756CDB349402B0D424019772D4076DEC806D8B34940D3A682378C762D407E092395FBB349405EBB5EE2277A2D4082444C897AB54940CBB09679E37E2D40EA486093E8B64940C4A456F106822D40BE9B40B983B7494096EF9CA7E48B2D401FF3213904B8494045976DE2FB932D40150E9D2EC8B8494077B8C5B6A59F2D40FF41775AB4B94940F88396E472A42D405B31136154B94940A8D238E7A4B32D40733B646F36B94940AF2CC89844B02D40797A914CA1B74940DFEC97C5E9B82D403076716190B6494006718DFB02B92D40FE63502446B64940B1F7474119C42D40F89CA11CD4B54940B8DAACEBE0C82D40909DADA5BBB44940B235767F69D62D406DAA6F0AC7B44940CE92B9471EDD2D4051C6546C2BB54940C5680D6765E02D403BAA323800B64940F352FFED0BD92D400090F70AE1B6494041BB22A278DF2D40B07CB9924FB74940878E12887CEB2D40C25472F958B749405316F9816CEB2D403C388B67F7B64940DD7F85CCBFEE2D407362950F97B64940C817A3DB9BED2D40595BA33033B649406DDE877529EF2D402116017558B54940AEDD446EFCED2D40C8D17B08CAB44940A9CF3F83D4EA2D40569764D278B4494004BFA05D8CEF2D40259DA4A78CB3494088B03F643CF02D4014D82C05FBB2494060473879B0EC2D40A6383C5EE5B249400121CFA2A5EA2D400D2452419EB249402A67C821C9EC2D40A9D31C8A8AB24940EFDA1B6195EE2D40389880D013B24940A093F650EAED2D4042417BEB7EB14940C777B8E042F02D4053E5420EE3B049407A28C02F30F02D4079DB30EC8AB04940B492E594A1F72D406A73B46DE1AF4940497665FE7AF42D404743F79944AF494038610B4470F42D4015B1945ECFAE49406D1B00252DEE2D40A4D0551940AE494005372D83AAEE2D40A391919104AE4940614D9396FEF12D40254BD1C30FAE4940E8F44B8DE1F32D40D4CFB33AB4AD4940C6C487CB95F42D40AF2E4C25BBAB4940758ECDF31BF62D402EDED21D7FAB4940A30578C1B1F62D40BBCD2864CCAA4940D376E9B5B0F82D4040C3802F90AA494077B3A30AF6F82D4041D1574A21AA49407D9E431F75FC2D40C6CE251A13AA4940E8ED44B9E7FC2D405CBC42FB44A949404A368902A9042E40351377458EA84940D5BB20106A032E409ACD64D4E1A74940E09F3FE773062E401EA82CB17FA74940457C6A9693062E40B227322A82A6494012D44E6EBC0A2E40CA593D3E83A64940E7948C60FB0E2E40EE9B2ACAFBA54940	Niesky
2	0106000020E610000001000000010300000001000000FF000000FDC9AEC39E642D40EB82104C60CC4940DD1C68217A6A2D40DDE9DA516FCC494071EEBF3AF0702D404897A44852CB4940B3D2CCC6E3702D405DA302610FCB4940223FD476B2752D40F08B3DE577CA4940985BEE804A742D4045D178B7A0C949404266AB0A296C2D40FC5D24BD00C849403C9E18BCF16E2D40568101DD08C749408F73A41E90722D40BA2EBD92E2C6494009EAA97766752D40F4E697B563C64940B4F0BF7985762D402E2E9DF6B0C549400296AFCDE2732D409791A06805C549403BE0AB5AF7752D40F3596933E9C34940E3DBFECD01792D40BE57BB4E4AC34940825AD9483B7C2D4084B9018E3FC349402D7CEC8E0C812D40922E8B75C8C2494040E2997730852D40ACFDD69E00C349404EEAD6F0D2872D40638029766DC24940A57E6B10048E2D401790E35542C24940295368332E912D40A5BAA2E35DC2494056063DA88C932D4083C2908C2EC24940E7585BE7B1972D40DE7419CD47C24940F1E179FC11992D40D4CC39FFF4C1494020ED98D6349C2D405B29D8A0DBC149402E859D19989F2D405ED56F15C8C049400AC227853FA32D400424B59EFDC049407341A08721A62D40AAFF040AA8C04940EF59A1341BAA2D404901D74C7FC049408D5CC30771AB2D40208A0305F0BF4940AE6B719809AD2D4065D66787DDBF49403806A70A0EAE2D40A5C496DF79BF4940E4D4310322B02D40D69E0CCF5ABF4940880714EF3FB42D40C46CD46EA5BE494075605C23C0BA2D40A73BAAD9C8BE494047971F8E5EBE2D407E21AD7E0ABE494015A2EDF438C62D406FA41EB277BE4940BC1716A85AC82D4028B2626903BE4940ADF7092DF0CB2D40828D9E52B2BD4940D57180927AD02D403D4B503BF3BD494065FC42ECFFD42D407FB3B53DEBBD494054D791127AD92D402DE9971F7EBD494082E5E44B56DA2D40CAF970C394BC4940D5B9D62CA7E52D40B0AC1D685FBC49405E96E1B5BDE92D40167C85FC4BBB49408BB3E17784E92D4041A4AB0FA9BA4940314B69D6FDEC2D406D6A68F0FAB949408CC66779C3EE2D4040211B8A25B94940D0827B69D0F22D40558B5AC584B84940C87578C1DDF02D40DF603B6055B74940E81C290D91ED2D40FD0A8F8896B74940878E12887CEB2D40C25472F958B7494041BB22A278DF2D40B07CB9924FB74940F352FFED0BD92D400090F70AE1B64940C5680D6765E02D403BAA323800B64940CE92B9471EDD2D4051C6546C2BB54940B235767F69D62D406DAA6F0AC7B44940B8DAACEBE0C82D40909DADA5BBB44940B1F7474119C42D40F89CA11CD4B5494006718DFB02B92D40FE63502446B64940DFEC97C5E9B82D403076716190B64940AF2CC89844B02D40797A914CA1B74940A8D238E7A4B32D40733B646F36B94940F88396E472A42D405B31136154B9494077B8C5B6A59F2D40FF41775AB4B9494045976DE2FB932D40150E9D2EC8B8494096EF9CA7E48B2D401FF3213904B84940C4A456F106822D40BE9B40B983B74940CBB09679E37E2D40EA486093E8B649405EBB5EE2277A2D4082444C897AB54940D3A682378C762D407E092395FBB349402B0D424019772D4076DEC806D8B3494028D3F0E88D712D40BAEEC756CDB349406AFDFB783D6C2D40CCEB809217B449406E1CE2E40A6C2D4000F26B0870B4494093B5E3534E682D40365EA6CABCB449409CDD6F25FA672D40C79718A367B44940533D2A310C662D406A6EFC9DB5B44940E72262099B6A2D40CC68BB95D2B349405A8CF012C9652D4008A7E7E839B3494010FC118EDC612D40C4A72B770FB2494022F6AF7FE5632D40B0970E7951B14940998FB4A55F602D40342F41D0FFAF4940FE73C4B8CD5B2D409948D245E1AF49406220011D31562D4002DCF1B9FBAE4940905107FEBA562D4000DDC83E64AE494073582D93B7542D40F57F00ABFFAD49407DC7AAE791542D407700F6D4C3AC4940CA0AFA7C4F532D40D423B1B954AC494026E05A0F38542D40F18D9F3537AC49402099E814D6522D40C2DA517DB8AB494058C6CD9C9C4F2D4080D2716206AB49403B895F11514C2D403135665E1DAB494054D55CD7344A2D401FEF0958CDAA4940DD64A573D84D2D40DA14735264AA494070E32E625F4F2D4065BACDC0A3AA49402063A1FFAC512D40CCECA9D05CAA49404EBE79AEEB522D402E0CC62B6AAA4940197460A7E5532D4028A7D59E27AA4940926A20CD92522D4043C6DA33DEA949408D4F6DBE2B4F2D401C0B4D26F4A949401A9F0BEB81502D40C471F07A7EA84940F41FE573DA452D40F43886BD33A849401CDA500270482D40D618179CEDA74940F158AD3C59492D40747B01E018A74940802AA5972E462D40E31E8D7AD0A649407B6EFA8FDF432D4077EB899F58A74940C528E22DC4432D4030EB558B0BA74940CDBA4AA7C1412D40CA7D03D0E5A64940D35CA291A9402D40377ED9B40DA749400DCEC54CAF3C2D40CFE2B59D08A74940FE3573AE4B3B2D40FE9C08E87FA6494059B079BB32382D40BEB29D7255A649402030AF7280352D40CBC9C7F8A6A64940483C776965362D404DA6B2EF59A74940DCCEE9C836302D401EE42B9A45A74940995BB91B6E322D40D66215ACE4A74940E7EFADFB6D2C2D4030931C32FBA7494076BEF96F042D2D40374018B87FA84940A218BF028F302D400AB6D5DFE5A84940FE954F63EA2C2D40E3C9E192F1A84940B9296E33D42D2D40DB5AB4D838A9494048FE71E1C0292D40B72E39774BA94940545F7E89B6272D4022D12A4A8BA94940FBAA0357FA232D40504391BE98A849403149A89671212D406D716DE596A84940E0FBDF7DC61D2D40AAAA445FA3A949407B426588C71B2D40C4FCF973D0A949403A8EADA1231C2D40DF9E515BFAA94940A3DE748EAC192D40E68D420327AA4940D960F2682E192D40078BAC54E8AA49404B570559E4142D405B53B3AC38AB494029B0F54EE1122D4016F461E0A2AB49401B6C435DD8112D403D6DCE9674AB4940DB50F4A2F4102D401617EB498FAB4940B2A3723513152D40475FE9DDBCAC49402EE5231AE8162D405E8AF562BAAD4940684BEE02B0142D405AE864DC87AD49400A324DE99F122D409A47F10A9FAC494050CA4A799B0C2D4017BA870D79AC494080F7432A220C2D4042A1F3CF26AC4940881B585C960A2D40F92405D10CAC4940D6D0EA32120B2D409695A48185AB49406BE9764A470C2D40550230746DAB4940A52DFF44A60A2D4006D502D42BAB4940A94B51631B0C2D40A64D402BEFAA4940EB388519DF092D409FF6E717C8AA4940C5969F8C1E0B2D4082B8042924AA4940B1D1DA0B18052D401561642A24AA49402930B004B1032D4030ED86A1F9A949406B6A2F27F4032D407E25647FBFA94940FCE9B6D268042D40AEE4A6C601A94940EDA30D9F79012D407D5BFBAB5CA94940E3067B6FBC012D40D979C157EBA94940611E12E6A2FD2C40182DE41FCBA94940996DF1B997F52C405431CF101CA94940956C64BF32F42C40A6D39CCB10A94940654DAE4F1BF22C40D6FC0C8E6DA949402C0A983090F22C40C4367212A8A9494065DA5CC6A6F32C4081F42199A6A9494003FED9E72AF32C40A99847B020AA4940A3356BB48BF12C409F8B1F796EAA49401C1D4B3665F12C402AA5EB76EAAB49400C7DBD38B1EF2C40DFED8F7145AC4940363277EA13ED2C40B530896A4EAC4940352679FC63EA2C409762C09E41AC4940BED785CFE6EC2C401DB6C89E8EAD4940EAE60447BBF12C405D31FF8206AF494066611DE3AAF22C40BDF4B71501AF4940B4E211761BF42C401BD5A6057DAF4940053D6EBF58F52C4099AE494461AF49404C47F6E9E4F72C408965124213B04940CE84291016F82C40E57BF93975B04940AE78EC883EF52C401A56E8D543B14940625D5F0AA6F62C4005255A1101B249409F589CF4A7F82C40DFD9E25545B24940DEF7827BA8FB2C401CEC6F6980B349407CF01CF64BFF2C40AE379B26C7B34940446E25F5AE002D407AD64C464AB44940FEA7E488DFF92C40E2F707D087B44940C2019C723D032D408A62D1B5BAB44940B5440D1A27032D40200E1C9D0DB54940128812A1B7062D40F941CA4B0CB549405751E19E64052D40E5593813A4B5494093B94F5F510A2D40961A54B310B74940B10C3ABC770B2D40FD0D0D950BB74940E96A2A1D690C2D40C928F2FE8DB7494002428CDF800B2D40DC033B07E3B749400B9A5DA46A042D4096383FDC03B849403D549A0809052D4067AEA7FBD2B849400D39877214032D40C45AE93962B9494015A92D4619FB2C401B11C00D65B94940D0E3E34067F72C40965EAB74AFB94940D381EAC336F92C4066965CF67FBA494030AFA29177FD2C4028B7DDDB07BB49406EB5CCF617FB2C403A207F0613BB494044EF6881DCF82C408151E9B874BB4940CF8F041415F82C4084CD6070A2BB49404B4F7B5A6CF92C40E1FE1C39E0BB4940CBF25D9CFBF32C401A06D13D47BC494080E34470E4F02C403E86E56200BD49400334922ED9F12C407ED418C8E6BC494059DA8924B7F32C40D41FA59F58BD49408463512BE6F32C403FD1F1D6C7BD4940A0BE6D249AF12C402B41A8BD07BE494045844B2B21F32C404B049D7E42BF494030E7838AE9F52C4071D4AC3124BF49408FA981DA5BF82C40555FA46174BF4940A3EADA34CDF22C40D7609E72CFBF49408F72DB15B1F22C40F8ACF5DA25C1494009D91C142AEB2C40D8A6F97274C14940A85160661EE12C40A847E8777CC149403056179B7BE72C4078115E7ADBC34940060ACB5F9BE62C40EEB89E8019C54940637CBDEB3BE52C40D0366A2F63C54940C7ADB204C3E42C40D636F465C1C6494064AFAD52DBE62C403708B03622C74940C74F3D95ACED2C409754B58E4FC749400B00B7C444ED2C40AC1D3D5023C74940A73FBEDE4DEE2C40D4AABDFB0DC74940F86D75C2F7EE2C405CBAD94D54C74940472DB33EE7FF2C40C9AAA8E396C74940794E92716D032D4094DC4EC24BC74940B62754D976042D40146DD60C76C74940C4E312FE2C082D400F8D11A6EBC64940974E67F2E60C2D4011AF5D267FC7494088122C8210152D40B097806EB3C74940362BAC316B182D409A45F3D526C84940FD0B3C95C1162D406EDC86336CC94940E21F3E952A1C2D40334F5C0339C94940761D701B361F2D40DCDAA5D56CC9494067E00924AB222D40EC9B3BD461CA4940FA1C9A6243292D40B6E6C4384FCA49403BB9E9337C2A2D4083FA33FC8AC94940F491F12EDC2F2D408686F9B180C94940DD02CB75B4322D409A7A4CBE1CC94940C6CB378D12342D403D2FDF21D2C74940B63B22DB7A362D40CB35CE5740C749406619038911352D40C98567B50DC74940C8EA076117372D40C78AC8CDD4C64940597D90FC26382D40A52AD5B46AC64940A68F2CED4E432D409429F90185C6494004C66D2AE1462D409C7071CAF5C64940F700096B1F542D4095B368FF00C7494022359483FA532D40F2EA3F8CC8C6494067DB0D5B16552D40C9D5DFC8DDC64940FA71B950ED582D40F73D50FC81C64940B7DEF815BA5A2D40BD7576A3A4C64940AC1C32E1D0612D4095CF738AF1C74940ECE5D76D90642D40D8E472449FC94940A54DAEBEB6622D403DEBD00CC5C94940FB95C397DA652D40A7350F0ADAC94940B685B46467672D4067552C4EA7C94940A1B13075DC692D403B18459DD3C94940BB07AB008E652D405B7B5A4E7BCB4940FDC9AEC39E642D40EB82104C60CC4940	Weißwasser
3	0106000020E610000001000000010300000001000000A30000002CB9F68DB6082E4036EF0AFC7C9B49401E8BDBFF06052E406B5549A0549B49406A78A42C1A052E400A027B650F9B4940BEA8F2D3A9062E402B7F3A10019B4940A23D22EDA0062E40738540F8A69A49405A30B3D5E5032E4071187E1E2F9A494031CB8B3904042E402D61B0178399494085D1E35D6A072E4024F8FE124C9949409E93F5D14F052E4098F86209AF984940DB5CC9BA68022E40715D139671984940FDCDAD1890042E40D3774E075297494057D29679C0002E404FA407EF08964940044DA28499022E408FB5FB4F78954940DFDBA9257DFC2D401A889220CB94494057FB912102FD2D4007C00EC726944940FD85A3537B002E405B63331334934940906E362825FE2D40BE9831E26F92494000F59B7F01FB2D40A306F8693B92494096EE818A91FD2D40D0E42FA392914940091C3FB759FE2D40D6B9A6D7DA9049409230BCAF51FD2D40E24FA14ADA8F4940063775B5DAFE2D40DF7B48CEAE8F4940005E7CCD4BFA2D404188D1CDE88E494024D9AFFA5AF82D40978EBFE6E68E4940EDB8E79360F72D4016D27EA4168F4940D3F320B62FF62D40EDB73463DA8E4940E9E736501AF72D40272EA2D4818E4940BB7C5794AEF52D40274A29BA218E4940D67FE0D962F62D4053748A20F48D4940E51F0D88CCF42D4001E66B28D08D49403B168655C1F72D40FCEC5A731A8D49408A96C9E5B8F72D402A9CAEC7748C494087B8654EDAF52D40E2FE1E22478C4940A70009531DF72D40B24EB6522C8C4940AECEA6DBC6F72D405FB5043E9F8B494041A8454EB7F52D402F940F86838B49407DFE0798AAF52D40E45B0517258B49409022CB74F8F32D40E51B8C3E2F8B4940E952AEE27AF52D406F44AACDE0894940E189858EA8EF2D40BD12C5F92C894940F702FDFC9DEF2D40DACF2790E888494099A8A07375F12D40A80F293EE08849403467868096F02D40ADD10B6DA58849401943808F4CF12D4044E8532666884940A4A40C40A7EF2D4045E271263788494080FA1CD7DDEC2D4090DEA0C12A874940FF589DF0AAE62D40FCE4F51A4C874940EE7FC11126E62D40D78409B3D38649405821501BD7E42D405A86AF68BA86494028E8B43382DD2D40C40FA63EF68649405BC5982421DE2D40DCA818D2FE874940144E824BADDB2D405694F5A984874940155B5122E3D82D4094712D698C874940DED90ECC3DD82D4050FB94AD61874940B44D3EEA57D62D40825389F38C8749403D3BFF88F3D52D403DF57A10768849400882828AC0D82D40CB609ADB90884940B760ADABBBD92D404F06FE36E38849401FB6FFB66BDB2D40BF12FA44E388494051289B1341DB2D4097AD8A4E91884940AD685B4851DD2D40AE456036F78849400A0A055BD7E22D406329D97BE08849409C45494338E22D40EDC6A9E8568949408542ABF6FCDC2D403A97080044894940499BE3C72AE62D40154E5E5EA5894940DFC00B508DE62D403FC858413A8A4940D03C040E9BE82D405843C8E6618A49407FA5306AAAE82D40201F7C196A8A4940DE7FFBF9CDE82D404C873F726B8A494015F20C3984E82D40F1BB05A5B98A4940ACAA3F06AFE52D400A4B7DA2958A4940A1FF207FD5E22D40A97143AECF8A4940383F0278B4DE2D40178EBF44E98A4940E9D9A9ED84D82D402885A432A48A4940DC9182BAF5D32D40EE0341B4A58A49409681B42B58D12D405EF5C7A4CA8A4940B0727A32B4D02D404B24E7A4058B4940E092B49F6DCA2D40FC1C16FAF28A4940EA1D56BAA1C82D40831FB05DE68A4940AD8D21C5BBC62D40ED417435838A4940766451617FC02D40EF66B7D1688A4940DD2A1C49FABE2D409B3841C2F9894940F2FBFF2082B52D40443CE553AA894940275B5C5A0FB12D40891A914BBB89494009B027E15AAF2D40909063DC2F8B49403D64805206B02D40F3686989D38B494028354C221FAE2D40E54C5EC5DC8B4940722FF7B041AC2D40C36840C5778C494022ABA97122AC2D4023138BDACF8B4940142D97259EAA2D40C260CB8F9A8B4940AFB08AF1FBA72D40288A1608B28B4940D744AE05ADA52D407822E36E948A494022CF613D27A42D40F624B668A58A49408635BD3B89A72D40F19AB440658C49407252D77B00A22D40C7F7DD0DD98C4940CA61FA7F3FA22D40AA100FC5208E49402FABD134B8A32D40E7E8A6C7A88E4940AFB7B00202A22D406EF1279F048F49408E303991C7A02D40C863F9F7FC8E49405BA4D7043FA22D403DE30564B38F4940E6C199C74AA12D40F90DE227F88F4940E74A56BF04A22D402BB3F6042B904940B123BF9E19A42D40EBE423B0199049409AB8B3E9E2A92D40BEBEDE0CE99049403E879C02B3AA2D4042E2B9ED7B914940098D37263CB02D4090B18274529249405E558438C8AF2D40C44EB13D279349405FF6C0E7DAB12D4099930DDF1D9349405C5F04E28EB12D400829222642934940D20740C1DCAC2D4048BCB03E93934940CDF2EE82CDAA2D408720BB2143934940441283A7B3A92D40322DF9CEA0934940F3E82A5032A82D407DACE78A8C93494055C1AE434AA82D408E923F0FBF934940F082F037FAAD2D40FC7010622D944940720CD3B754AE2D4024E7782FA894494047D31F77A3B02D402EF8481E0295494022A90D6606AE2D4076003B103695494064EB130940AE2D4024D98623E9954940DC2A3D6A1AAD2D40AE1D248700964940295D42BE60AC2D40770348317695494044618E18E3AB2D4071735547939549400113771690AC2D408D66EC3B4B9649405C90609444AB2D40433E335FB096494067E8D6A5B9AB2D40BBE5902705974940F98FA76813AA2D40CA3A1CCB02974940E54F67BC5EA82D40CCCED9B36F964940E0F954C337A82D401DD8C6D6AB9649400C7E866112A82D407012297636974940410DE60D28A62D4097B57292BE97494054CAD6114DA72D40C90F3E8DD3974940D11FCAA675A72D40F564F2679E9849407AE7B6DF1AAA2D40231534733A994940232882A993A92D400FFEEF358F994940DCD2EFF0D0AA2D40B73D0B3EB799494095F52957C4AC2D40DEBB1EC797994940411E324FE7AC2D407F43F47A1B9A4940ECEF129A11B42D40E7F43A4C969A4940897A6B65BFB72D4063C4BA437C9A4940C81BC89F66B82D40879D1639429A49408D965BE14FBC2D40B5F1DF252E9A49403B19F0929EBE2D40207D8A97D6994940C99CBCBB29C32D40A953BF85D09949409B2147AC95C42D40D821C3A587994940C4444ACF5EC72D4084BC27FCDF99494019ADCBDDC2CC2D40FCA4D98F149A4940F633B7EA40D22D40FBCF13A1D19949409199EAC988D42D400E9073E8B29A49409EE78EB807D32D40643B2366D89A4940B85608C428D42D40E7A8520E429B4940D27D518721D82D40D2D10E58189B4940853A954041D82D4042D0EEB30A9C49401EF51FCCBBDA2D403E8FB806859D49400BBE6A1ADADE2D40923D587DA29D49403B965A8D76E32D409971817B219D4940E12C8ACD98E72D40818D9A31919C494087C59D1B42E82D409DBA8681399C494031CD08A470F22D40DAAD3460AB9C49400554A6EA31F32D40D012977A209D49402F304F30B9F72D407E0E8383CC9C49404ADE1106A9022E4011C47B97979C494073EF943432092E40C9ECBC9B329C49402CB9F68DB6082E4036EF0AFC7C9B4940	Görlitz
4	0106000020E610000001000000010300000001000000F600000041CD9EBC68252D400759975BE68B4940F105A5161C252D40FAE0DFA0578C494066A284F08C232D401E66F83C4E8C4940CAD4C9B9A5212D400DD1B46A918C4940F4B28BDA8C222D40FEA406A8DB8C494028C25708172B2D40265B50D4788D4940CB7A034DDE282D4099D91954EB8D49405C2FA9AFC4282D4095FC1AE3568E4940292BC3A540252D4006EC8136A38E4940DB7593E199262D405E25E714648F49409447D92C5E292D401643A653398F49407FC2BBF9B22A2D40198443AC668F49404688339400302D40480BF75B578F494004DC73EB8D352D40EDE9DC03F68E4940440A34FA893C2D40A900E3000F8F494031F73D5C9C3C2D401190D4F0408F4940EF212FAA4D392D4092A03D53618F49405018B4E208392D40E874CA41B18F4940AADAEA2ABE352D40B538A912C58F494075B0E3D18C352D404E963D62FA8F4940685C2415CD382D40211BE03BB2904940B2E2592DAE392D40DC29495E80904940346D3529C83D2D40C0E21111639049409AD3B46B89402D40DD1E6DABAE904940F3F9A39389432D405E6CD79AA79049405EE8426022462D40974FEDB212914940B7E04CF62E482D40D23B81FBF49049407C5C268145492D40FE7A9A593A914940B0743ED945462D403873D3ED1D9149404E1BABB3E1432D407CB42912819149409B02262A48442D40C4098B10C9914940B90715DD62472D40C996C86BD7914940765D3DC37D472D40B78559098D9249407579F77B52482D4029259EAA8892494050BBD94C46492D4045D7A832D59249400D16A2C8404B2D40783AC200D6924940D0D5A665894C2D40ACBB10AF6B9349401A646E6BD94B2D40DF62BDD394934940DA8CF345BB4C2D401A155A688793494075D58535F04F2D40D2738E5B1B94494022D9DA5993512D401F077A71EE934940D27C68C545522D40B683D0B419944940752FBB22D7542D403B5972E6B3934940C45895786A552D405F28503AD2934940FA631984C0552D4004C213FB68934940DE08A07D8F582D407B48A2AC4F9349408E38CA3DF9572D40047AA41106934940BB9C1BE09D592D40CBFD3DCA01934940FB1BD796E1592D409586F7265893494093BAD411E75A2D40B3A6627259934940B5238086245A2D40981590B506934940AFD5C3EBBD5D2D40F2D011C0089349406F20FFDACC5D2D40F70A29B16A934940EB11393A685C2D40460D3C548A93494011F29589A45D2D40E2773FE841944940AEA535511A5B2D40500C1CCD7494494007D6BA06F45A2D40BA99A1E0B99449404C2794A88F5C2D40D305AB83DE9449402BFA63AC755C2D40131B87023F9549403EAB1F87A45E2D40FA64A9A1579549405B513023BD5D2D40E95113C984954940153C794C2B612D40B57C81314B954940DD66ADD4D8602D4055B6253DB695494018D18A7FF8612D40A659C101D995494057C9455675602D40215CA79F3096494055FD984D12642D4085A66A99AE96494027A4E74A33642D407AFAC32FE796494028E4100719672D40E9D1EC260897494007224AC63F672D404447162730974940165F9FB107642D40D0071BEBA9974940CEA57AA59C652D40FD6F3ED4D697494053D8FAFFE7622D405F7E07BCBC974940BA1BD0F84E5D2D404972B9C2ED974940C4CA009C2D5C2D4054797E13179849407606FC96735E2D409D460D6524984940A23D10669D5B2D406232B5856198494028B56AE11A5C2D40040B2EBF7C9849402B51E411E45A2D408997C8A854984940F2609E61555A2D400395F47C8298494085446F9DD0562D406097014DA2984940E9E5C983865B2D408CB236C3F1984940A696EC7C345A2D4008607C736B9949409B59EEE4755D2D40A715B6A7B9994940713668C4295D2D407D7179E8659A49400607A326C55E2D4032456931089B4940F24DA4EC97652D400A75AF79D79B49403BDD4ABD0D6A2D40CA87DAA52B9D4940BC9153DCCB6C2D40341306F4569D4940D007C5ED6A6E2D4093F41667BE9D4940DDEA0EEF4B712D408B7EF7FDCF9D49403F5A78D2D4732D40DE4C6842C99D494047F4C9F66E762D402A1926895D9D4940E42A64C6D87A2D4005E81109209C4940181CBCCB857A2D40937C15A6CD9B494026E632AD68762D40EA925D64719B4940B3CC8A8F32762D4066C4A848219B49406AF7B4506D842D4042DEDBAD469A494093C9FAFF66872D406633CE1C549A4940406E38E357872D400543AAEC189A4940D3D822FD4D892D401AD19EF10B9A4940D7F5F971299C2D403EFD4108EF9A4940ACF6C628AD9E2D40DB07AD572C9A49407402F403FEA02D402D341988DD9949408B55C70FE2A12D40BF928603219949400E1711FC4EA42D40950C6575F9984940EFDECBD525A52D406B110D7697984940D11FCAA675A72D40F564F2679E98494054CAD6114DA72D40C90F3E8DD3974940410DE60D28A62D4097B57292BE9749400C7E866112A82D407012297636974940E0F954C337A82D401DD8C6D6AB964940E54F67BC5EA82D40CCCED9B36F964940F98FA76813AA2D40CA3A1CCB0297494067E8D6A5B9AB2D40BBE59027059749405C90609444AB2D40433E335FB09649400113771690AC2D408D66EC3B4B96494044618E18E3AB2D407173554793954940295D42BE60AC2D407703483176954940DC2A3D6A1AAD2D40AE1D24870096494064EB130940AE2D4024D98623E995494022A90D6606AE2D4076003B103695494047D31F77A3B02D402EF8481E02954940720CD3B754AE2D4024E7782FA8944940F082F037FAAD2D40FC7010622D94494055C1AE434AA82D408E923F0FBF934940F3E82A5032A82D407DACE78A8C934940441283A7B3A92D40322DF9CEA0934940CDF2EE82CDAA2D408720BB2143934940D20740C1DCAC2D4048BCB03E939349405C5F04E28EB12D4008292226429349405FF6C0E7DAB12D4099930DDF1D9349405E558438C8AF2D40C44EB13D27934940098D37263CB02D4090B18274529249403E879C02B3AA2D4042E2B9ED7B9149409AB8B3E9E2A92D40BEBEDE0CE9904940B123BF9E19A42D40EBE423B019904940E74A56BF04A22D402BB3F6042B904940E6C199C74AA12D40F90DE227F88F49405BA4D7043FA22D403DE30564B38F49408E303991C7A02D40C863F9F7FC8E4940AFB7B00202A22D406EF1279F048F49402FABD134B8A32D40E7E8A6C7A88E4940CA61FA7F3FA22D40AA100FC5208E49407252D77B00A22D40C7F7DD0DD98C49408635BD3B89A72D40F19AB440658C494022CF613D27A42D40F624B668A58A4940D30EB50859A02D401E5D8064E78A49401EE7DE2C949B2D40D16D5EB9988B494007A61AC8AB982D403DDC227E2D8B4940C26FDE287A992D40C5814BEFF28A49400DA9E07163962D403189B04DC78A49404465E49F05932D403140D5CDC98A49407AE47FA3C38D2D401FF76B65348B4940B7C5E93EAA8B2D403B71FF2C148B49408795473F6E8A2D408C588CB4E789494031185D222D822D40BADE689EC88749400370C69CF9812D40F04163A09E8649402213F67137852D407C20384E798649403276FF802F8B2D402EBD1B269C864940BFB1A22D42932D40C8D76BBAEF854940553730D70C992D4064F32C33028549404F43B8DACC9C2D4016975200AE844940461209B13A9E2D40A1BE3CFCCD8449406B08FE567B9E2D40A9CF3E00488449403D6E2632BCA42D40862A84198C824940A6B0FB0A23A82D400274F19F76824940065849C26FA92D40D034F4781C82494017BBCD53DCAA2D4056B87F630E8149401236531456AC2D4087AE5656FC8049400CDF2F5B2DAD2D408C3998B49B804940A617EB6140AC2D40DD3BB972C67F4940E671AE08FCA92D407517DA11807F49406B128F2AEBA82D40A9DBCEC7F67E49402508088EF6A52D402ECC2F24F27B4940EAFA444CD1A22D409715531CA77B49403FD450755C9E2D4021322C69D37B49400CE32ACF2A972D40273A9D6D497C494082B6E23630932D40A4E2E6A5117C4940D84C0D2A79902D409D7F854C7C7C494086598327DF8C2D40A695BE6D6D7C4940ABAE225DD78C2D402199E889DD7C49406695E854B7882D40C2E54C64DF7C494024895A055D862D4029C105C16D7C4940175E9E7273832D4006793635AA7C49402AA3780EAA822D4051E4352CA77D4940D797795F94832D4089BEB408FB7D494007E7A010A1822D40C3F07F2C167E4940A4056B686C7B2D401703BF52547D4940B0649F2B38782D4054D3AA0DC97D49409F37004D2A762D40E20E762AA77D49403960EFE954702D40B9370C91D77D4940A2DB1185F45D2D40134B52486F7F4940D9F6BEBCA65A2D406ACAB571D87D49401E9EB0FB685A2D40F5A592B3E87C4940392F53B62B572D40C2135ED9527C4940399D63EC19522D402E6A7D0E137C49409AC2F067BA4D2D40996D4154727B494095CB7098BD4C2D408D2D647D637B4940940C53DDBE4B2D408F1E9FC0F77B494077C4D93DC14A2D4049220D2FE87B494049F6BA55AA472D40A76D418E5A7C494072A7131500452D409884C4EE5F7C4940421602F683402D404B0B0345007D49406884FF8EA73B2D40494FF78C2F7C4940AB616E95173A2D4022B30BFEB87A4940E45B4DF71A372D40386E6362867A494038EC075174342D40B6C39ED0A47A49401B2C3FC43B312D4083B63DA43A7B4940D4BBFC73312F2D400DE0162BBE7B4940225A560E95312D4005888F120C7C4940F5BB7B2FBA312D405DA4A45BB47C49407350457E88332D40487A71705D7D4940BB0129A963322D4065B76D8F887D49408378F6E5B9322D40D2F81AC15B7E4940809A710BBE2F2D4088EF7DDE6E7E49404FD39569BA292D40BE26A0242D7F494045AB2FD950282D404D9B91DC0B804940B1CC3CECFC222D40FDC20057958049407333170C0D212D40CC7D0C2C4D8149409362EFC3B41E2D408E1894F1EC804940E353F357CB112D40C9139BA77A804940C9F1EA8DB0102D40696608C3BC804940A455F5BDC2112D406CF688A01E8149407D547C3D5F142D4024B4C8565581494070D839B87A102D408EA782561F8249405074C62B48FF2C4082482CDBD3824940890714E1E2002D40BDF56E9C248449408B1C2A025B042D4085AF9F996A854940832D26768F022D402A5C5081AD854940617CBDAACDFF2C4075D40D9BF6854940C602A83A79FB2C4018B956A194854940E8C5875072FB2C40DA9B64932A864940521698832CF82C409D1CF4B940864940C14F32A9E7FA2C408D953868D7874940FDF57EFB64F52C400290294060884940B95F2EB6E9F52C40D56FC3997B88494027517583B0F32C40D5D22E77BD884940E7A7E5CC60F22C407D58EFA7038949406BE9F9F979F32C4051F5CF6E7A894940C1A1390B9BF92C40F8B3B2D3D0894940C51365A372002D4065D98824168A4940A8E3692378132D40AC8DC697958A49409A8E6979AC162D4042194009958A494078BBADC18B1A2D408FEAA013218A4940D3165DFCC61D2D40832938B2348A494041CD9EBC68252D400759975BE68B4940	Löbau
5	0106000020E610000001000000010300000001000000D40000000370C69CF9812D40F04163A09E86494031185D222D822D40BADE689EC88749408795473F6E8A2D408C588CB4E7894940B7C5E93EAA8B2D403B71FF2C148B49407AE47FA3C38D2D401FF76B65348B49404465E49F05932D403140D5CDC98A49400DA9E07163962D403189B04DC78A4940C26FDE287A992D40C5814BEFF28A494007A61AC8AB982D403DDC227E2D8B49401EE7DE2C949B2D40D16D5EB9988B4940D30EB50859A02D401E5D8064E78A494022CF613D27A42D40F624B668A58A4940D744AE05ADA52D407822E36E948A4940AFB08AF1FBA72D40288A1608B28B4940142D97259EAA2D40C260CB8F9A8B494022ABA97122AC2D4023138BDACF8B4940722FF7B041AC2D40C36840C5778C494028354C221FAE2D40E54C5EC5DC8B49403D64805206B02D40F3686989D38B494009B027E15AAF2D40909063DC2F8B4940275B5C5A0FB12D40891A914BBB894940F2FBFF2082B52D40443CE553AA894940DD2A1C49FABE2D409B3841C2F9894940766451617FC02D40EF66B7D1688A4940AD8D21C5BBC62D40ED417435838A4940EA1D56BAA1C82D40831FB05DE68A4940E092B49F6DCA2D40FC1C16FAF28A4940B0727A32B4D02D404B24E7A4058B49409681B42B58D12D405EF5C7A4CA8A4940DC9182BAF5D32D40EE0341B4A58A4940E9D9A9ED84D82D402885A432A48A4940383F0278B4DE2D40178EBF44E98A4940A1FF207FD5E22D40A97143AECF8A4940ACAA3F06AFE52D400A4B7DA2958A494015F20C3984E82D40F1BB05A5B98A4940DE7FFBF9CDE82D404C873F726B8A49407FA5306AAAE82D40201F7C196A8A4940D03C040E9BE82D405843C8E6618A4940DFC00B508DE62D403FC858413A8A4940499BE3C72AE62D40154E5E5EA58949408542ABF6FCDC2D403A970800448949409C45494338E22D40EDC6A9E8568949400A0A055BD7E22D406329D97BE0884940AD685B4851DD2D40AE456036F788494051289B1341DB2D4097AD8A4E918849401FB6FFB66BDB2D40BF12FA44E3884940B760ADABBBD92D404F06FE36E38849400882828AC0D82D40CB609ADB908849403D3BFF88F3D52D403DF57A1076884940B44D3EEA57D62D40825389F38C874940DED90ECC3DD82D4050FB94AD61874940155B5122E3D82D4094712D698C874940144E824BADDB2D405694F5A9848749405BC5982421DE2D40DCA818D2FE87494028E8B43382DD2D40C40FA63EF68649405821501BD7E42D405A86AF68BA864940EE7FC11126E62D40D78409B3D3864940FF589DF0AAE62D40FCE4F51A4C87494080FA1CD7DDEC2D4090DEA0C12A8749409E4C66C3D0ED2D402F511BB7108749400E2E1D8EEAED2D4001C84FF569864940E2A8B0E446EC2D40B8E0D2DD6686494095801F5A74EA2D40F1C59117FD854940041626195FE82D40C85BFA93FD85494053ECE2975EE72D40793ED91C6E85494019DD9D15B2E62D40CDBBA6A890854940F0418425A8E52D406E12CA2376854940053E9B2052E62D400A6A66983F854940C734A8B07FE52D40EF230DAC0C854940AF486B5258E72D40B953D83FD2844940689E15D9A3E42D405B8325E20D84494072A12351F4E52D40D52202B1E483494015B11F6E2BE42D4014F7E2E0628349406D23737175E12D40425328A95D834940189CF04885E22D404E4C64E3FF8249408B6D8841E3E02D40184C8357038349404C0BD72043E12D40E59BDD80A5824940CE5708690DE02D409D104FB9D782494097DB511DCDDE2D406EE7A4BA97824940E742AD3BFDDE2D4066506E0458824940D9050796ECE02D401A7FED632F8249408E1BB8BA3FE02D4080287B0C748149402270DEDDB6DB2D4050D7F123C07F4940DED7DECB91D92D4049662D39917F4940262A73692FD72D409C7A5074B87F49405C71AC64A0D52D408F0188136B7F494000B9B6C7C0D52D4014049802B87E49400D9C98A836D72D40DFED3CFA737E4940401A85A12CD62D40E96E7225CB7D494002F3E60BC2D62D402094B37CD87C494065A164901CD02D4004E726BD707C4940A2CB58D25DCE2D408F5CCA265E7C4940DD4E5B2BDBCE2D400F0D93EFD47B4940995CF1EA97CC2D40F54F2316537B4940381843C2BECE2D40B886B2DE027B4940CD8BE4B999CB2D40F6ACFE1DCF7A49403350D5B136C92D406187D88D947949407AE80D9E3ACB2D40645BE02989784940164FD900A2C82D40BC950CB5C7774940E9F04AD3B1C02D40CB8BDEA44C774940119503E75FBC2D4025C31FB177754940E226D38723B42D40F4F718E79174494044A2165D11B02D40227F9E9453734940FB2BC78A0BA42D40A0EE6FEF6E714940F9100E9385A22D40B8E0BDA68D704940EB698A80ACA32D4043852EE8D36F4940F2901AFF75A62D400599E8CC356F49405DC1C5C786A42D40845137C4FF6D4940F37A101C079F2D40CD9129E1F56C4940B5B4F132799D2D4087539DB3556C49405AE7B918B89D2D4015840E49126C49408B454029EC9A2D40E0188B2B136B49401130941FB2992D404D9CA3085A694940B6F3E851F6952D40EF25086FF4684940980D1EC3BC952D408E37819F69694940BE559098BD942D40342F6FD679694940519364C6F78E2D4029065946F6684940B0A5B9A96E882D40B1F801C6DC684940C107FE029D842D40B6BF12208D6949408F5C9F87E37F2D40B88FC4928269494062023CDDB57E2D4090D941BE166A4940FDD3CBAF4A7D2D4085A89A7A2C6A49404AEFAB4B567A2D40DAABE6451A6A49402ECA4A4EEE772D40D5D130DFA5694940F166CA10D7712D4058D3175439694940056B4E76F46E2D407376CED7696949403684E977E36E2D40C367426E1A6A4940AB163334AD702D40F7793C23886A49402C5BA4FE486C2D40EAE36580496B4940DDBAF7B4A46A2D40F42CBD60A06B4940A26ECAF041612D404A3DEE9C436B49405A4357607C542D4091B82A1FB26C49402B74093B8E502D4078EE0D15B76C49408EA6B5B6AB4B2D4085F00584A36C494018AB7AC22A442D406C4C6DD5716D4940B20F50AFE23C2D4092646808CB6D49401EE167F1EA3C2D40F33178A3A96E4940678DEC6C873F2D40006E19E1246F4940DA39F8EA31422D4029663AEEA8704940041B1124EE432D40BD685118107149405A60901BFA452D400ACFDF5AEC724940D038AD985A4B2D40C7022E52B6734940D559C557404E2D40825F6BD9E4734940B73CD363C54D2D403C51C5B09C764940B1A2094AE74C2D4048CA2B253C774940A88615C6704B2D40F554FEA93D774940991DF8426A472D405187EC2F1277494012DFC7A79F412D407D25137C7676494030DE6FB4F23B2D405825563679764940F38A5E1C79392D400B5F58B80E764940FF3012DFFE332D406F6DFEF2DC754940D641AE4ED02F2D40621F38D54A7549409E42EF2C892D2D40465CF54C5E754940E74A04C6F3292D407B2C9922EF7449409C01B65FE0272D409F2F15603D754940C17830001A212D40D7D713748D754940562A21F7091F2D409A0C2B416E7649405B4A3D7CDD242D4011617988007849406FBA2AEFDC292D40260FEF75A078494053214DC6B02B2D40356D004ED07949401B2C3FC43B312D4083B63DA43A7B494038EC075174342D40B6C39ED0A47A4940E45B4DF71A372D40386E6362867A4940AB616E95173A2D4022B30BFEB87A49406884FF8EA73B2D40494FF78C2F7C4940421602F683402D404B0B0345007D494072A7131500452D409884C4EE5F7C494049F6BA55AA472D40A76D418E5A7C494077C4D93DC14A2D4049220D2FE87B4940940C53DDBE4B2D408F1E9FC0F77B494095CB7098BD4C2D408D2D647D637B49409AC2F067BA4D2D40996D4154727B4940399D63EC19522D402E6A7D0E137C4940392F53B62B572D40C2135ED9527C49401E9EB0FB685A2D40F5A592B3E87C4940D9F6BEBCA65A2D406ACAB571D87D4940A2DB1185F45D2D40134B52486F7F49403960EFE954702D40B9370C91D77D49409F37004D2A762D40E20E762AA77D4940B0649F2B38782D4054D3AA0DC97D4940A4056B686C7B2D401703BF52547D494007E7A010A1822D40C3F07F2C167E4940D797795F94832D4089BEB408FB7D49402AA3780EAA822D4051E4352CA77D4940175E9E7273832D4006793635AA7C494024895A055D862D4029C105C16D7C49406695E854B7882D40C2E54C64DF7C4940ABAE225DD78C2D402199E889DD7C494086598327DF8C2D40A695BE6D6D7C4940D84C0D2A79902D409D7F854C7C7C494082B6E23630932D40A4E2E6A5117C49400CE32ACF2A972D40273A9D6D497C49403FD450755C9E2D4021322C69D37B4940EAFA444CD1A22D409715531CA77B49402508088EF6A52D402ECC2F24F27B49406B128F2AEBA82D40A9DBCEC7F67E4940E671AE08FCA92D407517DA11807F4940A617EB6140AC2D40DD3BB972C67F49400CDF2F5B2DAD2D408C3998B49B8049401236531456AC2D4087AE5656FC80494017BBCD53DCAA2D4056B87F630E814940065849C26FA92D40D034F4781C824940A6B0FB0A23A82D400274F19F768249403D6E2632BCA42D40862A84198C8249406B08FE567B9E2D40A9CF3E0048844940461209B13A9E2D40A1BE3CFCCD8449404F43B8DACC9C2D4016975200AE844940553730D70C992D4064F32C3302854940BFB1A22D42932D40C8D76BBAEF8549403276FF802F8B2D402EBD1B269C8649402213F67137852D407C20384E798649400370C69CF9812D40F04163A09E864940	Zittau
6	0106000020E61000000100000001030000000100000094010000B90715DD62472D40C996C86BD79149409B02262A48442D40C4098B10C99149404E1BABB3E1432D407CB4291281914940B0743ED945462D403873D3ED1D9149407C5C268145492D40FE7A9A593A914940B7E04CF62E482D40D23B81FBF49049405EE8426022462D40974FEDB212914940F3F9A39389432D405E6CD79AA79049409AD3B46B89402D40DD1E6DABAE904940346D3529C83D2D40C0E2111163904940B2E2592DAE392D40DC29495E80904940685C2415CD382D40211BE03BB290494075B0E3D18C352D404E963D62FA8F4940AADAEA2ABE352D40B538A912C58F49405018B4E208392D40E874CA41B18F4940EF212FAA4D392D4092A03D53618F494031F73D5C9C3C2D401190D4F0408F4940440A34FA893C2D40A900E3000F8F494004DC73EB8D352D40EDE9DC03F68E49404688339400302D40480BF75B578F49407FC2BBF9B22A2D40198443AC668F49409447D92C5E292D401643A653398F4940DB7593E199262D405E25E714648F4940292BC3A540252D4006EC8136A38E49405C2FA9AFC4282D4095FC1AE3568E4940CB7A034DDE282D4099D91954EB8D494028C25708172B2D40265B50D4788D4940F4B28BDA8C222D40FEA406A8DB8C4940CAD4C9B9A5212D400DD1B46A918C494066A284F08C232D401E66F83C4E8C4940F105A5161C252D40FAE0DFA0578C494041CD9EBC68252D400759975BE68B4940D3165DFCC61D2D40832938B2348A494078BBADC18B1A2D408FEAA013218A49409A8E6979AC162D4042194009958A4940A8E3692378132D40AC8DC697958A4940C51365A372002D4065D98824168A4940C1A1390B9BF92C40F8B3B2D3D08949406BE9F9F979F32C4051F5CF6E7A894940E7A7E5CC60F22C407D58EFA70389494027517583B0F32C40D5D22E77BD884940B95F2EB6E9F52C40D56FC3997B884940FDF57EFB64F52C400290294060884940C14F32A9E7FA2C408D953868D7874940521698832CF82C409D1CF4B940864940E8C5875072FB2C40DA9B64932A864940C602A83A79FB2C4018B956A19485494066E0FDBA17FD2C40A77E7920948449406A5D435245FC2C40D6F7F430FF8249404E1A4A2BE6F22C40F6E15DE044834940EE0CD49464F32C405A9AECBFC783494056F28108DCF02C4086C359C9F5834940A6C5A9306EEE2C40A7FED84E86844940E2A5E8645CE82C4090C063D599844940A6EE6A60CDDE2C40A3969E8675834940EF2301DF31DD2C403DB811F5FE824940530B4490F4D62C40A13E6A7B70824940885D5DBFA9D12C40AAD7F9186782494017166B018BC62C40A1B8B95E3C8349404CBD2BB034C42C403CD4C820A2834940CF2B85F4EEC32C40003CE0C8EE844940EC87165781BF2C401656D4B4F184494067F2A17A54B92C40465AF36BCD854940172127F393B12C40AAA0196C4E85494064806A48B5B02C40690CB8D3FE844940F3F9E88082AC2C4068C25CBFFD844940FB81B92566A72C40B98F9C96048649407454140A41A72C40FA3BD2EA50864940295386B9C9A22C40A3553EE40087494042E5747D51A32C4037ACDBAB4187494091CB5AB216A22C40B33190E2BD874940747B96BC389F2C40CB025C18A8874940B9B765A8059E2C4010C5F7A1E487494080FC461C1DA12C40CB005925EB874940C4CD17ED16A22C400FAEDFB4C1874940784F116A05A42C400CC7564CAA88494062D32FFC1E9A2C4078330976C3884940704365151C952C40BFD738014C8949406814A23A928E2C4018243ADF7589494017D1C7F8098B2C405B800EB37E884940A810BDF61B862C4069398568DC874940AE7C9FE7BE812C40C2FAD181B2874940760F52DB95822C40D62297BD478849409F6F7D6A59802C40E4B048FE8B8849401BD56D5F93802C40FB7EAD6DD28849404E0D17337E7E2C4092CC4FC06A894940B95CFAFC84782C40A199752BA48949400673164C76792C4028958959E1894940791DE04108772C40919E5D1E198A49404836A1CB95682C404C06CD15078B4940A0D30270E8672C4026264155E48A494002635D9F745F2C40E8823BED3A8B494038D681D1EB5C2C40CF5D860B828A4940F453E231E35B2C403B6F900CAE894940AADDEB5647592C4024325D12C989494080F8407490572C40D1AE572D99894940843C0181925B2C40B623D826228949406BF0324139552C4097EE61E71B894940EE878BAAE7542C4071E4F0A6C68849404E79A3F8D0572C40A9434497AD8849407AF212C904532C40D3902F9D8788494026B28BC162492C40CBB3457682894940299383FD5E492C40B764F7D6158A49406F14C178A5462C40ED6AA1438F8A49409BAC7DD8EB472C409610156AE98A4940F816E8D7E7462C40F7A5391BD18A49407ACD7127D5432C401030CEA9828B494085B83A9111412C40F8474B5D2B8B494078228916EE402C40EDE891D1CB8A49408D24F4C05B3D2C40CD7672B0808A49405E15B1A5A13A2C4047CE0613058A4940CA65FD4AF9382C40B2CA34592C8A4940BBDE877B60352C40C54D6F025C8949406E398F5CC9322C40841046CD45894940F104C5D1652C2C409996E13BC2894940C5084530D62A2C403BF565D65F894940DB34C3FC4B292C40D7181CB24F894940964CBA6F96272C40A7B1D541848949402EB0FC3FAC232C40E63C4D588D89494063921495CD202C40E626BD755F894940E7E6530C951A2C40BBE02132EC8A49400C92106C3F182C401DE7B430D38A49401D963E6956152C4048EE71A2D78A494070FD49E787102C40D113ED5E848B4940B6ADF37FD80C2C40FAA8BB0AAD8B49401BF70D57E10B2C40DBB74A97008C4940DDDC1EE3880A2C4070D844D1068C4940DEB658669F092C40452FE1BEB78C4940EFDF326E5C0A2C408594CB06068D494076296DF573072C40969010EEB98C49401EDB667C8D062C40D42137B5DB8C49408CA1E40D83082C40DB5B5C4B3E8D4940187CE110E0052C40FDECCAB5AE8D4940B887290122082C407E8ED4BE328E49404E0CE3C7C4072C40C1B0812E7F8E49406D3494E159022C40E197AF84F48E49401930907F5D012C40EAB64044608F49406465E72D12032C4017B12440808F49401FF3B20162032C40B54141315B8F4940B37A571046092C404972D589268F49407332C887230F2C40947270FC8E8F49408B28903FB5102C40188FF398409049409E3B26EE82142C40F60533DA3A9049406E88FAC0D3182C407E5BE727F18F49402B82F4F89A1F2C401E2411F9E58F4940E94A6230F2262C40196680FC7A9049409DA4BE0454292C403D62FE51B291494028872C188A282C407BD958C0A592494057ABCE2C003A2C401676D348F292494086240BADAA372C40CDE323BE6F9349404F4FE19282382C402A5D7C04549449401085216F56372C401401BF6170954940D9B66832BD322C40BBB140526B9549408D2EE231BF332C40A0C930F8C19549402E2EA72FD3322C40C757594339964940F013EB6DE82E2C40BF9D76E8D3954940A738EF75412E2C40151286AE0C964940BCAD1BB383302C406F2D17D0539649406AF8EB0B0C302C405B7763459796494094EF340753332C401FA06175B0964940D786FF433B382C4025ABA34C5596494009470C2E28392C4075BDCCDE98964940E3E8491F323A2C40F95A555A7E96494083EA04F9EC3B2C4070956F31F59649402E5D8ADBCF402C406569538C75964940F88F72B700482C40548A0285239749404EFB4BEE2D482C40F739D819CB97494075489FA5174C2C40CADA0CC219984940FBDCBFC550502C402B102F61509749401FAE4FD87E532C408D0FC5EC59974940F2841770F3582C40B018D398BA97494068F25013CE5B2C409856322175984940471A26C8275F2C40C5FCAA5D5F984940C51D53AB3A652C400EF6DB36CA984940BD677FA8EB662C402A8EC7944B994940FE3745FBA1652C403A15727E75994940EC70BDA759662C40049D4091B3994940D9B8D3C021652C4084FB328E039A49404A655E36DC612C407AD64BEBE599494016FCCC6E76612C40FCBF27FDC09A4940DFE0073F1F662C409AB1F679A19A49408B40EE7761662C4046509CE5FA9A494045DCFDBAC3662C401E1AB289B99A494050C67FCFC0672C40CD51D44EF19A49400DF4365F9A672C408E06355A4C9B4940621964F2D26A2C4010B7E3A6CD9B49406298AE77816C2C4036D1FA2FD99B49402689705B9F6C2C405BD157C1A39B494002725F1BD16C2C40B43F48E5DB9B49408F4FD68E4D742C40506C993B1B9C494096566CBEF5732C40FA0D3D8D739B4940CF285BC030772C40D90C0229469B49400448799122772C40636DA1B4229B4940A410A75516792C4040310949379B49403B3F1A761E7A2C404E0B513FDD9A4940CC171663917C2C40DD807D61BF9A4940F2160E48A17B2C40F43AAB3A809A4940B5AA5D7653802C404978DEBF249B4940F3F7C080E3842C40F96FACC2949A49404E05E6DA7C882C4004B9DB40939A4940625324FBD0882C4027EDB0BE199B49409B3ED235CF862C407ECEE4E1429B494009B67B4FEB872C4051A4BDAAAE9B49403B80E86257872C406FF4156DFA9B49404081A45E048A2C403D6A8930E79B4940140348DF708A2C4020B8163D4C9C49409F4BA16825912C40178545FA119C494039A88E4898912C407E2396866D9C4940A8F13C2C16942C4049FE5862579C49400C37E482ED912C4030857EE9DE9C49403925621B9C922C4044700E0E079D4940F4CFC7CF578E2C40CE9D35740C9D4940F62AC03AC08D2C4060AFD8BB429D494008274540EF8B2C40BEAF9F1E4F9D49403B2A8023B78B2C401CAC0D7F699E49400624CEB049852C40D734A5B1A89E494017A3731A32832C402AED6AF14E9F494082D503F47A842C40F5F7B1207B9F4940B852EAB348842C402B76AB393BA04940F406D245DE862C4069A560B67AA049403F00981F99862C403068CC60ACA1494054B8E4141B852C40F148EF2A18A24940D7A2B161B0852C40A80E3BB03DA2494069DC1B25A9822C405236BE8F49A2494057CC8165B0822C4099C2BCCEA1A249407742ADF3A1822C409A6F281C09A34940E5674ED5C2852C40799FAB2B62A34940BACBA8CD88852C407BEE7A6BD7A349405245DFE015882C403974D7AF3BA4494099B6E46574882C402CDF67B699A54940C7BDC49657882C40F68F5AF66AA64940E6D4E402CD8A2C40C596E7A4F3A749409FF20C54EF8A2C406B7082A6C0A84940C3280276618A2C40BB1AB392F2A949409DD8CEEAA5862C406C8DE7AF5BAB4940A2B653188D862C400283F56C85AB4940DC86E7FD94902C40B81C440B2AAC4940251715532E982C40472BFCE7E4AC4940DB8D203627A02C409B2C899C03AD4940149C3F0A8E9E2C40563904A2D0AD494091F5744C08A82C40513FF6F854AE49403DB53D4ECAB12C40041B3C1D2BAE49407440CE0AA8B32C40D39117B174AD49404DBFF3703BB32C40763E87D490AC4940E9A23F3DE4B02C4072204D5F9EAB4940CF3B68A905B62C40FBF162016EAB49401B4DCDDCACB62C40F49165C4C3A94940FCD2F138B6B72C4020DFB98B79A9494054438EF8ABBB2C408417F6D823A94940BB866B0B99BC2C4036E98AD097A84940E82857D4B5C62C40A47A4EA56FA84940B25C3967C3C42C408C6978FA17A74940FA80F4B30FCC2C40018B0623E7A649408AB321E002CF2C4049E15F518CA74940F34715BA2DD12C400FB7FA49BFA74940934C775F33D42C40A8900680BBA749402F8AB07531D52C402BC80B5538A849408BACCF46E6D62C4065B6C9E74EA849408F0B57ACA1D52C40BCDD577693A84940E25DB99F46D52C4008D12DC476A949409B71A0C601D92C40A8033D1DFEA84940627ED1338ADA2C402A13B1180CA949401794820B0BDD2C40FA6413BAA7A94940A4955CDA9FE12C40A585893A2AAB4940F739B0C2E3E82C40393C21686DAB494089ADC4A333EA2C4074AE9FE4EEAB4940363277EA13ED2C40B530896A4EAC49400C7DBD38B1EF2C40DFED8F7145AC49401C1D4B3665F12C402AA5EB76EAAB4940A3356BB48BF12C409F8B1F796EAA494003FED9E72AF32C40A99847B020AA494065DA5CC6A6F32C4081F42199A6A949402C0A983090F22C40C4367212A8A94940654DAE4F1BF22C40D6FC0C8E6DA94940956C64BF32F42C40A6D39CCB10A94940996DF1B997F52C405431CF101CA94940611E12E6A2FD2C40182DE41FCBA94940E3067B6FBC012D40D979C157EBA94940EDA30D9F79012D407D5BFBAB5CA94940FCE9B6D268042D40AEE4A6C601A949406B6A2F27F4032D407E25647FBFA949402930B004B1032D4030ED86A1F9A94940B1D1DA0B18052D401561642A24AA4940C5969F8C1E0B2D4082B8042924AA4940EB388519DF092D409FF6E717C8AA4940A94B51631B0C2D40A64D402BEFAA4940A52DFF44A60A2D4006D502D42BAB49406BE9764A470C2D40550230746DAB4940D6D0EA32120B2D409695A48185AB4940881B585C960A2D40F92405D10CAC494080F7432A220C2D4042A1F3CF26AC494050CA4A799B0C2D4017BA870D79AC49400A324DE99F122D409A47F10A9FAC4940684BEE02B0142D405AE864DC87AD49402EE5231AE8162D405E8AF562BAAD4940B2A3723513152D40475FE9DDBCAC4940DB50F4A2F4102D401617EB498FAB49401B6C435DD8112D403D6DCE9674AB494029B0F54EE1122D4016F461E0A2AB49404B570559E4142D405B53B3AC38AB4940D960F2682E192D40078BAC54E8AA4940A3DE748EAC192D40E68D420327AA49403A8EADA1231C2D40DF9E515BFAA949407B426588C71B2D40C4FCF973D0A94940E0FBDF7DC61D2D40AAAA445FA3A949403149A89671212D406D716DE596A84940FBAA0357FA232D40504391BE98A84940545F7E89B6272D4022D12A4A8BA9494048FE71E1C0292D40B72E39774BA94940B9296E33D42D2D40DB5AB4D838A94940FE954F63EA2C2D40E3C9E192F1A84940A218BF028F302D400AB6D5DFE5A8494076BEF96F042D2D40374018B87FA84940E7EFADFB6D2C2D4030931C32FBA74940995BB91B6E322D40D66215ACE4A74940DCCEE9C836302D401EE42B9A45A74940483C776965362D404DA6B2EF59A749402030AF7280352D40CBC9C7F8A6A649400D2D0D476F322D40AF9A0BF5C6A54940546B61C63E332D40628E1386F1A44940DDBF243763382D40595E205E74A4494032E34A78B5392D40C0B01BEFC9A349406703E89DFB3E2D4059FB7190C0A3494089815BF6D93C2D40E3EF523A19A24940E8C340DAEF392D408835D2DF43A14940F67466C70C412D40E162B37512A149407F49A4C0D7452D40D0040575D69F4940B11D4A825C452D40DC5B2D57E79E4940EE6D1D55F9432D40550B954DF09E494050868C5AD3412D40BD146219A39E4940E2947AADB13D2D40D2EFB4FC499D4940E7B4ED14B0412D40CE9E2306319D4940C549DCCB14452D409352AEC8409C4940126D7F2A4E452D409035A6666A9C4940D106835BE0462D403EE4AE2A679C4940B017DA28A1472D401C1CBEF9EE9C49408F1E68FA714A2D406905F2F1769D4940F8488C2B514C2D402F6DC32B829D49404BE723775E4E2D400FCACBDBE39C49403E30510CCE4C2D40F99F1E9AAB9C4940F03B026CDE4B2D404363573EDE9B494078CC6CCCE94D2D4083589FA6E09B4940CF91CD779F4E2D40EFC11A17999B4940C200843948512D4098A65EBB6B9B49409013BDA7DE502D40AC4824FB459B49407D23E7D261542D4042F8B9A0F89A4940E3F64B7124582D40D052321EFE9A4940A936461E77582D40BA8872163D9B4940917AD648B9592D40900AA8CD2C9B49402EFAF4EA8C592D40C58CA011019B49400607A326C55E2D4032456931089B4940713668C4295D2D407D7179E8659A49409B59EEE4755D2D40A715B6A7B9994940A696EC7C345A2D4008607C736B994940E9E5C983865B2D408CB236C3F198494085446F9DD0562D406097014DA2984940F2609E61555A2D400395F47C829849402B51E411E45A2D408997C8A85498494028B56AE11A5C2D40040B2EBF7C984940A23D10669D5B2D406232B585619849407606FC96735E2D409D460D6524984940C4CA009C2D5C2D4054797E1317984940BA1BD0F84E5D2D404972B9C2ED97494053D8FAFFE7622D405F7E07BCBC974940CEA57AA59C652D40FD6F3ED4D6974940165F9FB107642D40D0071BEBA997494007224AC63F672D40444716273097494028E4100719672D40E9D1EC260897494027A4E74A33642D407AFAC32FE796494055FD984D12642D4085A66A99AE96494057C9455675602D40215CA79F3096494018D18A7FF8612D40A659C101D9954940DD66ADD4D8602D4055B6253DB6954940153C794C2B612D40B57C81314B9549405B513023BD5D2D40E95113C9849549403EAB1F87A45E2D40FA64A9A1579549402BFA63AC755C2D40131B87023F9549404C2794A88F5C2D40D305AB83DE94494007D6BA06F45A2D40BA99A1E0B9944940AEA535511A5B2D40500C1CCD7494494011F29589A45D2D40E2773FE841944940EB11393A685C2D40460D3C548A9349406F20FFDACC5D2D40F70A29B16A934940AFD5C3EBBD5D2D40F2D011C008934940B5238086245A2D40981590B50693494093BAD411E75A2D40B3A6627259934940FB1BD796E1592D409586F72658934940BB9C1BE09D592D40CBFD3DCA019349408E38CA3DF9572D40047AA41106934940DE08A07D8F582D407B48A2AC4F934940FA631984C0552D4004C213FB68934940C45895786A552D405F28503AD2934940752FBB22D7542D403B5972E6B3934940D27C68C545522D40B683D0B41994494022D9DA5993512D401F077A71EE93494075D58535F04F2D40D2738E5B1B944940DA8CF345BB4C2D401A155A68879349401A646E6BD94B2D40DF62BDD394934940D0D5A665894C2D40ACBB10AF6B9349400D16A2C8404B2D40783AC200D692494050BBD94C46492D4045D7A832D59249407579F77B52482D4029259EAA88924940765D3DC37D472D40B78559098D924940B90715DD62472D40C996C86BD7914940	Altkreis Bautzen
\.


--
-- Name: availability_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.availability_id_seq', 15, true);


--
-- Name: company_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.company_id_seq', 8, true);


--
-- Name: event_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.event_group_id_seq', 704, true);


--
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.event_id_seq', 704, true);


--
-- Name: journey_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.journey_id_seq', 1, false);


--
-- Name: request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.request_id_seq', 352, true);


--
-- Name: ride_share_rating_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_share_rating_id_seq', 1, false);


--
-- Name: ride_share_tour_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_share_tour_id_seq', 76, true);


--
-- Name: ride_share_vehicle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_share_vehicle_id_seq', 13, true);


--
-- Name: ride_share_zone_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_share_zone_id_seq', 1, true);


--
-- Name: tour_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tour_id_seq', 227, true);


--
-- Name: user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_id_seq', 12, true);


--
-- Name: vehicle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vehicle_id_seq', 16, true);


--
-- Name: zone_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.zone_id_seq', 6, true);


--
-- Name: availability availability_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability
    ADD CONSTRAINT availability_pkey PRIMARY KEY (id);


--
-- Name: company company_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company
    ADD CONSTRAINT company_pkey PRIMARY KEY (id);


--
-- Name: fcm_token device_company; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fcm_token
    ADD CONSTRAINT device_company UNIQUE (device_id, company);


--
-- Name: event_group event_group_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event_group
    ADD CONSTRAINT event_group_pkey PRIMARY KEY (id);


--
-- Name: event event_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_pkey PRIMARY KEY (id);


--
-- Name: journey journey_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey
    ADD CONSTRAINT journey_pkey PRIMARY KEY (id);


--
-- Name: kysely_migration_lock kysely_migration_lock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kysely_migration_lock
    ADD CONSTRAINT kysely_migration_lock_pkey PRIMARY KEY (id);


--
-- Name: kysely_migration kysely_migration_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kysely_migration
    ADD CONSTRAINT kysely_migration_pkey PRIMARY KEY (name);


--
-- Name: request request_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_pkey PRIMARY KEY (id);


--
-- Name: ride_share_rating ride_share_rating_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_rating
    ADD CONSTRAINT ride_share_rating_pkey PRIMARY KEY (id);


--
-- Name: ride_share_tour ride_share_tour_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_tour
    ADD CONSTRAINT ride_share_tour_pkey PRIMARY KEY (id);


--
-- Name: ride_share_vehicle ride_share_vehicle_license_plate; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_vehicle
    ADD CONSTRAINT ride_share_vehicle_license_plate UNIQUE (license_plate, owner);


--
-- Name: ride_share_vehicle ride_share_vehicle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_vehicle
    ADD CONSTRAINT ride_share_vehicle_pkey PRIMARY KEY (id);


--
-- Name: ride_share_zone ride_share_zone_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_zone
    ADD CONSTRAINT ride_share_zone_pkey PRIMARY KEY (id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- Name: tour tour_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tour
    ADD CONSTRAINT tour_pkey PRIMARY KEY (id);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: vehicle vehicle_license_plate_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle
    ADD CONSTRAINT vehicle_license_plate_key UNIQUE (license_plate);


--
-- Name: vehicle vehicle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle
    ADD CONSTRAINT vehicle_pkey PRIMARY KEY (id);


--
-- Name: zone zone_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zone
    ADD CONSTRAINT zone_pkey PRIMARY KEY (id);


--
-- Name: availability_vehicle_start_end_time_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX availability_vehicle_start_end_time_idx ON public.availability USING btree (vehicle, start_time, end_time);


--
-- Name: tour_vehicle_departure_arrival_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX tour_vehicle_departure_arrival_idx ON public.tour USING btree (vehicle, departure, arrival);


--
-- Name: zone_area_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX zone_area_idx ON public.zone USING gist (area);


--
-- Name: availability availability_vehicle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability
    ADD CONSTRAINT availability_vehicle_fkey FOREIGN KEY (vehicle) REFERENCES public.vehicle(id);


--
-- Name: company company_zone_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company
    ADD CONSTRAINT company_zone_fkey FOREIGN KEY (zone) REFERENCES public.zone(id);


--
-- Name: event event_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_group_id_fk FOREIGN KEY (event_group_id) REFERENCES public.event_group(id);


--
-- Name: event event_request_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_request_fkey FOREIGN KEY (request) REFERENCES public.request(id);


--
-- Name: journey journey_request1_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey
    ADD CONSTRAINT journey_request1_fkey FOREIGN KEY (request1) REFERENCES public.request(id);


--
-- Name: journey journey_request2_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey
    ADD CONSTRAINT journey_request2_fkey FOREIGN KEY (request2) REFERENCES public.request(id);


--
-- Name: journey journey_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey
    ADD CONSTRAINT journey_user_fkey FOREIGN KEY ("user") REFERENCES public."user"(id);


--
-- Name: request request_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_customer_fkey FOREIGN KEY (customer) REFERENCES public."user"(id);


--
-- Name: request request_ride_share_tour_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_ride_share_tour_fkey FOREIGN KEY (ride_share_tour) REFERENCES public.ride_share_tour(id);


--
-- Name: request request_tour_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_tour_fkey FOREIGN KEY (tour) REFERENCES public.tour(id);


--
-- Name: ride_share_rating ride_share_rating_request_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_rating
    ADD CONSTRAINT ride_share_rating_request_fkey FOREIGN KEY (request) REFERENCES public.request(id);


--
-- Name: ride_share_tour ride_share_tour_vehicle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_tour
    ADD CONSTRAINT ride_share_tour_vehicle_fkey FOREIGN KEY (vehicle) REFERENCES public.ride_share_vehicle(id);


--
-- Name: ride_share_vehicle ride_share_vehicle_owner_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_share_vehicle
    ADD CONSTRAINT ride_share_vehicle_owner_fkey FOREIGN KEY (owner) REFERENCES public."user"(id);


--
-- Name: session session_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: tour tour_vehicle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tour
    ADD CONSTRAINT tour_vehicle_fkey FOREIGN KEY (vehicle) REFERENCES public.vehicle(id);


--
-- Name: user user_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.company(id);


--
-- Name: vehicle vehicle_company_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle
    ADD CONSTRAINT vehicle_company_fkey FOREIGN KEY (company) REFERENCES public.company(id);


--
-- PostgreSQL database dump complete
--

\unrestrict NnSfHSVmjTbhQn7Kd3daxrbgChG97ht0SGTgRJJVcLkYeOEQQT5iUJoS4jCGwhz

