--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Debian 16.4-1.pgdg110+2)
-- Dumped by pg_dump version 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1)

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
	grp text
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
	ticket_price integer
);


ALTER TYPE public.request_type OWNER TO postgres;

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
-- Name: create_and_merge_tours(public.request_type, public.event_type, public.event_type, integer[], public.tour_type, jsonb, jsonb, public.direct_duration_type, public.direct_duration_type, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_and_merge_tours(p_request public.request_type, p_event1 public.event_type, p_event2 public.event_type, p_merge_tour_list integer[], p_tour public.tour_type, p_update_next_leg_durations jsonb, p_update_prev_leg_durations jsonb, p_update_direct_duration_dropoff public.direct_duration_type, p_update_direct_duration_pickup public.direct_duration_type, p_update_scheduled_times jsonb, p_prev_leg_updates jsonb, p_next_leg_updates jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
        DECLARE
            v_request_id INTEGER;
            v_tour_id INTEGER;
        BEGIN
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

            CALL update_prev_leg_duration(p_prev_leg_updates);
            CALL update_next_leg_duration(p_next_leg_updates);

            RETURN v_request_id;
        END;
        $$;


ALTER FUNCTION public.create_and_merge_tours(p_request public.request_type, p_event1 public.event_type, p_event2 public.event_type, p_merge_tour_list integer[], p_tour public.tour_type, p_update_next_leg_durations jsonb, p_update_prev_leg_durations jsonb, p_update_direct_duration_dropoff public.direct_duration_type, p_update_direct_duration_pickup public.direct_duration_type, p_update_scheduled_times jsonb, p_prev_leg_updates jsonb, p_next_leg_updates jsonb) OWNER TO postgres;

--
-- Name: insert_event(public.event_type, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_event(IN p_event public.event_type, IN p_request_id integer)
    LANGUAGE plpgsql
    AS $$
	BEGIN
		INSERT INTO event (
			is_pickup, lat, lng, scheduled_time_start, scheduled_time_end, communicated_time,
			address, request, prev_leg_duration, next_leg_duration, event_group, cancelled
		)
	VALUES (
		p_event.is_pickup, p_event.lat, p_event.lng, p_event.scheduled_time_start, p_event.scheduled_time_end,
		p_event.communicated_time, p_event.address,
		p_request_id, p_event.prev_leg_duration, p_event.next_leg_duration, p_event.grp, FALSE
	);
END;
$$;


ALTER PROCEDURE public.insert_event(IN p_event public.event_type, IN p_request_id integer) OWNER TO postgres;

--
-- Name: insert_request(public.request_type, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_request(IN p_request public.request_type, IN p_tour_id integer, OUT v_request_id integer)
    LANGUAGE plpgsql
    AS $$
			BEGIN
				INSERT INTO request (passengers, wheelchairs, bikes, luggage, customer, tour, ticket_code, ticket_checked, ticket_price, cancelled, kids_zero_to_two, kids_three_to_four, kids_five_to_six)
				VALUES (p_request.passengers, p_request.wheelchairs, p_request.bikes, p_request.luggage, p_request.customer, p_tour_id, md5(random()::text), FALSE, p_request.ticket_price, FALSE, p_request.kids_zero_to_two, p_request.kids_three_to_four, p_request.kids_five_to_six)
				RETURNING id INTO v_request_id;
			END;
			$$;


ALTER PROCEDURE public.insert_request(IN p_request public.request_type, IN p_tour_id integer, OUT v_request_id integer) OWNER TO postgres;

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
-- Name: update_next_leg_duration(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_next_leg_duration(IN p_next_leg_updates jsonb)
    LANGUAGE plpgsql
    AS $$
        DECLARE
            v_duration BIGINT;
            v_item jsonb;
            v_event_id INTEGER;
        BEGIN
            FOR v_item IN SELECT * FROM jsonb_array_elements(p_next_leg_updates)
            LOOP
                v_event_id := (v_item ->> 'event')::INTEGER;
                v_duration := (v_item ->> 'duration')::BIGINT;

                UPDATE event e
                SET next_leg_duration = v_duration
                WHERE e.id = v_event_id;
            END LOOP;
        END;
        $$;


ALTER PROCEDURE public.update_next_leg_duration(IN p_next_leg_updates jsonb) OWNER TO postgres;

--
-- Name: update_next_leg_durations(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_next_leg_durations(IN p_next_leg_durations jsonb)
    LANGUAGE plpgsql
    AS $$
	BEGIN
		IF jsonb_typeof(p_next_leg_durations) <> 'array' THEN
			RAISE EXCEPTION 'Input must be a JSON array';
		END IF;

		IF EXISTS (
			SELECT 1 
			FROM jsonb_array_elements(p_next_leg_durations) elem 
			WHERE NOT (
				elem ? 'id' 
				AND elem ? 'next_leg_duration' 
				AND jsonb_typeof(elem->'id') = 'number' 
				AND jsonb_typeof(elem->'next_leg_duration') = 'number'
			)
		) THEN
			RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "next_leg_duration" (integer)';
		END IF;

		UPDATE event e
		SET next_leg_duration = updates.next_leg_duration
		FROM (
			SELECT 
				(record->>'id')::INTEGER AS id, 
				(record->>'next_leg_duration')::INTEGER AS next_leg_duration
			FROM jsonb_array_elements(p_next_leg_durations) AS record
		) AS updates
		WHERE e.id = updates.id;
	END;
	$$;


ALTER PROCEDURE public.update_next_leg_durations(IN p_next_leg_durations jsonb) OWNER TO postgres;

--
-- Name: update_prev_leg_duration(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_prev_leg_duration(IN p_prev_leg_updates jsonb)
    LANGUAGE plpgsql
    AS $$
        DECLARE
            v_duration BIGINT;
            v_item jsonb;
            v_event_id INTEGER;
        BEGIN
            FOR v_item IN SELECT * FROM jsonb_array_elements(p_prev_leg_updates)
            LOOP
                v_event_id := (v_item ->> 'event')::INTEGER;
                v_duration := (v_item ->> 'duration')::BIGINT;

                UPDATE event e
                SET prev_leg_duration = v_duration
                WHERE e.id = v_event_id;
            END LOOP;
        END;
        $$;


ALTER PROCEDURE public.update_prev_leg_duration(IN p_prev_leg_updates jsonb) OWNER TO postgres;

--
-- Name: update_prev_leg_durations(jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_prev_leg_durations(IN p_prev_leg_durations jsonb)
    LANGUAGE plpgsql
    AS $$
		BEGIN
			IF jsonb_typeof(p_prev_leg_durations) <> 'array' THEN
				RAISE EXCEPTION 'Input must be a JSON array';
			END IF;

			IF EXISTS (
				SELECT 1 
				FROM jsonb_array_elements(p_prev_leg_durations) elem 
				WHERE NOT (
					elem ? 'id' 
					AND elem ? 'prev_leg_duration' 
					AND jsonb_typeof(elem->'id') = 'number' 
					AND jsonb_typeof(elem->'prev_leg_duration') = 'number'
				)
			) THEN
				RAISE EXCEPTION 'Each JSON object must contain "id" (integer) and "prev_leg_duration" (integer)';
			END IF;

			UPDATE event e
			SET prev_leg_duration = updates.prev_leg_duration
			FROM (
				SELECT 
					(record->>'id')::INTEGER AS id, 
					(record->>'prev_leg_duration')::INTEGER AS prev_leg_duration
				FROM jsonb_array_elements(p_prev_leg_durations) AS record
			) AS updates
			WHERE e.id = updates.id;
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
-- Name: booking_api_parameters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.booking_api_parameters (
    id integer NOT NULL,
    start_lat1 real,
    start_lng1 real,
    target_lat1 real,
    target_lng1 real,
    start_time1 bigint,
    target_time1 bigint,
    start_address1 character varying,
    target_address1 character varying,
    start_fixed1 boolean,
    start_lat2 real,
    start_lng2 real,
    target_lat2 real,
    target_lng2 real,
    start_time2 bigint,
    target_time2 bigint,
    start_address2 character varying,
    target_address2 character varying,
    start_fixed2 boolean,
    kids_zero_to_two integer,
    kids_three_to_four integer,
    kids_five_to_six integer,
    passengers integer,
    wheelchairs integer,
    bikes integer,
    luggage integer
);


ALTER TABLE public.booking_api_parameters OWNER TO postgres;

--
-- Name: booking_api_parameters_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.booking_api_parameters_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.booking_api_parameters_id_seq OWNER TO postgres;

--
-- Name: booking_api_parameters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.booking_api_parameters_id_seq OWNED BY public.booking_api_parameters.id;


--
-- Name: company; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company (
    id integer NOT NULL,
    lat real,
    lng real,
    name character varying,
    address character varying,
    zone integer
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
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    scheduled_time_start bigint NOT NULL,
    scheduled_time_end bigint NOT NULL,
    communicated_time bigint NOT NULL,
    prev_leg_duration integer NOT NULL,
    next_leg_duration integer NOT NULL,
    event_group character varying NOT NULL,
    request integer NOT NULL,
    address character varying NOT NULL,
    cancelled boolean NOT NULL
);


ALTER TABLE public.event OWNER TO postgres;

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
    comment character varying
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
    tour integer NOT NULL,
    customer integer NOT NULL,
    ticket_code character varying NOT NULL,
    ticket_checked boolean NOT NULL,
    cancelled boolean NOT NULL,
    ticket_price integer DEFAULT 0 NOT NULL
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
    company_id integer
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
-- Name: booking_api_parameters id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.booking_api_parameters ALTER COLUMN id SET DEFAULT nextval('public.booking_api_parameters_id_seq'::regclass);


--
-- Name: company id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company ALTER COLUMN id SET DEFAULT nextval('public.company_id_seq'::regclass);


--
-- Name: event id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.event ALTER COLUMN id SET DEFAULT nextval('public.event_id_seq'::regclass);


--
-- Name: journey id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.journey ALTER COLUMN id SET DEFAULT nextval('public.journey_id_seq'::regclass);


--
-- Name: request id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request ALTER COLUMN id SET DEFAULT nextval('public.request_id_seq'::regclass);


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
1	1750467600000	1750543200000	1
2	1750208400000	1750284000000	1
3	1750074690431	1750111200000	1
4	1750122000000	1750197600000	1
5	1750554000000	1750629600000	1
6	1750294800000	1750370400000	1
7	1750381200000	1750456800000	1
8	1750640400000	1750716000000	1
9	1750813200000	1750888800000	1
10	1750726800000	1750802400000	1
11	1750899600000	1750975200000	1
12	1750986000000	1751061600000	1
13	1751072400000	1751148000000	1
14	1751158800000	1751234400000	1
15	1751245200000	1751284290431	1
16	1750122000000	1750197600000	2
17	1750208400000	1750284000000	2
18	1750640400000	1750716000000	2
19	1750294800000	1750370400000	2
20	1750726800000	1750802400000	2
21	1750554000000	1750629600000	2
22	1750381200000	1750456800000	2
23	1750467600000	1750543200000	2
24	1750813200000	1750888800000	2
25	1750074690515	1750111200000	2
26	1750899600000	1750975200000	2
27	1750986000000	1751061600000	2
28	1751072400000	1751148000000	2
29	1751158800000	1751234400000	2
30	1751245200000	1751284290515	2
31	1750122000000	1750197600000	1
32	1750381200000	1750456800000	1
33	1750208400000	1750284000000	1
34	1750079218375	1750111200000	1
35	1750554000000	1750629600000	1
36	1750640400000	1750716000000	1
37	1750294800000	1750370400000	1
38	1750467600000	1750543200000	1
39	1750813200000	1750888800000	1
40	1750726800000	1750802400000	1
41	1750899600000	1750975200000	1
42	1750986000000	1751061600000	1
43	1751072400000	1751148000000	1
44	1751158800000	1751234400000	1
45	1751245200000	1751288818375	1
46	1750122000000	1750197600000	2
47	1750079218467	1750111200000	2
48	1750208400000	1750284000000	2
50	1750381200000	1750456800000	2
51	1750554000000	1750629600000	2
49	1750294800000	1750370400000	2
52	1750467600000	1750543200000	2
53	1750640400000	1750716000000	2
54	1750726800000	1750802400000	2
55	1750813200000	1750888800000	2
56	1750899600000	1750975200000	2
57	1750986000000	1751061600000	2
58	1751072400000	1751148000000	2
59	1751158800000	1751234400000	2
60	1751245200000	1751288818467	2
61	1750208400000	1750284000000	1
62	1750294800000	1750370400000	1
63	1750554000000	1750629600000	1
64	1750467600000	1750543200000	1
65	1750079313757	1750111200000	1
66	1750640400000	1750716000000	1
67	1750122000000	1750197600000	1
68	1750381200000	1750456800000	1
69	1750726800000	1750802400000	1
70	1750813200000	1750888800000	1
71	1750899600000	1750975200000	1
72	1750986000000	1751061600000	1
73	1751072400000	1751148000000	1
74	1751158800000	1751234400000	1
75	1751245200000	1751288913757	1
76	1750294800000	1750370400000	2
78	1750079313848	1750111200000	2
79	1750208400000	1750284000000	2
77	1750381200000	1750456800000	2
80	1750467600000	1750543200000	2
82	1750726800000	1750802400000	2
83	1750813200000	1750888800000	2
84	1750122000000	1750197600000	2
81	1750640400000	1750716000000	2
85	1750554000000	1750629600000	2
86	1750899600000	1750975200000	2
87	1750986000000	1751061600000	2
88	1751072400000	1751148000000	2
89	1751158800000	1751234400000	2
90	1751245200000	1751288913848	2
\.


--
-- Data for Name: booking_api_parameters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.booking_api_parameters (id, start_lat1, start_lng1, target_lat1, target_lng1, start_time1, target_time1, start_address1, target_address1, start_fixed1, start_lat2, start_lng2, target_lat2, target_lng2, start_time2, target_time2, start_address2, target_address2, start_fixed2, kids_zero_to_two, kids_three_to_four, kids_five_to_six, passengers, wheelchairs, bikes, luggage) FROM stdin;
1	51.536407	51.536407	51.54014	14.681131	1751135617346	1751138269750	Jahnring 5b	Seeweg 27	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
2	51.53388	51.53388	51.54135	14.716318	1750269875077	1750272227632	Dorfstraße 105a	Am Jungfernberg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
3	51.54269	51.54269	51.472366	14.838825	1751138036608	1751141236551	Hoyerswerdaer Straße 37	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
4	51.543312	51.543312	51.44024	14.672051	1750645097709	1750648394055	Hoyerswerdaer Straße 33	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
5	51.440315	51.440315	51.5394	14.53161	1750131852877	1750134837733	WSG 4km	Strugaaue 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
6	51.53053	51.53053	51.33553	14.5008745	1750174686019	1750177241895	Rohner Weg 10	Eichenallee 25a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
7	51.543312	51.543312	51.48843	14.672327	1750594541463	1750597473752	Hoyerswerdaer Straße 33	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
8	51.531925	51.531925	51.344646	14.476376	1750506551922	1750508907942	Dorfstraße 80	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
9	51.53388	51.53388	51.518127	14.558777	1750409103255	1750411369900	Dorfstraße 105a	Hinterberg	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
10	51.509792	51.509792	51.543312	14.530944	1750937775379	1750939138572	WSG 4km	Hoyerswerdaer Straße 33	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
11	51.53411	51.53411	51.375786	14.685719	1750137583710	1750138633544	Schleifer Straße 3	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
12	51.540573	51.540573	51.42358	14.60762	1750131240357	1750132800153	Thälmann-Siedlung 25	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
13	51.336967	51.336967	51.527706	14.524263	1751006902848	1751009969440	Kirchweg 218	Trebendorfer Weg 116b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
14	51.39858	51.39858	51.541874	14.537528	1750092589681	1750093975353	WSG 4km	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
15	51.39071	51.39071	51.535065	14.528915	1750180311067	1750183133814	WSG 4km	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
16	51.510017	51.510017	51.53536	14.535053	1750607730396	1750610871981	WSG 4km	Werksweg 12	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
17	51.541874	51.541874	51.509045	14.661913	1750244228686	1750246850850	Friedensstraße 77a	Waldhausstraße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
18	51.539474	51.539474	51.541817	14.606253	1751248489616	1751251038582	Hoyerswerdaer Straße 94	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
19	51.532295	51.532295	51.524803	14.5751095	1750824503444	1750826899607	Reinert Ranch	Grüne Aue 11	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
20	51.404945	51.404945	51.53531	14.528985	1750484382262	1750485452154	WSG 4km	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
21	51.535732	51.535732	51.41212	14.554286	1751113757660	1751116212441	Jahnring 13	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
22	51.536358	51.536358	51.438488	14.564571	1750918358211	1750921284917	Friedensstraße 1	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
23	51.46723	51.46723	51.534004	14.521774	1750431502383	1750434303526	WSG 4km	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
24	51.490414	51.490414	51.53053	14.532026	1750499615225	1750501387086	Stele und Baggerschaufel	Rohner Weg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
25	51.35797	51.35797	51.53429	14.533877	1750346874593	1750350076919	WSG 4km	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
26	51.586163	51.586163	51.539997	14.516031	1750843243376	1750845667305	WSG 4km	Hoyerswerdaer Straße 90	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
27	51.407185	51.407185	51.54356	14.529777	1750515149810	1750517610487	Eichenweg 125	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
28	51.534313	51.534313	51.50632	14.735871	1751227428713	1751230136675	Forstweg 78a	Krauschwitzer Straße 24	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
29	51.365387	51.365387	51.534203	14.521786	1751170228687	1751172363934	Hauptstraße 24	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
30	51.529552	51.529552	51.442173	14.516115	1750328657396	1750330901580	Tischlereiweg 115a	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
31	51.527905	51.527905	51.455574	14.858544	1751028497565	1751031624172	Trebendorfer Weg 81	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
32	51.55175	51.55175	51.54356	14.529777	1750673849996	1750676947565	WSG 4km	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
33	51.541637	51.541637	51.514427	14.64662	1751251057231	1751254430614	Lindenweg 20	Grube-Hermann-Straße 9	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
34	51.532295	51.532295	51.436066	14.636085	1750330612980	1750332121129	Reinert Ranch	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
35	51.533173	51.533173	51.375103	14.5100155	1751215852793	1751218402214	Mühlroser Straße 8a	Hundestrand (dog's beach)	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
36	51.536026	51.536026	51.38086	14.660007	1750449069949	1750449994696	Friedensstraße 1	Mittelweg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
37	51.385597	51.385597	51.541725	14.534854	1750426940784	1750430024020	WSG 4km	Gemeindeamt	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
38	51.531242	51.531242	51.460003	14.499989	1750644302506	1750646689725	Mühlweg 5b	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
39	51.530224	51.530224	51.553997	14.5812235	1750691624503	1750693239681	Tischlereiweg 113b	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
40	51.535473	51.535473	51.540085	14.512858	1750697925023	1750698957356	Werksweg 10	Hoyerswerdaer Straße 98	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
41	51.445526	51.445526	51.540573	14.520827	1750421122240	1750423207131	WSG 4km	Thälmann-Siedlung 25	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
42	51.499226	51.499226	51.531254	14.516953	1750935181342	1750936834399	Grüner Weg 6	Dorfstraße 103	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
43	51.519352	51.519352	51.53429	14.533877	1750390496806	1750392690192	WSG 4km	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
44	51.439137	51.439137	51.53411	14.53515	1750665556958	1750667468691	07	Schleifer Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
45	51.484013	51.484013	51.529236	14.521395	1750783158962	1750786062537	WSG 4km	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
46	51.45327	51.45327	51.534004	14.521774	1751162494004	1751164671277	WSG 4km	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
47	51.33486	51.33486	51.536026	14.528657	1750337709366	1750340393845	Östlicher Bahnteich	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
48	51.534447	51.534447	51.42596	14.599368	1750361103911	1750363146897	Mulkwitzer Weg 10	Parkstraße 64	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
49	51.51481	51.51481	51.540085	14.512858	1751109337079	1751110725125	Neustädter Straße 64	Hoyerswerdaer Straße 98	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
50	51.534428	51.534428	51.535065	14.528915	1751042242237	1751044246652	Mühlroser Straße 3	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
51	51.54356	51.54356	51.490944	14.718349	1751088236193	1751090168165	Alter Postweg 11	Zum Floßgraben 19	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
52	51.534534	51.534534	51.472736	14.853577	1750990403539	1750993292131	Neustädter Straße 7	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
53	51.524796	51.524796	51.533836	14.536425	1750933761657	1750936591299	Buchenweg 2	Schleifer Straße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
54	51.378563	51.378563	51.534428	14.529578	1750602445790	1750604434765	WSG 4km	Mühlroser Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
55	51.545673	51.545673	51.500736	14.774182	1750781673193	1750782638054	Spremberger Straße 17	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
56	51.529552	51.529552	51.540005	14.669153	1750221643779	1750222761607	Tischlereiweg 115a	Dorfstraße 56a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
57	51.52923	51.52923	51.417736	14.64951	1750604251863	1750605739423	Rohner Weg 3a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
58	51.52028	51.52028	51.531242	14.511581	1750817675708	1750819044137	WSG 4km	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
59	51.41297	51.41297	51.529625	14.523734	1750679817965	1750680893696	WSG 4km	Tischlereiweg 115a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
60	51.501587	51.501587	51.534534	14.523995	1750877409691	1750879949362	Kaupener Straße 11	Neustädter Straße 7	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
61	51.553696	51.553696	51.545673	14.534669	1750499835183	1750500906555	WSG 4km	Spremberger Straße 17	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
62	51.539795	51.539795	51.482243	14.744741	1750147065839	1750149126234	Strugaaue 37	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
63	51.539474	51.539474	51.499107	14.642865	1750444980236	1750447284825	Hoyerswerdaer Straße 94	Lutherstraße 31	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
64	51.53388	51.53388	51.46837	14.502518	1750535226934	1750536679798	Dorfstraße 105a	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
65	51.534756	51.534756	51.354176	14.50377	1750262295541	1750263671561	Tiefbau-Service-Berton	Gasverteiler	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
66	51.40209	51.40209	51.541637	14.528906	1750446073016	1750448623517	Hammerstraße 50 D	Lindenweg 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
67	51.53841	51.53841	51.432285	14.938639	1750257518422	1750258813934	Jahnring 21	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
68	51.540573	51.540573	51.4584	14.739746	1750332844980	1750335166394	Thälmann-Siedlung 25	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
69	51.541348	51.541348	51.534428	14.529578	1750471241712	1750473051801	WSG 4km	Mühlroser Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
70	51.544353	51.544353	51.35063	14.629985	1750658779058	1750661482487	Friedensstraße 62	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
71	51.34939	51.34939	51.529236	14.521395	1750093581638	1750095683607	Straße der Jugend 57	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
72	51.430683	51.430683	51.527905	14.522943	1750946736110	1750948923622	WSG 4km	Trebendorfer Weg 81	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
73	51.54269	51.54269	51.36874	14.502143	1750864505478	1750867071691	Hoyerswerdaer Straße 37	Müllerteich 1	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
74	51.46723	51.46723	51.54356	14.529777	1750592526270	1750594926795	WSG 4km	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
75	51.51629	51.51629	51.536026	14.528657	1750696757667	1750699251956	Muskauer Straße 4	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
76	51.541874	51.541874	51.452023	14.499507	1750590964871	1750593079040	Friedensstraße 77a	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
77	51.536026	51.536026	51.30785	14.628223	1751012324518	1751013782310	Friedensstraße 1	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
78	51.53875	51.53875	51.53388	14.520264	1750191695051	1750193244371	Station 6	Dorfstraße 105a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
79	51.495735	51.495735	51.53429	14.533877	1750147925451	1750151094363	Am Braunsteich 2a	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
80	51.541786	51.541786	51.365067	14.65528	1750695824824	1750698140030	Hoyerswerdaer Straße 50	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
81	51.412342	51.412342	51.5394	14.53161	1750922052647	1750924480174	WSG 4km	Strugaaue 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
82	51.423008	51.423008	51.54002	14.524071	1750278820312	1750281174436	WSG 4km	Thälmann-Siedlung 8	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
83	51.54356	51.54356	51.38796	14.586662	1750342418618	1750345474833	Alter Postweg 11	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
84	51.361183	51.361183	51.532936	14.519677	1750255175813	1750258163225	WSG 4km	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
85	51.500443	51.500443	51.53053	14.532026	1750660198042	1750661109555	Tagebau Nochten Busbahnhof	Rohner Weg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
86	51.455578	51.455578	51.541874	14.537528	1751042269201	1751043518606	WSG 4km	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
87	51.399433	51.399433	51.531254	14.516953	1751140389342	1751143787170	WSG 4km	Dorfstraße 103	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
88	51.53841	51.53841	51.45649	14.880252	1750672629650	1750675404164	Jahnring 21	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
89	51.37575	51.37575	51.54002	14.524071	1750310487095	1750312261725	A6	Thälmann-Siedlung 8	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
90	51.50228	51.50228	51.530224	14.525203	1750166199218	1750167956343	Karl-Liebknecht-Straße 8	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
91	51.4729	51.4729	51.529236	14.521395	1750137301068	1750138793294	Heideweg 6a	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
92	51.338028	51.338028	51.528664	14.536682	1750269607720	1750272248502	Eichenallee 6a	Rohner Weg 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
93	51.538887	51.538887	51.499527	14.666523	1750184831146	1750185847723	Zum Sportplatz 5	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
94	51.53388	51.53388	51.332333	14.488661	1750410166756	1750413401129	Dorfstraße 105a	Feldteich	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
95	51.54356	51.54356	51.344612	14.472863	1750407002253	1750410514484	Alter Postweg 11	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
96	51.536026	51.536026	51.45652	14.504509	1750853205619	1750854683715	Friedensstraße 1	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
97	51.534756	51.534756	51.404327	14.658179	1750573056646	1750576116803	Tiefbau-Service-Berton	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
98	51.534203	51.534203	51.375153	14.600626	1751092795062	1751094096471	Dorfstraße 106a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
99	51.457367	51.457367	51.541637	14.528906	1750095366724	1750098931295	WSG 4km	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
100	51.541874	51.541874	51.46443	14.729286	1751126147275	1751127391792	Friedensstraße 77a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
101	51.53973	51.53973	51.45941	14.612236	1750259161531	1750260442847	NORMA	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
102	51.534004	51.534004	51.511204	14.511303	1751106283469	1751107399221	Dorfstraße 106a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
103	51.53841	51.53841	51.489616	14.506559	1750990883492	1750992695518	Jahnring 21	Dorfstraße 41	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
104	51.491554	51.491554	51.538887	14.518962	1751087230633	1751089820061	Zum Floßgraben 10D	Zum Sportplatz 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
105	51.36421	51.36421	51.539474	14.515927	1751194524640	1751198022558	WSG 4km	Hoyerswerdaer Straße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
106	51.340828	51.340828	51.545673	14.534669	1750597291630	1750599844273	WSG 4km	Spremberger Straße 17	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
107	51.485615	51.485615	51.541725	14.534854	1751102227007	1751104520588	WSG 4km	Gemeindeamt	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
108	51.541637	51.541637	51.42596	14.599368	1750763501323	1750767009726	Lindenweg 20	Parkstraße 64	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
109	51.532936	51.532936	51.476707	14.9136505	1750242605907	1750244575813	Dorfstraße 106	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
110	51.43502	51.43502	51.530224	14.525203	1750937532562	1750938574999	WSG 4km	Tischlereiweg 113b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
111	51.524925	51.524925	51.54356	14.529777	1750263186764	1750266717573	Buchenweg 45	Alter Postweg 11	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
112	51.534203	51.534203	51.52366	14.668089	1750695302942	1750696492368	Dorfstraße 106a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
113	51.531925	51.531925	51.3591	14.653446	1750499849648	1750502321387	Dorfstraße 80	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
114	51.541786	51.541786	51.35797	14.4826765	1750316812431	1750319813226	Hoyerswerdaer Straße 50	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
115	51.529236	51.529236	51.426483	14.613249	1750096549902	1750098995981	Gefallenendenkmale Rohne	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
116	51.53016	51.53016	51.467533	14.775203	1751093881444	1751095985963	Tischlereiweg 113b	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
117	51.534313	51.534313	51.458916	14.783337	1750762203266	1750765185902	Forstweg 78a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
118	51.52923	51.52923	51.54045	14.608036	1750142381059	1750145664056	Rohner Weg 3a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
119	51.530006	51.530006	51.534313	14.513616	1750520046634	1750522505567	WSG 4km	Forstweg 78a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
120	51.52923	51.52923	51.37077	14.5764065	1750227551061	1750229339487	Rohner Weg 3a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
121	51.531254	51.531254	51.52826	14.639348	1750616886142	1750618371733	Dorfstraße 103	Fichte 4	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
122	51.42465	51.42465	51.534313	14.513616	1750125072780	1750128580987	Ltg MN und MP Boxberg - Bärwalde	Forstweg 78a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
123	51.423035	51.423035	51.532936	14.519677	1750528332234	1750530810425	WSG 4km	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
124	51.535065	51.535065	51.38339	14.623073	1751201027573	1751202529385	Siedlung - Sydlišćo	Rietschener Straße 34	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
125	51.530224	51.530224	51.50411	14.61364	1751121755546	1751123865085	Tischlereiweg 113b	Vorwerkstraße 40	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
126	51.53536	51.53536	51.568535	14.569539	1750770691238	1750774090781	Werksweg 12	Dorfstraße 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
127	51.53861	51.53861	51.557182	14.551211	1750263051398	1750265336815	Hoyerswerdaer Straße 91	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
128	51.5394	51.5394	51.410057	14.629069	1750689038666	1750692337418	Strugaaue 2	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
129	51.540573	51.540573	51.51184	14.671644	1750855411952	1750856890860	Thälmann-Siedlung 25	Weißwasser-Waldhaus	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
130	51.49555	51.49555	51.541786	14.524831	1750333229519	1750334182483	Straße des Fortschritts 25B	Hoyerswerdaer Straße 50	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
131	51.483135	51.483135	51.529552	14.524057	1751029604184	1751032818774	Fichtenweg 1	Tischlereiweg 115a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
132	51.53325	51.53325	51.538002	14.603175	1751219659420	1751221201827	Mühlweg 5b	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
133	51.49607	51.49607	51.54269	14.530803	1750471099279	1750474499587	Wiesenweg 5	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
134	51.53841	51.53841	51.508617	14.768811	1751132225052	1751135542596	Jahnring 21	Am Sportplatz 50	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
135	51.541786	51.541786	51.499977	14.651861	1751252188086	1751253827165	Hoyerswerdaer Straße 50	Rothenburger Straße 41	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
136	51.326027	51.326027	51.535732	14.519293	1750731004730	1750733804014	Heuhotel Ferienhof Erlengrund	Jahnring 13	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
137	51.543312	51.543312	51.45001	14.671395	1750581045582	1750583348517	Hoyerswerdaer Straße 33	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
138	51.4709	51.4709	51.541874	14.537528	1751253061415	1751255153498	Dorfstraße 19	Friedensstraße 77a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
139	51.529625	51.529625	51.316944	14.589471	1750569192569	1750570367864	Tischlereiweg 115a	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
140	51.350483	51.350483	51.540573	14.520827	1750348495605	1750351145531	Gartenweg 361	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
141	51.455578	51.455578	51.53325	14.514113	1750755712661	1750757577668	WSG 4km	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
142	51.534203	51.534203	51.51629	14.719355	1750191675447	1750193087124	Dorfstraße 106a	Muskauer Straße 4	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
143	51.539474	51.539474	51.364998	14.576466	1750566819097	1750568019000	Hoyerswerdaer Straße 94	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
144	51.5394	51.5394	51.347305	14.65752	1750780179549	1750783185968	Strugaaue 2	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
145	51.530624	51.530624	51.543312	14.530944	1750125092988	1750127856292	Erlenbruch 11	Hoyerswerdaer Straße 33	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
146	51.351295	51.351295	51.543312	14.530944	1750142070914	1750143687532	WSG 4km	Hoyerswerdaer Straße 33	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
147	51.530224	51.530224	51.471382	14.776319	1751134626539	1751136623705	Tischlereiweg 113b	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
148	51.360092	51.360092	51.534313	14.513616	1751167729612	1751168920373	WSG 4km	Forstweg 78a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
149	51.37244	51.37244	51.529625	14.523734	1750785112571	1750787817229	WSG 4km	Tischlereiweg 115a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
150	51.488773	51.488773	51.536407	14.524572	1750486994963	1750490107700	WSG 4km	Jahnring 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
151	51.532936	51.532936	51.527443	14.726684	1750603324681	1750604446117	Dorfstraße 106	Muskauer Straße 155	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
152	51.555695	51.555695	51.539795	14.538614	1750925758136	1750926674866	Wohnpark Am Wasserturm 1	Strugaaue 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
153	51.51958	51.51958	51.539795	14.538614	1750485668639	1750488630346	Wilhelmstraße 12	Strugaaue 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
154	51.345158	51.345158	51.54269	14.530803	1750159803426	1750163292850	WSG 4km	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
155	51.54002	51.54002	51.397987	14.621625	1750394628433	1750398172342	Thälmann-Siedlung 8	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
156	51.5446	51.5446	51.55097	14.536926	1750823933379	1750826167297	Schleife - Slepo	Neu-Mühlrose - Nowy Miłoraz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
157	51.535065	51.535065	51.42243	14.57093	1750645967510	1750648504857	Siedlung - Sydlišćo	Boxberg Block P	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
158	51.43599	51.43599	51.534447	14.526812	1751265929020	1751268909520	Herzlich willkommen im Lausitzer Seenland Witajće do tužiskeje jězoriny	Mulkwitzer Weg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
159	51.536358	51.536358	51.533237	14.604314	1750654937078	1750656730400	Friedensstraße 1	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
160	51.540928	51.540928	51.539474	14.515927	1750536725045	1750539982215	WSG 4km	Hoyerswerdaer Straße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
161	51.563477	51.563477	51.54269	14.530803	1750997714848	1751001255376	Lieskauer Weg 7	Hoyerswerdaer Straße 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
162	51.53325	51.53325	51.38847	14.543599	1750126286738	1750127632979	Mühlweg 5b	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
163	51.521366	51.521366	51.53016	14.524709	1750768680990	1750771792138	Unterdorf 98	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
164	51.329243	51.329243	51.539474	14.515927	1750263312931	1750264512454	Grenzstein 79 KS	Hoyerswerdaer Straße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
165	51.54269	51.54269	51.43791	14.939541	1750613814318	1750615466432	Hoyerswerdaer Straße 37	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
166	51.534428	51.534428	51.50678	14.67079	1750432207388	1750434884303	Mühlroser Straße 3	Waldhaus	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
167	51.5394	51.5394	51.36627	14.580802	1751012886800	1751016273765	Strugaaue 2	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
168	51.528763	51.528763	51.42237	14.663784	1750837242374	1750839032753	Trebendorfer Weg 116c	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
169	51.52923	51.52923	51.303318	14.605337	1750333224742	1750334264989	Rohner Weg 3a	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
170	51.561848	51.561848	51.531254	14.516953	1750796407355	1750799936881	Berliner Chaussee 98b	Dorfstraße 103	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
171	51.383957	51.383957	51.539795	14.538614	1750498823068	1750502115281	WSG 4km	Strugaaue 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
172	51.440674	51.440674	51.544353	14.540508	1750223131444	1750224754893	WSG 4km	Friedensstraße 62	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
173	51.535908	51.535908	51.53325	14.514113	1750179436697	1750181229283	WSG 4km	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
174	51.4674	51.4674	51.528664	14.536682	1750613694696	1750615791745	WSG 4km	Rohner Weg 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
175	51.531254	51.531254	51.460667	14.938535	1750675073044	1750676614117	Dorfstraße 103	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
176	51.53536	51.53536	51.52905	14.627068	1750996943658	1750997870637	Werksweg 12	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
177	51.43599	51.43599	51.534428	14.529578	1750250680038	1750252722757	Herzlich willkommen im Lausitzer Seenland Witajće do tužiskeje jězoriny	Mühlroser Straße 3	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
178	51.541637	51.541637	51.515476	14.611478	1750871999055	1750873724408	Lindenweg 20	Auensiedlung 4	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
179	51.53325	51.53325	51.391407	14.5651045	1750949014805	1750951953304	Mühlweg 5b	WSG 4km	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
180	51.527706	51.527706	51.375202	14.686608	1750566851342	1750568797627	Trebendorfer Weg 116b	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
181	51.527706	51.527706	51.50037	14.83414	1750690153972	1750692170614	Trebendorfer Weg 116b	WSG 4km	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
182	51.449276	51.449276	51.535732	14.519293	1750100806835	1750101994842	WSG 4km	Jahnring 13	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
\.


--
-- Data for Name: company; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.company (id, lat, lng, name, address, zone) FROM stdin;
1	51.493713	14.625855	Taxi Weißwasser	Werner-Seelenbinder-Straße 70A, 02943 Weißwasser/Oberlausitz	2
2	51.532974	14.660599	Taxi Gablenz	Schulstraße 21, 02953 Gablenz	2
3	51.38096	14.666578	Taxi Reichwalde	Robert-Koch-Straße 45, 02943 Boxberg/Oberlausitz	1
4	51.30576	14.782109	Taxi Moholz	Postweg 10, 02906 Niesky	1
5	51.302185	14.834551	Taxi Niesky	Trebuser Str. 4, 02906 Niesky	1
6	51.321884	14.944467	Taxi Rothenburg	Zur Wasserscheide 37, 02929 Rothenburg/Oberlausitz	1
7	51.166775	14.934901	Taxi Schöpstal	Ebersbacher Str. 43, 02829 Schöpstal	3
8	51.129536	14.941331	Taxi Görlitz	Plantagenweg 3, 02827 Görlitz	3
\.


--
-- Data for Name: event; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.event (id, is_pickup, lat, lng, scheduled_time_start, scheduled_time_end, communicated_time, prev_leg_duration, next_leg_duration, event_group, request, address, cancelled) FROM stdin;
1	t	51.5364085	14.524572	1751136502750	1751137102750	1751136502750	955000	1167000		1	Jahnring 5b	t
2	f	51.5401365	14.681131	1751138269750	1751138869750	1751138869750	1167000	773000		1	Seeweg 27	t
3	t	51.5338793	14.5202632	1750269275077	1750269875077	1750269275077	953000	1525000		2	Dorfstraße 105a	t
4	f	51.5413524	14.7163178	1750271400077	1750272000077	1750272000077	1525000	1028000		2	Am Jungfernberg 10	t
17	t	51.5338793	14.5202632	1750408503255	1750409103255	1750408503255	953000	813000		9	Dorfstraße 105a	t
18	f	51.5181275	14.558777	1750409916255	1750410516255	1750410516255	813000	1002000		9	Hinterberg	t
13	t	51.5433114	14.5309437	1750593941463	1750594541463	1750593941463	992000	1331000		7	Hoyerswerdaer Straße 33	t
14	f	51.4884283	14.6723274	1750595872463	1750596472463	1750596472463	1331000	446000		7	WSG 4km	t
9	t	51.4403134	14.5638603	1750131252877	1750131852877	1750131252877	2710000	3080000		5	WSG 4km	t
10	f	51.5393992	14.5316092	1750134932877	1750135532877	1750135532877	3080000	998000		5	Strugaaue 2	t
15	t	51.5319259	14.52021	1750505786942	1750506386942	1750505786942	1016000	2521000		8	Dorfstraße 80	t
16	f	51.3446469	14.4763756	1750508907942	1750509507942	1750509507942	2521000	2500000		8	WSG 4km	t
7	t	51.5433114	14.5309437	1750644497709	1750645097709	1750644497709	992000	1492000		4	Hoyerswerdaer Straße 33	t
8	f	51.4402384	14.6720513	1750646589709	1750647189709	1750647189709	1492000	538000		4	WSG 4km	t
23	t	51.5405733	14.520827	1750130841153	1750131441153	1750130841153	1062000	1359000		12	Thälmann-Siedlung 25	t
24	f	51.423582	14.60762	1750132800153	1750133400153	1750133400153	1359000	802000		12	WSG 4km	t
19	t	51.5097936	14.5894485	1750937175379	1750937775379	1750937175379	427000	641000		10	WSG 4km	t
20	f	51.5433114	14.5309437	1750938416379	1750939016379	1750939016379	641000	1052000		10	Hoyerswerdaer Straße 33	t
11	t	51.5305303	14.5320261	1750174759895	1750175359895	1750174759895	886000	1882000		6	Rohner Weg 10	t
12	f	51.3355277	14.5008743	1750177241895	1750177841895	1750177841895	1882000	1781000		6	Eichenallee 25a	t
27	t	51.3985791	14.5041561	1750092084353	1750092684353	1750092084353	1157000	1291000		14	WSG 4km	t
28	f	51.5418744	14.537528	1750093975353	1750094575353	1750094575353	1291000	1004000		14	Friedensstraße 77a	t
25	t	51.3369678	14.5876444	1751007514440	1751008114440	1751007514440	1672000	1855000		13	Kirchweg 218	t
26	f	51.5277052	14.5242631	1751009969440	1751010569440	1751010569440	1855000	1024000		13	Trebendorfer Weg 116b	t
5	t	51.5426918	14.5308026	1751137436608	1751138036608	1751137436608	1031000	2218000		3	Hoyerswerdaer Straße 37	t
6	f	51.4723673	14.8388251	1751140254608	1751140854608	1751140854608	2218000	1345000		3	WSG 4km	t
21	t	51.5341111	14.5351491	1750135918544	1750136518544	1750135918544	860000	2115000		11	Schleifer Straße 3	t
22	f	51.3757859	14.6857186	1750138633544	1750139233544	1750139233544	2115000	1986000		11	WSG 4km	t
33	t	51.5418744	14.537528	1750245141850	1750245741850	1750245141850	944000	1109000		17	Friedensstraße 77a	t
34	f	51.5090442	14.6619131	1750246850850	1750247450850	1750247450850	1109000	485000		17	Waldhausstraße 94	t
29	t	51.3907087	14.5003564	1750179711067	1750180311067	1750179711067	1190000	1288000		15	WSG 4km	t
30	f	51.5350649	14.5289157	1750181599067	1750182199067	1750182199067	1288000	1005000		15	Siedlung - Sydlišćo	t
37	t	51.5322939	14.5345323	1750823903444	1750824503444	1750823903444	980000	565000		19	Reinert Ranch	t
38	f	51.5248035	14.5751099	1750825068444	1750825668444	1750825668444	565000	712000		19	Grüne Aue 11	t
39	t	51.4049451	14.6374585	1750482983154	1750483583154	1750482983154	1054000	1869000		20	WSG 4km	t
40	f	51.5353088	14.5289849	1750485452154	1750486052154	1750486052154	1869000	998000		20	Siedlung - Sydlišćo	t
41	t	51.5357337	14.5192924	1751114601441	1751115201441	1751114601441	981000	1011000		21	Jahnring 13	t
42	f	51.4121191	14.5542856	1751116212441	1751116812441	1751116812441	1011000	1037000		21	WSG 4km	t
35	t	51.5394742	14.5159274	1751249653582	1751250253582	1751249653582	1056000	785000		18	Hoyerswerdaer Straße 94	t
36	f	51.5418167	14.6062523	1751251038582	1751251638582	1751251638582	785000	1052000		18	WSG 4km	t
45	t	51.4672323	14.9315979	1750431331526	1750431931526	1750431331526	1513000	2372000		23	WSG 4km	t
46	f	51.5340052	14.5217744	1750434303526	1750434903526	1750434903526	2372000	1007000		23	Dorfstraße 106a	t
47	t	51.4904154	14.627253	1750499015225	1750499615225	1750499015225	80000	988000		24	Stele und Baggerschaufel	t
48	f	51.5305303	14.5320261	1750500603225	1750501203225	1750501203225	988000	946000		24	Rohner Weg 10	t
53	t	51.4071828	14.5896058	1750515308487	1750515908487	1750515308487	1323000	1702000		27	Eichenweg 125	t
54	f	51.5435594	14.5297765	1750517610487	1750518210487	1750518210487	1702000	1090000		27	Alter Postweg 11	t
63	t	51.5517516	14.6340534	1750675442565	1750676042565	1750675442565	984000	905000		32	WSG 4km	t
64	f	51.5435594	14.5297765	1750676947565	1750677547565	1750677547565	905000	1090000		32	Alter Postweg 11	t
51	t	51.5861607	14.7205212	1750842643376	1750843243376	1750842643376	1971000	2552000		26	WSG 4km	t
52	f	51.5399955	14.5160315	1750845795376	1750846395376	1750846395376	2552000	1111000		26	Hoyerswerdaer Straße 90	t
67	t	51.5322939	14.5345323	1750330012980	1750330612980	1750330012980	980000	2684000		34	Reinert Ranch	t
68	f	51.4360659	14.636085	1750333296980	1750333896980	1750333896980	2684000	2151000		34	WSG 4km	t
31	t	51.5100161	14.8003036	1750608457981	1750609057981	1750608457981	981000	1814000		16	WSG 4km	t
32	f	51.535357	14.5350536	1750610871981	1750611471981	1750611471981	1814000	981000		16	Werksweg 12	t
69	t	51.533173	14.529221	1751215252793	1751215852793	1751215252793	948000	2215000		35	Mühlroser Straße 8a	t
70	f	51.3751032	14.5100156	1751218067793	1751218667793	1751218667793	2215000	2174000		35	Hundestrand (dog's beach)	t
61	t	51.5279047	14.5229428	1751027897565	1751028497565	1751027897565	951000	2381000		31	Trebendorfer Weg 81	t
62	f	51.4555724	14.858544	1751030878565	1751031478565	1751031478565	2381000	1578000		31	WSG 4km	t
65	t	51.5416387	14.5289058	1751252653614	1751253253614	1751252653614	975000	1177000		33	Lindenweg 20	t
59	t	51.5295517	14.5240575	1750329390580	1750329990580	1750329390580	1083000	911000		30	Tischlereiweg 115a	t
60	f	51.4421732	14.5161153	1750330901580	1750331501580	1750331501580	911000	908000		30	WSG 4km	t
66	f	51.5144253	14.6466197	1751254430614	1751255030614	1751255030614	1177000	639000		33	Grube-Hermann-Straße 9	t
49	t	51.3579704	14.4826766	1750347467919	1750348067919	1750347467919	1899000	2009000		25	WSG 4km	t
50	f	51.5342917	14.5338773	1750350076919	1750350676919	1750350676919	2009000	931000		25	Schleifer Straße 2	t
57	t	51.3653879	14.5016774	1751170320934	1751170920934	1751170320934	1408000	1443000		29	Hauptstraße 24	t
58	f	51.5342031	14.5217853	1751172363934	1751172963934	1751172963934	1443000	1006000		29	Dorfstraße 106a	t
43	t	51.536356	14.5290886	1750917758211	1750918358211	1750917758211	916000	2952000		22	Friedensstraße 1	t
44	f	51.4384864	14.564571	1750921310211	1750921814866	1750921910211	2952000	3315000		22	WSG 4km	t
55	t	51.5343123	14.5136158	1751226828713	1751227428713	1751226828713	1117000	1632000		28	Forstweg 78a	t
56	f	51.5063194	14.7358714	1751229060713	1751229660713	1751229660713	1632000	663000		28	Krauschwitzer Straße 24	t
73	t	51.385598	14.4795199	1750427992020	1750428592020	1750427992020	1303000	1432000		37	WSG 4km	f
71	t	51.5360245	14.5286573	1750448469949	1750449069949	1750448469949	920000	1754000		36	Friedensstraße 1	t
72	f	51.3808593	14.6600076	1750450823949	1750451423949	1750451423949	1754000	1587000		36	Mittelweg 10	t
90	f	51.5292355	14.5213952	1750786062537	1750786662537	1750786662537	983000	1076000		45	Gefallenendenkmale Rohne	f
100	f	51.5350649	14.5289157	1751044246652	1751044846652	1751044846652	89000	1005000		50	Siedlung - Sydlišćo	f
101	t	51.5435594	14.5297765	1751087990165	1751088590165	1751087990165	1030000	1578000		51	Alter Postweg 11	f
102	f	51.4909425	14.7183496	1751090168165	1751090768165	1751090768165	1578000	706000		51	Zum Floßgraben 19	f
103	t	51.5345327	14.5239956	1750989803539	1750990403539	1750989803539	938000	2142000		52	Neustädter Straße 7	f
104	f	51.4727379	14.8535762	1750992545539	1750993145539	1750993145539	2142000	1352000		52	WSG 4km	f
123	t	51.5397943	14.5386138	1750146165234	1750146765234	1750146165234	976000	2361000		62	Strugaaue 37	f
124	f	51.4822417	14.7447419	1750149126234	1750149726234	1750149726234	2361000	1543000		62	WSG 4km	f
131	t	51.4020863	14.5661985	1750445473016	1750446073016	1750445473016	1037000	1316000		66	Hammerstraße 50 D	t
132	f	51.5416387	14.5289058	1750447389016	1750447989016	1750447989016	1316000	1035000		66	Lindenweg 20	t
107	t	51.3785639	14.6131511	1750602119765	1750602719765	1750602119765	1556000	1715000		54	WSG 4km	f
91	t	51.4532681	14.6801653	1751161894004	1751162494004	1751161894004	394000	1363000		46	WSG 4km	t
92	f	51.5340052	14.5217744	1751163857004	1751164457004	1751164457004	1363000	1007000		46	Dorfstraße 106a	t
77	t	51.5302251	14.5252029	1750692068681	1750692668681	1750692068681	1112000	571000		39	Tischlereiweg 113b	t
113	t	51.5292289	14.5391334	1750604558766	1750604682766	1750604558766	248000	1714000		57	Rohner Weg 3a	f
114	f	51.4177357	14.6495106	1750606396766	1750606996766	1750606996766	1714000	921000		57	WSG 4km	f
78	f	51.5539972	14.5812236	1750693239681	1750693839681	1750693839681	571000	927000		39	WSG 4km	t
108	f	51.5344271	14.5295784	1750604434765	1750604434766	1750605034765	1715000	248000		54	Mühlroser Straße 3	f
115	t	51.5202791	14.5877114	1750817366137	1750817966137	1750817366137	1066000	1078000		58	WSG 4km	t
116	f	51.5312432	14.5115818	1750819044137	1750819644137	1750819644137	1078000	1082000		58	Mühlweg 5b	t
94	f	51.5360245	14.5286573	1750340071366	1750340671366	1750340671366	2362000	980000		47	Friedensstraße 1	t
135	t	51.5405733	14.520827	1750332244980	1750332844980	1750332244980	908000	1945000		68	Thälmann-Siedlung 25	t
136	f	51.4584016	14.7397464	1750334789980	1750335389980	1750335389980	1945000	2454000		68	WSG 4km	t
93	t	51.33486	14.6405355	1750337243980	1750337709366	1750337109366	2454000	2362000		47	Östlicher Bahnteich	t
85	t	51.5193517	14.4847529	1750391219192	1750391819192	1750391219192	1682000	871000		43	WSG 4km	t
81	t	51.4455256	14.8741445	1750420173131	1750420773131	1750420173131	3144000	2434000		41	WSG 4km	t
121	t	51.5536938	14.6448058	1750499235183	1750499835183	1750499235183	963000	854000		61	WSG 4km	t
109	t	51.5456749	14.5346691	1750779822536	1750780422536	1750779822536	948000	1806000		55	Spremberger Straße 17	t
110	f	51.5007357	14.7741827	1750782228536	1750782828536	1750782828536	1806000	1016000		55	WSG 4km	t
95	t	51.5344465	14.5268116	1750361290897	1750361890897	1750361290897	937000	1256000		48	Mulkwitzer Weg 10	t
96	f	51.4259589	14.5993683	1750363146897	1750363746897	1750363746897	1256000	843000		48	Parkstraße 64	t
129	t	51.5347542	14.5339465	1750261695541	1750262295541	1750261695541	877000	1710000		65	Tiefbau-Service-Berton	t
130	f	51.3541739	14.5037703	1750264005541	1750264605541	1750264605541	1710000	1654000		65	Gasverteiler	t
125	t	51.5394742	14.5159274	1750444380236	1750444980236	1750444380236	1056000	1262000		63	Hoyerswerdaer Straße 94	t
126	f	51.4991058	14.6428654	1750446242236	1750446842236	1750446842236	1262000	370000		63	Lutherstraße 31	t
117	t	51.4129717	14.6402782	1750679217965	1750679817965	1750679217965	1061000	2075000		59	WSG 4km	t
118	f	51.5296246	14.5237337	1750681892965	1750682492965	1750682492965	2075000	1132000		59	Tischlereiweg 115a	t
127	t	51.5338793	14.5202632	1750535461798	1750536061798	1750535461798	68000	618000		64	Dorfstraße 105a	f
89	t	51.4840125	14.5072644	1750784479537	1750785079537	1750784479537	2304000	983000		45	WSG 4km	f
111	t	51.5295517	14.5240575	1750221043779	1750221643779	1750221043779	1083000	1222000		56	Tischlereiweg 115a	t
112	f	51.5400033	14.6691529	1750222865779	1750223465779	1750223465779	1222000	701000		56	Dorfstraße 56a	t
75	t	51.5312432	14.5115818	1750643702506	1750644302506	1750643702506	1022000	624000		38	Mühlweg 5b	t
76	f	51.460002	14.4999889	1750644926506	1750645526506	1750645526506	624000	1394000		38	WSG 4km	t
74	f	51.5417264	14.5348536	1750430024020	1750430624020	1750430624020	1432000	185000		37	Gemeindeamt	f
134	f	51.4322843	14.9386389	1750258813934	1750259076454	1750259413934	2657000	3308000		67	WSG 4km	f
86	f	51.5342917	14.5338773	1750392690192	1750393290192	1750393290192	871000	931000		43	Schleifer Straße 2	t
119	t	51.5015882	14.7252495	1750876809691	1750877409691	1750876809691	584000	1434000		60	Kaupener Straße 11	t
120	f	51.5345327	14.5239956	1750878843691	1750879443691	1750879443691	1434000	998000		60	Neustädter Straße 7	t
80	f	51.5400866	14.5128586	1750698314023	1750698914023	1750698914023	389000	2822000		40	Hoyerswerdaer Straße 98	t
79	t	51.5354713	14.5457966	1750697325023	1750697925023	1750697325023	314000	389000		40	Werksweg 10	t
139	t	51.5443525	14.5405083	1750658179058	1750658779058	1750658179058	468000	1827000		70	Friedensstraße 62	f
98	f	51.5400866	14.5128586	1751110725125	1751111325125	1751111325125	480000	1146000		49	Hoyerswerdaer Straße 98	t
97	t	51.5148072	14.5031761	1751109645125	1751110245125	1751109645125	191000	480000		49	Neustädter Straße 64	t
137	t	51.5413485	14.6522713	1750471210801	1750471810801	1750471210801	940000	1241000		69	WSG 4km	t
138	f	51.5344271	14.5295784	1750473051801	1750473651801	1750473651801	1241000	994000		69	Mühlroser Straße 3	t
105	t	51.5247947	14.6908681	1750933161657	1750933761657	1750933161657	585000	863000		53	Buchenweg 2	t
106	f	51.5338373	14.5364242	1750937378341	1750937470341	1750937470341	1657000	184000		53	Schleifer Straße 5	t
88	f	51.5341111	14.5351491	1750667468691	1750668068691	1750668068691	1650000	920000		44	Schleifer Straße 3	t
128	f	51.4683672	14.5025175	1750536679798	1750537174000	1750537279798	618000	1450000		64	WSG 4km	f
87	t	51.4391381	14.6042397	1750665218691	1750665818691	1750665218691	1295000	1650000		44	07	t
133	t	51.538412	14.5250691	1750255556934	1750256156934	1750255556934	131000	2657000		67	Jahnring 21	f
143	t	51.4306816	14.6460468	1750946919622	1750947519622	1750946919622	609000	1404000		72	WSG 4km	f
150	f	51.5360245	14.5286573	1750698250667	1750698850667	1750698850667	1493000	980000		75	Friedensstraße 1	f
82	f	51.5405733	14.520827	1750423207131	1750423807131	1750423807131	2434000	1122000		41	Thälmann-Siedlung 25	t
122	f	51.5456749	14.5346691	1750500689183	1750501289183	1750501289183	854000	1008000		61	Spremberger Straße 17	t
155	t	51.5387499	14.5784948	1750191095051	1750191695051	1750191095051	929000	635000		78	Station 6	f
156	f	51.5338793	14.5202632	1750192330051	1750192930051	1750192930051	635000	1013000		78	Dorfstraße 105a	f
157	t	51.4957339	14.6858783	1750149318363	1750149918363	1750149318363	393000	1176000		79	Am Braunsteich 2a	t
158	f	51.5342917	14.5338773	1750151094363	1750151694363	1750151694363	1176000	931000		79	Schleifer Straße 2	t
165	t	51.5435594	14.5297765	1750342933833	1750343533833	1750342933833	1030000	1941000		83	Alter Postweg 11	f
161	t	51.4123407	14.6289028	1750921452647	1750922052647	1750921452647	1057000	1980000		81	WSG 4km	t
162	f	51.5393992	14.5316092	1750924032647	1750924632647	1750924632647	1980000	998000		81	Strugaaue 2	t
167	t	51.3611837	14.6438373	1750255247225	1750255847225	1750255247225	2221000	2316000		84	WSG 4km	f
171	t	51.4555784	14.5985841	1751040266606	1751040866606	1751040266606	2156000	2652000		86	WSG 4km	f
172	f	51.5418744	14.537528	1751043518606	1751043838129	1751043838129	2652000	147000		86	Friedensstraße 77a	f
99	t	51.5344271	14.5295784	1751043838129	1751044157652	1751043557652	147000	89000		50	Mühlroser Straße 3	f
173	t	51.3994332	14.5985556	1751142004170	1751142604170	1751142004170	1105000	1183000		87	WSG 4km	f
174	f	51.5312531	14.516953	1751143787170	1751144387170	1751144387170	1183000	1033000		87	Dorfstraße 103	f
175	t	51.538412	14.5250691	1750672486164	1750673086164	1750672486164	965000	2318000		88	Jahnring 21	f
176	f	51.4564898	14.8802523	1750675404164	1750676004164	1750676004164	2318000	1501000		88	WSG 4km	f
177	t	51.3757525	14.5332024	1750309047725	1750309647725	1750309047725	2403000	2614000		89	A6	f
179	t	51.5022794	14.6323187	1750166217343	1750166817343	1750166217343	232000	1139000		90	Karl-Liebknecht-Straße 8	f
180	f	51.5302251	14.5252029	1750167956343	1750168556343	1750168556343	1139000	1172000		90	Tischlereiweg 113b	f
169	t	51.5004407	14.508437	1750659598042	1750660198042	1750659598042	1347000	587000		85	Tagebau Nochten Busbahnhof	t
170	f	51.5305303	14.5320261	1750660785042	1750661385042	1750661385042	587000	946000		85	Rohner Weg 10	t
181	t	51.4729001	14.709348	1750136383294	1750136983294	1750136383294	882000	1810000		91	Heideweg 6a	f
166	f	51.3879586	14.5866627	1750345474833	1750346074833	1750346074833	1941000	1745000		83	WSG 4km	f
183	t	51.3380296	14.4993256	1750269638502	1750270238502	1750269638502	1713000	2010000		92	Eichenallee 6a	f
184	f	51.5286634	14.5366817	1750272248502	1750272848502	1750272848502	2010000	1034000		92	Rohner Weg 6	f
191	t	51.5360245	14.5286573	1750852605619	1750853205619	1750852605619	920000	776000		96	Friedensstraße 1	f
159	t	51.5417871	14.524831	1750695224824	1750695824824	1750695224824	1017000	314000		80	Hoyerswerdaer Straße 50	t
160	f	51.3650649	14.6552798	1750712400000	1750713000000	1750713000000	2822000	2599000		80	WSG 4km	t
195	t	51.5342031	14.5217853	1751092195062	1751092795062	1751092195062	946000	1966000		98	Dorfstraße 106a	f
196	f	51.3751527	14.6006261	1751094761062	1751095361062	1751095361062	1966000	1922000		98	WSG 4km	f
199	t	51.5418744	14.537528	1751125547275	1751126147275	1751125547275	944000	2107000		100	Friedensstraße 77a	f
200	f	51.464432	14.7292862	1751128254275	1751128854275	1751128854275	2107000	1321000		100	WSG 4km	f
147	t	51.4672323	14.9315979	1750591881795	1750592481795	1750591881795	1513000	2445000		74	WSG 4km	t
201	t	51.5397309	14.5335292	1750258662378	1750259161531	1750258662378	181000	2847000		101	NORMA	f
202	f	51.4594134	14.6122363	1750262008531	1750262608531	1750262608531	2847000	2401000		101	WSG 4km	f
168	f	51.5329343	14.5196775	1750258163225	1750258662378	1750258763225	2316000	181000		84	Dorfstraße 106	f
148	f	51.5435594	14.5297765	1750594926795	1750595526795	1750595526795	2445000	1090000		74	Alter Postweg 11	t
205	t	51.538412	14.5250691	1750990283492	1750990883492	1750990283492	965000	970000		103	Jahnring 21	f
206	f	51.4896166	14.5065593	1750991853492	1750992453492	1750992453492	970000	1825000		103	Dorfstraße 41	f
197	t	51.4573667	14.7969306	1750096260295	1750096860295	1750096260295	1184000	2071000		99	WSG 4km	t
198	f	51.5416387	14.5289058	1750098931295	1750099531295	1750099531295	2071000	1035000		99	Lindenweg 20	t
207	t	51.4915553	14.7143354	1751086630633	1751087230633	1751086630633	670000	1612000		104	Zum Floßgraben 10D	f
203	t	51.5340052	14.5217744	1751105683469	1751106283469	1751105683469	198000	348000		102	Dorfstraße 106a	f
178	f	51.5400192	14.5240712	1750312261725	1750312861725	1750312861725	2614000	97000		89	Thälmann-Siedlung 8	f
208	f	51.5388861	14.5189616	1751088842633	1751089442633	1751089442633	1612000	345000		104	Zum Sportplatz 5	f
182	f	51.5292355	14.5213952	1750138793294	1750139393294	1750139393294	1810000	278000		91	Gefallenendenkmale Rohne	f
189	t	51.5435594	14.5297765	1750407215484	1750407815484	1750407215484	1030000	2699000		95	Alter Postweg 11	t
190	f	51.3446115	14.4728635	1750410514484	1750411114484	1750411114484	2699000	2572000		95	WSG 4km	t
163	t	51.4230079	14.6414855	1750278220312	1750278820312	1750278220312	646000	1529000		82	WSG 4km	t
204	f	51.511205	14.5113027	1751106631469	1751107231469	1751107231469	348000	1294000		102	WSG 4km	f
145	t	51.5426918	14.5308026	1750864633691	1750865233691	1750864633691	1031000	1838000		73	Hoyerswerdaer Straße 37	t
146	f	51.3687383	14.5021425	1750867071691	1750867671691	1750867671691	1838000	1710000		73	Müllerteich 1	t
192	f	51.4565214	14.5045092	1750853981619	1750854581619	1750854581619	776000	808000		96	WSG 4km	f
141	t	51.3493881	14.6026773	1750093448607	1750094048607	1750093448607	1486000	1635000		71	Straße der Jugend 57	t
185	t	51.5388861	14.5189616	1750183689723	1750184289723	1750183689723	1026000	1558000		93	Zum Sportplatz 5	t
187	t	51.5338793	14.5202632	1750410932129	1750411532129	1750410932129	953000	1869000		94	Dorfstraße 105a	t
151	t	51.5418744	14.537528	1750591687040	1750592287040	1750591687040	944000	792000		76	Friedensstraße 77a	t
194	f	51.4043272	14.658179	1750576116803	1750576716803	1750576716803	2437000	1725000		97	WSG 4km	t
193	t	51.5347542	14.5339465	1750573079803	1750573679803	1750573079803	2117000	2437000		97	Tiefbau-Service-Berton	t
186	f	51.4995282	14.6665234	1750185847723	1750186447723	1750186447723	1558000	804000		93	WSG 4km	t
140	f	51.3506321	14.6299847	1750660606058	1750661206058	1750661206058	1827000	1681000		70	WSG 4km	f
188	f	51.332332	14.4886606	1750413401129	1750414001129	1750414001129	1869000	1898000		94	Feldteich	t
149	t	51.5162888	14.719355	1750696157667	1750696757667	1750696157667	2073000	1493000		75	Muskauer Straße 4	f
144	f	51.5279047	14.5229428	1750948923622	1750948923623	1750949523622	1404000	243000		72	Trebendorfer Weg 81	f
209	t	51.364207	14.6390924	1751195212558	1751195812558	1751195212558	1960000	2210000		105	WSG 4km	t
210	f	51.5394742	14.5159274	1751198022558	1751198622558	1751198622558	2210000	1110000		105	Hoyerswerdaer Straße 94	t
213	t	51.4856166	14.6618971	1751101627007	1751102227007	1751101627007	265000	1204000		107	WSG 4km	f
214	f	51.5417264	14.5348536	1751103431007	1751104031007	1751104031007	1204000	198000		107	Gemeindeamt	f
215	t	51.5416387	14.5289058	1750762901323	1750763501323	1750762901323	975000	1308000		108	Lindenweg 20	f
216	f	51.4259589	14.5993683	1750764809323	1750765409323	1750765409323	1308000	843000		108	Parkstraße 64	f
219	t	51.4350193	14.5317591	1750936932562	1750937532562	1750936932562	1169000	1013000		110	WSG 4km	f
220	f	51.5302251	14.5252029	1750938545562	1750939145562	1750939145562	1013000	1172000		110	Tischlereiweg 113b	f
223	t	51.5342031	14.5217853	1750694702942	1750695302942	1750694702942	946000	1142000		112	Dorfstraße 106a	f
224	f	51.5236589	14.6680893	1750696444942	1750697044942	1750697044942	1142000	519000		112	WSG 4km	f
225	t	51.5319259	14.52021	1750499249648	1750499849648	1750499249648	1016000	2698000		113	Dorfstraße 80	f
226	f	51.3590998	14.6534461	1750502547648	1750503147648	1750503147648	2698000	2608000		113	WSG 4km	f
227	t	51.5417871	14.524831	1750316212431	1750316812431	1750316212431	97000	2069000		114	Hoyerswerdaer Straße 50	f
228	f	51.3579704	14.4826766	1750318881431	1750319481431	1750319481431	2069000	1959000		114	WSG 4km	f
231	t	51.5301599	14.5247083	1751092866963	1751093466963	1751092866963	345000	2519000		116	Tischlereiweg 113b	f
232	f	51.4675314	14.7752031	1751095985963	1751096585963	1751096585963	2519000	1574000		116	WSG 4km	f
234	f	51.4589164	14.7833362	1750764359266	1750764959266	1750764959266	2156000	1187000		117	WSG 4km	f
221	t	51.5249249	14.696017	1750262586764	1750263186764	1750262586764	626000	1326000		111	Buchenweg 45	t
222	f	51.5435594	14.5297765	1750264512764	1750265112764	1750265112764	1326000	1090000		111	Alter Postweg 11	t
235	t	51.5292289	14.5391334	1750141781059	1750142381059	1750141781059	278000	630000		118	Rohner Weg 3a	f
236	f	51.5404513	14.6080357	1750143011059	1750143611059	1750143611059	630000	727000		118	WSG 4km	f
164	f	51.5400192	14.5240712	1750280349312	1750280949312	1750280949312	1529000	1118000		82	Thälmann-Siedlung 8	t
242	f	51.5282586	14.6393476	1750618371733	1750618971733	1750618971733	1048000	811000		121	Fichte 4	f
243	t	51.4246473	14.5455887	1750125000000	1750125600000	1750125000000	1067000	976000		122	Ltg MN und MP Boxberg - Bärwalde	f
245	t	51.4230357	14.5264746	1750529234425	1750529834425	1750529234425	1163000	976000		123	WSG 4km	f
246	f	51.5329343	14.5196775	1750530810425	1750531410425	1750531410425	976000	68000		123	Dorfstraße 106	f
249	t	51.5302251	14.5252029	1751121155546	1751121755546	1751121155546	1112000	972000		125	Tischlereiweg 113b	f
250	f	51.5041089	14.6136402	1751122727546	1751123327546	1751123327546	972000	306000		125	Vorwerkstraße 40	f
251	t	51.535357	14.5350536	1750770091238	1750770691238	1750770091238	921000	618000		126	Werksweg 12	f
252	f	51.5685353	14.5695395	1750771309238	1750771909238	1750771909238	618000	1100000		126	Dorfstraße 20	f
217	t	51.5329343	14.5196775	1750241631813	1750242231813	1750241631813	958000	2344000		109	Dorfstraße 106	t
218	f	51.4767088	14.9136507	1750244575813	1750245175813	1750245175813	2344000	1534000		109	WSG 4km	t
254	f	51.5571805	14.5512115	1750265336815	1750265936815	1750265936815	511000	1206000		127	WSG 4km	f
255	t	51.5393992	14.5316092	1750688438666	1750689038666	1750688438666	938000	1961000		128	Strugaaue 2	f
256	f	51.4100565	14.6290698	1750690999666	1750691599666	1750691599666	1961000	1150000		128	WSG 4km	f
83	t	51.499227	14.7416324	1750934624657	1750935181342	1750934581342	896000	1781000		42	Grüner Weg 6	t
84	f	51.5312531	14.516953	1750937562341	1750937562342	1750937562342	1781000	1033000		42	Dorfstraße 103	t
257	t	51.5405733	14.520827	1750854811952	1750855411952	1750854811952	808000	1373000		129	Thälmann-Siedlung 25	f
258	f	51.5118404	14.6716441	1750856784952	1750857384952	1750857384952	1373000	603000		129	Weißwasser-Waldhaus	f
247	t	51.5350649	14.5289157	1751200427573	1751201027573	1751200427573	945000	1473000		124	Siedlung - Sydlišćo	t
248	f	51.3833882	14.6230725	1751202500573	1751203100573	1751203100573	1473000	1366000		124	Rietschener Straße 34	t
259	t	51.4955492	14.7091329	1750332629519	1750333229519	1750332629519	591000	1524000		130	Straße des Fortschritts 25B	f
260	f	51.5417871	14.524831	1750334753519	1750335353519	1750335353519	1524000	1077000		130	Hoyerswerdaer Straße 50	f
263	t	51.5332486	14.5141138	1751219969827	1751220569827	1751219969827	1038000	632000		132	Mühlweg 5b	f
264	f	51.5380033	14.6031756	1751221201827	1751221801827	1751221801827	632000	696000		132	WSG 4km	f
233	t	51.5343123	14.5136158	1750761603266	1750762203266	1750761603266	278000	2156000		117	Forstweg 78a	f
142	f	51.5292355	14.5213952	1750095683607	1750096283607	1750096283607	1635000	0		71	Gefallenendenkmale Rohne	t
269	t	51.5417871	14.524831	1751251588086	1751252188086	1751251588086	1017000	1301000		135	Hoyerswerdaer Straße 50	f
270	f	51.4999762	14.6518614	1751253489086	1751254089086	1751254089086	1301000	550000		135	Rothenburger Straße 41	f
271	t	51.3260267	14.6311949	1750731004014	1750731604014	1750731004014	2058000	2200000		136	Heuhotel Ferienhof Erlengrund	f
272	f	51.5357337	14.5192924	1750733804014	1750734404014	1750734404014	2200000	1041000		136	Jahnring 13	f
273	t	51.5433114	14.5309437	1750580445582	1750581045582	1750580445582	992000	2720000		137	Hoyerswerdaer Straße 33	f
274	f	51.4500094	14.6713956	1750583765582	1750584365582	1750584365582	2720000	1789000		137	WSG 4km	f
229	t	51.5292355	14.5213952	1750097117981	1750097717981	1750097117981	0	1278000		115	Gefallenendenkmale Rohne	t
230	f	51.4264839	14.6132488	1750098995981	1750099595981	1750099595981	1278000	790000		115	WSG 4km	t
237	t	51.5300072	14.4892926	1750519446634	1750520046634	1750519446634	1204000	334000		119	WSG 4km	t
238	f	51.5343123	14.5136158	1750520380634	1750520980634	1750520980634	334000	1177000		119	Forstweg 78a	t
267	t	51.538412	14.5250691	1751133215596	1751133815596	1751133215596	965000	1727000		134	Jahnring 21	t
268	f	51.5086191	14.768811	1751135542596	1751136142596	1751136142596	1727000	912000		134	Am Sportplatz 50	t
241	t	51.5312531	14.516953	1750616723733	1750617323733	1750616723733	360000	1048000		121	Dorfstraße 103	f
265	t	51.4960707	14.7190451	1750470600000	1750471200000	1750470600000	593000	1530000		133	Wiesenweg 5	t
244	f	51.5343123	14.5136158	1750126576000	1750126576001	1750127176000	976000	278000		122	Forstweg 78a	f
253	t	51.5386074	14.5148166	1750264669135	1750264825815	1750264225815	78000	511000		127	Hoyerswerdaer Straße 91	f
239	t	51.5292289	14.5391334	1750226951061	1750227551061	1750226951061	3369000	305000		120	Rohner Weg 3a	f
266	f	51.5426918	14.5308026	1750472730000	1750473330000	1750473330000	1530000	1091000		133	Hoyerswerdaer Straße 37	t
261	t	51.4831347	14.7196442	1751029004184	1751029604184	1751029004184	752000	1747000		131	Fichtenweg 1	t
262	f	51.5295517	14.5240575	1751031351184	1751031951184	1751031951184	1747000	1143000		131	Tischlereiweg 115a	t
275	t	51.4709032	14.7148166	1751252461415	1751253061415	1751252461415	957000	1803000		138	Dorfstraße 19	f
276	f	51.5418744	14.537528	1751254864415	1751255464415	1751255464415	1803000	1004000		138	Friedensstraße 77a	f
212	f	51.5456749	14.5346691	1750599685630	1750600285630	1750600285630	2394000	1008000		106	Spremberger Straße 17	t
152	f	51.4520215	14.4995069	1750593079040	1750593679040	1750593679040	792000	1676000		76	WSG 4km	t
211	t	51.3408297	14.4794545	1750596691630	1750597291630	1750596691630	2204000	2394000		106	WSG 4km	t
281	t	51.4555784	14.5985841	1750755112661	1750755712661	1750755112661	2156000	2556000		141	WSG 4km	f
282	f	51.5332486	14.5141138	1750758268661	1750758868661	1750758868661	2556000	278000		141	Mühlweg 5b	f
283	t	51.5342031	14.5217853	1750190964124	1750191564124	1750190964124	946000	1523000		142	Dorfstraße 106a	f
284	f	51.5162888	14.719355	1750193087124	1750193687124	1750193687124	1523000	721000		142	Muskauer Straße 4	f
285	t	51.5394742	14.5159274	1750565364000	1750565964000	1750565364000	1056000	2055000		143	Hoyerswerdaer Straße 94	f
286	f	51.3649972	14.5764653	1750568019000	1750568619000	1750568619000	2055000	1868000		143	WSG 4km	f
287	t	51.5393992	14.5316092	1750779579549	1750780179549	1750779579549	938000	1875000		144	Strugaaue 2	f
288	f	51.3473055	14.6575203	1750782054549	1750782654549	1750782654549	1875000	2304000		144	WSG 4km	f
289	t	51.5306226	14.7303642	1750125000000	1750125600000	1750125000000	866000	1649000		145	Erlenbruch 11	f
290	f	51.5433114	14.5309437	1750127249000	1750127849000	1750127849000	1649000	1052000		145	Hoyerswerdaer Straße 33	f
291	t	51.3512947	14.6364822	1750141470914	1750142070914	1750141470914	1652000	1883000		146	WSG 4km	f
292	f	51.5433114	14.5309437	1750143953914	1750144553914	1750144553914	1883000	1052000		146	Hoyerswerdaer Straße 33	f
293	t	51.5302251	14.5252029	1751134026539	1751134626539	1751134026539	1112000	2497000		147	Tischlereiweg 113b	f
294	f	51.471382	14.7763185	1751137123539	1751137723539	1751137723539	2497000	1533000		147	WSG 4km	f
295	t	51.3600924	14.5377566	1751166600373	1751167200373	1751166600373	1609000	1720000		148	WSG 4km	f
296	f	51.5343123	14.5136158	1751168920373	1751169520373	1751169520373	1720000	1177000		148	Forstweg 78a	f
299	t	51.4887723	14.8272801	1750486394963	1750486994963	1750486394963	1059000	1926000		150	WSG 4km	f
300	f	51.5364085	14.524572	1750488920963	1750489520963	1750489520963	1926000	1015000		150	Jahnring 5b	f
301	t	51.5329343	14.5196775	1750602222117	1750602822117	1750602222117	958000	1624000		151	Dorfstraße 106	f
302	f	51.5274444	14.7266837	1750604446117	1750605046117	1750605046117	1624000	840000		151	Muskauer Straße 155	f
304	f	51.5397943	14.5386138	1750926674866	1750927274866	1750927274866	1545000	1036000		152	Strugaaue 37	f
305	t	51.5195813	14.7140247	1750486543346	1750487143346	1750486543346	721000	1487000		153	Wilhelmstraße 12	f
306	f	51.5397943	14.5386138	1750488630346	1750489230346	1750489230346	1487000	1036000		153	Strugaaue 37	f
309	t	51.5400192	14.5240712	1750395546342	1750396146342	1750395546342	1058000	2026000		155	Thälmann-Siedlung 8	f
310	f	51.3979883	14.6216253	1750398172342	1750398772342	1750398772342	2026000	1673000		155	WSG 4km	f
311	t	51.5446031	14.5355952	1750823333379	1750823933379	1750823333379	1011000	327000		156	Schleife - Slepo	f
312	f	51.5509673	14.5369265	1750824260379	1750824860379	1750824860379	327000	1176000		156	Neu-Mühlrose - Nowy Miłoraz	f
315	t	51.4359877	14.6040302	1751265329020	1751265929020	1751265329020	941000	1379000		158	Herzlich willkommen im Lausitzer Seenland Witajće do tužiskeje jězoriny	f
316	f	51.5344465	14.5268116	1751267308020	1751267908020	1751267908020	1379000	997000		158	Mulkwitzer Weg 10	f
317	t	51.536356	14.5290886	1750655594400	1750656194400	1750655594400	916000	536000		159	Friedensstraße 1	f
318	f	51.5332369	14.6043139	1750656730400	1750657330400	1750657330400	536000	468000		159	WSG 4km	f
313	t	51.5350649	14.5289157	1750645367510	1750645967510	1750645367510	945000	2093000		157	Siedlung - Sydlišćo	t
314	f	51.4224273	14.5709291	1750648060510	1750648660510	1750648660510	2093000	1774000		157	Boxberg Block P	t
319	t	51.5409269	14.6459115	1750538024000	1750538624000	1750538024000	1450000	976000		160	WSG 4km	f
320	f	51.5394742	14.5159274	1750539600000	1750540200000	1750540200000	976000	1110000		160	Hoyerswerdaer Straße 94	f
277	t	51.5296246	14.5237337	1750567584864	1750568184864	1750567584864	1072000	2183000		139	Tischlereiweg 115a	t
278	f	51.3169451	14.5894706	1750570367864	1750570967864	1750570967864	2183000	2117000		139	WSG 4km	t
322	f	51.5426918	14.5308026	1751001255376	1751001855376	1751001855376	536000	1091000		161	Hoyerswerdaer Straße 37	f
323	t	51.5332486	14.5141138	1750126715001	1750126854001	1750126715001	278000	2390000		162	Mühlweg 5b	f
324	f	51.3884686	14.5435989	1750129244001	1750129844001	1750129844001	2390000	2401000		162	WSG 4km	f
325	t	51.5213658	14.7562811	1750769400138	1750770000138	1750769400138	787000	1792000		163	Unterdorf 98	f
326	f	51.5301599	14.5247083	1750771792138	1750772392138	1750772392138	1792000	1153000		163	Tischlereiweg 113b	f
327	t	51.3292444	14.5518577	1750261784454	1750262384454	1750261784454	3308000	2128000		164	Grenzstein 79 KS	f
328	f	51.5394742	14.5159274	1750264512454	1750264669134	1750264669134	2128000	78000		164	Hoyerswerdaer Straße 94	f
329	t	51.5426918	14.5308026	1750613214318	1750613814318	1750613214318	1031000	2678000		165	Hoyerswerdaer Straße 37	f
330	f	51.43791	14.9395405	1750616492318	1750617092318	1750617092318	2678000	1805000		165	WSG 4km	f
331	t	51.5344271	14.5295784	1750431607388	1750432207388	1750431607388	185000	1236000		166	Mühlroser Straße 3	f
332	f	51.5067774	14.67079	1750433443388	1750434043388	1750434043388	1236000	590000		166	Waldhaus	f
154	f	51.3078485	14.6282237	1751014612518	1751015212518	1751015212518	2221000	981000		77	WSG 4km	f
333	t	51.5393992	14.5316092	1751011825519	1751011926519	1751011825519	202000	2221000		167	Strugaaue 2	f
334	f	51.3662679	14.580802	1751016273765	1751016873765	1751016873765	981000	1853000		167	WSG 4km	f
153	t	51.5360245	14.5286573	1751011724518	1751011724519	1751011724518	920000	202000		77	Friedensstraße 1	f
335	t	51.528762	14.5279248	1750836642374	1750837242374	1750836642374	910000	1614000		168	Trebendorfer Weg 116c	f
336	f	51.4223703	14.6637836	1750838856374	1750839456374	1750839456374	1614000	742000		168	WSG 4km	f
339	t	51.5618483	14.6963472	1750795807355	1750796407355	1750795807355	1090000	1609000		170	Berliner Chaussee 98b	f
340	f	51.5312531	14.516953	1750798016355	1750798616355	1750798616355	1609000	1033000		170	Dorfstraße 103	f
303	t	51.5556962	14.708072	1750924529866	1750925129866	1750924529866	1090000	1545000		152	Wohnpark Am Wasserturm 1	f
321	t	51.5634756	14.5651963	1751000119376	1751000719376	1751000119376	1153000	536000		161	Lieskauer Weg 7	f
297	t	51.3724396	14.6473456	1750784512571	1750785112571	1750784512571	1586000	1840000		149	WSG 4km	t
298	f	51.5296246	14.5237337	1750786952571	1750787552571	1750787552571	1840000	1132000		149	Tischlereiweg 115a	t
337	t	51.5292289	14.5391334	1750332624742	1750333224742	1750332624742	831000	2458000		169	Rohner Weg 3a	t
338	f	51.3033164	14.6053368	1750335682742	1750336282742	1750336282742	2458000	2218000		169	WSG 4km	t
307	t	51.3451588	14.499609	1750159203426	1750159803426	1750159203426	1652000	1840000		154	WSG 4km	t
308	f	51.5426918	14.5308026	1750161643426	1750162243426	1750162243426	1840000	1091000		154	Hoyerswerdaer Straße 37	t
341	t	51.3839563	14.5894868	1750500083281	1750500683281	1750500083281	1194000	1432000		171	WSG 4km	f
342	f	51.5397943	14.5386138	1750502115281	1750502715281	1750502715281	1432000	1036000		171	Strugaaue 37	f
343	t	51.4406751	14.8737293	1750222531444	1750223131444	1750222531444	2626000	3369000		172	WSG 4km	f
344	f	51.5443525	14.5405083	1750228245060	1750228845060	1750228845060	305000	2189000		172	Friedensstraße 62	f
240	f	51.3707682	14.5764067	1750230434060	1750230434061	1750230434061	2189000	2043000		120	WSG 4km	f
345	t	51.5359089	14.5038922	1750180297283	1750180897283	1750180297283	1126000	332000		173	WSG 4km	f
346	f	51.5332486	14.5141138	1750181229283	1750181829283	1750181829283	332000	1098000		173	Mühlweg 5b	f
279	t	51.3504836	14.5912418	1750347895605	1750348495605	1750347895605	1140000	1808000		140	Gartenweg 361	t
280	f	51.5405733	14.520827	1750350303605	1750350903605	1750350903605	1808000	1122000		140	Thälmann-Siedlung 25	t
347	t	51.4674012	14.8227873	1750612821745	1750613421745	1750612821745	1484000	2370000		174	WSG 4km	f
348	f	51.5286634	14.5366817	1750615791745	1750616391745	1750616391745	2370000	360000		174	Rohner Weg 6	f
349	t	51.5312531	14.516953	1750674473044	1750675073044	1750674473044	973000	2440000		175	Dorfstraße 103	f
350	f	51.4606685	14.9385343	1750677513044	1750678113044	1750678113044	2440000	1615000		175	WSG 4km	f
351	t	51.535357	14.5350536	1750996343658	1750996943658	1750996343658	921000	1228000		176	Werksweg 12	f
352	f	51.5290478	14.6270677	1750998171658	1750998771658	1750998771658	1228000	1153000		176	WSG 4km	f
353	t	51.4359877	14.6040302	1750250080038	1750250680038	1750250080038	941000	1390000		177	Herzlich willkommen im Lausitzer Seenland Witajće do tužiskeje jězoriny	f
354	f	51.5344271	14.5295784	1750252070038	1750252670038	1750252670038	1390000	131000		177	Mühlroser Straße 3	f
355	t	51.5416387	14.5289058	1750872441408	1750873041408	1750872441408	975000	683000		178	Lindenweg 20	f
356	f	51.5154746	14.611478	1750873724408	1750874324408	1750874324408	683000	451000		178	Auensiedlung 4	f
357	t	51.5332486	14.5141138	1750949045123	1750949166623	1750949045123	243000	1614000		179	Mühlweg 5b	f
358	f	51.3914062	14.5651047	1750950780623	1750951380623	1750951380623	1614000	1556000		179	WSG 4km	f
359	t	51.5277052	14.5242631	1750566354627	1750566954627	1750566354627	964000	1843000		180	Trebendorfer Weg 116b	f
360	f	51.3752023	14.6866084	1750568797627	1750569397627	1750569397627	1843000	1723000		180	WSG 4km	f
361	t	51.5277052	14.5242631	1750688365614	1750688965614	1750688365614	964000	3205000		181	Trebendorfer Weg 116b	f
362	f	51.5003717	14.8341397	1750692170614	1750692770614	1750692770614	3205000	2073000		181	WSG 4km	f
363	t	51.4492768	14.5083326	1750100449842	1750101049842	1750100449842	1457000	945000		182	WSG 4km	f
364	f	51.5357337	14.5192924	1750101994842	1750102594842	1750102594842	945000	1041000		182	Jahnring 13	f
\.


--
-- Data for Name: fcm_token; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fcm_token (device_id, company, fcm_token) FROM stdin;
\.


--
-- Data for Name: journey; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.journey (id, json, "user", request1, request2, rating, comment) FROM stdin;
\.


--
-- Data for Name: kysely_migration; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.kysely_migration (name, "timestamp") FROM stdin;
2024-07-01	2025-06-16T11:51:20.302Z
2025-03-24	2025-06-16T11:51:20.307Z
2025-04-07	2025-06-16T11:51:20.310Z
2025-04-24-json-and-latlng-precision	2025-06-16T11:51:20.339Z
2025-04-30	2025-06-16T11:51:20.405Z
2025-05-21	2025-06-16T11:51:20.410Z
2025-06-06-update-scheduled-times	2025-06-16T11:51:20.415Z
2025-06-11-update-direct-durations	2025-06-16T11:51:20.420Z
2025-06-12-reconstructable-requests	2025-06-16T11:51:20.446Z
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

COPY public.request (id, passengers, kids_zero_to_two, kids_three_to_four, kids_five_to_six, wheelchairs, bikes, luggage, tour, customer, ticket_code, ticket_checked, cancelled, ticket_price) FROM stdin;
1	2	0	0	0	0	0	0	1	1	9e309eb7baad75f662618b3f44e8459f	f	t	600
2	1	0	0	0	0	0	0	2	1	686ad2a0429782cb958ee20306ddd03f	f	t	300
9	1	0	0	0	0	0	0	9	1	552cca9f352a35a4be6e98263226516a	f	t	300
7	1	0	0	0	0	0	0	7	1	061fb364d21740715ea3c9e94960b48f	f	t	300
5	1	0	0	0	0	0	0	5	1	e06514dd69fb9ebfd54a184c4c34101b	f	t	300
8	1	0	0	0	0	0	0	8	1	46e0cb22eb62eded854a68787942e6d0	f	t	300
4	2	0	0	0	0	0	0	4	1	a435ceac93b963a9a0c941e41fd866d4	f	t	600
12	1	0	0	0	0	0	0	12	1	1fd2076b39293fd8d0650d8dfd1a058c	f	t	300
10	2	0	0	0	0	0	0	10	1	8a21a6501fc943c8945b8ff99c071282	f	t	600
6	2	0	0	0	0	0	0	6	1	18ff12af4168301451beeb4d11adb3ee	f	t	600
14	2	0	0	0	0	0	0	14	1	4a2c5d02c94029beeb734dfa1113e20a	f	t	600
13	1	0	0	0	0	0	0	13	1	20660406fba2342795e6dd2f2391b498	f	t	300
3	2	0	0	0	0	0	0	3	1	e4c36bb0a500667c807584d903913b82	f	t	600
11	2	0	0	0	0	0	0	11	1	bc5daeb0ae3e06c922b4db391d49cb1e	f	t	600
17	1	0	0	0	0	0	0	17	1	5dbd6cc8e63ad4e07c79f1b80c3201cf	f	t	300
15	2	0	0	0	0	0	0	15	1	6e1c103ec95406c140aa73b2621f650e	f	t	600
19	1	0	0	0	0	0	0	19	1	79ab72dffab12822ec9112c25bccba62	f	t	300
20	1	0	0	0	0	0	0	20	1	0a4435a2142bc179903668d254c8ddcc	f	t	300
21	1	0	0	0	0	0	0	21	1	7d735f237336ccf32185c7e0c61378b8	f	t	300
18	2	0	0	0	0	0	0	18	1	5b6f1d8b82019873e3bf38f35c0c4879	f	t	600
23	2	0	0	0	0	0	0	23	1	46e95a2fc401d50103605ebe4da09425	f	t	600
24	2	0	0	0	0	0	0	24	1	3db2d3aec0c569a83a9c10d33e5bc7a9	f	t	600
27	1	0	0	0	0	0	0	27	1	1deadce67a482d3f05e5632dcbdadb57	f	t	300
32	1	0	0	0	0	0	0	32	1	75d9fe28305477afb0dcc724946e3195	f	t	300
28	1	0	0	0	0	0	0	28	1	0e2f1e9a63a4dd2ac12678b84ce7c6f0	f	t	300
37	1	0	0	0	0	0	0	37	1	267bdaf3a8bfa72067a92b68c7eabc40	f	f	300
26	2	0	0	0	0	0	0	26	1	e0ade8013064865972ac37cbe1ae4795	f	t	600
34	2	0	0	0	0	0	0	34	1	dab5275ea3a84ab2e844e82c8be4f77a	f	t	600
36	1	0	0	0	0	0	0	36	1	f7cc0a020e9e64e552d4544c3bf4614a	f	t	300
45	2	0	0	0	0	0	0	45	1	4f36db17203912eb5be15573f10589f3	f	f	600
50	2	0	0	0	0	0	0	50	1	60410c049941f62c98152f528041092e	f	f	600
16	1	0	0	0	0	0	0	16	1	b4b59a51643639e27f3162afd0a079fe	f	t	300
51	1	0	0	0	0	0	0	51	1	82e02e3075539783c9a9bc6668df39df	f	f	300
52	2	0	0	0	0	0	0	52	1	7988235e5b5c3a5991c9557d9dd65541	f	f	600
54	1	0	0	0	0	0	0	53	1	ddd1cc96acf1fc6ba0e7c4352b249854	f	f	300
46	1	0	0	0	0	0	0	46	1	b3d7cdd44b48cb26ffa7426802e0dcd1	f	t	300
35	2	0	0	0	0	0	0	35	1	384ca80870bf8132bedf1a815f56bcf5	f	t	600
57	1	0	0	0	0	0	0	53	1	bd10b2b19f88e8395e479cdc0c1b3923	f	f	300
31	2	0	0	0	0	0	0	31	1	5500190879978725c28c0a7977980902	f	t	600
62	1	0	0	0	0	0	0	60	1	9e66395bad754e3f7604b1e7ca9816d0	f	f	300
39	2	0	0	0	0	0	0	39	1	19ff9eb2ad9dcabfe787572654dd7912	f	t	600
64	1	0	0	0	0	0	0	62	1	1f9b5f5d8c4038fcd6b09d13e0fce41e	f	f	300
58	1	0	0	0	0	0	0	56	1	2e5874385de128c69ebc8ff2d1cc9d4a	f	t	300
47	1	0	0	0	0	0	0	47	1	f65b375fadf216118ec69810731948d8	f	t	300
30	2	0	0	0	0	0	0	47	1	24aac866914aae517b6b1a42bd220c18	f	t	600
68	2	0	0	0	0	0	0	47	1	914e8933a233de8014a8ffb888203032	f	t	600
70	2	0	0	0	0	0	0	44	1	1d27ee80c9c293ad9a83117c68dd4ecd	f	f	600
72	2	0	0	0	0	0	0	68	1	a0dc93678418bc875bafd65f7caa6240	f	f	600
61	2	0	0	0	0	0	0	59	1	6be001cef934b1261a32759ff3652d55	f	t	600
55	1	0	0	0	0	0	0	54	1	98eb9fdcb9a794eda7a95a4c595ac12c	f	t	300
33	1	0	0	0	0	0	0	33	1	d8b81627cd8251ac2b04b950baf79b9b	f	t	300
48	2	0	0	0	0	0	0	48	1	64dbed56c3b43a6c168ca59ad4193902	f	t	600
65	1	0	0	0	0	0	0	63	1	116dfdcdf9f3b594dcc9672fb0562d89	f	t	300
25	1	0	0	0	0	0	0	25	1	ccd4a89008ed1655c258f10c98f4bd34	f	t	300
63	2	0	0	0	0	0	0	61	1	4cf746449bd3b1b12f4c2fb7f500adb4	f	t	600
56	2	0	0	0	0	0	0	55	1	73454e9af9a4edadd7a5e92e8280aad2	f	t	600
38	1	0	0	0	0	0	0	38	1	00b8cc3e712f27357009963b59f309f0	f	t	300
67	2	0	0	0	0	0	0	112	1	6fab21103f9d4facfad1c3e33ca879e0	f	f	600
43	2	0	0	0	0	0	0	43	1	b369c9cf48f9659ff932e40a77f2967e	f	t	600
60	2	0	0	0	0	0	0	58	1	a07ce167509a347c60083cb33e62597c	f	t	600
40	1	0	0	0	0	0	0	40	1	cd9df926971f054b518b105fbe6f1cc9	f	t	300
74	1	0	0	0	0	0	0	70	1	fcf2cc5ba8c915d447677c38f09ae992	f	t	300
29	1	0	0	0	0	0	0	29	1	deec2012492c8403fae433437b3c3ea3	f	t	300
66	2	0	0	0	0	0	0	64	1	2b26270dd5d16cfad80fc59d0f20d32f	f	t	600
49	1	0	0	0	0	0	0	49	1	b6ebf4871a935f13cb74b7f7773d92f2	f	t	300
73	2	0	0	0	0	0	0	69	1	746990aa2871dbba0d1c69d8cb9e3dc9	f	t	600
69	1	0	0	0	0	0	0	66	1	4f12f3fe52293ffc7fcacf3f1dfea909	f	t	300
42	1	0	0	0	0	0	0	42	1	f56f6cedde6ecbe2de920bebfc5fc88c	f	t	300
71	2	0	0	0	0	0	0	67	1	de29a2f033a8e4952fdcba1d5f56fb60	f	t	600
44	1	0	0	0	0	0	0	44	1	d1d5cf896f8c8d953a1190272fcfb9cc	f	t	300
22	2	0	0	0	0	0	0	22	1	1e6f2f0566ace81af37757522b9d4cd8	f	t	600
75	1	0	0	0	0	0	0	71	1	9fd01f5a0ab4ece1c7992883d682dcfb	f	f	300
41	2	0	0	0	0	0	0	41	1	d56eb5435716a74f3d6705f7a35d0cc2	f	t	600
77	2	0	0	0	0	0	0	73	1	1680118fdf115ac55ecddfbbebaf9ef6	f	f	600
78	2	0	0	0	0	0	0	74	1	e146316e90efc3c19ff2ae9d3e3c2fd3	f	f	600
79	1	0	0	0	0	0	0	75	1	edd6cbebbe76769cee0e1a1095db57be	f	t	300
59	1	0	0	0	0	0	0	57	1	516c201db0f0a68ef20fd064a86494df	f	t	300
83	2	0	0	0	0	0	0	78	1	c35e1439b17c78d69e632750f9968515	f	f	600
81	1	0	0	0	0	0	0	76	1	8d51d124fb5cd707c9066f572b9f9428	f	t	300
84	2	0	0	0	0	0	0	79	1	432d144a8bf8a08c29de5fab0c2addd9	f	f	600
86	1	0	0	0	0	0	0	50	1	b83ce228cfca617c619fb30b91f09c55	f	f	300
87	1	0	0	0	0	0	0	81	1	10c422c23d7dd43114fd7c5658178841	f	f	300
88	1	0	0	0	0	0	0	82	1	22f016c8384fd2ebbe21949a0d9b85f8	f	f	300
89	2	0	0	0	0	0	0	83	1	91d119b536199048fc2a52224aa50f60	f	f	600
90	2	0	0	0	0	0	0	84	1	ece803c7e5078fa083a012f7e22aecdd	f	f	600
85	1	0	0	0	0	0	0	80	1	b471abb119cd3a609845f4d637ff0eaf	f	t	300
91	2	0	0	0	0	0	0	85	1	3347502e56c8ddcb6d859e5b9e92f334	f	f	600
92	1	0	0	0	0	0	0	86	1	fbce2fa15bd7ba20273b7abcd9c5eb2c	f	f	300
96	1	0	0	0	0	0	0	90	1	7508058a6d8bfe63eba411698ba7e41e	f	f	300
80	2	0	0	0	0	0	0	40	1	c7fa274ae90f390826bce0785dda6a62	f	t	600
98	2	0	0	0	0	0	0	92	1	b387e689c507afa87fbe96244c0fbefe	f	f	600
100	2	0	0	0	0	0	0	94	1	60ae8222b3224f245ea8f2a09216e9c9	f	f	600
101	1	0	0	0	0	0	0	79	1	b8882933b7135a20694cc56b616836e3	f	f	300
102	1	0	0	0	0	0	0	49	1	e02f3e19982fcd272f337cf0ab5bb9e0	f	f	300
103	2	0	0	0	0	0	0	95	1	57597e672693c6b4cd1df70f34333a6e	f	f	600
99	1	0	0	0	0	0	0	93	1	13ac7839c5a2c89b023d12a9915e4bcc	f	t	300
104	2	0	0	0	0	0	0	96	1	194d1bcc458cc80801a08f3a0d02e581	f	f	600
105	1	0	0	0	0	0	0	97	1	28def2ddb14f4f731456acab1262dcf8	f	t	300
107	2	0	0	0	0	0	0	49	1	10e7453dc3bc0618f7094dc941e202f9	f	f	600
108	2	0	0	0	0	0	0	98	1	1b24109ccff2c0f983c658dd77fb0866	f	f	600
110	2	0	0	0	0	0	0	100	1	5d432915b459ffc0faca751bd8e2f5f6	f	f	600
112	2	0	0	0	0	0	0	102	1	01867c66a307c38cdaa8bb7076ba84f2	f	f	600
113	2	0	0	0	0	0	0	103	1	b83d6767a6171c4cec35a84188e5c48f	f	f	600
114	1	0	0	0	0	0	0	83	1	b9344a40fe1381d0ae570734c678ee73	f	f	300
116	2	0	0	0	0	0	0	96	1	1b2c444aa6921a34bbcf20096aabc0c3	f	f	600
117	2	0	0	0	0	0	0	104	1	6fc0d86090f11f0f7918f22bd9b8886c	f	f	600
111	2	0	0	0	0	0	0	101	1	fbbec0c0ef134c08ea4280479f33118f	f	t	600
118	2	0	0	0	0	0	0	85	1	53d2acaf5e588447cb904508f836dddc	f	f	600
95	1	0	0	0	0	0	0	89	1	7357b69e5c4e11520d3305fa32ee2a6e	f	t	300
82	1	0	0	0	0	0	0	77	1	1c000847092233d3c537802dab4ee09c	f	t	300
120	1	0	0	0	0	0	0	106	1	dd0fc4ec09f37cb6080abf629ccf3cbe	f	f	300
121	1	0	0	0	0	0	0	107	1	bdca28f8b1e68cbea351409053d9be86	f	f	300
122	2	0	0	0	0	0	0	108	1	1ae9e1170d22272064b5e751a58e0d24	f	f	600
123	2	0	0	0	0	0	0	62	1	dcd968e13445caece764b93f1c246267	f	f	600
125	1	0	0	0	0	0	0	110	1	45fba4cf9757a68eae01ab2b954e6242	f	f	300
126	1	0	0	0	0	0	0	111	1	4bfe5b3ef7506d98b1ce15782f3a46c5	f	f	300
109	2	0	0	0	0	0	0	99	1	e0ee63b01f07185de65e7387a76b3915	f	t	600
127	1	0	0	0	0	0	0	112	1	6f21f561071e8c4b19e38f52a05ef6d3	f	f	300
128	2	0	0	0	0	0	0	113	1	391c3df8ce121a2066831bdc27e38112	f	f	600
53	2	0	0	0	0	0	0	42	1	a4f564fe0db9ef540465e5eba42fb6b2	f	t	600
129	2	0	0	0	0	0	0	90	1	3646b93f9eaa271ae2478172be23a346	f	f	600
124	1	0	0	0	0	0	0	109	1	842c4412aa3acfb623c242c3e90372ff	f	t	300
130	2	0	0	0	0	0	0	114	1	38e236a95d4b5454adbc90ff13b227a3	f	f	600
132	2	0	0	0	0	0	0	116	1	5022de791bfeff9233df452fd6f79120	f	f	600
141	1	0	0	0	0	0	0	104	1	df76a6b5fcda884c490186a9fac10178	f	f	300
135	2	0	0	0	0	0	0	119	1	d3a0adb28db9c57e225faccba1340b0a	f	f	600
136	2	0	0	0	0	0	0	120	1	39b1dcfa589db8b74020f61f9803ff68	f	f	600
137	2	0	0	0	0	0	0	121	1	a98d71677f1ba0664c98bbbccc60130c	f	f	600
138	1	0	0	0	0	0	0	122	1	8df6f5e49cf683d81852ad0a2368110d	f	f	300
106	1	0	0	0	0	0	0	72	1	a5dfd77aafd150758b40deb2e7ff6348	f	t	300
76	1	0	0	0	0	0	0	72	1	9978c047ebdf8518444cea5280d9d9a2	f	t	300
115	2	0	0	0	0	0	0	67	1	7fc84c275f337dad8d8c153908f2939b	f	t	600
142	2	0	0	0	0	0	0	123	1	a4f6430730066b3b89e53109ef7859fc	f	f	600
143	1	0	0	0	0	0	0	124	1	459c20c47c4995027a8419937b1f94f3	f	f	300
144	1	0	0	0	0	0	0	45	1	1100dd070fd7aff39f9cc6f149dd852a	f	f	300
145	2	0	0	0	0	0	0	125	1	69c137d24ed8891afde045da10b309d5	f	f	600
146	1	0	0	0	0	0	0	126	1	01ceccd9283f068d140c29a8227bb075	f	f	300
134	2	0	0	0	0	0	0	118	1	007506a9ff9d5e824ea8a2d38da4399e	f	t	600
97	1	0	0	0	0	0	0	91	1	d9c9a4927a91620be9c4898f315b57f4	f	t	300
93	2	0	0	0	0	0	0	87	1	012cc86c28f2aff820455d62856a7207	f	t	600
140	2	0	0	0	0	0	0	78	1	2d7dba8dd86d6914f9b57a041aab2fca	f	t	600
94	1	0	0	0	0	0	0	88	1	2201e4faaff8d6c47c869df644a52b0e	f	t	300
133	2	0	0	0	0	0	0	117	1	b78f7e623c8851d8da3dbd25d7717d47	f	t	600
131	2	0	0	0	0	0	0	115	1	c08964bbbeb758010b7cb14448a8be3f	f	t	600
147	1	0	0	0	0	0	0	127	1	f446cf051794ad8b70683af02ee3b0cf	f	f	300
148	2	0	0	0	0	0	0	128	1	09762d97956200d71305158fdc66d728	f	f	600
150	1	0	0	0	0	0	0	130	1	8f55e8ea2e780387edeeb4be73c9734a	f	f	300
151	1	0	0	0	0	0	0	131	1	578a7c7f965eb3aa6b876238056c11c6	f	f	300
152	1	0	0	0	0	0	0	22	1	64e2d0593ca6704a22ce8e57e5365951	f	f	300
153	2	0	0	0	0	0	0	132	1	0076fe94c6922c4bf090c937cb8d20a1	f	f	600
155	2	0	0	0	0	0	0	134	1	1900324194c6d4a716225b5271379c1f	f	f	600
156	1	0	0	0	0	0	0	135	1	89f09e4881a6653975948e0b1e5d3ea1	f	f	300
119	2	0	0	0	0	0	0	105	1	914f8d9229a0df50089971fb9a3ef8db	f	t	600
158	1	0	0	0	0	0	0	137	1	7c0e7cefba69a9aa54a6d51244555a9a	f	f	300
159	2	0	0	0	0	0	0	44	1	a827641e12ba40fb5dc98494d82db7b8	f	f	600
157	2	0	0	0	0	0	0	136	1	8ad72ba580791667d73dc1a05b40d6dc	f	t	600
160	2	0	0	0	0	0	0	62	1	2dd57f453df83c7da5beabe9a1927dcd	f	f	600
139	1	0	0	0	0	0	0	91	1	9f3090579b0e1f5e87f6e80e582f7576	f	t	300
161	1	0	0	0	0	0	0	138	1	ae8f590eeab4b5e12840ef922e7c3c1b	f	f	300
162	2	0	0	0	0	0	0	108	1	7a50d1afaf57db39a5ea10e7ccc5e18c	f	f	600
163	2	0	0	0	0	0	0	139	1	0bb49e98c94eaa3ae0aac7f24a99210d	f	f	600
164	2	0	0	0	0	0	0	112	1	9c20b14bd9cb2f368c653a30f0d6a0e3	f	f	600
165	1	0	0	0	0	0	0	140	1	fd57c01cff4d750bf44e76a09bc5e170	f	f	300
166	2	0	0	0	0	0	0	37	1	cf7bc1eeb70399f2eca0ddd64abcbe71	f	f	600
167	1	0	0	0	0	0	0	73	1	5734c80ce1462f7b09629b5a8ce52525	f	f	300
168	1	0	0	0	0	0	0	141	1	fbc1ad0afdd94da859502d796f1ec1fc	f	f	300
170	2	0	0	0	0	0	0	143	1	ecb5eaea2ff3e2734095aa60fbac37a4	f	f	600
171	2	0	0	0	0	0	0	144	1	6bcab43cb5fe153c7b940555265a2c83	f	f	600
172	1	0	0	0	0	0	0	106	1	d43773ba7da17a022991983db4adecfa	f	f	300
173	1	0	0	0	0	0	0	145	1	2588ad51b91230b00f698e9720e9b42a	f	f	300
174	2	0	0	0	0	0	0	107	1	9b689264fdbbf9f4f5dded9a12e17ba6	f	f	600
175	2	0	0	0	0	0	0	146	1	b1a3b4510984254201bba200a5439ae2	f	f	600
176	2	0	0	0	0	0	0	138	1	5ac18047685a04a14983699b359777d8	f	f	600
149	2	0	0	0	0	0	0	129	1	59d55f1cabeb65d97b8c23f57fe04293	f	t	600
177	2	0	0	0	0	0	0	112	1	2c3c0665128fb95cf5c9d0541ed72485	f	f	600
178	2	0	0	0	0	0	0	147	1	9f85dfcaaf9efd37133243d8d9981fa3	f	f	600
179	1	0	0	0	0	0	0	68	1	47cb7f69c0118ef657e35cb5df696699	f	f	300
180	1	0	0	0	0	0	0	148	1	4e23af8264683e3bc33890476227263d	f	f	300
169	2	0	0	0	0	0	0	142	1	914bbff6327f25bca4f97f8fd7cf469c	f	t	600
154	2	0	0	0	0	0	0	133	1	86af1e1a9b278fabfa236553397013fc	f	t	600
181	1	0	0	0	0	0	0	71	1	2b6eeb2a1dbd3e579ee2d32fab6db980	f	f	300
182	1	0	0	0	0	0	0	149	1	443f5c15def647d9a51bacc2142fe747	f	f	300
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
1	1751136147750	1751139042750	\N	1	\N	t	message
2	1750268922077	1750272428077	\N	1	\N	t	message
34	1750329632980	1750335447980	\N	2	\N	t	message
55	1750220560779	1750223566779	194000	1	\N	t	\N
9	1750408150255	1750410918255	\N	1	\N	t	\N
7	1750593549463	1750596318463	2539000	1	\N	t	\N
60	1750145789234	1750150669234	474000	1	\N	f	\N
5	1750129142877	1750135930877	\N	1	\N	t	message
8	1750505370942	1750511407942	1742000	1	\N	t	message
36	1750448149949	1750452410949	223000	1	\N	t	message
4	1750644105709	1750647127709	1820000	1	\N	t	\N
12	1750130379153	1750133602153	\N	1	\N	t	\N
10	1750937348379	1750939468379	2110000	1	\N	t	message
69	1750864202691	1750868781691	746000	1	\N	t	\N
6	1750174473895	1750179022895	2096000	1	\N	t	message
14	1750091527353	1750094979353	\N	1	\N	t	message
13	1751006442440	1751010993440	1189000	1	\N	t	\N
3	1751137005608	1751141599608	152000	1	\N	t	\N
11	1750135658544	1750140619544	\N	1	\N	t	message
17	1750244797850	1750247335850	98000	1	\N	t	\N
15	1750179121067	1750182604067	\N	1	\N	t	message
19	1750823523444	1750825780444	\N	1	\N	t	message
16	1750608076981	1750611852981	1823000	1	\N	t	message
84	1750166585343	1750169128343	1460000	1	\N	f	\N
20	1750482529154	1750486450154	1753000	1	\N	t	message
21	1751114220441	1751117249441	161000	1	\N	t	message
51	1751087560165	1751090874165	151000	1	\N	f	\N
18	1751249197582	1751252090582	3000000	1	\N	t	\N
23	1750430418526	1750435310526	\N	1	\N	t	\N
24	1750499535225	1750501549225	\N	1	\N	t	\N
27	1750514585487	1750518700487	\N	1	\N	t	\N
109	1751200082573	1751203866573	63000	1	\N	t	\N
32	1750675058565	1750678037565	868000	1	\N	t	\N
28	1751226311713	1751229723713	2165000	1	\N	t	\N
26	1750841272376	1750846906376	2443000	1	\N	t	message
41	1750417629131	1750424329131	\N	1	\N	t	message
38	1750643280506	1750646320506	1663000	1	\N	t	\N
46	1751162100004	1751164864004	1442000	1	\N	t	\N
90	1750852285619	1750857387952	1612000	1	\N	f	\N
35	1751214904793	1751220241793	66000	1	\N	t	message
82	1750672121164	1750676905164	1748000	1	\N	f	\N
31	1751027546565	1751032456565	2095000	1	\N	t	message
29	1751169512934	1751173369934	1354000	1	\N	t	message
76	1750920995647	1750925030647	\N	2	\N	t	\N
39	1750691556681	1750694166681	136000	1	\N	t	\N
73	1751010703518	1751018126765	239000	1	\N	f	\N
56	1750816900137	1750820126137	1012000	1	\N	t	\N
59	1750498872183	1750501697183	847000	1	\N	t	message
108	1750124533000	1750131645001	875000	1	\N	f	\N
47	1750328907580	1750341051366	1727000	1	\N	t	message
54	1750779474536	1750783244536	279000	1	\N	t	\N
33	1751252278614	1751255069614	93000	1	\N	t	message
48	1750360953897	1750363989897	66000	1	\N	t	\N
98	1750762526323	1750765652323	128000	1	\N	f	\N
63	1750261418541	1750265659541	2509000	1	\N	t	message
25	1750346168919	1750351007919	3239000	1	\N	t	\N
43	1750390137192	1750393621192	2115000	1	\N	t	\N
61	1750443924236	1750446612236	225000	1	\N	t	\N
102	1750694356942	1750696963942	1845000	1	\N	f	\N
75	1750149525363	1750152025363	\N	2	\N	t	message
70	1750590968795	1750596016795	2738000	1	\N	t	message
57	1750678756965	1750683024965	1883000	1	\N	t	\N
72	1750591343040	1750600693630	2991000	2	\N	t	message
100	1750936363562	1750939717562	934000	2	\N	f	\N
89	1750406785484	1750413086484	\N	2	\N	t	\N
80	1750658851042	1750661731042	630000	2	\N	t	\N
91	1750567112864	1750577841803	294000	1	\N	t	message
86	1750268525502	1750273282502	2041000	1	\N	f	\N
58	1750876825691	1750879841691	1794000	1	\N	t	\N
97	1751193852558	1751199132558	2007000	1	\N	t	message
40	1750694807824	1750714999000	2310000	1	\N	t	message
53	1750601163765	1750607317766	2201000	1	\N	f	\N
92	1751091849062	1751096683062	1444000	1	\N	f	\N
93	1750095676295	1750099966295	\N	2	\N	t	message
49	1751101962007	1751111871125	1687000	1	\N	f	\N
99	1750241273813	1750246109813	2015000	1	\N	t	\N
64	1750445036016	1750448424016	1783000	2	\N	t	\N
95	1750989918492	1750993678492	249000	2	\N	f	\N
77	1750278174312	1750281467312	1555000	1	\N	t	message
96	1751086560633	1751097559963	\N	2	\N	f	\N
101	1750262560764	1750265602764	1654000	1	\N	t	\N
66	1750470870801	1750474045801	1180000	1	\N	t	message
83	1750307244725	1750320840431	2640000	1	\N	f	\N
103	1750498833648	1750505155648	143000	1	\N	f	\N
44	1750655278400	1750668388691	927000	1	\N	f	\N
94	1751125203275	1751129575275	744000	1	\N	f	\N
110	1751120643546	1751123033546	475000	1	\N	f	\N
111	1750769770238	1750772409238	1281000	1	\N	f	\N
104	1750753556661	1750765546266	2520000	2	\N	f	\N
42	1750933176657	1750937995342	3058000	1	\N	t	message
81	1751141499170	1751144820170	1926000	1	\N	f	\N
106	1750220505444	1750231877061	\N	1	\N	f	\N
78	1750342503833	1750351425605	81000	1	\N	f	\N
67	1750092562607	1750099785981	\N	1	\N	t	message
79	1750253626225	1750264409531	2442000	2	\N	f	\N
22	1750917442211	1750927710866	1149000	1	\N	f	\N
105	1750518842634	1750521557634	2722000	1	\N	t	message
87	1750183263723	1750186651723	310000	1	\N	t	\N
62	1750528671425	1750540710000	1864000	1	\N	f	\N
85	1750136101294	1750143738059	2783000	1	\N	f	\N
74	1750190766051	1750193343051	660000	1	\N	f	\N
107	1750611937745	1750619182733	1905000	1	\N	f	\N
52	1750989465539	1750993897539	1549000	1	\N	f	\N
50	1751038710606	1751045251652	2384000	1	\N	f	\N
88	1750410579129	1750415299129	1786000	1	\N	t	\N
37	1750427289020	1750434033388	1202000	1	\N	f	\N
71	1750688001614	1750699230667	2371000	2	\N	f	\N
113	1750688100666	1750692149666	2231000	1	\N	f	\N
114	1750332638519	1750335830519	2050000	1	\N	f	\N
119	1751251171086	1751254039086	512000	1	\N	f	\N
120	1750729546014	1750734845014	2438000	1	\N	f	\N
122	1751252104415	1751255868415	\N	2	\N	f	\N
45	1750779241549	1750787138537	460000	1	\N	f	\N
125	1750124734000	1750128301000	\N	2	\N	f	\N
123	1750190618124	1750193808124	124000	2	\N	f	\N
126	1750140418914	1750145005914	1823000	2	\N	f	\N
127	1751133514539	1751138656539	2478000	2	\N	f	\N
116	1751219531827	1751221897827	218000	1	\N	f	\N
128	1751165591373	1751170097373	1555000	1	\N	f	\N
131	1750601864117	1750605286117	1840000	2	\N	f	\N
137	1751264988020	1751268305020	1345000	1	\N	f	\N
136	1750645022510	1750649834510	960000	1	\N	t	\N
118	1751132850596	1751136454596	2078000	1	\N	t	message
139	1750769213138	1750772945138	842000	2	\N	f	\N
140	1750612783318	1750618297318	1570000	2	\N	f	\N
141	1750836332374	1750839598374	388000	1	\N	f	\N
135	1750822922379	1750825436379	245000	1	\N	f	\N
143	1750795317355	1750799049355	1599000	1	\N	f	\N
124	1750564908000	1750569887000	219000	2	\N	f	\N
144	1750499489281	1750503151281	1372000	2	\N	f	\N
145	1750179771283	1750182327283	396000	1	\N	f	\N
134	1750395088342	1750399845342	1905000	1	\N	f	\N
146	1750674100044	1750679128044	2570000	2	\N	f	\N
138	1750996022658	1751002346376	2065000	1	\N	f	\N
129	1750783526571	1750788084571	1801000	2	\N	t	message
117	1750470607000	1750473821000	857000	1	\N	t	\N
130	1750485935963	1750489935963	1323000	1	\N	f	\N
112	1750249739038	1750266542815	1370000	1	\N	f	\N
147	1750872066408	1750874175408	1227000	1	\N	f	\N
68	1750946910622	1750952336623	1434000	1	\N	f	\N
121	1750580053582	1750585554582	1831000	1	\N	f	\N
148	1750565990627	1750570520627	287000	1	\N	f	\N
142	1750332393742	1750337900742	2874000	2	\N	t	message
132	1750486422346	1750489666346	2622000	2	\N	f	\N
133	1750158151426	1750162734426	2695000	1	\N	t	message
115	1751028852184	1751032494184	2105000	1	\N	t	message
149	1750099592842	1750103035842	\N	1	\N	f	\N
\.


--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public."user" (id, name, email, password_hash, is_taxi_owner, is_admin, is_email_verified, email_verification_code, email_verification_expires_at, password_reset_code, password_reset_expires_at, phone, company_id) FROM stdin;
1	John	foo@bar.de	$argon2id$v=19$m=19456,t=2,p=1$9fW6tfdNBJHtNC/RgNpMgg$z+hlFH7KXxKbIyt1q4fTK134FYcF8y10ZjSslzyqmFc	f	f	t	\N	\N	\N	\N	0815-1231234	\N
2	John	maintainer@zvon.de	$argon2id$v=19$m=19456,t=2,p=1$ZtuiFUoQYRyXUQRduYBkfQ$E+aREm5wKl8Ldn5ASP3wZnPf/jRriMIQmR3L3BhDaSA	f	t	t	\N	\N	\N	\N	\N	\N
3	John	taxi@weisswasser.de	$argon2id$v=19$m=19456,t=2,p=1$BoC0z8dXsKPZmUMvpnRXPw$Hc6rK5wlUNizsw5GQFjJ9oQ9uMhgWln42Ak4J2rO8yc	t	f	t	\N	\N	\N	\N	\N	1
4	John	taxi@gablenz.de	$argon2id$v=19$m=19456,t=2,p=1$3/CML3alHoFB7kYR3Fz9Hw$qQ7MYo7N6NO0SeCKXFs4VrPdiwGAT0FhE5KmwC0fv8U	t	f	t	\N	\N	\N	\N	\N	2
5	John	taxi@reichwalde.de	$argon2id$v=19$m=19456,t=2,p=1$UCIZz8oGzu9kCDOpmWXxYQ$amyxen1cjPmi/TwetOz7I/f+neLvlx6eQxM6OTvIzx0	t	f	t	\N	\N	\N	\N	\N	3
6	John	taxi@moholz.de	$argon2id$v=19$m=19456,t=2,p=1$TCAyMLkDNz0F7nceulTs4A$+dCc3qIYwS362mcrSH/Z7hmXx2KW5Ow5NLhZH0XpPEI	t	f	t	\N	\N	\N	\N	\N	4
7	John	taxi@niesky.de	$argon2id$v=19$m=19456,t=2,p=1$jxW4oxa3l0tg+OG3+4lllw$l5TN76xuwWqc01KNBHB37WukqjmqjKsm/ZBF2y+NvPY	t	f	t	\N	\N	\N	\N	\N	5
8	John	taxi@rothenburg.de	$argon2id$v=19$m=19456,t=2,p=1$dviKXplqYeVGdRA+UztyDg$/rQUv5OVgKufsy6VqYtFhXfE6jaHOCV6oE+3aDZVGMo	t	f	t	\N	\N	\N	\N	\N	6
9	John	taxi@schoepstal.de	$argon2id$v=19$m=19456,t=2,p=1$B7mjUX8IFZv+1G/jiu2dSQ$xGhHcG8PKvDYLwydw2aVVqaaovdjFanlIrBjF0TgDkI	t	f	t	\N	\N	\N	\N	\N	7
10	John	taxi@goerlitz.de	$argon2id$v=19$m=19456,t=2,p=1$6zvrI5rYSzw+NP8hRZ1Yxg$pAY9o3o3rhlCNGo2zVwP/Kq5YVOrm6yvLrqaSDeWxpw	t	f	t	\N	\N	\N	\N	\N	8
11	John	fahrer@test.de	$argon2id$v=19$m=19456,t=2,p=1$6zvrI5rYSzw+NP8hRZ1Yxg$pAY9o3o3rhlCNGo2zVwP/Kq5YVOrm6yvLrqaSDeWxpw	f	f	t	\N	\N	\N	\N	\N	1
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

SELECT pg_catalog.setval('public.availability_id_seq', 90, true);


--
-- Name: booking_api_parameters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.booking_api_parameters_id_seq', 182, true);


--
-- Name: company_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.company_id_seq', 8, true);


--
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.event_id_seq', 364, true);


--
-- Name: journey_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.journey_id_seq', 1, false);


--
-- Name: request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.request_id_seq', 182, true);


--
-- Name: tour_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tour_id_seq', 149, true);


--
-- Name: user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_id_seq', 11, true);


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
-- Name: booking_api_parameters booking_api_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.booking_api_parameters
    ADD CONSTRAINT booking_api_parameters_pkey PRIMARY KEY (id);


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
-- Name: request request_tour_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_tour_fkey FOREIGN KEY (tour) REFERENCES public.tour(id);


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

