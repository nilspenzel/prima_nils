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
1	1750208400000	1750284000000	1
2	1750294800000	1750370400000	1
3	1750178622810	1750197600000	1
4	1750467600000	1750543200000	1
5	1750813200000	1750888800000	1
6	1750554000000	1750629600000	1
7	1750899600000	1750975200000	1
8	1750381200000	1750456800000	1
9	1750640400000	1750716000000	1
10	1750726800000	1750802400000	1
11	1750986000000	1751061600000	1
12	1751072400000	1751148000000	1
13	1751158800000	1751234400000	1
14	1751245200000	1751320800000	1
15	1751331600000	1751388222810	1
16	1750178622854	1750197600000	2
17	1750208400000	1750284000000	2
18	1750294800000	1750370400000	2
19	1750381200000	1750456800000	2
20	1750467600000	1750543200000	2
21	1750554000000	1750629600000	2
22	1750640400000	1750716000000	2
23	1750726800000	1750802400000	2
24	1750813200000	1750888800000	2
25	1750899600000	1750975200000	2
26	1750986000000	1751061600000	2
27	1751072400000	1751148000000	2
28	1751158800000	1751234400000	2
29	1751245200000	1751320800000	2
30	1751331600000	1751388222854	2
\.


--
-- Data for Name: booking_api_parameters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.booking_api_parameters (id, start_lat1, start_lng1, target_lat1, target_lng1, start_time1, target_time1, start_address1, target_address1, start_fixed1, start_lat2, start_lng2, target_lat2, target_lng2, start_time2, target_time2, start_address2, target_address2, start_fixed2, kids_zero_to_two, kids_three_to_four, kids_five_to_six, passengers, wheelchairs, bikes, luggage) FROM stdin;
1	51.545673	51.545673	51.369095	14.491101	1751275055092	1751277982664	Spremberger Straße 17	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
2	51.387257	51.387257	51.529236	14.521395	1750878638201	1750881878826	Körnerplatz	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
3	51.557003	51.557003	51.53388	14.520264	1750266419010	1750268514273	Körnerplatz	Dorfstraße 105a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
4	51.53053	51.53053	51.56798	14.585452	1750593549128	1750596948166	Rohner Weg 10	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
5	51.368835	51.368835	51.53841	14.525069	1750786779641	1750788077375	Körnerplatz	Jahnring 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
6	51.532295	51.532295	51.53377	14.640212	1751305288803	1751307104916	Reinert Ranch	Eichenhügel	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
7	51.496647	51.496647	51.529022	14.529856	1751008570825	1751011021252	Am Walde 5	Rohner Weg 13b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
8	51.539795	51.539795	51.41557	14.647429	1750763744274	1750766785979	Strugaaue 37	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
9	51.528763	51.528763	51.374916	14.486753	1751137664601	1751141184580	Trebendorfer Weg 116c	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
10	51.535065	51.535065	51.3515	14.598518	1751090189339	1751091158514	Siedlung - Sydlišćo	Straße der Jugend 62	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
11	51.53388	51.53388	51.490414	14.627253	1750535770275	1750537815750	Dorfstraße 105a	Stele und Baggerschaufel	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
12	51.5226	51.5226	51.534203	14.521786	1750683162737	1750685241373	Eichenweg 124	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
13	51.453247	51.453247	51.52923	14.539133	1750311911982	1750314966886	Körnerplatz	Rohner Weg 3a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
14	51.527706	51.527706	51.334763	14.626449	1750475170682	1750476632012	Trebendorfer Weg 116b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
15	51.527706	51.527706	51.353207	14.607137	1751313158790	1751315419212	Trebendorfer Weg 116b	Kriegerdenkmal	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
16	51.538887	51.538887	51.49593	14.5236635	1750780524814	1750783287115	Zum Sportplatz 5	Kohlebahnweg 87	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
17	51.544353	51.544353	51.51528	14.587174	1750652542857	1750654316213	Friedensstraße 62	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
18	51.531925	51.531925	51.399906	14.579657	1751105758735	1751106914941	Dorfstraße 80	Thälmannstraße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
19	51.496555	51.496555	51.544353	14.540508	1750406129486	1750408079155	Raddatz	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
20	51.39224	51.39224	51.528664	14.536682	1750446772986	1750450272910	Mühlgrabenweg 11	Rohner Weg 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
21	51.510048	51.510048	51.531254	14.516953	1750844721194	1750847669780	Körnerplatz	Dorfstraße 103	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
22	51.504818	51.504818	51.534447	14.526812	1751138322489	1751140862568	Krauschwitzer Straße 4	Mulkwitzer Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
23	51.43445	51.43445	51.544353	14.540508	1751185480707	1751187180450	Körnerplatz	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
24	51.5394	51.5394	51.54763	14.729943	1750752179832	1750753645105	Strugaaue 2	Wehrinsel	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
25	51.341877	51.341877	51.54269	14.530803	1750914797185	1750916875480	Körnerplatz	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
26	51.429794	51.429794	51.527905	14.522943	1750436850962	1750438133164	Körnerplatz	Trebendorfer Weg 81	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
27	51.372066	51.372066	51.54002	14.524071	1750969797099	1750972012094	Körnerplatz	Thälmann-Siedlung 8	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
28	51.529068	51.529068	51.53429	14.533877	1751073724075	1751077058214	Körnerplatz	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
29	51.534428	51.534428	51.458427	14.732395	1750582207552	1750585210114	Mühlroser Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
30	51.540085	51.540085	51.434834	14.643171	1751100928625	1751102198694	Hoyerswerdaer Straße 98	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
31	51.35739	51.35739	51.534313	14.513616	1750954457910	1750956749590	Körnerplatz	Forstweg 78a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
32	51.529236	51.529236	51.517815	14.677887	1750475334943	1750476537644	Gefallenendenkmale Rohne	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
33	51.34439	51.34439	51.534428	14.529578	1750905173521	1750906889240	Körnerplatz	Mühlroser Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
34	51.478477	51.478477	51.534203	14.521786	1750678097116	1750680391470	Königshügel 5	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
35	51.49561	51.49561	51.534313	14.513616	1750730098975	1750732401923	Körnerplatz	Forstweg 78a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
36	51.505432	51.505432	51.540573	14.520827	1750508011653	1750510384154	Mulkwitz Außenkippe	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
37	51.53239	51.53239	51.528763	14.527925	1750790572089	1750792819872	Körnerplatz	Trebendorfer Weg 116c	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
38	51.533836	51.533836	51.483044	14.690007	1751017563821	1751020508327	Schleifer Straße 5	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
39	51.528664	51.528664	51.48474	14.794932	1750393041217	1750394091756	Rohner Weg 6	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
40	51.53411	51.53411	51.53345	14.61383	1750527192593	1750529796304	Schleifer Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
41	51.544353	51.544353	51.418423	14.539125	1750620516550	1750622127917	Friedensstraße 62	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
42	51.530224	51.530224	51.52203	14.613142	1751022620196	1751024434954	Tischlereiweg 113b	An der Philippine 28	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
43	51.54002	51.54002	51.44107	14.682814	1750188354389	1750189971079	Thälmann-Siedlung 8	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
44	51.543312	51.543312	51.399906	14.579657	1750405852929	1750407828044	Hoyerswerdaer Straße 33	Thälmannstraße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
45	51.46515	51.46515	51.534447	14.526812	1750864764633	1750866816238	Körnerplatz	Mulkwitzer Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
46	51.36118	51.36118	51.530224	14.525203	1751115608942	1751118123424	Körnerplatz	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
47	51.534428	51.534428	51.508183	14.627587	1751029117350	1751031799985	Mühlroser Straße 3	Jahnstraße 94	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
48	51.536026	51.536026	51.45252	14.655369	1750497272027	1750500213131	Friedensstraße 1	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
49	51.44426	51.44426	51.534447	14.526812	1750435501127	1750438644533	Körnerplatz	Mulkwitzer Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
50	51.541637	51.541637	51.536472	14.649014	1751356999592	1751358310214	Lindenweg 20	Gablenz Waldrand	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
51	51.520065	51.520065	51.532295	14.534533	1750833003190	1750835363181	Löschwasserentnahmestelle	Reinert Ranch	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
52	51.543312	51.543312	51.324383	14.599551	1751107818804	1751109525930	Hoyerswerdaer Straße 33	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
53	51.530224	51.530224	51.507538	14.657323	1751174023088	1751175587986	Tischlereiweg 113b	Braunsteichweg 39	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
54	51.474533	51.474533	51.540573	14.520827	1750251320937	1750254194900	Körnerplatz	Thälmann-Siedlung 25	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
55	51.473694	51.473694	51.52923	14.539133	1750397692814	1750400164349	Körnerplatz	Rohner Weg 3a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
56	51.541878	51.541878	51.536358	14.529089	1750516895525	1750518246741	Weinbergweg 38	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
57	51.456783	51.456783	51.529236	14.521395	1751185831990	1751188819560	Körnerplatz	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
230	51.522526	51.522526	51.534313	14.513616	1750493750047	1750495623317	Eichenweg 114	Forstweg 78a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
58	51.543312	51.543312	51.461575	14.95602	1750932754845	1750934903510	Hoyerswerdaer Straße 33	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
59	51.413605	51.413605	51.530224	14.525203	1750559120290	1750562443633	Körnerplatz	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
60	51.527706	51.527706	51.50881	14.527885	1751088999707	1751092080580	Trebendorfer Weg 116b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
61	51.322937	51.322937	51.53016	14.524709	1750955354017	1750958647022	Körnerplatz	Tischlereiweg 113b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
62	51.499153	51.499153	51.541637	14.528906	1750815593286	1750818757200	Lausitz	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
63	51.534447	51.534447	51.486202	14.642852	1750336772210	1750339082333	Mulkwitzer Weg 10	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
64	51.53536	51.53536	51.356915	14.492805	1750190010960	1750192665771	Werksweg 12	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
65	51.533173	51.533173	51.55117	14.713421	1750775758628	1750777681911	Mühlroser Straße 8a	Berliner Chaussee 12	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
66	51.429707	51.429707	51.536026	14.528657	1750565969920	1750567769225	Körnerplatz	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
67	51.531254	51.531254	51.522312	14.624241	1750692167464	1750695208942	Dorfstraße 103	Kromlauer Weg 70	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
68	51.543312	51.543312	51.53841	14.525069	1751376059956	1751377888839	Hoyerswerdaer Straße 33	Jahnring 21	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
69	51.494507	51.494507	51.53861	14.514816	1751052541928	1751054256526	Kaupener Straße 5	Hoyerswerdaer Straße 91	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
70	51.539997	51.539997	51.44928	14.612729	1750879760194	1750883054222	Hoyerswerdaer Straße 90	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
71	51.36525	51.36525	51.536026	14.528657	1750445189313	1750446730229	Hauptstraße 1	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
72	51.38796	51.38796	51.534004	14.521774	1750912902879	1750913984919	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
73	51.53329	51.53329	51.544353	14.540508	1750277922733	1750281151951	Station 9	Friedensstraße 62	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
74	51.540085	51.540085	51.560024	14.554679	1751009847710	1751012383161	Hoyerswerdaer Straße 98	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
75	51.303345	51.303345	51.534203	14.521786	1750230841688	1750233556883	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
76	51.534203	51.534203	51.480244	14.776761	1751300648601	1751304020685	Dorfstraße 106a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
77	51.53016	51.53016	51.42243	14.57093	1751047633259	1751050260205	Tischlereiweg 113b	Boxberg Block P	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
78	51.33718	51.33718	51.53841	14.525069	1750565641546	1750568835773	Körnerplatz	Jahnring 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
79	51.506935	51.506935	51.545673	14.534669	1750824892256	1750826347370	Körnerplatz	Spremberger Straße 17	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
80	51.530224	51.530224	51.403618	14.560892	1750838258151	1750839722959	Tischlereiweg 113b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
81	51.534313	51.534313	51.46225	14.931924	1750600442915	1750603088946	Forstweg 78a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
82	51.332333	51.332333	51.529236	14.521395	1750481778937	1750482693262	Feldteich	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
83	51.36617	51.36617	51.533173	14.529221	1750506039637	1750507397704	Hauptstraße 33	Mühlroser Straße 8a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
84	51.531242	51.531242	51.3591	14.653446	1751299367253	1751300595164	Mühlweg 5b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
85	51.5394	51.5394	51.50596	14.510235	1751295987350	1751297614715	Strugaaue 2	Mühlroser Straße 36b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
86	51.55175	51.55175	51.53016	14.524709	1751267198645	1751270747997	Körnerplatz	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
87	51.53388	51.53388	51.416073	14.526874	1750866355962	1750869098963	Dorfstraße 105a	Merzdorfer Straße 38	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
88	51.406948	51.406948	51.53531	14.528985	1751040852460	1751041752460	Hünlich Hügel	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
89	51.533173	51.533173	51.387146	14.655144	1750580082675	1750581853392	Mühlroser Straße 8a	Schadendorfer Weg 3	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
90	51.539997	51.539997	51.35974	14.538104	1751051905214	1751055467982	Hoyerswerdaer Straße 90	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
91	51.537174	51.537174	51.536358	14.529089	1751219959485	1751223037968	Rakotzbrücke	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
92	51.45546	51.45546	51.539795	14.538614	1751274620801	1751276312508	Körnerplatz	Strugaaue 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
93	51.35568	51.35568	51.536407	14.524572	1751109983433	1751113035806	Körnerplatz	Jahnring 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
94	51.54565	51.54565	51.530224	14.525203	1750690625550	1750691937457	Kirchplatz 7	Tischlereiweg 113b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
95	51.53429	51.53429	51.498253	14.722739	1750902132643	1750905716302	Schleifer Straße 2	Am Hammerlugk 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
96	51.543312	51.543312	51.35387	14.487819	1750847697561	1750850005847	Hoyerswerdaer Straße 33	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
97	51.533836	51.533836	51.3338	14.503558	1750434656319	1750436947658	Schleifer Straße 5	Hälterteich	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
98	51.53411	51.53411	51.342007	14.561943	1750274491156	1750277228307	Schleifer Straße 3	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
99	51.53973	51.53973	51.508713	14.73291	1750686987906	1750690166885	NORMA	Krauschwitzer Straße 24	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
100	51.34088	51.34088	51.53973	14.533529	1750522239180	1750523756023	Rokotschin	NORMA	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
101	51.541637	51.541637	51.553665	14.53386	1750597555436	1750598979338	Lindenweg 20	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
102	51.465942	51.465942	51.53053	14.532026	1751248394241	1751250149317	Körnerplatz	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
103	51.534447	51.534447	51.507744	14.644481	1750926266467	1750927976423	Mulkwitzer Weg 10	NKD	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
104	51.54356	51.54356	51.374344	14.573357	1751215588046	1751217007490	Alter Postweg 11	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
105	51.53536	51.53536	51.48378	14.531682	1751259627965	1751262391216	Werksweg 12	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
106	51.532936	51.532936	51.478477	14.906278	1750417758254	1750420978526	Dorfstraße 106	Königshügel 5	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
107	51.40243	51.40243	51.529236	14.521395	1750419009829	1750422309689	Körnerplatz	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
108	51.53411	51.53411	51.32103	14.627688	1750786080307	1750787648563	Schleifer Straße 3	Förstgener Straße 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
109	51.5446	51.5446	51.380405	14.615651	1750318932442	1750321628414	Schleife - Slepo	Klittener Straße 14	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
110	51.514935	51.514935	51.534447	14.526812	1750653139366	1750656678679	Körnerplatz	Mulkwitzer Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
111	51.3668	51.3668	51.528763	14.527925	1751017302210	1751020374275	Spreeschlößchen	Trebendorfer Weg 116c	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
112	51.364788	51.364788	51.533836	14.536425	1751213540889	1751215742971	Körnerplatz	Schleifer Straße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
113	51.538887	51.538887	51.424126	14.686156	1751190484768	1751191659798	Zum Sportplatz 5	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
114	51.534313	51.534313	51.375103	14.5100155	1751000882659	1751001844801	Forstweg 78a	Hundestrand (dog's beach)	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
115	51.527206	51.527206	51.543312	14.530944	1751270518875	1751273424094	Dorfstraße 1	Hoyerswerdaer Straße 33	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
116	51.53841	51.53841	51.523384	14.745468	1751171486667	1751173662718	Jahnring 21	Im Tale 13	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
117	51.51528	51.51528	51.529236	14.521395	1750239014166	1750240090852	Körnerplatz	Gefallenendenkmale Rohne	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
118	51.515476	51.515476	51.545673	14.534669	1750863301205	1750866528351	Auensiedlung 4	Spremberger Straße 17	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
119	51.354527	51.354527	51.541637	14.528906	1750393481110	1750395019230	Körnerplatz	Lindenweg 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
120	51.5394	51.5394	51.409554	14.519143	1750513251835	1750514839682	Strugaaue 2	Zulaufanlage Spree - Lohsa II	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
121	51.53429	51.53429	51.429924	14.73116	1750251036526	1750252700105	Schleifer Straße 2	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
122	51.53053	51.53053	51.536194	14.724071	1751336364483	1751338723011	Rohner Weg 10	Bautzener Straße 15	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
123	51.340717	51.340717	51.545673	14.534669	1750948616302	1750951202373	ehem. Lieskauer Teich	Spremberger Straße 17	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
124	51.44747	51.44747	51.53388	14.520264	1751215701611	1751217623257	FStR 2	Dorfstraße 105a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
125	51.532295	51.532295	51.453667	14.621868	1750683687035	1750686559634	Reinert Ranch	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
126	51.53531	51.53531	51.326984	14.643668	1750965913711	1750967355716	Siedlung - Sydlišćo	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
127	51.57438	51.57438	51.541637	14.528906	1751038894212	1751039942649	Schulstraße 26	Lindenweg 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
128	51.538887	51.538887	51.33553	14.5008745	1750226605140	1750228525123	Zum Sportplatz 5	Eichenallee 25a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
129	51.528584	51.528584	51.541786	14.524831	1750260135398	1750262984001	Am See 3	Hoyerswerdaer Straße 50	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
130	51.46395	51.46395	51.527706	14.524263	1751197122452	1751198183355	Körnerplatz	Trebendorfer Weg 116b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
131	51.329987	51.329987	51.53841	14.525069	1750618453267	1750620158385	Körnerplatz	Jahnring 21	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
132	51.541874	51.541874	51.451694	14.60767	1750587299715	1750590663007	Friedensstraße 77a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
133	51.52208	51.52208	51.529236	14.521395	1750655116008	1750657932892	Rothenburger Straße 38	Gefallenendenkmale Rohne	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
134	51.534203	51.534203	51.482815	14.654655	1750877666603	1750881182196	Dorfstraße 106a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
135	51.47475	51.47475	51.541786	14.524831	1750646429389	1750648392881	Körnerplatz	Hoyerswerdaer Straße 50	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
136	51.531925	51.531925	51.36872	14.518815	1750598926229	1750599949866	Dorfstraße 80	2.3	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
137	51.538887	51.538887	51.452293	14.633377	1751279383147	1751280556707	Zum Sportplatz 5	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
138	51.540085	51.540085	51.56152	14.581685	1750301008349	1750303493982	Hoyerswerdaer Straße 98	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
139	51.534428	51.534428	51.417583	14.661744	1750915609039	1750917165824	Mühlroser Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
140	51.540085	51.540085	51.368835	14.61775	1750578703978	1750579946019	Hoyerswerdaer Straße 98	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
141	51.49703	51.49703	51.534203	14.521786	1750923328951	1750924364749	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
142	51.344467	51.344467	51.541637	14.528906	1750954242997	1750956506620	Körnerplatz	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
143	51.53536	51.53536	51.500458	14.632439	1751013972319	1751015858031	Werksweg 12	Schweigstraße 23	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
144	51.530224	51.530224	51.499916	14.713628	1751023248787	1751025405968	Tischlereiweg 113b	Finkensteg 1	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
145	51.534313	51.534313	51.50999	14.633399	1750921054427	1750922670071	Forstweg 78a	Jahnstraße 52c	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
146	51.532295	51.532295	51.503067	14.475147	1751225837258	1751228747950	Reinert Ranch	Kiesbagger	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
147	51.486954	51.486954	51.53973	14.533529	1750531871425	1750533562770	Körnerplatz	NORMA	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
148	51.53973	51.53973	51.352592	14.587216	1750824528308	1750827292379	NORMA	Ernst-Thälmann-Straße 360	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
149	51.541637	51.541637	51.364372	14.471701	1750389462423	1750392225726	Lindenweg 20	Rotdornallee 32	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
150	51.536358	51.536358	51.418716	14.58435	1751137297065	1751139306336	Friedensstraße 1	Boxberg Kraftwerk	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
151	51.47074	51.47074	51.52923	14.539133	1751209166038	1751210083999	Körnerplatz	Rohner Weg 3a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
152	51.538887	51.538887	51.501736	14.626304	1750489669129	1750492145010	Zum Sportplatz 5	Forstweg 18	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
153	51.53325	51.53325	51.38977	14.652271	1750606521460	1750609592613	Mühlweg 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
154	51.48654	51.48654	51.541786	14.524831	1750850739038	1750852143011	Körnerplatz	Hoyerswerdaer Straße 50	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
155	51.532936	51.532936	51.55402	14.684579	1750433364371	1750436004719	Dorfstraße 106	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
156	51.541637	51.541637	51.50405	14.644075	1750190656617	1750191560640	Lindenweg 20	Kleingartensparte Reichsban.	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
157	51.449276	51.449276	51.53841	14.525069	1750305205246	1750307234328	Körnerplatz	Jahnring 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
158	51.536407	51.536407	51.4958	14.802045	1751190446935	1751193673899	Jahnring 5b	Zur Tanne 58	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
159	51.356915	51.356915	51.53388	14.520264	1750906153242	1750909020225	Körnerplatz	Dorfstraße 105a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
160	51.53531	51.53531	51.38811	14.604775	1750612527545	1750614503113	Siedlung - Sydlišćo	Rietschener Straße 6a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
161	51.45925	51.45925	51.528763	14.527925	1750260579203	1750263816734	Körnerplatz	Trebendorfer Weg 116c	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
162	51.53973	51.53973	51.330303	14.499657	1751350898483	1751352308551	NORMA	Oberteich Mönau	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
163	51.538887	51.538887	51.538918	14.54504	1751181689351	1751182703847	Zum Sportplatz 5	Am Großteich 3	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
164	51.53411	51.53411	51.39961	14.5879545	1751292286768	1751295379318	Schleifer Straße 3	Straße der Freundschaft 26	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
165	51.531254	51.531254	51.322063	14.633659	1750250309576	1750251599579	Dorfstraße 103	Im Erlengrund 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
166	51.410896	51.410896	51.534313	14.513616	1750346263750	1750347199436	Körnerplatz	Forstweg 78a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
167	51.53841	51.53841	51.543083	14.658567	1750794304062	1750797531572	Jahnring 21	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
168	51.535065	51.535065	51.53565	14.6929035	1751358815173	1751360851425	Siedlung - Sydlišćo	Eilandweg 15	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
169	51.526737	51.526737	51.528763	14.527925	1750945017970	1750946047875	Lange Straße 19	Trebendorfer Weg 116c	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
170	51.536026	51.536026	51.494476	14.6490135	1751090209610	1751092746148	Friedensstraße 1	Gartensparte Sonnenschein.	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
171	51.53053	51.53053	51.37774	14.648584	1750945103143	1750947129062	Rohner Weg 10	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
172	51.534313	51.534313	51.53388	14.520264	1751306474844	1751309425422	Forstweg 78a	Dorfstraße 105a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
173	51.536026	51.536026	51.52844	14.731528	1751301908953	1751302983165	Friedensstraße 1	Erlenbruch 11	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
174	51.58048	51.58048	51.539997	14.516031	1750759282165	1750761251425	Dorfstraße 60	Hoyerswerdaer Straße 90	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
175	51.535732	51.535732	51.48886	14.674902	1750345274720	1750347234271	Jahnring 13	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
176	51.5394	51.5394	51.409176	14.659903	1750497681108	1750499627444	Strugaaue 2	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
177	51.322063	51.322063	51.53053	14.532026	1750345374458	1750348305140	Im Erlengrund 2	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
178	51.536026	51.536026	51.51299	14.48911	1751057070835	1751060539612	Friedensstraße 1	Friedhof Mulkwitz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
179	51.361942	51.361942	51.540573	14.520827	1750671980240	1750673006221	Spreegasse 5a	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
180	51.538887	51.538887	51.518784	14.71738	1750488764307	1750490346414	Zum Sportplatz 5	Schäferstraße 8	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
181	51.535732	51.535732	51.399143	14.611401	1750564316139	1750565527090	Jahnring 13	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
182	51.5085	51.5085	51.539795	14.538614	1750857553298	1750860811843	Am Sportplatz 50	Strugaaue 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
183	51.528664	51.528664	51.524117	14.62265	1750875197339	1750877817497	Rohner Weg 6	Weißwasser/O.L.	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
184	51.347523	51.347523	51.538887	14.518962	1751109334155	1751112146390	Ernst-Thälmann-Straße 32	Zum Sportplatz 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
185	51.528763	51.528763	51.515446	14.502813	1750228480484	1750229683634	Trebendorfer Weg 116c	Neustädter Straße 65	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
186	51.534447	51.534447	51.305927	14.63685	1750932449236	1750934203674	Mulkwitzer Weg 10	Tauerwiesenteich	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
187	51.527905	51.527905	51.47811	14.497778	1751187923389	1751188947799	Trebendorfer Weg 81	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
188	51.513653	51.513653	51.531254	14.516953	1751277807028	1751280560787	Schwanenweg 23	Dorfstraße 103	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
189	51.53325	51.53325	51.42639	14.699231	1750661962167	1750665238794	Mühlweg 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
190	51.53861	51.53861	51.362858	14.510596	1750998130523	1750999247843	Hoyerswerdaer Straße 91	Lange Straße 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
191	51.538887	51.538887	51.347374	14.587806	1750362890833	1750366255793	Zum Sportplatz 5	Heidestraße 378	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
192	51.49993	51.49993	51.53325	14.514113	1750704208255	1750705688124	Lausitz	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
193	51.551674	51.551674	51.543312	14.530944	1751183161850	1751186350404	Freibad	Hoyerswerdaer Straße 33	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
194	51.53861	51.53861	51.487793	14.502786	1750854533953	1750856593769	Hoyerswerdaer Straße 91	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
195	51.53325	51.53325	51.37353	14.666382	1750937156025	1750940407417	Mühlweg 5b	Jahnstraße 29a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
196	51.540573	51.540573	51.48524	14.859044	1751124693241	1751127434987	Thälmann-Siedlung 25	Dorfstraße 97	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
197	51.535732	51.535732	51.52511	14.520677	1750995761423	1750999335085	Jahnring 13	Mulkwitzer Weg 83a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
198	51.391712	51.391712	51.539474	14.515927	1751294669951	1751298126538	Körnerplatz	Hoyerswerdaer Straße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
199	51.566986	51.566986	51.536358	14.529089	1751203959866	1751206300753	Körnerplatz	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
200	51.535065	51.535065	51.489315	14.8377905	1751076565364	1751080086357	Siedlung - Sydlišćo	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
201	51.498413	51.498413	51.54356	14.529777	1751289463101	1751292710958	Körnerplatz	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
202	51.533173	51.533173	51.447792	14.855615	1750478783854	1750480847288	Mühlroser Straße 8a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
203	51.48486	51.48486	51.544353	14.540508	1751257668207	1751260885129	Körnerplatz	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
204	51.48474	51.48474	51.53841	14.525069	1751226210467	1751228102634	Körnerplatz	Jahnring 21	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
205	51.50826	51.50826	51.5446	14.535595	1751110604119	1751112658894	Körnerplatz	Schleife - Slepo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
206	51.417347	51.417347	51.532936	14.519677	1750332009430	1750335529748	Körnerplatz	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
207	51.48355	51.48355	51.534534	14.523995	1750425466905	1750427760052	Königshügel 24	Neustädter Straße 7	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
208	51.51299	51.51299	51.534756	14.533946	1750426683772	1750429432133	Friedhof Mulkwitz	Tiefbau-Service-Berton	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
209	51.495163	51.495163	51.528664	14.536682	1751353529602	1751355362580	Zur Tanne 45	Rohner Weg 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
210	51.541786	51.541786	51.52136	14.613079	1751252448407	1751254738017	Hoyerswerdaer Straße 50	An der Philippine 28	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
211	51.53536	51.53536	51.520615	14.749516	1751038469728	1751040425162	Werksweg 12	Ein- und Ausstieg Sagar	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
212	51.531242	51.531242	51.443638	14.788996	1750653222269	1750654498596	Mühlweg 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
213	51.529625	51.529625	51.406918	14.554864	1750677401380	1750680122086	Tischlereiweg 115a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
214	51.388973	51.388973	51.528664	14.536682	1750665528257	1750666635557	Körnerplatz	Rohner Weg 6	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
215	51.53325	51.53325	51.37637	14.671603	1750365303037	1750366788410	Mühlweg 5b	Amselweg 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
216	51.545673	51.545673	51.505737	14.660381	1750238703793	1750241528454	Spremberger Straße 17	Sägewerk und Holzhandel Kopte	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
217	51.529068	51.529068	51.545673	14.534669	1751221001307	1751222896664	Körnerplatz	Spremberger Straße 17	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
218	51.541786	51.541786	51.51356	14.659799	1751053759898	1751056628238	Hoyerswerdaer Straße 50	Drachenbergweg 8	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
219	51.51513	51.51513	51.539474	14.515927	1751207311141	1751209552809	Kleingärtnerverein "Feldschlösschen"	Hoyerswerdaer Straße 94	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
220	51.53411	51.53411	51.543	14.719979	1750474798645	1750476995585	Schleifer Straße 3	Am Parkrand 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
221	51.416645	51.416645	51.536026	14.528657	1750781568498	1750783671076	Merzdorfer Straße 34	Friedensstraße 1	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
222	51.529236	51.529236	51.479614	14.540526	1750511175082	1750514610619	Gefallenendenkmale Rohne	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
223	51.442356	51.442356	51.539474	14.515927	1750775012034	1750776233660	Körnerplatz	Hoyerswerdaer Straße 94	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
224	51.5013	51.5013	51.53053	14.532026	1750990817725	1750993278679	Brandstraße 9	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
225	51.528267	51.528267	51.52923	14.539133	1750492105257	1750495188025	Friedhofsweg 4	Rohner Weg 3a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
226	51.534756	51.534756	51.48843	14.672327	1750955241236	1750957300587	Tiefbau-Service-Berton	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
227	51.38704	51.38704	51.53531	14.528985	1751349862106	1751353043279	Körnerplatz	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
228	51.323883	51.323883	51.54269	14.530803	1750478905639	1750482178886	Körnerplatz	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
229	51.43976	51.43976	51.53531	14.528985	1751046226830	1751049651023	22	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
231	51.52136	51.52136	51.532936	14.519677	1750535826675	1750537945720	An der Philippine 28	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
232	51.540085	51.540085	51.36974	14.628112	1751274848771	1751276879110	Hoyerswerdaer Straße 98	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
233	51.349606	51.349606	51.529625	14.523734	1750410799848	1750413067674	Feldweg 97	Tischlereiweg 115a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
234	51.333336	51.333336	51.539997	14.516031	1750516416361	1750518240836	Bornwiese	Hoyerswerdaer Straße 90	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
235	51.47296	51.47296	51.540085	14.512858	1750500727266	1750504157077	Körnerplatz	Hoyerswerdaer Straße 98	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
236	51.509136	51.509136	51.531925	14.52021	1751182199013	1751183885762	Körnerplatz	Dorfstraße 80	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
237	51.433346	51.433346	51.53536	14.535053	1750612884649	1750614345081	Schießbahn 11	Werksweg 12	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
238	51.371555	51.371555	51.53325	14.514113	1750386372674	1750389442062	Körnerplatz	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
239	51.532936	51.532936	51.37419	14.629496	1750692336544	1750695643391	Dorfstraße 106	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
240	51.52923	51.52923	51.410168	14.73362	1751197862559	1751200789021	Rohner Weg 3a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
241	51.53536	51.53536	51.40024	14.518891	1751100189586	1751101438346	Werksweg 12	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
242	51.43646	51.43646	51.538887	14.518962	1750536686396	1750538714826	Körnerplatz	Zum Sportplatz 5	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
243	51.50525	51.50525	51.528664	14.536682	1750749345117	1750751671314	Krauschwitzer Straße 28	Rohner Weg 6	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
244	51.51577	51.51577	51.53531	14.528985	1750779290155	1750780335457	Körnerplatz	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
245	51.49313	51.49313	51.528763	14.527925	1750587318070	1750588268215	Weißwasser/O.L.	Trebendorfer Weg 116c	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
246	51.539795	51.539795	51.39563	14.567016	1750836428707	1750839398978	Strugaaue 37	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
247	51.53429	51.53429	51.34287	14.490327	1750607281776	1750609426045	Schleifer Straße 2	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
248	51.53362	51.53362	51.541874	14.537528	1750340598609	1750343952362	Feldweg 2	Friedensstraße 77a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
249	51.536026	51.536026	51.541637	14.528906	1750565257310	1750567502079	Friedensstraße 1	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
250	51.497368	51.497368	51.527706	14.524263	1750487737121	1750489523805	In der Meschina 1	Trebendorfer Weg 116b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
251	51.5394	51.5394	51.512714	14.641681	1750994168584	1750995753897	Strugaaue 2	Teichstraße 28	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
252	51.52923	51.52923	51.508823	14.607952	1751287886150	1751290322321	Rohner Weg 3a	Tiergartenstraße 42	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
253	51.37946	51.37946	51.543312	14.530944	1750762228717	1750764659671	Sportverein 48 Reichwalde	Hoyerswerdaer Straße 33	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
254	51.418716	51.418716	51.536026	14.528657	1750472945316	1750475961040	Boxberg Kraftwerk	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
255	51.398117	51.398117	51.540573	14.520827	1750875492366	1750879010430	Körnerplatz	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
256	51.540085	51.540085	51.540985	14.633427	1751315036898	1751316633128	Hoyerswerdaer Straße 98	Jämlitzer Weg 51	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
257	51.36627	51.36627	51.536407	14.524572	1750691304591	1750694058938	Körnerplatz	Jahnring 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
258	51.53429	51.53429	51.473434	14.798178	1750663382210	1750665931915	Schleifer Straße 2	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
259	51.534447	51.534447	51.520443	14.705432	1750519286985	1750521342828	Mulkwitzer Weg 10	Oberschule "Geschwister Scholl" Krauschwitz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
260	51.531254	51.531254	51.562088	14.567434	1750824323153	1750827224952	Dorfstraße 103	Hühnerfarm	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
261	51.51481	51.51481	51.53325	14.514113	1750279265291	1750280581328	Neustädter Straße 64	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
262	51.586815	51.586815	51.54269	14.530803	1751030108519	1751031067642	Körnerplatz	Hoyerswerdaer Straße 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
263	51.53388	51.53388	51.500458	14.632439	1750244010663	1750244965161	Dorfstraße 105a	Schweigstraße 23	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
264	51.340244	51.340244	51.529022	14.529856	1751365381376	1751368731228	Körnerplatz	Rohner Weg 13b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
265	51.50117	51.50117	51.53973	14.533529	1751374865505	1751376575063	Körnerplatz	NORMA	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
266	51.37419	51.37419	51.53536	14.535053	1750241512669	1750243355782	Körnerplatz	Werksweg 12	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
267	51.478733	51.478733	51.529552	14.524057	1751095341586	1751098820619	Körnerplatz	Tischlereiweg 115a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
268	51.504353	51.504353	51.529236	14.521395	1751012274699	1751013283873	Grünstraße 14	Gefallenendenkmale Rohne	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
269	51.344254	51.344254	51.535732	14.519293	1751344690911	1751345874731	Körnerplatz	Jahnring 13	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
270	51.416157	51.416157	51.536358	14.529089	1750436451040	1750439845932	Körnerplatz	Friedensstraße 1	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
271	51.49925	51.49925	51.536358	14.529089	1751302531443	1751305633272	Körnerplatz	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
272	51.466877	51.466877	51.54356	14.529777	1750521179008	1750524368834	Körnerplatz	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
273	51.312267	51.312267	51.540085	14.512858	1751052611545	1751054731828	Körnerplatz	Hoyerswerdaer Straße 98	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
274	51.361206	51.361206	51.53325	14.514113	1750945698365	1750947611731	Körnerplatz	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
275	51.53861	51.53861	51.448734	14.675696	1750330532323	1750332402512	Hoyerswerdaer Straße 91	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
276	51.3358	51.3358	51.53411	14.53515	1750649897348	1750651330874	Westlicher Bahnteich	Schleifer Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
277	51.544353	51.544353	51.3775	14.62619	1751384097770	1751387335272	Friedensstraße 62	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
278	51.326454	51.326454	51.544353	14.540508	1750856840668	1750859230404	Körnerplatz	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
279	51.535732	51.535732	51.450127	14.618782	1750391161060	1750394095060	Jahnring 13	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
280	51.528763	51.528763	51.40355	14.539746	1751185223193	1751187227050	Trebendorfer Weg 116c	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
281	51.378906	51.378906	51.54002	14.524071	1751124539586	1751127568037	Körnerplatz	Thälmann-Siedlung 8	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
282	51.353954	51.353954	51.534004	14.521774	1750921677021	1750924079010	Körnerplatz	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
283	51.39326	51.39326	51.543312	14.530944	1750421718106	1750423745716	Körnerplatz	Hoyerswerdaer Straße 33	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
284	51.547283	51.547283	51.544353	14.540508	1750878288952	1750880284436	Löwe	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
285	51.53861	51.53861	51.513718	14.605209	1750854323282	1750857518588	Hoyerswerdaer Straße 91	Kleingärtnerverein "Feldschlösschen"	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
286	51.53861	51.53861	51.48225	14.89688	1751138728082	1751139935166	Hoyerswerdaer Straße 91	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
287	51.429756	51.429756	51.529625	14.523734	1750733708966	1750737300212	Reichwalder Weg 36	Tischlereiweg 115a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
288	51.539997	51.539997	51.326157	14.598035	1750840527837	1750841489504	Hoyerswerdaer Straße 90	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
289	51.53016	51.53016	51.508835	14.533541	1750685591617	1750687725687	Tischlereiweg 113b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
290	51.527905	51.527905	51.34067	14.660689	1750259646619	1750261061016	Trebendorfer Weg 81	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
291	51.53016	51.53016	51.34835	14.589883	1750396261966	1750399293385	Tischlereiweg 113b	Klitten Bahnhof	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
292	51.496136	51.496136	51.535732	14.519293	1750565070408	1750566015391	Fleischerei Richter	Jahnring 13	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
293	51.54635	51.54635	51.534203	14.521786	1750869789309	1750871818276	Campingplatz Halbendorfer See	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
294	51.527905	51.527905	51.530685	14.652493	1750748583749	1750752160724	Trebendorfer Weg 81	Sagoinza 26	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
295	51.53536	51.53536	51.463898	14.72194	1750757007570	1750758792168	Werksweg 12	Dorfstraße 9	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
296	51.472294	51.472294	51.540085	14.512858	1751261005052	1751262341657	Körnerplatz	Hoyerswerdaer Straße 98	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
297	51.518784	51.518784	51.531925	14.52021	1750570648344	1750573541467	Schäferstraße 8	Dorfstraße 80	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
298	51.500225	51.500225	51.533836	14.536425	1750757484421	1750758873282	Hermannsdorfer Straße 16	Schleifer Straße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
299	51.527905	51.527905	51.506763	14.779219	1751003871478	1751006945117	Trebendorfer Weg 81	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
300	51.36865	51.36865	51.53531	14.528985	1750989376349	1750992565896	Körnerplatz	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
301	51.531254	51.531254	51.542297	14.588239	1750416084953	1750418056122	Dorfstraße 103	Bahnhofstraße 95	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
302	51.534534	51.534534	51.487118	14.716346	1751080738084	1751082826504	Neustädter Straße 7	Lange Straße 8a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
303	51.402634	51.402634	51.545673	14.534669	1750240444981	1750241507440	Straße der Freundschaft 24	Spremberger Straße 17	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
304	51.532936	51.532936	51.546597	14.613016	1751038781417	1751042023054	Dorfstraße 106	AV Schleife e.V.	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
305	51.529022	51.529022	51.41332	14.5354595	1750192443076	1750195240664	Rohner Weg 13b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
306	51.37697	51.37697	51.53429	14.533877	1750298577103	1750300133752	Körnerplatz	Schleifer Straße 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
307	51.461456	51.461456	51.53531	14.528985	1751102159347	1751105335576	Körnerplatz	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
308	51.53411	51.53411	51.38637	14.533099	1750351204575	1750354069579	Schleifer Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
309	51.53053	51.53053	51.511204	14.511303	1750402595900	1750405857291	Rohner Weg 10	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
310	51.534447	51.534447	51.360195	14.588492	1750592483196	1750593938365	Mulkwitzer Weg 10	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
311	51.536407	51.536407	51.52803	14.680423	1750752913160	1750756310765	Jahnring 5b	Siedlung 30	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
312	51.40068	51.40068	51.53973	14.533529	1751206568416	1751209457666	Straße der Freundschaft 26	NORMA	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
313	51.48817	51.48817	51.531242	14.511581	1751256993637	1751259507407	Körnerplatz	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
314	51.401096	51.401096	51.532295	14.534533	1750218718300	1750221143429	Körnerplatz	Reinert Ranch	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
315	51.536407	51.536407	51.396324	14.615129	1751178967450	1751179968751	Jahnring 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
316	51.374973	51.374973	51.541874	14.537528	1751189515715	1751193086057	Körnerplatz	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
317	51.408226	51.408226	51.53053	14.532026	1751140302575	1751143892292	Eichenweg 146	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
318	51.529625	51.529625	51.544415	14.62657	1750516642580	1750519275122	Tischlereiweg 115a	Campingplatz Badesee Kromlau	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
319	51.439	51.439	51.534447	14.526812	1751162831179	1751165014793	Körnerplatz	Mulkwitzer Weg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
320	51.527905	51.527905	51.40167	14.497075	1751313406930	1751314487137	Trebendorfer Weg 81	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
321	51.43972	51.43972	51.5446	14.535595	1751084975242	1751088200856	Körnerplatz	Schleife - Slepo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
322	51.53411	51.53411	51.516796	14.593385	1751131118698	1751132755454	Schleifer Straße 3	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
323	51.535732	51.535732	51.505363	14.679076	1750251965426	1750255425766	Jahnring 13	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
324	51.540085	51.540085	51.453213	14.813759	1751132254474	1751135465729	Hoyerswerdaer Straße 98	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
325	51.48032	51.48032	51.529022	14.529856	1751131846574	1751133186983	Körnerplatz	Rohner Weg 13b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
326	51.504524	51.504524	51.53053	14.532026	1750559454299	1750561925681	Braunsteich	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
327	51.53531	51.53531	51.498535	14.670096	1750736915380	1750739499574	Siedlung - Sydlišćo	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
328	51.529552	51.529552	51.457012	14.505937	1750594378749	1750596551015	Tischlereiweg 115a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
329	51.527706	51.527706	51.418835	14.593888	1750488584931	1750492136714	Trebendorfer Weg 116b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
330	51.534428	51.534428	51.53432	14.690569	1750505453993	1750508591147	Mühlroser Straße 3	Krauschwitz / Baierweiche	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
331	51.369095	51.369095	51.53325	14.514113	1750252097323	1750253013839	Körnerplatz	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
332	51.50491	51.50491	51.540573	14.520827	1750854381525	1750857087238	Körnerplatz	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
333	51.545673	51.545673	51.540207	14.62155	1750620532834	1750621506386	Spremberger Straße 17	Am Lieskauer Weg 5	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
334	51.503605	51.503605	51.535732	14.519293	1751185104457	1751187020763	Mühlroser Straße 36b	Jahnring 13	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
335	51.536407	51.536407	51.389343	14.538902	1750354363341	1750355900288	Jahnring 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
336	51.471382	51.471382	51.534203	14.521786	1750431844326	1750434422235	Körnerplatz	Dorfstraße 106a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
337	51.528763	51.528763	51.412666	14.515212	1750351283071	1750354043081	Trebendorfer Weg 116c	Grotte	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
338	51.442024	51.442024	51.529022	14.529856	1751268122377	1751269780768	Körnerplatz	Rohner Weg 13b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
339	51.421085	51.421085	51.53536	14.535053	1751094158439	1751095263777	Dorfstraße 1	Werksweg 12	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
340	51.530617	51.530617	51.53861	14.514816	1751209072472	1751209990766	Am See 17	Hoyerswerdaer Straße 91	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
341	51.538887	51.538887	51.454567	14.727972	1751033092192	1751034013041	Zum Sportplatz 5	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
342	51.316944	51.316944	51.536407	14.524572	1750437520205	1750439283750	Körnerplatz	Jahnring 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
343	51.41034	51.41034	51.534447	14.526812	1750532332558	1750534852492	Brunnenweg 14b	Mulkwitzer Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
344	51.544353	51.544353	51.560326	14.587606	1750253125685	1750255061005	Friedensstraße 62	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
345	51.4575	51.4575	51.539795	14.538614	1750960359217	1750961483609	Körnerplatz	Strugaaue 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
346	51.579006	51.579006	51.545673	14.534669	1751165502270	1751167213909	Schulstraße 11	Spremberger Straße 17	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
347	51.465134	51.465134	51.540573	14.520827	1751020854582	1751023503953	Körnerplatz	Thälmann-Siedlung 25	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
348	51.569267	51.569267	51.541637	14.528906	1750687694947	1750690900312	Friedensweg 4	Lindenweg 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
349	51.53388	51.53388	51.406723	14.520038	1750576524292	1750579295488	Dorfstraße 105a	Rudolf Hünlich	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
350	51.438152	51.438152	51.541874	14.537528	1750781157442	1750783726106	Gudrun u. Wolfgang Boxberg	Friedensstraße 77a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
351	51.430683	51.430683	51.533173	14.529221	1750939606865	1750941782051	Körnerplatz	Mühlroser Straße 8a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
352	51.535065	51.535065	51.475975	14.516705	1750330154255	1750331995869	Siedlung - Sydlišćo	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
353	51.514595	51.514595	51.541874	14.537528	1750920355055	1750922891333	Skerbersdorfer Straße 104	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
354	51.49607	51.49607	51.540573	14.520827	1751294603237	1751296967256	Wiesenweg 5	Thälmann-Siedlung 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
355	51.52512	51.52512	51.5446	14.535595	1750272620738	1750275857042	Wiesengrund 9	Schleife - Slepo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
356	51.399406	51.399406	51.532936	14.519677	1751295590824	1751297433042	Körnerplatz	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
357	51.38905	51.38905	51.54269	14.530803	1750673647675	1750675178028	C6	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
358	51.50741	51.50741	51.53325	14.514113	1750262455060	1750265136173	Görlitzer Straße 40	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
359	51.534447	51.534447	51.389343	14.538902	1750400358246	1750402287131	Mulkwitzer Weg 10	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
360	51.441704	51.441704	51.528763	14.527925	1750517858585	1750520472183	Körnerplatz	Trebendorfer Weg 116c	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
361	51.36782	51.36782	51.535065	14.528915	1751088113475	1751089710222	Körnerplatz	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
362	51.54002	51.54002	51.358337	14.5623045	1750526323379	1750528180945	Thälmann-Siedlung 8	Restaurant Arche	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
363	51.45062	51.45062	51.541725	14.534854	1750644438192	1750647674300	Körnerplatz	Gemeindeamt	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
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
5	t	51.5570032	14.5965654	1750267261273	1750267861273	1750267261273	972000	653000		3	Körnerplatz	t
6	f	51.5338793	14.5202632	1750268514273	1750269114273	1750269114273	653000	1015000		3	Dorfstraße 105a	t
25	t	51.4532458	14.9006663	1750311311982	1750311911982	1750311311982	1498000	2268000		13	Körnerplatz	f
26	f	51.5292289	14.5391334	1750314179982	1750314779982	1750314779982	2268000	893000		13	Rohner Weg 3a	f
23	t	51.5225986	14.7178032	1750682562737	1750683162737	1750682562737	669000	1505000		12	Eichenweg 124	t
24	f	51.5342031	14.5217853	1750684667737	1750685267737	1750685267737	1505000	1007000		12	Dorfstraße 106a	t
38	f	51.5443525	14.5405083	1750408079155	1750408679155	1750408679155	959000	1622000		19	Friedensstraße 62	f
34	f	51.5152804	14.5871743	1750653172857	1750653772857	1750653772857	630000	525000		17	Körnerplatz	f
37	t	51.4965557	14.632122	1750406520155	1750407120155	1750406520155	92000	959000		19	Raddatz	f
41	t	51.5100497	14.6885074	1750844121194	1750844721194	1750844121194	627000	1539000		21	Körnerplatz	t
42	f	51.5312531	14.516953	1750846260194	1750846860194	1750846860194	1539000	1035000		21	Dorfstraße 103	t
19	t	51.5350649	14.5289157	1751089589339	1751090189339	1751089589339	946000	1597000		10	Siedlung - Sydlišćo	t
20	f	51.3515016	14.5985187	1751091786339	1751092386339	1751092386339	1597000	1488000		10	Straße der Jugend 62	t
47	t	51.5393992	14.5316092	1750751579832	1750752179832	1750751579832	939000	1818000		24	Strugaaue 2	t
48	f	51.5476309	14.7299436	1750753997832	1750754597832	1750754597832	1818000	1255000		24	Wehrinsel	t
72	f	51.5405733	14.520827	1750508497653	1750509097653	1750509097653	486000	1123000		36	Thälmann-Siedlung 25	f
69	t	51.4956087	14.8374543	1750729800000	1750730400000	1750729800000	964000	2022000		35	Körnerplatz	t
7	t	51.5305303	14.5320261	1750595571166	1750596171166	1750595571166	887000	777000		4	Rohner Weg 10	t
8	f	51.5679823	14.5854519	1750596948166	1750597548166	1750597548166	777000	1240000		4	Körnerplatz	t
39	t	51.3922386	14.6112847	1750448215910	1750448815910	1750448215910	1087000	1457000		20	Mühlgrabenweg 11	t
40	f	51.5286634	14.5366817	1750450272910	1750450872910	1750450872910	1457000	1036000		20	Rohner Weg 6	t
55	t	51.5290698	14.4788025	1751075979214	1751076579214	1751075979214	1291000	479000		28	Körnerplatz	t
56	f	51.5342917	14.5338773	1751077058214	1751077658214	1751077658214	479000	932000		28	Schleifer Straße 2	t
3	t	51.3872569	14.6321873	1750879538826	1750880138826	1750879538826	1591000	1740000		2	Körnerplatz	t
51	t	51.4297942	14.927655	1750436250962	1750436850962	1750436250962	1684000	2573000		26	Körnerplatz	t
52	f	51.5279047	14.5229428	1750439423962	1750440023962	1750440023962	2573000	1012000		26	Trebendorfer Weg 81	t
57	t	51.5344271	14.5295784	1750582215114	1750582815114	1750582215114	935000	2395000		29	Mühlroser Straße 3	t
58	f	51.4584259	14.7323951	1750585210114	1750585810114	1750585810114	2395000	1584000		29	Körnerplatz	t
13	t	51.4966469	14.6979787	1751007970825	1751008570825	1751007970825	439000	1270000		7	Am Walde 5	t
14	f	51.5290227	14.5298561	1751009840825	1751010440825	1751010440825	1270000	954000		7	Rohner Weg 13b	t
35	t	51.5319259	14.52021	1751105158735	1751105758735	1751105158735	1018000	1077000		18	Dorfstraße 80	t
36	f	51.3999074	14.5796563	1751106835735	1751107435735	1751107435735	1077000	984000		18	Thälmannstraße 5	t
45	t	51.4344475	14.63292	1751184275450	1751184875450	1751184275450	1823000	2305000		23	Körnerplatz	t
46	f	51.5443525	14.5405083	1751187180450	1751187780450	1751187780450	2305000	968000		23	Friedensstraße 62	t
11	t	51.5322939	14.5345323	1751305407916	1751306007916	1751305407916	983000	1097000		6	Reinert Ranch	t
12	f	51.5337707	14.6402118	1751307104916	1751307704916	1751307704916	1097000	756000		6	Eichenhügel	t
17	t	51.528762	14.5279248	1751139298580	1751139898580	1751139298580	911000	1286000		9	Trebendorfer Weg 116c	t
18	f	51.3749162	14.4867533	1751141184580	1751141784580	1751141784580	1286000	1216000		9	Körnerplatz	t
65	t	51.3443899	14.633519	1750904632240	1750905232240	1750904632240	1498000	1657000		33	Körnerplatz	t
66	f	51.5344271	14.5295784	1750906889240	1750907489240	1750907489240	1657000	995000		33	Mühlroser Straße 3	t
67	t	51.478477	14.9062781	1750677497116	1750678097116	1750677497116	1298000	2182000		34	Königshügel 5	t
68	f	51.5342031	14.5217853	1750680279116	1750680879116	1750680879116	2182000	1007000		34	Dorfstraße 106a	t
53	t	51.3720647	14.5699514	1750968324000	1750968924000	1750968324000	2390000	2676000		27	Körnerplatz	t
49	t	51.3418759	14.4936016	1750914197185	1750914797185	1750914197185	1598000	1798000		25	Körnerplatz	t
71	t	51.5054325	14.4818658	1750507797704	1750508011653	1750507411653	400000	486000		36	Mulkwitz Außenkippe	f
50	f	51.5426918	14.5308026	1750916595185	1750917195185	1750917195185	1798000	1088000		25	Hoyerswerdaer Straße 37	t
59	t	51.5400866	14.5128586	1751098852694	1751099452694	1751098852694	1094000	2746000		30	Hoyerswerdaer Straße 98	t
60	f	51.4348354	14.6431714	1751102198694	1751102798694	1751102798694	2746000	1343000		30	Körnerplatz	t
21	t	51.5338793	14.5202632	1750535170275	1750535770275	1750535170275	955000	1055000		11	Dorfstraße 105a	t
2	f	51.3690959	14.4911016	1751277982664	1751277995787	1751278582664	1400000	1258000		1	Körnerplatz	f
29	t	51.5277052	14.5242631	1751313322212	1751313922212	1751313322212	965000	1497000		15	Trebendorfer Weg 116b	t
33	t	51.5443525	14.5405083	1750651942857	1750652542857	1750651942857	197000	630000		17	Friedensstraße 62	f
30	f	51.3532067	14.6071363	1751315419212	1751316019212	1751316019212	1497000	1375000		15	Kriegerdenkmal	t
63	t	51.5292355	14.5213952	1750474684644	1750474684645	1750474684644	175000	223000		32	Gefallenendenkmale Rohne	f
16	f	51.4155678	14.6474292	1750766785979	1750767385979	1750767385979	1750000	896000		8	Körnerplatz	t
43	t	51.5048166	14.7430017	1751138731568	1751139331568	1751138731568	654000	1531000		22	Krauschwitzer Straße 4	t
44	f	51.5344465	14.5268116	1751140862568	1751141462568	1751141462568	1531000	999000		22	Mulkwitzer Weg 10	t
27	t	51.5277052	14.5242631	1750474169012	1750474769012	1750474169012	965000	1863000		14	Trebendorfer Weg 116b	t
28	f	51.3347642	14.6264482	1750476632012	1750477232012	1750477232012	1863000	1066000		14	Körnerplatz	t
15	t	51.5397943	14.5386138	1750764836671	1750765035979	1750764435979	177000	1750000		8	Strugaaue 37	t
9	t	51.3688353	14.6177504	1750786124375	1750786724375	1750786124375	1480000	1353000		5	Körnerplatz	t
1	t	51.5456749	14.5346691	1751276492508	1751276582664	1751275982664	195000	1400000		1	Spremberger Straße 17	f
54	f	51.5400192	14.5240712	1750971600000	1750972200000	1750972200000	2676000	1122000		27	Thälmann-Siedlung 8	t
61	t	51.3573906	14.5244262	1750953857910	1750954323909	1750953857910	1536000	324000		31	Körnerplatz	f
32	f	51.4959292	14.5236633	1750783287115	1750783887115	1750783887115	787000	757000		16	Kohlebahnweg 87	t
31	t	51.5388861	14.5189616	1750781900115	1750782500115	1750781900115	197000	787000		16	Zum Sportplatz 5	t
70	f	51.5343123	14.5136158	1750732422000	1750733022000	1750733022000	2022000	1181000		35	Forstweg 78a	t
79	t	51.5341111	14.5351491	1750528581304	1750529181304	1750528581304	862000	615000		40	Schleifer Straße 3	f
80	f	51.5334503	14.6138292	1750529796304	1750530396304	1750530396304	615000	753000		40	Körnerplatz	f
81	t	51.5443525	14.5405083	1750619916550	1750620516550	1750619916550	907000	1197000		41	Friedensstraße 62	f
82	f	51.4184245	14.5391254	1750621713550	1750622313550	1750622313550	1197000	1289000		41	Körnerplatz	f
87	t	51.5433114	14.5309437	1750405252929	1750405852929	1750405252929	987000	1154000		44	Hoyerswerdaer Straße 33	t
88	f	51.3999074	14.5796563	1750407006929	1750407606929	1750407606929	1154000	984000		44	Thälmannstraße 5	t
4	f	51.5292355	14.5213952	1750881878826	1750882478826	1750882478826	1740000	1077000		2	Gefallenendenkmale Rohne	t
95	t	51.5360245	14.5286573	1750496672027	1750497272027	1750496672027	921000	3164000		48	Friedensstraße 1	f
101	t	51.5200641	14.5659281	1750832403190	1750833003190	1750832403190	545000	513000		51	Löschwasserentnahmestelle	f
102	f	51.5322939	14.5345323	1750833516190	1750834116190	1750834116190	513000	1043000		51	Reinert Ranch	f
105	t	51.5302251	14.5252029	1751173720986	1751174320986	1751173720986	1114000	1267000		53	Tischlereiweg 113b	f
106	f	51.5075368	14.6573233	1751175587986	1751176187986	1751176187986	1267000	443000		53	Braunsteichweg 39	f
85	t	51.5400192	14.5240712	1750187845079	1750188445079	1750187845079	1062000	1526000		43	Thälmann-Siedlung 8	t
86	f	51.44107	14.6828135	1750189971079	1750190571079	1750190571079	1526000	504000		43	Körnerplatz	t
115	t	51.5433114	14.5309437	1750931708510	1750932308510	1750931708510	987000	2595000		58	Hoyerswerdaer Straße 33	f
116	f	51.4615757	14.9560208	1750934903510	1750935503510	1750935503510	2595000	1740000		58	Körnerplatz	f
83	t	51.5302251	14.5252029	1751022020196	1751022620196	1751022020196	1114000	1057000		42	Tischlereiweg 113b	t
84	f	51.5220316	14.6131422	1751023677196	1751024277196	1751024277196	1057000	639000		42	An der Philippine 28	t
104	f	51.3243826	14.5995512	1751110061155	1751110125930	1751110125930	727000	1374000		52	Körnerplatz	f
117	t	51.4136066	14.6653959	1750560060633	1750560660633	1750560060633	813000	1783000		59	Körnerplatz	f
118	f	51.5302251	14.5252029	1750562443633	1750563043633	1750563043633	1783000	1174000		59	Tischlereiweg 113b	f
123	t	51.4991522	14.6139573	1750817223200	1750817823200	1750817223200	225000	934000		62	Lausitz	f
124	f	51.5416387	14.5289058	1750818757200	1750819357200	1750819357200	934000	1037000		62	Lindenweg 20	f
127	t	51.535357	14.5350536	1750189410960	1750190010960	1750189410960	926000	2111000		64	Werksweg 12	f
128	f	51.3569153	14.4928046	1750192121960	1750192721960	1750192721960	2111000	1995000		64	Körnerplatz	f
140	f	51.4492815	14.6127289	1750883054222	1750883654222	1750883654222	2241000	1777000		70	Körnerplatz	f
119	t	51.5277052	14.5242631	1751088399707	1751088999707	1751088399707	965000	439000		60	Trebendorfer Weg 116b	t
120	f	51.5088072	14.5278851	1751089438707	1751090038707	1751090038707	439000	1358000		60	Körnerplatz	t
133	t	51.5312531	14.516953	1750691567464	1750692167464	1750691567464	975000	910000		67	Dorfstraße 103	t
76	f	51.4830445	14.6900076	1751019204821	1751019804821	1751019804821	1641000	914000		38	Körnerplatz	t
134	f	51.522312	14.6242412	1750693077464	1750693677464	1750693677464	910000	583000		67	Kromlauer Weg 70	t
109	t	51.4736944	14.9126396	1750397092814	1750397692814	1750397092814	820000	2086000		55	Körnerplatz	t
89	t	51.4651482	14.769476	1750864364238	1750864964238	1750864364238	975000	1852000		45	Körnerplatz	t
125	t	51.5344465	14.5268116	1750337387333	1750337987333	1750337387333	939000	1095000		63	Mulkwitzer Weg 10	t
126	f	51.4862006	14.6428515	1750339082333	1750339682333	1750339682333	1095000	196000		63	Körnerplatz	t
135	t	51.5433114	14.5309437	1751375459956	1751376059956	1751375459956	987000	181000		68	Hoyerswerdaer Straße 33	t
110	f	51.5292289	14.5391334	1750399778814	1750400378814	1750400378814	2086000	893000		55	Rohner Weg 3a	t
136	f	51.538412	14.5250691	1751376240956	1751376840956	1751376840956	181000	1026000		68	Jahnring 21	t
137	t	51.4945052	14.7227536	1751052122526	1751052722526	1751052122526	529000	1534000		69	Kaupener Straße 5	t
138	f	51.5386074	14.5148166	1751054256526	1751054856526	1751054856526	1534000	1121000		69	Hoyerswerdaer Straße 91	t
107	t	51.4745329	14.7840515	1750251292900	1750251292901	1750251292900	1302000	2136000		54	Körnerplatz	f
99	t	51.5416387	14.5289058	1751356853214	1751357453214	1751356853214	977000	857000		50	Lindenweg 20	t
100	f	51.5364723	14.6490149	1751358310214	1751358910214	1751358910214	857000	719000		50	Gablenz Waldrand	t
129	t	51.533173	14.529221	1750775597911	1750776197911	1750775597911	952000	1484000		65	Mühlroser Straße 8a	t
130	f	51.5511707	14.7134208	1750777681911	1750778281911	1750778281911	1484000	990000		65	Berliner Chaussee 12	t
121	t	51.3229373	14.5619758	1750954754017	1750955354017	1750954754017	2398000	2674000		61	Körnerplatz	t
122	f	51.5301599	14.5247083	1750958028017	1750958628017	1750958628017	2674000	1155000		61	Tischlereiweg 113b	t
103	t	51.5433114	14.5309437	1751106693930	1751107293930	1751106693930	987000	1658000		52	Hoyerswerdaer Straße 33	f
90	f	51.5344465	14.5268116	1750866816238	1750866816239	1750867416238	1852000	349000		45	Mulkwitzer Weg 10	t
139	t	51.5399955	14.5160315	1750880535436	1750880813222	1750880213222	251000	2241000		70	Hoyerswerdaer Straße 90	f
108	f	51.5405733	14.520827	1750254705901	1750254794900	1750254794900	726000	1123000		54	Thälmann-Siedlung 25	f
96	f	51.4525182	14.6553684	1750500436027	1750500722077	1750501036027	3164000	2560000		48	Körnerplatz	f
73	t	51.5323924	14.4823163	1750791749872	1750792349872	1750791749872	469000	470000		37	Körnerplatz	t
91	t	51.3611789	14.5322164	1751115870424	1751116470424	1751115870424	1419000	1653000		46	Körnerplatz	t
92	f	51.5302251	14.5252029	1751118123424	1751118723424	1751118723424	1653000	1174000		46	Tischlereiweg 113b	t
131	t	51.4297069	14.6697606	1750565369920	1750565969920	1750565369920	575000	1395000		66	Körnerplatz	t
132	f	51.5360245	14.5286573	1750567364920	1750567964920	1750567964920	1395000	981000		66	Friedensstraße 1	t
74	f	51.528762	14.5279248	1750792819872	1750793419872	1750793419872	470000	208000		37	Trebendorfer Weg 116c	t
113	t	51.4567824	14.8916755	1751185798560	1751185798561	1751185798560	1467000	2356000		57	Körnerplatz	t
75	t	51.5338373	14.5364242	1751016963821	1751017563821	1751016963821	887000	1641000		38	Schleifer Straße 5	t
10	f	51.538412	14.5250691	1750788077375	1750788677375	1750788677375	1353000	120000		5	Jahnring 21	t
78	f	51.4847396	14.7949326	1750395064217	1750395664217	1750395664217	2023000	2621000		39	Körnerplatz	t
111	t	51.5418779	14.7131259	1750516616682	1750516616683	1750516295525	1777000	1591000		56	Weinbergweg 38	f
77	t	51.5286634	14.5366817	1750392441217	1750393041217	1750392441217	369000	2023000		39	Rohner Weg 6	t
143	t	51.3879586	14.5866627	1750911695919	1750912295919	1750911695919	1581000	1689000		72	Körnerplatz	f
150	f	51.5342031	14.5217853	1750233556883	1750234156883	1750234156883	2094000	1007000		75	Dorfstraße 106a	f
153	t	51.5301599	14.5247083	1751047033259	1751047633259	1751047033259	1095000	2099000		77	Tischlereiweg 113b	f
154	f	51.4224273	14.5709291	1751049732259	1751050332259	1751050332259	2099000	1691000		77	Boxberg Block P	f
93	t	51.5344271	14.5295784	1751028517350	1751029117350	1751028517350	935000	823000		47	Mühlroser Straße 3	t
94	f	51.5081833	14.6275876	1751029940350	1751030540350	1751030540350	823000	331000		47	Jahnstraße 94	t
155	t	51.3371817	14.5148276	1750566503773	1750567103773	1750566503773	1603000	1732000		78	Körnerplatz	t
156	f	51.538412	14.5250691	1750568835773	1750569435773	1750569435773	1732000	1026000		78	Jahnring 21	t
141	t	51.3652514	14.5136475	1750444589313	1750445189313	1750444589313	1363000	1447000		71	Hauptstraße 1	t
142	f	51.5360245	14.5286573	1750446636313	1750447236313	1750447236313	1447000	981000		71	Friedensstraße 1	t
162	f	51.4622509	14.931924	1750602944915	1750603544915	1750603544915	2502000	1504000		81	Körnerplatz	f
166	f	51.533173	14.529221	1750507397704	1750507397704	1750507397704	1324000	400000		83	Mühlroser Straße 8a	f
157	t	51.5069356	14.6860662	1750824327370	1750824927370	1750824327370	549000	1420000		79	Körnerplatz	t
22	f	51.4904154	14.627253	1750536825275	1750537425275	1750537425275	1055000	140000		11	Stele und Baggerschaufel	t
189	t	51.5342917	14.5338773	1750903825302	1750904425302	1750903825302	872000	1291000		95	Schleifer Straße 2	f
190	f	51.4982519	14.7227396	1750905716302	1750906316302	1750906316302	1291000	543000		95	Am Hammerlugk 3	f
191	t	51.5433114	14.5309437	1750847097561	1750847697561	1750847097561	987000	2182000		96	Hoyerswerdaer Straße 33	f
195	t	51.5341111	14.5351491	1750273891156	1750274491156	1750273891156	862000	1918000		98	Schleifer Straße 3	f
196	f	51.3420085	14.5619432	1750276409156	1750277009156	1750277009156	1918000	1786000		98	Körnerplatz	f
161	t	51.5343123	14.5136158	1750599842915	1750600442915	1750599842915	517000	2502000		81	Forstweg 78a	f
202	f	51.5536653	14.5338599	1750598979338	1750599325915	1750599325915	302000	517000		101	Körnerplatz	f
203	t	51.4659413	14.6928302	1751248293317	1751248893317	1751248293317	349000	1256000		102	Körnerplatz	f
179	t	51.5399955	14.5160315	1751053106982	1751053706982	1751053106982	1058000	1761000		90	Hoyerswerdaer Straße 90	t
180	f	51.3597408	14.5381044	1751055467982	1751056067982	1751056067982	1761000	1631000		90	Körnerplatz	t
206	f	51.5077448	14.6444804	1750927252467	1750927852467	1750927852467	986000	328000		103	NKD	f
171	t	51.5517516	14.6340534	1751269115997	1751269715997	1751269115997	985000	1032000		86	Körnerplatz	t
147	t	51.5400866	14.5128586	1751011212161	1751011812161	1751011212161	1094000	571000		74	Hoyerswerdaer Straße 98	t
148	f	51.5600258	14.5546788	1751012383161	1751012983161	1751012983161	571000	1159000		74	Körnerplatz	t
177	t	51.533173	14.529221	1750579482675	1750580082675	1750579482675	952000	1468000		89	Mühlroser Straße 8a	t
192	f	51.3538706	14.4878188	1750849879561	1750849879562	1750850479561	2182000	2432000		96	Körnerplatz	f
178	f	51.3871444	14.6551437	1750581550675	1750582150675	1750582150675	1468000	1353000		89	Schadendorfer Weg 3	t
208	f	51.3743446	14.5733566	1751218400046	1751219000046	1751219000046	2812000	2614000		104	Körnerplatz	t
145	t	51.5332904	14.5729768	1750277322733	1750277922733	1750277322733	676000	575000		73	Station 9	f
201	t	51.5416387	14.5289058	1750598077338	1750598677338	1750598077338	696000	302000		101	Lindenweg 20	f
144	f	51.5340052	14.5217744	1750913984919	1750914584919	1750914584919	1689000	113000		72	Dorfstraße 106a	f
205	t	51.5344465	14.5268116	1750925666467	1750926266467	1750925666467	102000	986000		103	Mulkwitzer Weg 10	f
197	t	51.5397309	14.5335292	1750686387906	1750686987906	1750686387906	992000	1485000		99	NORMA	t
198	f	51.5087137	14.7329097	1750688472906	1750689072906	1750689072906	1485000	617000		99	Krauschwitzer Straße 24	t
168	f	51.3590998	14.6534461	1751300595164	1751301195164	1751301195164	2531000	2489000		84	Körnerplatz	t
167	t	51.5312432	14.5115818	1751298064163	1751298064164	1751297464164	604000	2531000		84	Mühlweg 5b	t
158	f	51.5456749	14.5346691	1750826347370	1750826947370	1750826947370	1420000	1005000		79	Spremberger Straße 17	t
175	t	51.406948	14.519467	1751040252460	1751040852460	1751040252460	1224000	1296000		88	Hünlich Hügel	t
176	f	51.5353088	14.5289849	1751042148460	1751042748460	1751042748460	1296000	1000000		88	Siedlung - Sydlišćo	t
173	t	51.5338793	14.5202632	1750866926239	1750866926239	1750866926239	110000	926000		87	Dorfstraße 105a	t
149	t	51.3033464	14.6170254	1750230862883	1750231462883	1750230862883	2291000	2094000		75	Körnerplatz	f
182	f	51.536356	14.5290886	1751220738485	1751221338485	1751221338485	779000	978000		91	Friedensstraße 1	t
181	t	51.5371756	14.64237	1751219359485	1751219959485	1751219359485	821000	779000		91	Rakotzbrücke	t
204	f	51.5305303	14.5320261	1751250149317	1751250749317	1751250749317	1256000	261000		102	Rohner Weg 10	f
159	t	51.5302251	14.5252029	1750837993959	1750838593959	1750837993959	1114000	1129000		80	Tischlereiweg 113b	t
152	f	51.480245	14.7767609	1751304020685	1751304156844	1751304620685	2144000	2318000		76	Körnerplatz	t
151	t	51.5342031	14.5217853	1751301276685	1751301876685	1751301276685	203000	2144000		76	Dorfstraße 106a	t
163	t	51.332332	14.4886606	1750480342262	1750480942262	1750480342262	1071000	1863000		82	Feldteich	f
164	f	51.5292355	14.5213952	1750483293261	1750483293262	1750483293262	291000	1077000		82	Gefallenendenkmale Rohne	f
199	t	51.3408812	14.4856542	1750521929122	1750522207834	1750521639180	2654000	1470000		100	Rokotschin	f
169	t	51.5393992	14.5316092	1751296349237	1751296796163	1751296196163	194000	664000		85	Strugaaue 2	f
146	f	51.5443525	14.5405083	1750278497733	1750278862291	1750279097733	575000	403000		73	Friedensstraße 62	f
165	t	51.3661679	14.4977355	1750505592077	1750506073704	1750505473704	2560000	1324000		83	Hauptstraße 33	f
184	f	51.5397943	14.5386138	1751276312508	1751276312508	1751276312508	2340000	180000		92	Strugaaue 37	t
200	f	51.5397309	14.5335292	1750524587834	1750524897180	1750524897180	219000	1052000		100	NORMA	f
160	f	51.4036164	14.5608918	1750839722959	1750840322959	1750840322959	1129000	955000		80	Körnerplatz	t
209	t	51.535357	14.5350536	1751261091129	1751261172216	1751260572216	267000	1219000		105	Werksweg 12	f
174	f	51.4160738	14.5268735	1750867852239	1750868452239	1750868452239	926000	1123000		87	Merzdorfer Straße 38	t
183	t	51.4554602	14.8286936	1751273912875	1751273972508	1751273372508	2356000	2340000		92	Körnerplatz	t
193	t	51.5338373	14.5364242	1750434267326	1750434656319	1750434056319	157000	1703000		97	Schleifer Straße 5	f
194	f	51.3338013	14.5035584	1750436359319	1750436795205	1750436959319	1703000	725000		97	Hälterteich	f
188	f	51.5302251	14.5252029	1750692365550	1750692365551	1750692965550	321000	289000		94	Tischlereiweg 113b	f
187	t	51.5456497	14.723616	1750690025550	1750690479550	1750690025550	655000	1565000		94	Kirchplatz 7	f
210	f	51.4837802	14.5316818	1751262391216	1751262991216	1751262991216	1219000	2036000		105	Körnerplatz	f
217	t	51.5446031	14.5355952	1750319619414	1750320219414	1750319619414	1007000	1409000		109	Schleife - Slepo	f
218	f	51.3804046	14.6156514	1750321628414	1750322228414	1750322228414	1409000	1144000		109	Klittener Straße 14	f
219	t	51.5149346	14.5999361	1750654888679	1750655488679	1750654888679	818000	1190000		110	Körnerplatz	f
220	f	51.5344465	14.5268116	1750656678679	1750657278679	1750657278679	1190000	999000		110	Mulkwitzer Weg 10	f
215	t	51.5341111	14.5351491	1750785129563	1750785729563	1750785129563	862000	1919000		108	Schleifer Straße 3	t
216	f	51.3210288	14.6276886	1750787648563	1750788248563	1750788248563	1919000	1787000		108	Förstgener Straße 6	t
172	f	51.5301599	14.5247083	1751270747997	1751271347997	1751271347997	1032000	1155000		86	Tischlereiweg 113b	t
235	t	51.5154746	14.611478	1750865306351	1750865906351	1750865306351	393000	622000		118	Auensiedlung 4	f
236	f	51.5456749	14.5346691	1750866528351	1750867128351	1750867128351	622000	1005000		118	Spremberger Straße 17	f
239	t	51.5393992	14.5316092	1750513102682	1750513702682	1750513102682	939000	1137000		120	Strugaaue 2	f
240	f	51.4095539	14.5191427	1750514839682	1750514839682	1750514839682	1137000	1777000		120	Zulaufanlage Spree - Lohsa II	f
207	t	51.5435594	14.5297765	1751215129889	1751215588046	1751214988046	245000	2812000		104	Alter Postweg 11	t
267	t	51.5342031	14.5217853	1750879438196	1750880038196	1750879438196	947000	1144000		134	Dorfstraße 106a	t
243	t	51.5305303	14.5320261	1751336645011	1751337245011	1751336645011	887000	1478000		122	Rohner Weg 10	f
244	f	51.5361935	14.7240704	1751338723011	1751339323011	1751339323011	1478000	881000		122	Bautzener Straße 15	f
253	t	51.5743795	14.7197938	1751038294212	1751038894212	1751038294212	1516000	2045000		127	Schulstraße 26	f
276	f	51.5615182	14.5816849	1750303493982	1750304093982	1750304093982	715000	1382000		138	Körnerplatz	f
263	t	51.5418744	14.537528	1750586699715	1750587299715	1750586699715	940000	2287000		132	Friedensstraße 77a	f
231	t	51.538412	14.5250691	1751170886667	1751171486667	1751170886667	966000	1737000		116	Jahnring 21	t
232	f	51.523383	14.7454683	1751173223667	1751173823667	1751173823667	1737000	894000		116	Im Tale 13	t
269	t	51.4747499	14.7174983	1750645829389	1750646429389	1750645829389	804000	1763000		135	Körnerplatz	f
270	f	51.5417871	14.524831	1750648192389	1750648792389	1750648792389	1763000	197000		135	Hoyerswerdaer Straße 50	f
213	t	51.4024298	14.5437325	1750420707689	1750421307689	1750420707689	914000	1002000		107	Körnerplatz	t
214	f	51.5292355	14.5213952	1750422309689	1750422909689	1750422909689	1002000	1077000		107	Gefallenendenkmale Rohne	t
277	t	51.5344271	14.5295784	1750915017824	1750915617824	1750915017824	113000	1548000		139	Mühlroser Straße 3	f
278	f	51.4175837	14.6617439	1750917165824	1750917765824	1750917765824	1548000	774000		139	Körnerplatz	f
268	f	51.4828139	14.6546554	1750881182196	1750881782196	1750881782196	1144000	237000		134	Körnerplatz	t
271	t	51.5319259	14.52021	1750598326229	1750598926229	1750598326229	1018000	1699000		136	Dorfstraße 80	t
222	f	51.528762	14.5279248	1751018819210	1751019419210	1751019419210	1517000	305000		111	Trebendorfer Weg 116c	f
241	t	51.5342917	14.5338773	1750250127105	1750250727105	1750250127105	872000	1973000		121	Schleifer Straße 2	t
242	f	51.4299222	14.7311601	1750252700105	1750253300105	1750253300105	1973000	1225000		121	Körnerplatz	t
224	f	51.5338373	14.5364242	1751214884889	1751214884889	1751214884889	1344000	910000		112	Schleifer Straße 5	t
223	t	51.3647865	14.4905975	1751212940889	1751213540889	1751212940889	1444000	1344000		112	Körnerplatz	t
249	t	51.5322939	14.5345323	1750683087035	1750683687035	1750683087035	983000	2655000		125	Reinert Ranch	t
211	t	51.5329343	14.5196775	1750418184526	1750418784526	1750418184526	959000	2194000		106	Dorfstraße 106	t
212	f	51.478477	14.9062781	1750420978526	1750421578526	1750421578526	2194000	1358000		106	Königshügel 5	t
233	t	51.5152804	14.5871743	1750238414166	1750239014166	1750238414166	465000	662000		117	Körnerplatz	t
234	f	51.5292355	14.5213952	1750239676166	1750240276166	1750240276166	662000	1077000		117	Gefallenendenkmale Rohne	t
256	f	51.3355277	14.5008743	1750228311140	1750228911140	1750228911140	1706000	914000		128	Eichenallee 25a	t
255	t	51.5388861	14.5189616	1750226005140	1750226605140	1750226005140	337000	1706000		128	Zum Sportplatz 5	t
227	t	51.5343123	14.5136158	1750999165801	1750999765801	1750999165801	1121000	2079000		114	Forstweg 78a	t
228	f	51.3751032	14.5100156	1751001844801	1751002444801	1751002444801	2079000	2013000		114	Hundestrand (dog's beach)	t
251	t	51.5353088	14.5289849	1750965313711	1750965913711	1750965313711	940000	2316000		126	Siedlung - Sydlišćo	t
252	f	51.3269836	14.6436683	1750968229711	1750968829711	1750968829711	2316000	2213000		126	Körnerplatz	t
247	t	51.4474711	14.7242936	1751215101611	1751215701611	1751215101611	1891000	2784000		124	FStR 2	t
248	f	51.5338793	14.5202632	1751218485611	1751218538485	1751218538485	2784000	821000		124	Dorfstraße 105a	t
257	t	51.528584	14.5778809	1750261752001	1750262352001	1750261752001	713000	632000		129	Am See 3	t
258	f	51.5417871	14.524831	1750262984001	1750263584001	1750263584001	632000	1081000		129	Hoyerswerdaer Straße 50	t
265	t	51.5220779	14.7303482	1750654516008	1750655116008	1750654516008	783000	1734000		133	Rothenburger Straße 38	t
266	f	51.5292355	14.5213952	1750656850008	1750657450008	1750657450008	1734000	1077000		133	Gefallenendenkmale Rohne	t
246	f	51.5456749	14.5346691	1750951202373	1750951802373	1750951802373	1893000	1608000		123	Spremberger Straße 17	t
245	t	51.3407172	14.5485383	1750948709373	1750949309373	1750948709373	1821000	1893000		123	ehem. Lieskauer Teich	t
250	f	51.4536668	14.6218683	1750686342035	1750686942035	1750686942035	2655000	2138000		125	Körnerplatz	t
225	t	51.5388861	14.5189616	1751189884768	1751190484768	1751189884768	281000	1663000		113	Zum Sportplatz 5	t
259	t	51.4639528	14.6013636	1751195141768	1751195193355	1751195141768	2394000	2990000		130	Körnerplatz	t
272	f	51.3687208	14.5188148	1750600625229	1750601225229	1750601225229	1699000	1666000		136	2.3	t
275	t	51.5400866	14.5128586	1750302178982	1750302778982	1750302178982	282000	715000		138	Hoyerswerdaer Straße 98	f
238	f	51.5416387	14.5289058	1750395602110	1750395959966	1750396202110	2121000	302000		119	Lindenweg 20	f
254	f	51.5416387	14.5289058	1751040939212	1751041166054	1751041539212	2045000	166000		127	Lindenweg 20	f
230	f	51.5433114	14.5309437	1751271556875	1751271556875	1751271556875	1038000	195000		115	Hoyerswerdaer Straße 33	f
264	f	51.4516936	14.6076696	1750589586715	1750589983365	1750590186715	2287000	2229000		132	Körnerplatz	f
229	t	51.5272056	14.6569	1751270518874	1751270518875	1751269918875	1139000	1038000		115	Dorfstraße 1	f
221	t	51.3667974	14.5171523	1751016702210	1751017302210	1751016702210	3112000	1517000		111	Spreeschlößchen	f
273	t	51.5388861	14.5189616	1751279383147	1751279383147	1751279383147	1357000	3351000		137	Zum Sportplatz 5	t
274	f	51.4522918	14.6333772	1751282734147	1751283334147	1751283334147	3351000	2918000		137	Körnerplatz	t
283	t	51.3444663	14.5017947	1750954647909	1750954647909	1750954647909	324000	1614000		142	Körnerplatz	f
284	f	51.5416387	14.5289058	1750956261909	1750956261909	1750956261909	1614000	328000		142	Lindenweg 20	f
288	f	51.4999172	14.713628	1751025405968	1751026005968	1751026005968	1514000	528000		144	Finkensteg 1	f
289	t	51.5343123	14.5136158	1750921002071	1750921602071	1750921002071	1121000	1068000		145	Forstweg 78a	f
290	f	51.5099892	14.6333986	1750922670071	1750923270071	1750923270071	1068000	390000		145	Jahnstraße 52c	f
293	t	51.4869528	14.7430081	1750530799770	1750531399770	1750530799770	1233000	2163000		147	Körnerplatz	f
294	f	51.5397309	14.5335292	1750533562770	1750534162770	1750534162770	2163000	1052000		147	NORMA	f
295	t	51.5397309	14.5335292	1750825028379	1750825628379	1750825028379	992000	1664000		148	NORMA	f
296	f	51.3525933	14.5872166	1750827292379	1750827892379	1750827892379	1664000	1509000		148	Ernst-Thälmann-Straße 360	f
301	t	51.4707431	14.8885298	1751208566038	1751209166038	1751208566038	1272000	2042000		151	Körnerplatz	f
303	t	51.5388861	14.5189616	1750489069129	1750489669129	1750489069129	1027000	989000		152	Zum Sportplatz 5	f
304	f	51.5017365	14.626304	1750490658129	1750491258129	1750491258129	989000	247000		152	Forstweg 18	f
305	t	51.5332486	14.5141138	1750605921460	1750606521460	1750605921460	1041000	1425000		153	Mühlweg 5b	f
306	f	51.3897709	14.6522716	1750607946460	1750608546460	1750608546460	1425000	1363000		153	Körnerplatz	f
309	t	51.5329343	14.5196775	1750432764371	1750433364371	1750432764371	959000	2535000		155	Dorfstraße 106	f
310	f	51.5540195	14.6845789	1750438015532	1750438015532	1750438015532	1906000	1229000		155	Körnerplatz	f
98	f	51.5344465	14.5268116	1750439244532	1750439244533	1750439244533	1229000	999000		49	Mulkwitzer Weg 10	f
97	t	51.4442614	14.9237641	1750435899371	1750436109532	1750435529533	2535000	1906000		49	Körnerplatz	f
311	t	51.5416387	14.5289058	1750189872640	1750190472640	1750189872640	977000	1088000		156	Lindenweg 20	f
313	t	51.4492768	14.5083326	1750305696328	1750306296328	1750305696328	1382000	938000		157	Körnerplatz	f
314	f	51.538412	14.5250691	1750307234328	1750307834328	1750307834328	938000	1026000		157	Jahnring 21	f
316	f	51.4957987	14.8020445	1751192360935	1751192960935	1751192960935	1914000	1033000		158	Zur Tanne 58	f
317	t	51.3569153	14.4928046	1750905553242	1750906153242	1750905553242	1935000	1978000		159	Körnerplatz	f
318	f	51.5338793	14.5202632	1750908131242	1750908731242	1750908731242	1978000	1015000		159	Dorfstraße 105a	f
320	f	51.3881113	14.6047754	1750614503113	1750615103113	1750615103113	1251000	1117000		160	Rietschener Straße 6a	f
307	t	51.4865406	14.4795294	1750850139038	1750850739038	1750850139038	1333000	585000		154	Körnerplatz	t
308	f	51.5417871	14.524831	1750851324038	1750851924038	1750851924038	585000	1081000		154	Hoyerswerdaer Straße 50	t
291	t	51.5322939	14.5345323	1751227606950	1751228206950	1751227606950	983000	541000		146	Reinert Ranch	t
292	f	51.5030684	14.4751476	1751228747950	1751229347950	1751229347950	541000	1291000		146	Kiesbagger	t
323	t	51.5397309	14.5335292	1751349972551	1751350572551	1751349972551	992000	1736000		162	NORMA	f
324	f	51.3303024	14.4996563	1751352308551	1751352908551	1751352908551	1736000	1641000		162	Oberteich Mönau	f
302	f	51.5292289	14.5391334	1751211208038	1751211496889	1751211496889	2042000	893000		151	Rohner Weg 3a	f
340	f	51.4944768	14.6490131	1751092746148	1751093346148	1751093346148	1077000	316000		170	Gartensparte Sonnenschein.	f
341	t	51.5305303	14.5320261	1750944503143	1750945103143	1750944503143	887000	1622000		171	Rohner Weg 10	f
342	f	51.3777392	14.6485841	1750946725143	1750947325143	1750947325143	1622000	1449000		171	Körnerplatz	f
279	t	51.5400866	14.5128586	1750578103978	1750578703978	1750578103978	1094000	1450000		140	Hoyerswerdaer Straße 98	t
319	t	51.5353088	14.5289849	1750612652113	1750613252113	1750612652113	1729000	1251000		160	Siedlung - Sydlišćo	f
299	t	51.536356	14.5290886	1751137584336	1751138184336	1751137584336	918000	1122000		150	Friedensstraße 1	t
297	t	51.5416387	14.5289058	1750388862423	1750389462423	1750388862423	977000	1923000		149	Lindenweg 20	t
298	f	51.3643733	14.4717007	1750391385423	1750391879110	1750391879110	1923000	1002000		149	Rotdornallee 32	t
237	t	51.3545262	14.4878931	1750392881110	1750393481110	1750392881110	1981000	2121000		119	Körnerplatz	f
315	t	51.5364085	14.524572	1751189846935	1751190446935	1751189846935	237000	1914000		158	Jahnring 5b	f
260	f	51.5277052	14.5242631	1751198183355	1751198783355	1751198783355	2990000	1025000		130	Trebendorfer Weg 116b	t
327	t	51.5341111	14.5351491	1751291686768	1751292286768	1751291686768	862000	1139000		164	Schleifer Straße 3	t
328	f	51.3996098	14.5879542	1751293425768	1751294025768	1751294025768	1139000	786000		164	Straße der Freundschaft 26	t
300	f	51.418717	14.5843492	1751139306336	1751139906336	1751139906336	1122000	960000		150	Boxberg Kraftwerk	t
321	t	51.459253	14.8196006	1750259979203	1750260579203	1750259979203	1468000	2316000		161	Körnerplatz	t
322	f	51.528762	14.5279248	1750262895203	1750263495203	1750263495203	2316000	971000		161	Trebendorfer Weg 116c	t
335	t	51.5350649	14.5289157	1751359003425	1751359603425	1751359003425	946000	1248000		168	Siedlung - Sydlišćo	t
329	t	51.5312531	14.516953	1750249709576	1750250309576	1750249709576	975000	1896000		165	Dorfstraße 103	t
334	f	51.5430823	14.6585674	1750797531572	1750798131572	1750798131572	1143000	781000		167	Körnerplatz	t
331	t	51.4108944	14.6075087	1750345663750	1750346263750	1750345663750	1766000	1793000		166	Körnerplatz	f
226	f	51.4241256	14.6861564	1751192147768	1751192747768	1751192747768	1663000	828000		113	Körnerplatz	t
336	f	51.5356475	14.6929038	1751360851425	1751361451425	1751361451425	1248000	737000		168	Eilandweg 15	t
343	t	51.5343123	14.5136158	1751306474844	1751306474844	1751306474844	269000	242000		172	Forstweg 78a	f
333	t	51.538412	14.5250691	1750795788572	1750796388572	1750795788572	757000	1143000		167	Jahnring 21	t
286	f	51.5004574	14.6324384	1751015858031	1751016076821	1751016076821	965000	235000		143	Schweigstraße 23	t
285	t	51.535357	14.5350536	1751014293031	1751014893031	1751014293031	267000	965000		143	Werksweg 12	t
325	t	51.5388861	14.5189616	1751181089351	1751181689351	1751181089351	1027000	309000		163	Zum Sportplatz 5	t
326	f	51.5389164	14.5450397	1751181998351	1751182598351	1751182598351	309000	316000		163	Am Großteich 3	t
312	f	51.5040503	14.6440753	1750191560640	1750191560641	1750192160640	1088000	1030000		156	Kleingartensparte Reichsban.	f
338	f	51.528762	14.5279248	1750946411970	1750946888373	1750946888373	1394000	1536000		169	Trebendorfer Weg 116c	f
330	f	51.3220639	14.6336592	1750252205576	1750252805576	1750252805576	1896000	1879000		165	Im Erlengrund 2	t
339	t	51.5360245	14.5286573	1751091069148	1751091669148	1751091069148	365000	1077000		170	Friedensstraße 1	f
62	f	51.5343123	14.5136158	1750956589909	1750956589910	1750956589910	328000	3076000		31	Forstweg 78a	f
337	t	51.5267372	14.7081132	1750944417970	1750945017970	1750944417970	1402000	1394000		169	Lange Straße 19	f
287	t	51.5302251	14.5252029	1751023891967	1751023891968	1751023291968	407000	1514000		144	Tischlereiweg 113b	f
344	f	51.5338793	14.5202632	1751306716844	1751307316844	1751307316844	242000	1015000		172	Dorfstraße 105a	f
170	f	51.5059576	14.5102353	1751297460163	1751297460163	1751297460163	664000	646000		85	Mühlroser Straße 36b	f
345	t	51.5360245	14.5286573	1751301308953	1751301908953	1751301308953	646000	1709000		173	Friedensstraße 1	f
346	f	51.5284399	14.7315282	1751303617953	1751304217953	1751304217953	1709000	850000		173	Erlenbruch 11	f
280	f	51.3688353	14.6177504	1750580153978	1750580753978	1750580753978	1450000	1224000		140	Körnerplatz	t
349	t	51.5357337	14.5192924	1750344674720	1750345274720	1750344674720	982000	1347000		175	Jahnring 13	f
350	f	51.488862	14.6749018	1750346621720	1750347221720	1750347221720	1347000	437000		175	Körnerplatz	f
354	f	51.5305303	14.5320261	1750348248749	1750348248749	1750348248749	1793000	361000		177	Rohner Weg 10	f
361	t	51.5357337	14.5192924	1750562918090	1750563518090	1750562918090	222000	2009000		181	Jahnring 13	f
362	f	51.3991425	14.6114006	1750565527090	1750566127090	1750566127090	2009000	1928000		181	Körnerplatz	f
351	t	51.5393992	14.5316092	1750497081108	1750497681108	1750497081108	939000	1715000		176	Strugaaue 2	t
352	f	51.4091751	14.6599025	1750499396108	1750499996108	1750499996108	1715000	937000		176	Körnerplatz	t
367	t	51.3475242	14.6142785	1751108951930	1751109334155	1751108951930	1658000	727000		184	Ernst-Thälmann-Straße 32	f
369	t	51.528762	14.5279248	1750228719634	1750229319634	1750228719634	911000	364000		185	Trebendorfer Weg 116c	f
370	f	51.5154456	14.5028135	1750229683634	1750230283634	1750230283634	364000	1261000		185	Neustädter Straße 65	f
377	t	51.5332486	14.5141138	1750661362167	1750661962167	1750661362167	1041000	1422000		189	Mühlweg 5b	f
380	f	51.3628562	14.5105966	1750999247843	1750999847843	1750999847843	1553000	1414000		190	Lange Straße 21	f
357	t	51.3619426	14.5148622	1750671380240	1750671980240	1750671380240	1458000	1659000		179	Spreegasse 5a	t
358	f	51.5405733	14.520827	1750673639240	1750674239240	1750674239240	1659000	1123000		179	Thälmann-Siedlung 25	t
375	t	51.5136543	14.6399818	1751279560787	1751279560787	1751279560787	1565000	1000000		188	Schwanenweg 23	t
376	f	51.5312531	14.516953	1751280560787	1751281160787	1751281160787	1000000	1035000		188	Dorfstraße 103	t
381	t	51.5388861	14.5189616	1750363982793	1750364582793	1750363982793	1027000	1673000		191	Zum Sportplatz 5	f
382	f	51.3473751	14.5878057	1750366255793	1750366855793	1750366855793	1673000	1514000		191	Heidestraße 378	f
386	f	51.5433114	14.5309437	1751186350404	1751186950404	1751186950404	325000	237000		193	Hoyerswerdaer Straße 33	f
388	f	51.4877942	14.5027859	1750856593769	1750857193769	1750857193769	1084000	1870000		194	Körnerplatz	f
347	t	51.5804789	14.5714555	1750759989425	1750760589425	1750759989425	1042000	662000		174	Dorfstraße 60	t
359	t	51.5388861	14.5189616	1750488164307	1750488764307	1750488164307	1027000	1590000		180	Zum Sportplatz 5	t
360	f	51.5187819	14.7173798	1750490354307	1750490954307	1750490954307	1590000	698000		180	Schäferstraße 8	t
403	t	51.533173	14.529221	1750478183854	1750478783854	1750478183854	952000	2422000		202	Mühlroser Straße 8a	f
404	f	51.447792	14.8556146	1750481205854	1750481805854	1750481805854	2422000	1593000		202	Körnerplatz	f
407	t	51.4847396	14.7949326	1751225610467	1751226210467	1751225610467	1110000	2013000		204	Körnerplatz	t
393	t	51.5357337	14.5192924	1750998455085	1750999055085	1750998455085	982000	280000		197	Jahnring 13	t
378	f	51.4263902	14.699231	1750663384167	1750663984167	1750663984167	1422000	832000		189	Körnerplatz	f
408	f	51.538412	14.5250691	1751228223467	1751228823467	1751228823467	2013000	1026000		204	Jahnring 21	t
365	t	51.5286634	14.5366817	1750876227497	1750876827497	1750876227497	976000	990000		183	Rohner Weg 6	t
366	f	51.5241162	14.6226502	1750877817497	1750878417497	1750878417497	990000	572000		183	Weißwasser/O.L.	t
401	t	51.4984126	14.49606	1751291419958	1751292019958	1751291419958	1133000	691000		201	Körnerplatz	f
395	t	51.3917108	14.6859731	1751295605538	1751296205538	1751295605538	1671000	1921000		198	Körnerplatz	t
396	f	51.5394742	14.5159274	1751298126538	1751298726538	1751298726538	1921000	315000		198	Hoyerswerdaer Straße 94	t
385	t	51.5516729	14.5331897	1751185425404	1751186025404	1751185425404	345000	325000		193	Freibad	f
371	t	51.5344465	14.5268116	1750931595674	1750932195674	1750931595674	939000	2008000		186	Mulkwitzer Weg 10	t
332	f	51.5343123	14.5136158	1750348609749	1750348609750	1750348609750	361000	320000		166	Forstweg 78a	f
397	t	51.5669862	14.5847805	1751203359866	1751203959866	1751203359866	1195000	693000		199	Körnerplatz	t
398	f	51.536356	14.5290886	1751204652866	1751205252866	1751205252866	693000	978000		199	Friedensstraße 1	t
399	t	51.5350649	14.5289157	1751077637357	1751078237357	1751077637357	946000	1849000		200	Siedlung - Sydlišćo	t
400	f	51.4893142	14.8377904	1751080086357	1751080686357	1751080686357	1849000	1026000		200	Körnerplatz	t
379	t	51.5386074	14.5148166	1750997094843	1750997694843	1750997094843	1127000	1553000		190	Hoyerswerdaer Straße 91	f
355	t	51.5360245	14.5286573	1751056470835	1751057070835	1751056470835	921000	458000		178	Friedensstraße 1	t
405	t	51.4848611	14.7723957	1751258167129	1751258767129	1751258167129	1284000	2118000		203	Körnerplatz	t
356	f	51.5129889	14.4891103	1751057528835	1751058128835	1751058128835	458000	1282000		178	Friedhof Mulkwitz	t
373	t	51.5279047	14.5229428	1751188154561	1751188154561	1751188154561	2356000	591000		187	Trebendorfer Weg 81	t
374	f	51.478112	14.4977775	1751188745561	1751188745561	1751188745561	591000	590000		187	Körnerplatz	t
383	t	51.4999307	14.6146668	1750704150124	1750704750124	1750704150124	165000	938000		192	Lausitz	t
384	f	51.5332486	14.5141138	1750705688124	1750706288124	1750706288124	938000	1101000		192	Mühlweg 5b	t
409	t	51.5082583	14.6870685	1751093030149	1751093630149	1751093030149	568000	1156000		205	Körnerplatz	f
372	f	51.3059291	14.6368499	1750934203674	1750934803674	1750934803674	2008000	1982000		186	Tauerwiesenteich	t
389	t	51.5332486	14.5141138	1750936785674	1750937156025	1750936785674	1982000	1598000		195	Mühlweg 5b	t
348	f	51.5399955	14.5160315	1750761251425	1750761357671	1750761851425	662000	1661000		174	Hoyerswerdaer Straße 90	t
406	f	51.5443525	14.5405083	1751260885129	1751260885129	1751260885129	2118000	206000		203	Friedensstraße 62	t
391	t	51.5405733	14.520827	1751124524987	1751125124987	1751124524987	2263000	2310000		196	Thälmann-Siedlung 25	t
392	f	51.485242	14.8590441	1751127434987	1751128034987	1751128034987	2310000	2274000		196	Dorfstraße 97	t
185	t	51.3556797	14.4788459	1751109383433	1751109983433	1751109383433	782000	1963000		93	Körnerplatz	f
402	f	51.5435594	14.5297765	1751292710958	1751293103237	1751293310958	691000	1500000		201	Alter Postweg 11	f
368	f	51.5388861	14.5189616	1751137643729	1751138196567	1751138196567	2178000	110000		184	Zum Sportplatz 5	f
387	t	51.5386074	14.5148166	1750855200525	1750855509769	1750854909769	120000	1084000		194	Hoyerswerdaer Straße 91	f
363	t	51.5084986	14.7681123	1750856953298	1750857553298	1750856953298	2432000	1667000		182	Am Sportplatz 50	f
364	f	51.5397943	14.5386138	1750859356404	1750859820298	1750859820298	1667000	1033000		182	Strugaaue 37	f
410	f	51.5446031	14.5355952	1751112070432	1751112070432	1751112070432	1963000	332000		205	Schleife - Slepo	f
186	f	51.5364085	14.524572	1751112402432	1751112402433	1751112402433	332000	1018000		93	Jahnring 5b	f
413	t	51.4835497	14.9127776	1750424419052	1750425019052	1750424419052	1864000	2741000		207	Königshügel 24	f
414	f	51.5345327	14.5239956	1750427760052	1750428360052	1750428360052	2741000	1000000		207	Neustädter Straße 7	f
416	f	51.5347542	14.5339465	1750427099772	1750427699772	1750427699772	416000	938000		208	Tiefbau-Service-Berton	f
417	t	51.4951632	14.8120412	1751352909580	1751353509580	1751352909580	940000	1853000		209	Zur Tanne 45	f
418	f	51.5286634	14.5366817	1751355362580	1751355962580	1751355962580	1853000	1036000		209	Rohner Weg 6	f
419	t	51.5417871	14.524831	1751253257017	1751253857017	1751253257017	261000	881000		210	Hoyerswerdaer Straße 50	f
394	f	51.5251095	14.5206766	1750999335085	1750999935085	1750999935085	280000	1092000		197	Mulkwitzer Weg 83a	t
421	t	51.535357	14.5350536	1751037869728	1751038469728	1751037869728	926000	1617000		211	Werksweg 12	f
422	f	51.5206163	14.749516	1751040086728	1751040686728	1751040686728	1617000	814000		211	Ein- und Ausstieg Sagar	f
424	f	51.4436365	14.7889953	1750655262269	1750655862269	1750655862269	2040000	1140000		212	Körnerplatz	f
426	f	51.4069161	14.5548636	1750680122086	1750680722086	1750680722086	1061000	928000		213	Körnerplatz	f
427	t	51.3889744	14.4857561	1750664928257	1750665528257	1750664928257	832000	1425000		214	Körnerplatz	f
428	f	51.5286634	14.5366817	1750666953257	1750667553257	1750667553257	1425000	1036000		214	Rohner Weg 6	f
431	t	51.5456749	14.5346691	1750239667454	1750240267454	1750239667454	944000	1261000		216	Spremberger Straße 17	t
432	f	51.5057379	14.6603813	1750241528454	1750242128454	1750242128454	1261000	638000		216	Sägewerk und Holzhandel Kopte	t
436	f	51.5135616	14.6597986	1751056628238	1751057228238	1751057228238	1373000	651000		218	Drachenbergweg 8	f
439	t	51.5341111	14.5351491	1750474907645	1750474907645	1750474907645	223000	1523000		220	Schleifer Straße 3	f
440	f	51.5429981	14.719979	1750476430645	1750476430645	1750476430645	1523000	569000		220	Am Parkrand 1	f
64	f	51.5178137	14.6778871	1750476999645	1750477137644	1750477137644	569000	555000		32	Körnerplatz	f
443	t	51.5292355	14.5213952	1750510575082	1750511175082	1750510575082	1017000	1473000		222	Gefallenendenkmale Rohne	f
445	t	51.4423564	14.9283829	1750774412034	1750775012034	1750774412034	1626000	2620000		223	Körnerplatz	f
446	f	51.5394742	14.5159274	1750777632034	1750778232034	1750778232034	2620000	1111000		223	Hoyerswerdaer Straße 94	f
449	t	51.5282656	14.6977824	1750491505257	1750492105257	1750491505257	626000	1226000		225	Friedhofsweg 4	f
450	f	51.5292289	14.5391334	1750493331257	1750493931257	1750493931257	1226000	893000		225	Rohner Weg 3a	f
453	t	51.3870386	14.6485926	1751349262106	1751349862106	1751349262106	1276000	1440000		227	Körnerplatz	f
454	f	51.5353088	14.5289849	1751351302106	1751351902106	1751351902106	1440000	1000000		227	Siedlung - Sydlišćo	f
455	t	51.3238821	14.5737188	1750478305639	1750478905639	1750478305639	2016000	1071000		228	Körnerplatz	f
456	f	51.5426918	14.5308026	1750483002261	1750483002261	1750483002261	1863000	291000		228	Hoyerswerdaer Straße 37	f
457	t	51.4397584	14.5959057	1751047349023	1751047949023	1751047349023	1265000	1702000		229	22	f
460	f	51.5343123	14.5136158	1750495623317	1750496223317	1750496223317	1662000	1181000		230	Forstweg 78a	f
462	f	51.5329343	14.5196775	1750537945720	1750538545720	1750538545720	857000	1019000		231	Dorfstraße 106	f
465	t	51.3496069	14.6117363	1750410800674	1750411400674	1750410800674	1622000	1667000		233	Feldweg 97	f
437	t	51.5151296	14.603911	1751207767809	1751208367809	1751207767809	717000	1185000		219	Kleingärtnerverein "Feldschlösschen"	t
438	f	51.5394742	14.5159274	1751209552809	1751210152809	1751210152809	1185000	1111000		219	Hoyerswerdaer Straße 94	t
444	f	51.4796152	14.5405261	1750512648082	1750513248082	1750513248082	1473000	2642000		222	Körnerplatz	f
471	t	51.5091363	14.5942805	1751181599013	1751182199013	1751181599013	411000	671000		236	Körnerplatz	f
472	f	51.5319259	14.52021	1751182870013	1751183470013	1751183470013	671000	345000		236	Dorfstraße 80	f
473	t	51.4333469	14.7086724	1750612284649	1750612884649	1750612284649	541000	1487000		237	Schießbahn 11	f
474	f	51.535357	14.5350536	1750614371649	1750614971649	1750614971649	1487000	986000		237	Werksweg 12	f
429	t	51.5332486	14.5141138	1750364603410	1750365203410	1750364603410	1041000	1585000		215	Mühlweg 5b	t
412	f	51.5329343	14.5196775	1750335529748	1750336129748	1750336129748	1022000	962000		206	Dorfstraße 106	f
451	t	51.5347542	14.5339465	1750954641236	1750955241236	1750954641236	878000	1226000		226	Tiefbau-Service-Berton	t
458	f	51.5353088	14.5289849	1751049651023	1751050251023	1751050251023	1702000	2094000		229	Siedlung - Sydlišćo	f
463	t	51.5400866	14.5128586	1751274230110	1751274830110	1751274230110	1094000	2049000		232	Hoyerswerdaer Straße 98	t
464	f	51.3697393	14.6281118	1751276879110	1751277479110	1751277479110	2049000	1823000		232	Körnerplatz	t
353	t	51.3220639	14.6336592	1750323990415	1750324590415	1750323990415	1818000	2078000		177	Im Erlengrund 2	f
411	t	51.4173479	14.587332	1750333907748	1750334507748	1750333907748	429000	1022000		206	Körnerplatz	f
423	t	51.5312432	14.5115818	1750652622269	1750653222269	1750652622269	223000	2040000		212	Mühlweg 5b	f
433	t	51.5290698	14.4788025	1751220401307	1751221001307	1751220401307	1291000	560000		217	Körnerplatz	t
434	f	51.5456749	14.5346691	1751221561307	1751222161307	1751222161307	560000	1005000		217	Spremberger Straße 17	t
415	t	51.5129889	14.4891103	1750426083772	1750426683772	1750426083772	459000	416000		208	Friedhof Mulkwitz	f
447	t	51.5013016	14.7578131	1750991009679	1750991609679	1750991009679	845000	1669000		224	Brandstraße 9	t
448	f	51.5305303	14.5320261	1750993278679	1750993878679	1750993878679	1669000	179000		224	Rohner Weg 10	t
452	f	51.4884283	14.6723274	1750956467236	1750957067236	1750957067236	1226000	420000		226	Körnerplatz	t
466	f	51.5296246	14.5237337	1750413067674	1750413667674	1750413667674	1667000	264000		233	Tischlereiweg 115a	f
420	f	51.5213573	14.613079	1751254738017	1751255338017	1751255338017	881000	1440000		210	An der Philippine 28	f
469	t	51.4729599	14.5174138	1750503336077	1750503336077	1750503336077	2614000	821000		235	Körnerplatz	t
470	f	51.5400866	14.5128586	1750504157077	1750504157077	1750504157077	821000	1435000		235	Hoyerswerdaer Straße 98	t
441	t	51.4166442	14.5201333	1750781915076	1750782515076	1750781915076	1167000	1156000		221	Merzdorfer Straße 34	t
442	f	51.5360245	14.5286573	1750783671076	1750784271076	1750784271076	1156000	981000		221	Friedensstraße 1	t
459	t	51.5225275	14.7155931	1750493361317	1750493961317	1750493361317	1059000	1662000		230	Eichenweg 114	f
461	t	51.5213573	14.613079	1750536488720	1750537088720	1750536488720	838000	857000		231	An der Philippine 28	f
425	t	51.5296246	14.5237337	1750678461086	1750679061086	1750678461086	340000	1061000		213	Tischlereiweg 115a	f
475	t	51.3715549	14.5912593	1750385772674	1750386372674	1750385772674	1801000	1924000		238	Körnerplatz	t
476	f	51.5332486	14.5141138	1750388296674	1750388896674	1750388896674	1924000	189000		238	Mühlweg 5b	t
467	t	51.3333354	14.6021606	1750515890082	1750515890083	1750515890082	2642000	1275000		234	Bornwiese	f
477	t	51.5329343	14.5196775	1750692654551	1750692654551	1750692654551	289000	1988000		239	Dorfstraße 106	f
478	f	51.3741902	14.6294957	1750694642551	1750695242551	1750695242551	1988000	1954000		239	Körnerplatz	f
483	t	51.4364572	14.5331526	1750537244826	1750537844826	1750537244826	1050000	870000		242	Körnerplatz	f
484	f	51.5388861	14.5189616	1750538714826	1750539314826	1750539314826	870000	1081000		242	Zum Sportplatz 5	f
430	f	51.3763695	14.6716033	1750366788410	1750367388410	1750367388410	1585000	1523000		215	Amselweg 3	t
485	t	51.5052496	14.7320134	1750749625314	1750750225314	1750749625314	532000	1446000		243	Krauschwitzer Straße 28	f
486	f	51.5286634	14.5366817	1750751671314	1750752271314	1750752271314	1446000	1036000		243	Rohner Weg 6	f
491	t	51.5397943	14.5386138	1750837356978	1750837956978	1750837356978	972000	1442000		246	Strugaaue 37	f
493	t	51.5342917	14.5338773	1750607079045	1750607679045	1750607079045	872000	1747000		247	Schleifer Straße 2	f
494	f	51.3428674	14.4903266	1750609426045	1750610026045	1750610026045	1747000	1729000		247	Körnerplatz	f
495	t	51.5336188	14.6526312	1750339998609	1750340598609	1750339998609	962000	881000		248	Feldweg 2	f
496	f	51.5418744	14.537528	1750341479609	1750342079609	1750342079609	881000	1766000		248	Friedensstraße 77a	f
498	f	51.5416387	14.5289058	1750567502079	1750568102079	1750568102079	128000	1037000		249	Lindenweg 20	f
499	t	51.4973683	14.6613079	1750487137121	1750487737121	1750487137121	930000	1696000		250	In der Meschina 1	f
502	f	51.512713	14.6416805	1750995753897	1750995967843	1750995967843	974000	1127000		251	Teichstraße 28	f
503	t	51.5292289	14.5391334	1751287286150	1751287886150	1751287286150	833000	540000		252	Rohner Weg 3a	f
504	f	51.5088223	14.6079517	1751288426150	1751289026150	1751289026150	540000	1133000		252	Tiergartenstraße 42	f
507	t	51.418717	14.5843492	1750472345316	1750472945316	1750472345316	867000	1158000		254	Boxberg Kraftwerk	f
508	f	51.5360245	14.5286573	1750474103316	1750474509644	1750474509644	1158000	175000		254	Friedensstraße 1	f
509	t	51.3981179	14.5135724	1750874892366	1750875492366	1750874892366	1004000	1205000		255	Körnerplatz	f
479	t	51.5292289	14.5391334	1751197667021	1751198267021	1751197667021	833000	2522000		240	Rohner Weg 3a	t
480	f	51.4101669	14.7336195	1751200789021	1751201389021	1751201389021	2522000	2051000		240	Körnerplatz	t
511	t	51.5400866	14.5128586	1751315194128	1751315794128	1751315194128	1094000	839000		256	Hoyerswerdaer Straße 98	f
512	f	51.5409837	14.633427	1751316633128	1751317233128	1751317233128	839000	874000		256	Jämlitzer Weg 51	f
514	f	51.5364085	14.524572	1750693161591	1750693761591	1750693761591	1857000	1018000		257	Jahnring 5b	f
515	t	51.5342917	14.5338773	1750662782210	1750663382210	1750662782210	872000	2113000		258	Schleifer Straße 2	f
516	f	51.4734329	14.7981781	1750665495210	1750666095210	1750666095210	2113000	1364000		258	Körnerplatz	f
114	f	51.5292355	14.5213952	1751189335561	1751189419560	1751189419560	590000	281000		57	Gefallenendenkmale Rohne	t
521	t	51.5148072	14.5031761	1750279265291	1750279265291	1750279265291	403000	317000		261	Neustädter Straße 64	f
522	f	51.5332486	14.5141138	1750279582291	1750280182291	1750280182291	317000	1101000		261	Mühlweg 5b	f
523	t	51.5868133	14.7078697	1751028290642	1751028890642	1751028290642	1621000	2177000		262	Körnerplatz	f
526	f	51.5004574	14.6324384	1750244965161	1750245565161	1750245565161	994000	235000		263	Schweigstraße 23	f
527	t	51.3402431	14.5150357	1751364781376	1751365381376	1751364781376	1594000	1741000		264	Körnerplatz	f
528	f	51.5290227	14.5298561	1751367122376	1751367722376	1751367722376	1741000	954000		264	Rohner Weg 13b	f
529	t	51.5011694	14.4747117	1751375513063	1751376113063	1751375513063	1240000	462000		265	Körnerplatz	f
530	f	51.5397309	14.5335292	1751376575063	1751377175063	1751377175063	462000	1052000		265	NORMA	f
390	f	51.3735315	14.6663815	1750938754025	1750939354025	1750939354025	1598000	1536000		195	Jahnstraße 29a	t
531	t	51.3741902	14.6294957	1750240912669	1750241512669	1750240912669	1893000	2130000		266	Körnerplatz	f
532	f	51.535357	14.5350536	1750243642669	1750243642669	1750243642669	2130000	198000		266	Werksweg 12	f
525	t	51.5338793	14.5202632	1750243840669	1750243971161	1750243371161	198000	994000		263	Dorfstraße 105a	f
481	t	51.535357	14.5350536	1751099589586	1751100189586	1751099589586	328000	1153000		241	Werksweg 12	f
533	t	51.4787315	14.7951387	1751095992619	1751096592619	1751095992619	1156000	2228000		267	Körnerplatz	f
534	f	51.5295517	14.5240575	1751098820619	1751099261586	1751099261586	2228000	328000		267	Tischlereiweg 115a	f
535	t	51.5043515	14.6198675	1751011674699	1751012274699	1751011674699	362000	973000		268	Grünstraße 14	f
537	t	51.344254	14.5179688	1751343552731	1751344152731	1751343552731	1641000	1722000		269	Körnerplatz	f
538	f	51.5357337	14.5192924	1751345874731	1751346474731	1751346474731	1722000	1042000		269	Jahnring 13	f
541	t	51.4992501	14.7881752	1751301931443	1751302531443	1751301931443	903000	1758000		271	Körnerplatz	f
542	f	51.536356	14.5290886	1751304289443	1751304889443	1751304889443	1758000	269000		271	Friedensstraße 1	f
543	t	51.4668778	14.4934071	1750523677834	1750523677834	1750523677834	1470000	691000		272	Körnerplatz	f
544	f	51.5435594	14.5297765	1750524368834	1750524368834	1750524368834	691000	219000		272	Alter Postweg 11	f
505	t	51.3794584	14.6675256	1750763018671	1750763018671	1750763018671	1410000	1641000		253	Sportverein 48 Reichwalde	f
513	t	51.3662679	14.580802	1750690704591	1750691304591	1750690704591	2012000	1857000		257	Körnerplatz	f
510	f	51.5405733	14.520827	1750876697366	1750876965436	1750877297366	1205000	1749000		255	Thälmann-Siedlung 25	f
492	f	51.3956285	14.5670154	1750839398978	1750839398979	1750839998978	1442000	1454000		246	Körnerplatz	f
497	t	51.5360245	14.5286573	1750566774079	1750567374079	1750566774079	148000	128000		249	Friedensstraße 1	f
517	t	51.5344465	14.5268116	1750519061836	1750519286985	1750519061836	221000	181000		259	Mulkwitzer Weg 10	f
501	t	51.5393992	14.5316092	1750994179897	1750994779897	1750994179897	109000	974000		251	Strugaaue 2	f
519	t	51.5312531	14.516953	1750826087952	1750826687952	1750826087952	975000	537000		260	Dorfstraße 103	t
487	t	51.5157714	14.7453693	1750779081034	1750779592035	1750779081034	849000	1726000		244	Körnerplatz	t
488	f	51.5353088	14.5289849	1750781318035	1750781703115	1750781703115	1726000	197000		244	Siedlung - Sydlišćo	t
489	t	51.4931288	14.6280856	1750586698215	1750587298215	1750586698215	39000	970000		245	Weißwasser/O.L.	t
490	f	51.528762	14.5279248	1750588268215	1750588868215	1750588868215	970000	971000		245	Trebendorfer Weg 116c	t
500	f	51.5277052	14.5242631	1750489433121	1750490033121	1750490033121	1696000	0		250	Trebendorfer Weg 116b	f
506	f	51.5433114	14.5309437	1750764659671	1750764659671	1750764659671	1641000	1048000		253	Hoyerswerdaer Straße 33	f
482	f	51.4002411	14.5188913	1751101342586	1751101942586	1751101942586	1153000	782000		241	Körnerplatz	f
524	f	51.5426918	14.5308026	1751031067642	1751031258041	1751031667642	2177000	234000		262	Hoyerswerdaer Straße 37	f
518	f	51.5204432	14.7054315	1750521346984	1750521346985	1750521346985	1468000	847000		259	Oberschule "Geschwister Scholl" Krauschwitz	f
545	t	51.3122668	14.608818	1751052345023	1751052514828	1751052345023	2094000	2217000		273	Körnerplatz	f
546	f	51.5400866	14.5128586	1751054731828	1751054731828	1751054731828	2217000	182000		273	Hoyerswerdaer Straße 98	f
435	t	51.5417871	14.524831	1751054913828	1751055255238	1751054655238	182000	1373000		218	Hoyerswerdaer Straße 50	f
549	t	51.5386074	14.5148166	1750329932323	1750330532323	1750329932323	2078000	1470000		275	Hoyerswerdaer Straße 91	f
550	f	51.4487333	14.6756959	1750332002323	1750332602323	1750332602323	1470000	429000		275	Körnerplatz	f
553	t	51.5443525	14.5405083	1751383497770	1751384097770	1751383497770	907000	1509000		277	Friedensstraße 62	f
554	f	51.3774987	14.6261899	1751385606770	1751386206770	1751386206770	1509000	1361000		277	Körnerplatz	f
536	f	51.5292355	14.5213952	1751013247699	1751013847699	1751013847699	973000	1077000		268	Gefallenendenkmale Rohne	f
561	t	51.378908	14.6063079	1751123939586	1751124539586	1751123939586	1374000	1709000		281	Körnerplatz	f
597	t	51.5279047	14.5229428	1751003271478	1751003871478	1751003271478	952000	1659000		299	Trebendorfer Weg 81	f
563	t	51.3539553	14.6578938	1750921077021	1750921677021	1750921077021	1603000	1760000		282	Körnerplatz	t
564	f	51.5340052	14.5217744	1750924903748	1750924903748	1750924903748	515000	61000		282	Dorfstraße 106a	t
598	f	51.5067623	14.7792183	1751005530478	1751006130478	1751006130478	1659000	830000		299	Körnerplatz	f
557	t	51.5357337	14.5192924	1750390561060	1750391161060	1750390561060	189000	369000		279	Jahnring 13	t
282	f	51.5342031	14.5217853	1750924964748	1750924964749	1750924964749	514000	102000		141	Dorfstraße 106a	f
565	t	51.3932617	14.6598379	1750421434716	1750422034716	1750421434716	1480000	1711000		283	Körnerplatz	f
566	f	51.5433114	14.5309437	1750423745716	1750424345716	1750424345716	1711000	459000		283	Hoyerswerdaer Straße 33	f
567	t	51.5472831	14.7246142	1750878714436	1750878714436	1750878714436	1749000	1570000		284	Löwe	f
568	f	51.5443525	14.5405083	1750880284436	1750880284436	1750880284436	1570000	251000		284	Friedensstraße 62	f
579	t	51.5279047	14.5229428	1750259046619	1750259646619	1750259046619	952000	2525000		290	Trebendorfer Weg 81	t
571	t	51.5386074	14.5148166	1751138306567	1751138728082	1751138306567	110000	2251000		286	Hoyerswerdaer Straße 91	f
572	f	51.482252	14.8968801	1751140979082	1751141579082	1751141579082	2251000	1313000		286	Körnerplatz	f
573	t	51.4297543	14.6037459	1750733108966	1750733708966	1750733108966	832000	1359000		287	Reichwalder Weg 36	f
575	t	51.5399955	14.5160315	1750840852979	1750840852979	1750840852979	1454000	2141000		288	Hoyerswerdaer Straße 90	f
576	f	51.3261566	14.5980347	1750842993979	1750843593979	1750843593979	2141000	1951000		288	Körnerplatz	f
577	t	51.5301599	14.5247083	1750686561687	1750687161687	1750686561687	1095000	564000		289	Tischlereiweg 113b	f
578	f	51.5088333	14.533541	1750687725687	1750688325687	1750688325687	564000	2012000		289	Körnerplatz	f
581	t	51.5301599	14.5247083	1750396261966	1750396261966	1750396261966	302000	1716000		291	Tischlereiweg 113b	f
582	f	51.3483511	14.5898825	1750397977966	1750398577966	1750398577966	1716000	1501000		291	Klitten Bahnhof	f
583	t	51.4961347	14.6334661	1750564470408	1750565070408	1750564470408	105000	1047000		292	Fleischerei Richter	f
584	f	51.5357337	14.5192924	1750566117408	1750566626079	1750566626079	1047000	148000		292	Jahnring 13	f
585	t	51.5463484	14.569041	1750869189309	1750869789309	1750869189309	349000	356000		293	Campingplatz Halbendorfer See	t
587	t	51.5279047	14.5229428	1750747983749	1750748583749	1750747983749	952000	1110000		294	Trebendorfer Weg 81	f
588	f	51.5306846	14.6524928	1750749693749	1750750293749	1750750293749	1110000	630000		294	Sagoinza 26	f
591	t	51.4722955	14.9025282	1751259393657	1751259993657	1751259393657	1317000	2348000		296	Körnerplatz	f
592	f	51.5400866	14.5128586	1751262341657	1751262941657	1751262941657	2348000	1148000		296	Hoyerswerdaer Straße 98	f
593	t	51.5187819	14.7173798	1750571348467	1750571948467	1750571348467	641000	1593000		297	Schäferstraße 8	f
596	f	51.5338373	14.5364242	1750758531421	1750759131421	1750759131421	1047000	910000		298	Schleifer Straße 5	f
599	t	51.3686496	14.5862105	1750989900896	1750990500896	1750989900896	1901000	2065000		300	Körnerplatz	f
600	f	51.5353088	14.5289849	1750992565896	1750993165896	1750993165896	2065000	109000		300	Siedlung - Sydlišćo	f
601	t	51.5312531	14.516953	1750416994122	1750417594122	1750416994122	264000	462000		301	Dorfstraße 103	f
602	f	51.5422955	14.5882385	1750418056122	1750418656122	1750418656122	462000	721000		301	Bahnhofstraße 95	f
603	t	51.5345327	14.5239956	1751080138084	1751080738084	1751080138084	940000	1519000		302	Neustädter Straße 7	f
607	t	51.5329343	14.5196775	1751041332054	1751041332054	1751041332054	166000	691000		304	Dorfstraße 106	f
608	f	51.5465954	14.6130163	1751042023054	1751042623054	1751042623054	691000	1032000		304	AV Schleife e.V.	f
609	t	51.5290227	14.5298561	1750192590641	1750192590641	1750192590641	1030000	1203000		305	Rohner Weg 13b	f
610	f	51.4133176	14.5354593	1750193793641	1750194393641	1750194393641	1203000	1169000		305	Körnerplatz	f
611	t	51.3769673	14.5956182	1750297977103	1750298577103	1750297977103	1941000	2123000		306	Körnerplatz	f
595	t	51.5002257	14.6486007	1750756884421	1750757484421	1750756884421	565000	1047000		298	Hermannsdorfer Straße 16	f
605	t	51.4026342	14.5909016	1750239844981	1750240444981	1750239844981	1180000	1493000		303	Straße der Freundschaft 24	t
560	f	51.4035508	14.5397459	1751187227050	1751187827050	1751187827050	1044000	1298000		280	Körnerplatz	f
589	t	51.535357	14.5350536	1750756079424	1750756679424	1750756079424	926000	1835000		295	Werksweg 12	t
590	f	51.4638967	14.7219401	1750758514424	1750759114424	1750759114424	1835000	1033000		295	Dorfstraße 9	t
562	f	51.5400192	14.5240712	1751126248586	1751126848586	1751126848586	1709000	261000		281	Thälmann-Siedlung 8	f
604	f	51.4871166	14.716346	1751082257084	1751082616856	1751082857084	1519000	2641000		302	Lange Straße 8a	f
574	f	51.5296246	14.5237337	1750735067966	1750735667966	1750735667966	1359000	243000		287	Tischlereiweg 115a	f
569	t	51.5386074	14.5148166	1750853723282	1750854323282	1750853723282	1963000	1116000		285	Hoyerswerdaer Straße 91	t
570	f	51.5137195	14.6052094	1750855439282	1750855623298	1750855623298	1116000	1330000		285	Kleingärtnerverein "Feldschlösschen"	t
580	f	51.3406705	14.6606894	1750262171619	1750262771619	1750262771619	2525000	2436000		290	Körnerplatz	t
606	f	51.5456749	14.5346691	1750241937981	1750242537981	1750242537981	1493000	1005000		303	Spremberger Straße 17	t
559	t	51.528762	14.5279248	1751185779457	1751186183050	1751185583050	224000	1044000		280	Trebendorfer Weg 116c	f
594	f	51.5319259	14.52021	1750573541467	1750574141467	1750574141467	1593000	128000		297	Dorfstraße 80	f
556	f	51.5443525	14.5405083	1750859230404	1750859230404	1750859230404	1602000	126000		278	Friedensstraße 62	t
558	f	51.4501267	14.6187824	1750405111154	1750405711154	1750405711154	2621000	1917000		279	Körnerplatz	t
281	t	51.4970298	14.5070647	1750923505333	1750923850749	1750923250749	614000	514000		141	Körnerplatz	f
551	t	51.3357988	14.6377567	1750648462874	1750649062874	1750648462874	3029000	2276000		276	Westlicher Bahnteich	f
612	f	51.5342917	14.5338773	1750300700103	1750301300103	1750301300103	2123000	282000		306	Schleifer Straße 2	f
615	t	51.5341111	14.5351491	1750351201579	1750351801579	1750351201579	320000	2268000		308	Schleifer Straße 3	f
616	f	51.3863717	14.533099	1750354069579	1750354669579	1750354669579	2268000	2196000		308	Körnerplatz	f
547	t	51.3612079	14.5817166	1750937637511	1750938237511	1750937637511	1594000	2063000		274	Körnerplatz	t
548	f	51.5332486	14.5141138	1750947611731	1750948211731	1750948211731	283000	1468000		274	Mühlweg 5b	t
618	f	51.511205	14.5113027	1750405857291	1750406457291	1750406457291	476000	1296000		309	Körnerplatz	f
619	t	51.5344465	14.5268116	1750592212365	1750592212365	1750592212365	2229000	1726000		310	Mulkwitzer Weg 10	f
621	t	51.5364085	14.524572	1750754479765	1750755079765	1750754479765	958000	1231000		311	Jahnring 5b	f
622	f	51.5280289	14.6804229	1750756310765	1750756319421	1750756319421	1231000	565000		311	Siedlung 30	f
520	f	51.5620876	14.5674343	1750827224952	1750827824952	1750827824952	537000	1035000		260	Hühnerfarm	t
625	t	51.4881701	14.8398785	1751256778017	1751256993637	1751256778017	1440000	1939000		313	Körnerplatz	f
626	f	51.5312432	14.5115818	1751258932637	1751259532637	1751259532637	1939000	267000		313	Mühlweg 5b	f
627	t	51.4010976	14.6186056	1750218118300	1750218718300	1750218118300	1757000	2131000		314	Körnerplatz	f
629	t	51.5364085	14.524572	1751178367450	1751178967450	1751178367450	958000	1742000		315	Jahnring 5b	f
586	f	51.5342031	14.5217853	1750870145309	1750870745309	1750870745309	356000	1007000		293	Dorfstraße 106a	t
631	t	51.3749749	14.5027794	1751190204057	1751190804057	1751190204057	1298000	2282000		316	Körnerplatz	f
632	f	51.5418744	14.537528	1751193086057	1751193686057	1751193686057	2282000	1001000		316	Friedensstraße 77a	f
633	t	51.4082275	14.5843903	1751141871292	1751142471292	1751141871292	1074000	1421000		317	Eichenweg 146	f
634	f	51.5305303	14.5320261	1751143892292	1751144492292	1751144492292	1421000	947000		317	Rohner Weg 10	f
646	f	51.5053637	14.6790766	1750255425766	1750256025766	1750256025766	1406000	547000		323	Körnerplatz	t
635	t	51.5296246	14.5237337	1750518207683	1750518207683	1750518207683	1591000	221000		318	Tischlereiweg 115a	f
636	f	51.5444149	14.6265697	1750519275122	1750519275122	1750519275122	733000	2654000		318	Campingplatz Badesee Kromlau	f
112	f	51.536356	14.5290886	1750518428683	1750518542122	1750518927525	221000	733000		56	Friedensstraße 1	f
637	t	51.4389995	14.6159032	1751162231179	1751162831179	1751162231179	1576000	1998000		319	Körnerplatz	f
638	f	51.5344465	14.5268116	1751164829179	1751165429179	1751165429179	1998000	999000		319	Mulkwitzer Weg 10	f
639	t	51.5279047	14.5229428	1751312806930	1751313406930	1751312806930	952000	1725000		320	Trebendorfer Weg 81	f
640	f	51.4016682	14.4970751	1751315131930	1751315731930	1751315731930	1725000	1696000		320	Körnerplatz	f
641	t	51.439721	14.6386335	1751085257856	1751085257856	1751085257856	2641000	2943000		321	Körnerplatz	f
642	f	51.5446031	14.5355952	1751088200856	1751088800856	1751088800856	2943000	365000		321	Schleife - Slepo	f
643	t	51.5341111	14.5351491	1751130518698	1751131118698	1751130518698	261000	536000		322	Schleifer Straße 3	f
644	f	51.5167955	14.5933846	1751131654698	1751132254698	1751132254698	536000	768000		322	Körnerplatz	f
647	t	51.5400866	14.5128586	1751133022698	1751133227729	1751133022698	768000	2238000		324	Hoyerswerdaer Straße 98	f
648	f	51.4532138	14.8137591	1751135465729	1751135465729	1751135465729	2238000	2178000		324	Körnerplatz	f
649	t	51.4803208	14.8343571	1751131246574	1751131846574	1751131246574	1126000	1957000		325	Körnerplatz	f
650	f	51.5290227	14.5298561	1751133803574	1751134403574	1751134403574	1957000	954000		325	Rohner Weg 13b	f
651	t	51.5045254	14.6697374	1750560107681	1750560707681	1750560107681	564000	1218000		326	Braunsteich	f
652	f	51.5305303	14.5320261	1750561925681	1750562525681	1750562525681	1218000	222000		326	Rohner Weg 10	f
653	t	51.5353088	14.5289849	1750736315380	1750736915380	1750736315380	243000	1583000		327	Siedlung - Sydlišćo	f
654	f	51.4985366	14.6700961	1750738498380	1750739098380	1750739098380	1583000	766000		327	Körnerplatz	f
665	t	51.5456749	14.5346691	1750620145268	1750620145268	1750620145268	2292000	213000		333	Spremberger Straße 17	f
655	t	51.5295517	14.5240575	1750595790015	1750595790015	1750595790015	1843000	761000		328	Tischlereiweg 115a	f
656	f	51.4570121	14.5059364	1750596551015	1750597151015	1750597151015	761000	696000		328	Körnerplatz	f
620	f	51.3601964	14.5884921	1750593938365	1750593947015	1750594538365	1726000	1843000		310	Körnerplatz	f
657	t	51.5277052	14.5242631	1750490410714	1750491010714	1750490410714	0	1126000		329	Trebendorfer Weg 116b	f
658	f	51.4188334	14.5938883	1750492136714	1750492302317	1750492302317	1126000	1059000		329	Körnerplatz	f
659	t	51.5344271	14.5295784	1750504853993	1750505453993	1750504853993	935000	1236000		330	Mühlroser Straße 3	f
660	f	51.5343194	14.6905686	1750506689993	1750507289993	1750507289993	1236000	865000		330	Krauschwitz / Baierweiche	f
666	f	51.5402086	14.6215496	1750621506386	1750622106386	1750622106386	715000	878000		333	Am Lieskauer Weg 5	f
661	t	51.3690959	14.4911016	1750251497323	1750252097323	1750251497323	1198000	1260000		331	Körnerplatz	f
663	t	51.5049107	14.5796706	1750853781525	1750854381525	1750853781525	491000	699000		332	Körnerplatz	f
664	f	51.5405733	14.520827	1750855080525	1750855080525	1750855080525	699000	120000		332	Thälmann-Siedlung 25	f
261	t	51.3299848	14.565352	1750617853267	1750617853268	1750617853267	1117000	2292000		131	Körnerplatz	f
262	f	51.538412	14.5250691	1750620672267	1750620791386	1750621272267	213000	715000		131	Jahnring 21	f
630	f	51.3963229	14.6151297	1751180709450	1751181309450	1751181309450	1742000	1604000		315	Körnerplatz	f
667	t	51.503605	14.5063565	1751184504457	1751185104457	1751184504457	1604000	451000		334	Mühlroser Straße 36b	f
668	f	51.5357337	14.5192924	1751185555457	1751185555457	1751185555457	451000	224000		334	Jahnring 13	f
670	f	51.3893435	14.5389024	1750356551341	1750357151341	1750357151341	2188000	2112000		335	Körnerplatz	f
671	t	51.471382	14.7763185	1750431244326	1750431844326	1750431244326	1382000	2266000		336	Körnerplatz	f
672	f	51.5342031	14.5217853	1750434110326	1750434110326	1750434110326	2266000	157000		336	Dorfstraße 106a	f
669	t	51.5364085	14.524572	1750353763341	1750354363341	1750353763341	1219000	2188000		335	Jahnring 5b	f
673	t	51.528762	14.5279248	1750350683071	1750351283071	1750350683071	911000	1213000		337	Trebendorfer Weg 116c	f
674	f	51.4126663	14.5152125	1750352496071	1750352544341	1750352544341	1213000	1219000		337	Grotte	f
675	t	51.4420236	14.6950434	1751267405874	1751268005874	1751267405874	460000	1374000		338	Körnerplatz	f
676	f	51.5290227	14.5298561	1751269379874	1751269379874	1751269379874	1374000	1139000		338	Rohner Weg 13b	f
555	t	51.3264526	14.4927592	1750851365562	1750851365562	1750851365562	1486000	2184000		278	Körnerplatz	t
613	t	51.4614557	14.7420632	1751103450586	1751103580576	1751103450586	1508000	1755000		307	Körnerplatz	t
617	t	51.5305303	14.5320261	1750404782967	1750405381291	1750404781291	2225000	476000		309	Rohner Weg 10	f
614	f	51.5353088	14.5289849	1751105335576	1751105935576	1751105935576	1755000	1801000		307	Siedlung - Sydlišćo	t
628	f	51.5322939	14.5345323	1750220849300	1750221449300	1750221449300	2131000	2291000		314	Reinert Ranch	f
645	t	51.5357337	14.5192924	1750253546323	1750254019766	1750253419766	189000	1406000		323	Jahnring 13	t
677	t	51.4210865	14.5336854	1751093558439	1751094158439	1751093558439	1041000	1037000		339	Dorfstraße 1	f
678	f	51.535357	14.5350536	1751095195439	1751095795439	1751095795439	1037000	986000		339	Werksweg 12	f
623	t	51.4006816	14.5899779	1751207685666	1751208285666	1751207685666	1546000	1172000		312	Straße der Freundschaft 26	f
679	t	51.530615	14.5780375	1751194146058	1751194746058	1751194146058	659000	1546000		340	Am See 17	f
680	f	51.5386074	14.5148166	1751209990766	1751210590766	1751210590766	267000	1121000		340	Hoyerswerdaer Straße 91	f
624	f	51.5397309	14.5335292	1751209457666	1751209723766	1751210057666	1172000	267000		312	NORMA	f
681	t	51.5388861	14.5189616	1751031492041	1751031492041	1751031492041	234000	2521000		341	Zum Sportplatz 5	f
682	f	51.4545685	14.7279721	1751034013041	1751034613041	1751034613041	2521000	1624000		341	Körnerplatz	f
683	t	51.3169451	14.5894706	1750437520205	1750437520205	1750437520205	725000	1127000		342	Körnerplatz	f
684	f	51.5364085	14.524572	1750440339931	1750440339931	1750440339931	946000	106000		342	Jahnring 5b	f
539	t	51.4161576	14.5531501	1750438647205	1750438939932	1750438339932	1127000	946000		270	Körnerplatz	f
540	f	51.536356	14.5290886	1750440445931	1750440445932	1750440445932	106000	978000		270	Friedensstraße 1	f
685	t	51.4103412	14.577371	1750533135492	1750533735492	1750533135492	855000	1117000		343	Brunnenweg 14b	f
686	f	51.5344465	14.5268116	1750534852492	1750535452492	1750535452492	1117000	838000		343	Mulkwitzer Weg 10	f
687	t	51.5443525	14.5405083	1750253428901	1750253428901	1750253428901	2136000	551000		344	Friedensstraße 62	f
688	f	51.5603242	14.5876068	1750253979901	1750253979901	1750253979901	551000	726000		344	Körnerplatz	f
689	t	51.4575017	14.669677	1750959759217	1750960359217	1750959759217	3076000	3128000		345	Körnerplatz	f
690	f	51.5397943	14.5386138	1750963487217	1750964087217	1750964087217	3128000	1033000		345	Strugaaue 37	f
693	t	51.4651327	14.8901701	1750989000000	1750989600000	1750989000000	2071000	3112000		347	Körnerplatz	f
694	f	51.5405733	14.520827	1751023484967	1751023484967	1751023484967	305000	407000		347	Thälmann-Siedlung 25	f
695	t	51.5692679	14.7163712	1750687094947	1750687694947	1750687094947	1413000	655000		348	Friedensweg 4	f
696	f	51.5416387	14.5289058	1750692044550	1750692044550	1750692044550	1565000	321000		348	Lindenweg 20	f
697	t	51.5338793	14.5202632	1750577447488	1750578047488	1750577447488	128000	1248000		349	Dorfstraße 105a	f
698	f	51.4067236	14.5200375	1750579295488	1750579895488	1750579895488	1248000	1296000		349	Rudolf Hünlich	f
699	t	51.4381515	14.6040972	1750780557442	1750781157442	1750780557442	981000	1461000		350	Gudrun u. Wolfgang Boxberg	f
700	f	51.5418744	14.537528	1750782618442	1750783218442	1750783218442	1461000	1001000		350	Friedensstraße 77a	f
701	t	51.4306816	14.6460468	1750939886051	1750940486051	1750939886051	547000	1296000		351	Körnerplatz	f
702	f	51.533173	14.529221	1750941782051	1750942382051	1750942382051	1296000	1402000		351	Mühlroser Straße 8a	f
703	t	51.5350649	14.5289157	1750329554255	1750330154255	1750329554255	946000	1446000		352	Siedlung - Sydlišćo	f
704	f	51.4759759	14.5167044	1750331600255	1750332200255	1750332200255	1446000	2330000		352	Körnerplatz	f
705	t	51.5145961	14.7667367	1750920753333	1750921353333	1750920753333	671000	1538000		353	Skerbersdorfer Straße 104	f
706	f	51.5418744	14.537528	1750922891333	1750922891333	1750922891333	1538000	614000		353	Friedensstraße 77a	f
707	t	51.4960707	14.7190451	1751294603237	1751294603237	1751294603237	1500000	1552000		354	Wiesenweg 5	f
708	f	51.5405733	14.520827	1751296155237	1751296155237	1751296155237	1552000	194000		354	Thälmann-Siedlung 25	f
709	t	51.5251215	14.6649478	1750274134042	1750274734042	1750274134042	540000	1123000		355	Wiesengrund 9	f
710	f	51.5446031	14.5355952	1750275857042	1750276457042	1750276457042	1123000	676000		355	Schleife - Slepo	f
711	t	51.399407	14.6548184	1751294694042	1751295294042	1751294694042	1520000	2139000		356	Körnerplatz	f
712	f	51.5329343	14.5196775	1751297433042	1751298033042	1751298033042	2139000	1019000		356	Dorfstraße 106	f
713	t	51.3890481	14.5739453	1750673047675	1750673647675	1750673047675	1500000	1759000		357	C6	f
714	f	51.5426918	14.5308026	1750675406675	1750676006675	1750676006675	1759000	340000		357	Hoyerswerdaer Straße 37	f
715	t	51.5074097	14.7190637	1750262863173	1750263463173	1750262863173	698000	1673000		358	Görlitzer Straße 40	f
716	f	51.5332486	14.5141138	1750265136173	1750265736173	1750265736173	1673000	1101000		358	Mühlweg 5b	f
717	t	51.5344465	14.5268116	1750399817967	1750400417967	1750399817967	939000	2140000		359	Mulkwitzer Weg 10	f
718	f	51.3893435	14.5389024	1750402557967	1750402557967	1750402557967	2140000	2225000		359	Körnerplatz	f
719	t	51.4417032	14.6895141	1750517165083	1750517165083	1750517165083	1275000	1530000		360	Körnerplatz	f
720	f	51.528762	14.5279248	1750519878984	1750519878984	1750519878984	181000	1468000		360	Trebendorfer Weg 116c	f
468	f	51.5399955	14.5160315	1750518695083	1750518840836	1750518840836	1530000	221000		234	Hoyerswerdaer Straße 90	f
721	t	51.3678204	14.6341347	1751087513475	1751088113475	1751087513475	1482000	1652000		361	Körnerplatz	f
722	f	51.5350649	14.5289157	1751089765475	1751090365475	1751090365475	1652000	1006000		361	Siedlung - Sydlišćo	f
662	f	51.5332486	14.5141138	1750253357323	1750253357323	1750253357323	1260000	1101000		331	Mühlweg 5b	f
723	t	51.5400192	14.5240712	1750525641945	1750526241945	1750525641945	1062000	1939000		362	Thälmann-Siedlung 8	f
724	f	51.3583391	14.5623049	1750528180945	1750528780945	1750528780945	1939000	1774000		362	Restaurant Arche	f
691	t	51.5790064	14.720352	1751164548909	1751165148909	1751164548909	1592000	2065000		346	Schulstraße 11	t
692	f	51.5456749	14.5346691	1751167213909	1751167813909	1751167813909	2065000	1005000		346	Spremberger Straße 17	t
725	t	51.4506186	14.6652795	1750643838192	1750644438192	1750643838192	1862000	3029000		363	Körnerplatz	f
726	f	51.5417264	14.5348536	1750651708873	1750651708873	1750651708873	2276000	222000		363	Gemeindeamt	f
552	f	51.5341111	14.5351491	1750651930873	1750651930874	1750651930874	222000	223000		276	Schleifer Straße 3	f
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
2024-07-01	2025-06-17T16:43:24.292Z
2025-03-24	2025-06-17T16:43:24.293Z
2025-04-07	2025-06-17T16:43:24.294Z
2025-04-24-json-and-latlng-precision	2025-06-17T16:43:24.308Z
2025-04-30	2025-06-17T16:43:24.347Z
2025-05-21	2025-06-17T16:43:24.349Z
2025-06-06-update-scheduled-times	2025-06-17T16:43:24.350Z
2025-06-11-update-direct-durations	2025-06-17T16:43:24.352Z
2025-06-12-reconstructable-requests	2025-06-17T16:43:24.366Z
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
1	2	0	0	0	0	0	0	1	1	f51f64b011e27ca7c038e73aa19270bc	f	f	600
3	1	0	0	0	0	0	0	3	1	297eaa254d872cb41e3326dc37dd0fd0	f	t	300
13	2	0	0	0	0	0	0	13	1	39e97443501effdd04e30d9f6f03b582	f	f	600
12	1	0	0	0	0	0	0	12	1	146d830d8c6c95f93abdf5374cfd99e8	f	t	300
17	1	0	0	0	0	0	0	16	1	2e73a3817d824f8ec7fe85a7c6b119e1	f	f	300
19	1	0	0	0	0	0	0	18	1	cbba1e9c3e7ea8d2225685db1c2c73c4	f	f	300
21	1	0	0	0	0	0	0	20	1	e15185727b1a7662567719d5cda6fd5b	f	t	300
10	1	0	0	0	0	0	0	10	1	7deda171973f81ca11dd14303bfb00a6	f	t	300
24	2	0	0	0	0	0	0	23	1	1cbc9fcdfddadc3b1b5a7f41ce4f9f98	f	t	600
31	2	0	0	0	0	0	0	30	1	54eaccbe5758a5f0a38cf7426efef274	f	f	600
32	2	0	0	0	0	0	0	31	1	61fab022e819518e43e8ae099396bc50	f	f	600
36	2	0	0	0	0	0	0	35	1	4859e5f2737fefdcf9c458c304b98b6f	f	f	600
35	1	0	0	0	0	0	0	34	1	39939c82bc843a1f02e11fc374bc7d3c	f	t	300
4	2	0	0	0	0	0	0	4	1	d10a2cdc1efc5ddbc2b2dae3445d32a7	f	t	600
40	2	0	0	0	0	0	0	38	1	6eb8f5f7f4414e1740cf1f175e287f01	f	f	600
41	2	0	0	0	0	0	0	39	1	d69d75e123fd73b7902c07eee5b8f3c8	f	f	600
20	1	0	0	0	0	0	0	19	1	7df590b645aed1245441f8d9ad7cf2e2	f	t	300
44	2	0	0	0	0	0	0	42	1	1d2198a34aeea898195b5479bd95c284	f	t	600
28	2	0	0	0	0	0	0	27	1	4a1cc274eefd6d2abe9b7f206dcfcbd8	f	t	600
2	2	0	0	0	0	0	0	2	1	afe4f6d3c33bd675bd032ee9dc082c9d	f	t	600
26	1	0	0	0	0	0	0	25	1	ec0b6977c42f412ca9b981b37a42843a	f	t	300
49	2	0	0	0	0	0	0	47	1	80a818dd3bc7f27a34ad5184be49919e	f	f	600
51	2	0	0	0	0	0	0	49	1	5c071283c0d6895d5b88a6beff6e484c	f	f	600
29	1	0	0	0	0	0	0	28	1	bc9c2d38814fa2bb151f7330c812cde7	f	t	300
7	2	0	0	0	0	0	0	7	1	7e3880fbdfe836b18775797d03b822b0	f	t	600
52	2	0	0	0	0	0	0	50	1	dae1bcaf67c5eeaa9279e334564bb76c	f	f	600
18	2	0	0	0	0	0	0	17	1	2867c140f08bfcd68270cbeb5782a9b6	f	t	600
23	1	0	0	0	0	0	0	22	1	ec1db9791e72de416f8dfca086d6d06d	f	t	300
6	2	0	0	0	0	0	0	6	1	a3f97f532ee802a6d2269c5fb3fb57b2	f	t	600
53	2	0	0	0	0	0	0	51	1	b2f0dba6896703e8a85b25f529381234	f	f	600
54	1	0	0	0	0	0	0	52	1	dddd68ea124c36d674139eab8e368299	f	f	300
43	2	0	0	0	0	0	0	41	1	37c86df00914383dd929da68b056a5c4	f	t	600
56	1	0	0	0	0	0	0	53	1	572291b42c4922c86d7d99880b07a774	f	f	300
58	2	0	0	0	0	0	0	55	1	fb4f38abd2c79a9da38cf82dd99146a9	f	f	600
42	2	0	0	0	0	0	0	40	1	e93e92171c54352e17f9a15b522330e7	f	t	600
59	2	0	0	0	0	0	0	56	1	aa534f410e41820aa6c81e9f16b6148c	f	f	600
62	2	0	0	0	0	0	0	59	1	88d4f3d4f42c734fb8cb6f246b7d9be8	f	f	600
64	2	0	0	0	0	0	0	61	1	678fd135ccff5b3351da03939182d63c	f	f	600
70	1	0	0	0	0	0	0	67	1	98ae9769462bacc0b2709bf10b16d6a9	f	f	300
9	2	0	0	0	0	0	0	9	1	63a22ead127630e59545194c1761a4c8	f	t	600
72	1	0	0	0	0	0	0	69	1	0fccbea27c142be5c429a85d5169afbe	f	f	300
73	1	0	0	0	0	0	0	70	1	40a6c361cef6b6a2af08b09b25f2caf6	f	f	300
47	2	0	0	0	0	0	0	45	1	9e4034002f0a0ec5995cc2411ea526d8	f	t	600
71	2	0	0	0	0	0	0	68	1	90bf743b06d21ee61dbc0f7e8e6338df	f	t	600
60	2	0	0	0	0	0	0	57	1	402f2e7a4f9807b6cc5ab558c62a9ac4	f	t	600
34	2	0	0	0	0	0	0	33	1	104a02bc3dc475432391d6c1ad59d449	f	t	600
25	1	0	0	0	0	0	0	24	1	533b3c00ec1bef0b763f26a4f4a6fc19	f	t	300
30	2	0	0	0	0	0	0	29	1	e956de1ab245470b07aa8e95f8246aad	f	t	600
67	2	0	0	0	0	0	0	64	1	e2fac7a965be7791f9f4e8ac5c5d1736	f	t	600
11	2	0	0	0	0	0	0	11	1	278e24df8b903af4e94b6352da87d999	f	t	600
74	1	0	0	0	0	0	0	71	1	cb6c30e4d0da2ce6cbdc47dfbe4af4a9	f	t	300
63	1	0	0	0	0	0	0	60	1	9273b67023f40026f9745150793bcee4	f	t	300
68	2	0	0	0	0	0	0	65	1	3346423491e2e76376f1f74e96020046	f	t	600
69	2	0	0	0	0	0	0	66	1	ba59451d51265c0c148d66403ad2af39	f	t	600
50	1	0	0	0	0	0	0	48	1	d5ff16bc006fb985b8429dda3b5b9e12	f	t	300
15	1	0	0	0	0	0	0	15	1	59a0d2c4ec3b65d539281806b847785c	f	t	300
65	2	0	0	0	0	0	0	62	1	501b2b881e912829bb025ae3e7410ee4	f	t	600
61	2	0	0	0	0	0	0	58	1	7a13dfb610ad45ff979cb386e7ba8bf6	f	t	600
45	2	0	0	0	0	0	0	43	1	4105e920b59d5a900a352fa2fc2f09d5	f	t	600
22	1	0	0	0	0	0	0	21	1	dcb92ad06500718d7da45828d16f9ae3	f	t	300
14	2	0	0	0	0	0	0	14	1	7e80d722f5c93e59748984a554d49b90	f	t	600
8	1	0	0	0	0	0	0	8	1	ae2e87e6057fd208d73285d234520006	f	t	300
48	1	0	0	0	0	0	0	35	1	3c2f594ac6f81a9974388c352b4410a5	f	f	300
46	2	0	0	0	0	0	0	44	1	6b9895da49a5bf71537fc705c02fe79b	f	t	600
66	2	0	0	0	0	0	0	63	1	6efeb402c614e30c8e7a696f99489bd3	f	t	600
57	1	0	0	0	0	0	0	54	1	925d0cfa599f700e0edd3adab67a4940	f	t	300
27	2	0	0	0	0	0	0	26	1	b061bb2b1f54891f6dd395418ffc1fc3	f	t	600
16	2	0	0	0	0	0	0	5	1	786fad3f3c53b498fd1b22fc2392c429	f	t	600
39	1	0	0	0	0	0	0	37	1	14d4401565948fdfd7035b3741c74586	f	t	300
55	2	0	0	0	0	0	0	37	1	0b364b591862af90ce777184540abec1	f	t	600
75	1	0	0	0	0	0	0	72	1	2a620c54e5eb6e42c55b391197d5b82d	f	f	300
77	2	0	0	0	0	0	0	74	1	920cae1e3d0b00fcdf60c2e59aeb8542	f	f	600
33	1	0	0	0	0	0	0	32	1	8232382e906e5be46c6ee640900c3460	f	t	300
78	2	0	0	0	0	0	0	75	1	1c016aecf06037c8bdf0d6cf915ea108	f	t	600
81	2	0	0	0	0	0	0	78	1	79c750890eb073de7ecec56e73be6e04	f	f	600
82	2	0	0	0	0	0	0	14	1	2241988600e33777459dfc0dc8052d29	f	f	600
83	2	0	0	0	0	0	0	35	1	59b18aa10f8f17bc741824ef58da2495	f	f	600
85	1	0	0	0	0	0	0	79	1	4c061d9f0965f03de8bd25db6320b1b3	f	f	300
93	1	0	0	0	0	0	0	85	1	a8003fdd54f1106408f6c7b04b253247	f	f	300
94	2	0	0	0	0	0	0	86	1	e1a8f8c295d9672ad701aa31699bd770	f	f	600
95	1	0	0	0	0	0	0	87	1	9c1f8860e13f689e2d8d3139d9d900c4	f	f	300
97	2	0	0	0	0	0	0	89	1	75fd51d3d43d0b202cd823cff122eed7	f	f	600
98	2	0	0	0	0	0	0	90	1	d01cfe2c88f771771bd69b3ed16ee1b5	f	f	600
100	2	0	0	0	0	0	0	53	1	3b50460d490d1da5808abb9187f3ea80	f	f	600
101	2	0	0	0	0	0	0	78	1	7543491132e7988e7c117e88687dfe5b	f	f	600
90	1	0	0	0	0	0	0	83	1	667e6cb2fa8d4ee1120267c8415cc1c8	f	t	300
103	1	0	0	0	0	0	0	93	1	0919b2819671be1955c65a5afb159ee8	f	f	300
105	2	0	0	0	0	0	0	95	1	84d51be7799e96a7c2ef587f1ae8a8d6	f	f	600
109	1	0	0	0	0	0	0	99	1	f5d3b7373f096eb5079e0b1667d93507	f	f	300
110	2	0	0	0	0	0	0	100	1	22450b7740e5aa2f17a18ecbe83a7c1f	f	f	600
111	1	0	0	0	0	0	0	101	1	265e68834952220b771405e03c7db916	f	f	300
108	1	0	0	0	0	0	0	98	1	012f5306c6386a6b73c9901be68a5595	f	t	300
86	2	0	0	0	0	0	0	80	1	6ce31cf64be7ce37f95bc5eb548aad0a	f	t	600
115	2	0	0	0	0	0	0	1	1	44a3518ad52aefdbe8484b132af3d726	f	f	600
118	2	0	0	0	0	0	0	105	1	22f10be9a4383d6756cc423556975e6b	f	f	600
119	2	0	0	0	0	0	0	106	1	64a8daa6aaac0dc8dfc08a0d39b47858	f	f	600
120	2	0	0	0	0	0	0	53	1	920226b8487b4289b5d7122643c7650a	f	f	600
89	2	0	0	0	0	0	0	82	1	6d6ae663af69d58443a79a1ed7fa3012	f	t	600
104	2	0	0	0	0	0	0	94	1	b1fb4c89eee7b9bf9fd0e3057ce2ba6e	f	t	600
122	1	0	0	0	0	0	0	108	1	5cb9d89e46eb449c6e5e28cb19ba9358	f	f	300
127	1	0	0	0	0	0	0	111	1	7217023e57464a438f5d70573e4303a6	f	f	300
131	2	0	0	0	0	0	0	113	1	0b8805568847fd011091932319120749	f	f	600
116	2	0	0	0	0	0	0	103	1	9d9af38e9dc3ba2ab48abd65366257af	f	t	600
135	2	0	0	0	0	0	0	16	1	11e9faa0f095707c61b5eb1563d57e41	f	f	600
107	2	0	0	0	0	0	0	97	1	920152c94127069fa84f1bfb091d6ca9	f	t	600
138	1	0	0	0	0	0	0	118	1	c8e816b1010c9963eaf689eddea14a83	f	f	300
139	2	0	0	0	0	0	0	69	1	af1755ecdfc87fbc730254967b23ae4f	f	f	600
141	1	0	0	0	0	0	0	93	1	7fe009f20388365fc210b69e865099f9	f	f	300
142	1	0	0	0	0	0	0	30	1	1f89202fbf2079a4b7895cdf85194dda	f	f	300
99	1	0	0	0	0	0	0	91	1	dc0b8d251732bfb4efac71eaa107063a	f	t	300
145	2	0	0	0	0	0	0	121	1	cf3db304c63866eaf1e700649177b664	f	f	600
147	2	0	0	0	0	0	0	123	1	26a7139dcd4d5e4f4fd94d26b6249a47	f	f	600
148	1	0	0	0	0	0	0	124	1	bac10b1eb3e109bb94f2f02a9dd41d50	f	f	300
84	1	0	0	0	0	0	0	79	1	e4682a8ba95c3e76dfc24ee3e4565084	f	t	300
121	1	0	0	0	0	0	0	107	1	19a91591b5e1762ffa65f22390bf178f	f	t	300
146	1	0	0	0	0	0	0	122	1	53997d26d821892c6ec9c14ab30fe03d	f	t	300
79	2	0	0	0	0	0	0	76	1	5bbe5403d6473a91ddc106b171484eee	f	t	600
112	1	0	0	0	0	0	0	94	1	dba49bf7755f9923c8c17121800d9f92	f	t	300
134	1	0	0	0	0	0	0	116	1	f4c33eccb6b2311bd48b8fe54b701239	f	t	300
140	1	0	0	0	0	0	0	119	1	20f66588a72b436e0ce1775a3d20416f	f	t	300
106	1	0	0	0	0	0	0	96	1	9af476ceecf2b11ccc1cd6ede38bdf02	f	t	300
128	1	0	0	0	0	0	0	72	1	8e64a918089c5ec6416dacf172e6ae97	f	t	300
114	1	0	0	0	0	0	0	102	1	ecf444649d846b6c930e236f6cf4c20e	f	t	300
126	2	0	0	0	0	0	0	110	1	86f3256f7ae12145f642bb4d89cf5aaf	f	t	600
88	1	0	0	0	0	0	0	81	1	9a2a1812084415f2b127da72c6e9c719	f	t	300
91	2	0	0	0	0	0	0	84	1	0651ebff30704732b7724bbd20849dc4	f	t	600
129	1	0	0	0	0	0	0	112	1	534b447e10bbb5957895b4513401c580	f	t	300
133	2	0	0	0	0	0	0	115	1	af9d18c52b8d00a47fb59061c87fedeb	f	t	600
123	1	0	0	0	0	0	0	30	1	0e0c60384a36cca75bbde1f8ad95d386	f	t	300
76	2	0	0	0	0	0	0	73	1	d14d0d5d6134c2d7da5c595b963caee7	f	t	600
125	2	0	0	0	0	0	0	109	1	e0a9edbb2dea5bed41d75361089eb665	f	t	600
113	1	0	0	0	0	0	0	54	1	e370e049d451ef12b85c9238219a8af0	f	t	300
96	2	0	0	0	0	0	0	147	1	eb662bda7e5d3a3551ef7a8d15e4a139	f	f	600
143	2	0	0	0	0	0	0	36	1	8dab10eda74bdac4721b8f56938fa50e	f	t	600
80	1	0	0	0	0	0	0	77	1	5566f8fd25b3f34b6e190da378e196a2	f	t	300
136	2	0	0	0	0	0	0	117	1	612c6c9189cda30f0fecad2ad3cd7a92	f	t	600
102	2	0	0	0	0	0	0	95	1	566cce8ccbb036875d7189b39901d922	f	f	600
87	2	0	0	0	0	0	0	43	1	385a852daa5221b96f129739b97405c7	f	t	600
132	1	0	0	0	0	0	0	78	1	724fadd21c9ebafe7b051cb92675a537	f	f	300
92	1	0	0	0	0	0	0	1	1	4ebd0e310980ba2102661b8d57fdf145	f	t	300
144	2	0	0	0	0	0	0	101	1	83c46a16af5edb0c470a2b77cfa5ee7a	f	f	600
137	2	0	0	0	0	0	0	1	1	963c8dae6921ac5fb17b0fa33f373707	f	t	600
151	2	0	0	0	0	0	0	94	1	b58b8c890ac0cd8a71d24744c1024475	f	f	600
152	2	0	0	0	0	0	0	126	1	d2eae75aa4ea57224f2fafde1f6989d7	f	f	600
153	2	0	0	0	0	0	0	127	1	0aab11af5866d30922f5ed3380ec733a	f	f	600
155	1	0	0	0	0	0	0	47	1	ae0a1df657e942f02bcae592cbd0fe57	f	f	300
156	2	0	0	0	0	0	0	129	1	8d4c043690cdc2d3e50d3fab66dc5957	f	f	600
157	2	0	0	0	0	0	0	118	1	c015e7a17660e09d8a1a5ea050fb131d	f	f	600
158	1	0	0	0	0	0	0	130	1	3c96cc053c1ba41d6167639def7171a1	f	f	300
159	1	0	0	0	0	0	0	131	1	00542a7d835f6c15e7d63b65bb8f2bb0	f	f	300
160	2	0	0	0	0	0	0	113	1	213d6e1e0d40627974792196f4b6b1c6	f	f	600
154	1	0	0	0	0	0	0	128	1	b5e0aeac91e0294473169b6f464f53c6	f	t	300
162	1	0	0	0	0	0	0	133	1	fdacf09cfa3427fe3552da03670ec9da	f	f	300
166	1	0	0	0	0	0	0	137	1	8799a5b610f330406a98573289e5e5c1	f	f	300
169	1	0	0	0	0	0	0	30	1	8081a025bfef1dee04d212fa9b9d582e	f	f	300
170	1	0	0	0	0	0	0	139	1	85eeec1d01212c785448f988d16d5c96	f	f	300
171	1	0	0	0	0	0	0	140	1	c58b8fc08338d65c72bd8b08148b3d4a	f	f	300
172	2	0	0	0	0	0	0	73	1	7d4af4a9ccf0ee9582588a71f3c1c5e0	f	f	600
173	2	0	0	0	0	0	0	79	1	2b65b182af56ff75e7d571b2958f090e	f	f	600
175	1	0	0	0	0	0	0	141	1	922ddd6be7f92a8201b658707b75ea03	f	f	300
117	1	0	0	0	0	0	0	104	1	ffe1b40c39375679e70a7261b62219e8	f	t	300
177	2	0	0	0	0	0	0	137	1	b965e26d122a904c88190fbc8b174954	f	f	600
181	1	0	0	0	0	0	0	146	1	e348080c463eea6acf999c5ec490e510	f	f	300
182	1	0	0	0	0	0	0	147	1	13d61554f83cec99198bc728a73bbf85	f	f	300
176	2	0	0	0	0	0	0	142	1	03fa47eddff045d392af565d89dd1ccc	f	t	600
184	1	0	0	0	0	0	0	50	1	4ad2d682c7baffc7827105595a026991	f	f	300
185	2	0	0	0	0	0	0	149	1	59176ff89e2e0f7eb6d2268fde245e50	f	f	600
189	1	0	0	0	0	0	0	151	1	fa26d18c558c75ea785061537e2d05af	f	f	300
190	1	0	0	0	0	0	0	152	1	7f00cbc6e88df4da066e9cb6acb5675c	f	f	300
179	2	0	0	0	0	0	0	144	1	345a9135b90a70c85e7b55250097b5b3	f	t	600
188	1	0	0	0	0	0	0	1	1	1584fa3151b3c947131a4b626761f953	f	t	300
191	2	0	0	0	0	0	0	153	1	9c5999e62435f4b76721544b32b8012b	f	f	600
149	2	0	0	0	0	0	0	106	1	44effc9847b51a57e11de9f076c001c4	f	t	600
193	1	0	0	0	0	0	0	130	1	221ca8954e15d4496058867c8ce5898b	f	f	300
194	1	0	0	0	0	0	0	155	1	e9e80f773c6972fed202a87f16ccc7e1	f	f	300
180	1	0	0	0	0	0	0	145	1	f863d485c3c3185156678f89459d3208	f	t	300
207	1	0	0	0	0	0	0	161	1	68c4ca7367c56f21d1b857c86d39a0e0	f	f	300
124	1	0	0	0	0	0	0	84	1	882c082f40990e44dcac4d5f8b4f3b02	f	t	300
201	1	0	0	0	0	0	0	79	1	7f1c14879d3666a4faa530fd32f56e11	f	f	300
202	2	0	0	0	0	0	0	159	1	90fe5ae212ca1a7769f96cdbaa34d7f3	f	f	600
164	2	0	0	0	0	0	0	73	1	8c2faa2e165c2a35704730e54816b50a	f	t	600
205	1	0	0	0	0	0	0	85	1	fabe27b708e8761a2ea8cef0ecfcfe60	f	f	300
206	1	0	0	0	0	0	0	137	1	4cb8b8ae3cee2470984ed994316ef987	f	f	300
150	1	0	0	0	0	0	0	125	1	62ee1fd9f9a22ab9e96fecd75c59f9f0	f	t	300
208	1	0	0	0	0	0	0	162	1	03e5c8530365e49332badcda26958ea3	f	f	300
209	1	0	0	0	0	0	0	163	1	523bfb407960412e6e47626f06aee69d	f	f	300
161	2	0	0	0	0	0	0	132	1	689b3acfa23bb7f824ac99bc106c1ef0	f	t	600
197	1	0	0	0	0	0	0	156	1	e4886d457211f5926dc51264399afb84	f	t	300
211	1	0	0	0	0	0	0	164	1	c72c25db104d0cf969f171de4677149c	f	f	300
212	1	0	0	0	0	0	0	165	1	70a01c2ace63305acab59783e2978967	f	f	300
213	2	0	0	0	0	0	0	166	1	876d1d2d2af3553ba7ee84e0f3237056	f	f	600
214	2	0	0	0	0	0	0	151	1	309d2527b1060b86dc9cb955cb184a7b	f	f	600
216	1	0	0	0	0	0	0	168	1	eae2f3cb9f13906388ff517e8bf6ccca	f	t	300
218	2	0	0	0	0	0	0	170	1	f8309f28bd15b57476be9accc6de804b	f	f	600
183	1	0	0	0	0	0	0	148	1	93792238ed7124bf5627a9d75aaf9f47	f	t	300
220	1	0	0	0	0	0	0	31	1	256a4825ceb721ffafa9a1c06db66e4f	f	f	300
204	1	0	0	0	0	0	0	160	1	831afe8ebaefb2917db2de090c661be6	f	t	300
219	1	0	0	0	0	0	0	171	1	f80898908eb033159a7b56d046aafac1	f	t	300
215	2	0	0	0	0	0	0	167	1	bbc376c59a504550a364443c104c08bc	f	t	600
199	1	0	0	0	0	0	0	157	1	99b4e930545ac348e234304dadcd227c	f	t	300
200	2	0	0	0	0	0	0	158	1	7eb5e42f16ab4fabda2561643ea515ce	f	t	600
130	2	0	0	0	0	0	0	54	1	60aca6e3cd47c796c45d8b04b82362d6	f	t	600
192	2	0	0	0	0	0	0	154	1	ef28376e3afbfad8eda852e015985d1c	f	t	600
186	2	0	0	0	0	0	0	150	1	47bbe643e9b5c125d2e80985afa31baa	f	t	600
195	1	0	0	0	0	0	0	150	1	fd451af83b382e19f46d03e4ae23842e	f	t	300
174	1	0	0	0	0	0	0	8	1	5f361fe759ccf4934d3193b38e2f9304	f	t	300
203	2	0	0	0	0	0	0	95	1	8b125d65a324ffb8dcdf922dfba3a4fa	f	t	600
196	2	0	0	0	0	0	0	50	1	9fe5e1d016862bdf0ff63fb3902445f1	f	t	600
217	2	0	0	0	0	0	0	169	1	098a8102f70900ce5ba0bef22bca7363	f	t	600
168	1	0	0	0	0	0	0	138	1	3c9c31c685b5b75a527eed234c8c9d06	f	t	300
163	2	0	0	0	0	0	0	134	1	94436ddddb40b7dfb0af7df44e99b81d	f	t	600
210	1	0	0	0	0	0	0	95	1	9af57348e4af6d55150bd5de2b92a10e	f	f	300
167	1	0	0	0	0	0	0	5	1	5e6b9579d7e9bb6365e457bfe5bd090b	f	t	300
165	2	0	0	0	0	0	0	136	1	6f25a92b814786de2e8d46e92fe9669d	f	t	600
222	2	0	0	0	0	0	0	173	1	dc837e9d57c34caa4daadfa84baab236	f	f	600
223	1	0	0	0	0	0	0	174	1	92c504fd246ffbddedb16ef7e607b427	f	f	300
198	1	0	0	0	0	0	0	73	1	c0176a40b83c2f2d3cf66aee6cb39f5c	f	t	300
225	1	0	0	0	0	0	0	175	1	9d05b96879881704fe8ae31932ed8b7c	f	f	300
227	2	0	0	0	0	0	0	177	1	6561e7865365fa16b2f567ef7e0dbe1d	f	f	600
228	1	0	0	0	0	0	0	14	1	2023b8dd7ab23e91e2985c573ad0af6e	f	f	300
230	2	0	0	0	0	0	0	179	1	3dac73e644aea80787d0511eb2218d06	f	f	600
231	2	0	0	0	0	0	0	180	1	45967b36601e199f322508d730b7bdaa	f	f	600
233	1	0	0	0	0	0	0	18	1	2c4f68bf3b523e2bd69796cbcc97d681	f	f	300
234	2	0	0	0	0	0	0	173	1	5ef9c482d85788c0e76ff38c6856560b	f	f	600
236	1	0	0	0	0	0	0	130	1	8da16963343e648d1157336e212e0057	f	f	300
237	1	0	0	0	0	0	0	182	1	f1fd84a60c93c64e9ac667d4992402ef	f	f	300
239	2	0	0	0	0	0	0	86	1	588317575547f4c5a3f6106e751967df	f	f	600
241	2	0	0	0	0	0	0	85	1	fccbb6c0f47b529e5206a7322d3caa95	f	f	600
242	2	0	0	0	0	0	0	184	1	a99ab1bce41fb0f1f011c2d10332b8aa	f	f	600
243	1	0	0	0	0	0	0	185	1	56bb06c78ed2b65b8df8d378bdb3af8d	f	f	300
246	1	0	0	0	0	0	0	187	1	1f5c28360b89c87561c9580c54c3fd38	f	f	300
247	2	0	0	0	0	0	0	113	1	8dc2ded03ca4dd40f184357ea2d49fb8	f	f	600
248	1	0	0	0	0	0	0	137	1	17cfd35b0507970d9a430e37e01a76a8	f	f	300
249	1	0	0	0	0	0	0	188	1	3c2f2347e786eee952bd89322d87af1e	f	f	300
251	1	0	0	0	0	0	0	152	1	f01cdee4b840a3dbcbe3d30739e0d9e7	f	f	300
252	2	0	0	0	0	0	0	79	1	97be06a4c80468f1ca08b8554aae5de5	f	f	600
253	2	0	0	0	0	0	0	8	1	82c3e4a28ec2ebc716648f3ceeadee45	f	f	600
254	1	0	0	0	0	0	0	31	1	ea2ca37197ca2026af38ae8450dfb971	f	f	300
255	1	0	0	0	0	0	0	67	1	78af484031bb51534e6dad08ad721f8a	f	f	300
240	2	0	0	0	0	0	0	183	1	a96281cc059aaac02e3f56c8e4e29f9f	f	t	600
256	2	0	0	0	0	0	0	190	1	edc65f3660cd564eca9adce5473f76e9	f	f	600
257	2	0	0	0	0	0	0	191	1	df1cfd5bec80b07c1a535e40d8333691	f	f	600
178	1	0	0	0	0	0	0	143	1	e37e486bafe1c03e403ade38848da13e	f	t	300
258	1	0	0	0	0	0	0	192	1	bb3b7dfb6a797da06ceda0451b0bc953	f	f	300
259	1	0	0	0	0	0	0	173	1	be2638cc5310b423fc87729e0355b897	f	f	300
187	1	0	0	0	0	0	0	54	1	6d981e863ee564bef270092ca651b18f	f	t	300
261	1	0	0	0	0	0	0	70	1	6eb4a900539cddde841c93773ac75949	f	f	300
262	2	0	0	0	0	0	0	194	1	86389b2bbcc389e09a2950d4dab7becb	f	f	600
263	1	0	0	0	0	0	0	195	1	c394421a28115e1c5529d71c778078a7	f	f	300
264	2	0	0	0	0	0	0	196	1	db773af2cdff7423fa4067a807aa030c	f	f	600
265	2	0	0	0	0	0	0	197	1	74b074f8bc4c6077d9ecd43baeabb8d3	f	f	600
266	1	0	0	0	0	0	0	195	1	d947963916ba41a6c2375212eb5c79f0	f	f	300
267	2	0	0	0	0	0	0	85	1	a1afb925039d84c277feda9fa307910d	f	f	600
268	1	0	0	0	0	0	0	36	1	6f49710fb929818452c7f3a951ba1464	f	f	300
269	1	0	0	0	0	0	0	198	1	07d6f7288fb03ff00c2d5800ff77b76b	f	f	300
270	1	0	0	0	0	0	0	89	1	b12ae6a95a0941c90feb2228b6b695e2	f	f	300
271	2	0	0	0	0	0	0	73	1	da32691118c61781c76199e4418a4205	f	f	600
272	1	0	0	0	0	0	0	53	1	3fa367b6d2c75c669eee745a4295cf2d	f	f	300
229	2	0	0	0	0	0	0	170	1	d51ca65b2ec501f806972c05018e9820	f	f	600
273	1	0	0	0	0	0	0	170	1	fc090887b8a9bf8b291ba0b577ea2145	f	f	300
232	2	0	0	0	0	0	0	181	1	8da3e257bc817fbebc58a156d0275050	f	t	600
275	1	0	0	0	0	0	0	137	1	4294a58dd4574e69b9d1ab12b68452b4	f	f	300
276	1	0	0	0	0	0	0	165	1	b3a8d1cb4bbe340d9f3d620c8cb235b3	f	f	300
38	2	0	0	0	0	0	0	36	1	2e6cc17bd085e7c77b35ff8d00a417e1	f	t	600
277	2	0	0	0	0	0	0	199	1	23896b2bd19f91c64ecf68d118f172b7	f	f	600
280	1	0	0	0	0	0	0	134	1	aa114ee91256e22a5b9ff354f0ee6f81	f	f	300
281	2	0	0	0	0	0	0	50	1	0fdf423de450f09c730af20465c81b06	f	f	600
282	1	0	0	0	0	0	0	93	1	e1925d073ffcba4967ca8dd6071fa614	f	t	300
283	2	0	0	0	0	0	0	162	1	8803180ff9fa0a3511655129de2ba904	f	f	600
284	1	0	0	0	0	0	0	67	1	2b7b26ab01aa840948a1dee35b777e2c	f	f	300
286	2	0	0	0	0	0	0	50	1	04074ac86bcf45b28037a6ad9327a365	f	f	600
287	1	0	0	0	0	0	0	200	1	b04fa994121810eba639654c19946d38	f	f	300
288	1	0	0	0	0	0	0	187	1	efbbd97e162253f4601ec9b7593835f3	f	f	300
289	1	0	0	0	0	0	0	191	1	dcfcdd3f806e6c3f7824ce682ea95d2b	f	f	300
291	1	0	0	0	0	0	0	106	1	c893376c9f69619b25bfe041e8e7f734	f	f	300
226	2	0	0	0	0	0	0	176	1	31d66d9ebc42018d8b5dd0a024025b19	f	t	600
274	1	0	0	0	0	0	0	30	1	38ad1a77af206ac95ff171a282b47c02	f	t	300
260	2	0	0	0	0	0	0	193	1	579dc3498ee5652a53ae7f21dabc9f6c	f	t	600
235	1	0	0	0	0	0	0	35	1	fcb46e8c686015f1013a625d60a056cc	f	t	300
244	1	0	0	0	0	0	0	5	1	573b4b7a9bedd2e9ba2295b3abbe902b	f	t	300
221	2	0	0	0	0	0	0	172	1	425f6aeb09c19dc8ee42d3dc8a75c542	f	t	600
245	2	0	0	0	0	0	0	186	1	b4860d408a4490dcb35a5c4b5b0f24cf	f	t	600
285	1	0	0	0	0	0	0	147	1	0333614a30472e08cd5b0061eecdd5bf	f	t	300
250	2	0	0	0	0	0	0	179	1	aaccbfd2aa48a0055be3b45bdc7d360e	f	f	600
290	1	0	0	0	0	0	0	201	1	5cf3193fd1c803a85504c0095c78af60	f	t	300
278	1	0	0	0	0	0	0	147	1	07b7eb91568a6b271e78cc72f360bff0	f	t	300
238	1	0	0	0	0	0	0	37	1	09772d30f2c88205621184e5875b5964	f	t	300
292	2	0	0	0	0	0	0	188	1	fee2ff4d5a0ad063edda30614a5b8d22	f	f	600
224	1	0	0	0	0	0	0	152	1	d0da22d4855335fee29a8e067e436242	f	t	300
294	1	0	0	0	0	0	0	202	1	dfe76bf93f8630b13b390f38e0f82a1c	f	f	300
296	1	0	0	0	0	0	0	204	1	2edf7f8314734e7a50ccb3e43f56dd9d	f	f	300
297	1	0	0	0	0	0	0	205	1	d0539981dad9add94eb98cf20c9749f6	f	f	300
298	1	0	0	0	0	0	0	206	1	22efe6239d4dc1fbca6461f489f9290d	f	f	300
299	1	0	0	0	0	0	0	207	1	923e64b8260d2a16589019fe9cd9407c	f	f	300
300	2	0	0	0	0	0	0	152	1	8c5242c6567cf8540e190dcd2496b414	f	f	600
301	2	0	0	0	0	0	0	18	1	91ec0b581522e171f639f3f2191127b7	f	f	600
304	2	0	0	0	0	0	0	111	1	a2745fe0ef8167949f75e02644219c0d	f	f	600
305	2	0	0	0	0	0	0	129	1	d8b5169bade2081cfeed8cd686096928	f	f	600
306	2	0	0	0	0	0	0	118	1	7447fedb184d41ac86d3c4e7eb3cb532	f	f	600
308	2	0	0	0	0	0	0	137	1	c9209993a850a6af6f084a7fdf93a60d	f	f	600
309	1	0	0	0	0	0	0	210	1	0fcea92745dec6132f11f6d6f842c6ed	f	f	300
311	2	0	0	0	0	0	0	206	1	2b4d542377cf69554e09184cefa545a8	f	f	600
312	1	0	0	0	0	0	0	211	1	29acbdaa289953a8ae41a751e8fd18be	f	f	300
313	1	0	0	0	0	0	0	95	1	e01cb4760a05777e747d45c1b6db66c9	f	f	300
314	2	0	0	0	0	0	0	72	1	d69f0cbd0c952e042ffce1f33decb615	f	f	600
37	2	0	0	0	0	0	0	5	1	2d1b0e75766596b98fe97be054eb180f	f	t	600
5	2	0	0	0	0	0	0	5	1	31a806205ef0423d88222bb832a08ad2	f	t	600
315	2	0	0	0	0	0	0	134	1	1da732842eebe3cc2db19eb40d221298	f	f	600
293	2	0	0	0	0	0	0	43	1	58fd9bda7827a17d20f149fac33eeb58	f	t	600
316	1	0	0	0	0	0	0	134	1	722f632eea3af937358e1f6538e24b44	f	f	300
317	2	0	0	0	0	0	0	212	1	3e44470ce7fdb85076840ff185ac6263	f	f	600
318	1	0	0	0	0	0	0	53	1	c1a8c78258d0d7546ba3baf5f6f720d4	f	f	300
319	1	0	0	0	0	0	0	213	1	fa23d8802038deb51694840361a9034d	f	f	300
320	2	0	0	0	0	0	0	214	1	5c0279861f2f2771dbdf156aca21d192	f	f	600
295	2	0	0	0	0	0	0	203	1	4f8040c63f71d6cbce50aa5494d3b5ab	f	t	600
302	1	0	0	0	0	0	0	139	1	6bbf5a32e7a988bc3573b13c9d784b62	f	f	300
321	1	0	0	0	0	0	0	139	1	c95a4744a96bfd6ef530ccb526a101c5	f	f	300
322	2	0	0	0	0	0	0	50	1	abee30dc31212bbb12fae53f6e72e6f6	f	f	600
324	2	0	0	0	0	0	0	50	1	61f51b57533903b2c501f8f846e0bd72	f	f	600
325	1	0	0	0	0	0	0	216	1	3487acb6dbb7da2f30b824e066509b48	f	f	300
326	1	0	0	0	0	0	0	146	1	c2cbedd06ce67d04fa71ffc1d32d6de3	f	f	300
327	1	0	0	0	0	0	0	200	1	18a458e296f59b679c9e77f7a096243b	f	f	300
310	2	0	0	0	0	0	0	78	1	05646017e35f24f5bd3bddcd07d35fe8	f	f	600
328	2	0	0	0	0	0	0	78	1	88ac89d8fd144f68f4771ea061939c1f	f	f	600
329	1	0	0	0	0	0	0	179	1	9b7e04e5271f4928ff7f6f1ccbb04741	f	f	300
330	1	0	0	0	0	0	0	217	1	61d1e85e506d3af5a831c103ca324a7c	f	f	300
331	1	0	0	0	0	0	0	215	1	f9e3d69d3fa04579e9e791bdc449d78f	f	f	300
332	1	0	0	0	0	0	0	155	1	decb7cf81cf4db328ac3692d83f8c3b2	f	f	300
333	1	0	0	0	0	0	0	113	1	cab9dacfedc6dcd5736c25375df55168	f	f	300
334	2	0	0	0	0	0	0	134	1	8025d59e97bc6251500770d253799fbd	f	f	600
335	1	0	0	0	0	0	0	218	1	db546ce16b534bf6e72ebf23fa2fb00a	f	f	300
336	1	0	0	0	0	0	0	89	1	faaf36d0f46e229f339d7b17ff69522e	f	f	300
337	2	0	0	0	0	0	0	218	1	622e781750bc5db73544d213e836a77d	f	f	600
338	2	0	0	0	0	0	0	1	1	07644fddd4b641bd4e01b4939f14682d	f	f	600
339	2	0	0	0	0	0	0	219	1	c2f3669de07ad250c1f5d1eb31f38719	f	f	600
340	2	0	0	0	0	0	0	211	1	eff87fe15c92e18d6f968cdfc39373b4	f	f	600
341	1	0	0	0	0	0	0	194	1	2cd01c9748bd7d9626021f5a664b0aef	f	f	300
342	2	0	0	0	0	0	0	89	1	372a1c0585917356ce54d64bdb105960	f	f	600
343	1	0	0	0	0	0	0	180	1	ad7badada8dfa71f6cd6d74c270485ce	f	f	300
344	2	0	0	0	0	0	0	52	1	881dba62ef615b34da18a897c74cc217	f	f	600
345	2	0	0	0	0	0	0	30	1	d36658076bef7aaa70e948ba49b4a101	f	f	600
303	1	0	0	0	0	0	0	209	1	26eb873099904ca71730bb5256943b0d	f	t	300
347	2	0	0	0	0	0	0	101	1	58372fbb2dbf3b97c5752b94e2c03a6a	f	f	600
348	1	0	0	0	0	0	0	86	1	ef378c7368da3efa30b4d59c361ac8fa	f	f	300
349	2	0	0	0	0	0	0	205	1	2aa2cf1d4c9d57a42dc1dfc07cc4e5d2	f	f	600
350	2	0	0	0	0	0	0	221	1	4e3459b876c8a10d24ab4c0e158f8cd3	f	f	600
351	1	0	0	0	0	0	0	30	1	cf357860f7bb9048d74e125d0b612518	f	f	300
352	1	0	0	0	0	0	0	222	1	7912cef580b7c92763f5b38af49065ad	f	f	300
353	1	0	0	0	0	0	0	93	1	e0f7b4febe49d693aa579dae63bf1801	f	f	300
354	1	0	0	0	0	0	0	79	1	cef2ead756d4b1abe2d3636e5daa10b7	f	f	300
355	2	0	0	0	0	0	0	70	1	a5d4f3e0e6b55b0309c346bfa4dbb7aa	f	f	600
356	1	0	0	0	0	0	0	223	1	1f42bd9d81b7f4b97dba36bc7957f0d8	f	f	300
357	2	0	0	0	0	0	0	166	1	55de92b3a39aa64d0e85bd083935db59	f	f	600
358	1	0	0	0	0	0	0	224	1	1171408db29eb39f2ba9aff9ad3d1aaf	f	f	300
359	2	0	0	0	0	0	0	210	1	ac7441ce2f6a294f49396fdd2cae06ba	f	f	600
307	2	0	0	0	0	0	0	85	1	0cb57d507dfcde99902346f13bb53a8c	f	t	600
279	2	0	0	0	0	0	0	37	1	6a455e321ec269d829a2bd618bf82b13	f	t	600
360	1	0	0	0	0	0	0	173	1	dd008719b28593393f7172b21d10a19b	f	f	300
361	2	0	0	0	0	0	0	225	1	d5646db28db59ad7ab978de969bc70d1	f	f	600
323	2	0	0	0	0	0	0	215	1	5c35d7b0a0210d1c41c033f90b97885b	f	t	600
362	1	0	0	0	0	0	0	226	1	16067c6a10a9f87f378b47ba1b85b6ed	f	f	300
346	1	0	0	0	0	0	0	220	1	d5673e0b7e9550a21ed606bb75d39a42	f	t	300
363	2	0	0	0	0	0	0	165	1	b339c673022ed64598d7318aa01f0752	f	f	600
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
163	1751352569580	1751356398580	1757000	2	\N	f	\N
3	1750266889273	1750269529273	\N	1	\N	t	\N
81	1751039628460	1751043148460	1763000	1	\N	t	\N
7	1751008131825	1751010794825	1378000	1	\N	t	\N
110	1750964973711	1750970442711	1492000	2	\N	t	message
47	1750432405371	1750439643533	21000	1	\N	f	\N
17	1751104740735	1751107819735	2052000	1	\N	t	message
12	1750682493737	1750685674737	1613000	1	\N	t	message
22	1751183052450	1751188148450	1609000	1	\N	t	message
55	1750931321510	1750936643510	952000	1	\N	f	\N
6	1751305024916	1751307860916	1381000	1	\N	t	\N
44	1751115051424	1751119297424	1480000	1	\N	t	message
50	1751106306930	1751142292082	168000	2	\N	f	\N
20	1750844094194	1750847295194	1470000	1	\N	t	message
32	1750903734240	1750907884240	1845000	1	\N	t	message
10	1751089243339	1751093274339	123000	1	\N	t	message
41	1750187383079	1750190475079	\N	1	\N	t	\N
87	1750903553302	1750906259302	2112000	1	\N	f	\N
23	1750751240832	1750755252832	\N	1	\N	t	message
74	1751046538259	1751051423259	1726000	1	\N	f	\N
8	1750759547425	1750767681979	1720000	1	\N	f	\N
77	1750837479959	1750840677959	364000	1	\N	t	message
109	1750682704035	1750688480035	1940000	2	\N	t	message
36	1751011912699	1751020118821	999000	1	\N	f	\N
94	1751207894038	1751221014046	579000	2	\N	f	\N
34	1750729436000	1750733603000	1788000	1	\N	t	message
45	1751028182350	1751030271350	817000	1	\N	t	message
63	1750565394920	1750568345920	1485000	1	\N	t	message
4	1750595284166	1750598188166	2288000	1	\N	t	\N
97	1750420393689	1750423386689	994000	2	\N	t	message
39	1750619609550	1750623002550	146000	1	\N	f	\N
19	1750447728910	1750451308910	1177000	1	\N	t	message
42	1750404865929	1750407990929	\N	2	\N	t	message
15	1751312957212	1751316794212	2102000	1	\N	t	message
27	1751075288214	1751077990214	1173000	1	\N	t	message
2	1750878547826	1750882955826	1680000	1	\N	t	\N
25	1750435166962	1750440435962	2459000	1	\N	t	\N
29	1751098358694	1751103541694	31000	1	\N	t	message
75	1750565500773	1750569861773	\N	2	\N	t	\N
56	1750559847633	1750563617633	1523000	1	\N	f	\N
28	1750581880114	1750586794114	975000	1	\N	t	message
102	1750998644801	1751003857801	297000	1	\N	t	message
160	1751225100467	1751229249467	1922000	1	\N	t	\N
61	1750189084960	1750194116960	\N	1	\N	f	\N
71	1751010718161	1751013542161	117000	1	\N	t	\N
64	1750691192464	1750693660464	560000	1	\N	t	message
9	1751138987580	1751142400580	252000	1	\N	t	\N
111	1751037378212	1751043055054	1096000	2	\N	f	\N
68	1750443826313	1750447617313	1391000	1	\N	t	\N
57	1751088034707	1751090796707	297000	1	\N	t	\N
70	1750274194042	1750280683291	1159000	1	\N	f	\N
112	1750261639001	1750264065001	615000	1	\N	t	message
108	1751336358011	1751339604011	716000	1	\N	f	\N
33	1750676799116	1750681286116	1640000	1	\N	t	message
26	1750966534000	1750972722000	2517000	1	\N	t	message
53	1750512763682	1750525639834	134000	1	\N	f	\N
43	1750863989238	1750871152309	1815000	1	\N	t	message
38	1750528319304	1750530549304	131000	1	\N	f	\N
24	1750913199185	1750917683185	1945000	1	\N	t	\N
49	1750832458190	1750834559190	447000	1	\N	f	\N
11	1750534815275	1750536965275	540000	1	\N	t	\N
89	1750430462326	1750441423931	2137000	2	\N	f	\N
96	1750417825526	1750422336526	114000	1	\N	t	message
161	1750423155052	1750428760052	2392000	1	\N	f	\N
58	1750952956017	1750959183017	2677000	2	\N	t	\N
100	1750654670679	1750657677679	725000	1	\N	f	\N
83	1751052648982	1751057098982	\N	2	\N	t	message
60	1750337048333	1750339278333	1172000	1	\N	t	\N
76	1750824378370	1750827352370	1403000	1	\N	t	message
99	1750319212414	1750322772414	363000	1	\N	f	\N
31	1750472078316	1750477554645	1062000	2	\N	f	\N
98	1750784867563	1750789435563	\N	2	\N	t	\N
106	1750388485423	1750399478966	2161000	2	\N	f	\N
80	1751268730997	1751271902997	1854000	1	\N	t	\N
78	1750586359715	1750604448915	1291000	1	\N	f	\N
67	1750874488366	1750884831222	1122000	1	\N	f	\N
79	1751287053150	1751304467953	349000	2	\N	f	\N
82	1750579130675	1750582903675	43000	1	\N	t	\N
103	1751170520667	1751174117667	75000	2	\N	t	\N
65	1751375072956	1751377266956	783000	1	\N	t	message
91	1750685995906	1750689089906	101000	1	\N	t	\N
66	1751052193526	1751055377526	1754000	1	\N	t	\N
5	1750778743035	1750798312572	1777000	1	\N	t	message
72	1750216961300	1750234563883	2119000	1	\N	f	\N
51	1751173206986	1751176030986	177000	1	\N	f	\N
16	1750645625389	1750653697857	1627000	1	\N	f	\N
164	1751037543728	1751040900728	2367000	1	\N	f	\N
59	1750817598200	1750819794200	838000	1	\N	f	\N
48	1751356476214	1751359029214	1433000	1	\N	t	\N
105	1750865513351	1750867533351	1490000	2	\N	f	\N
62	1750775245911	1750778671911	1627000	1	\N	t	message
69	1750910714919	1750917939824	1625000	2	\N	f	\N
21	1751138677568	1751141861568	1552000	2	\N	t	message
13	1750310413982	1750315072982	2341000	1	\N	f	\N
107	1750249855105	1750253925105	948000	2	\N	t	\N
1	1751267545874	1751281595787	1984000	1	\N	f	\N
101	1750987529000	1751025933968	3055000	2	\N	f	\N
104	1750238549166	1750240753166	532000	1	\N	t	message
30	1750939939051	1750964520217	1821000	1	\N	f	\N
93	1750920682333	1750927580467	189000	1	\N	f	\N
37	1750384571674	1750407028154	900000	1	\N	t	message
84	1751213810611	1751221716485	2686000	1	\N	t	message
18	1750407028155	1750418777122	1468000	1	\N	f	\N
40	1751021506196	1751024316196	148000	1	\N	t	message
115	1750654333008	1750657927008	1621000	2	\N	t	\N
220	1751163556909	1751168218909	1811000	2	\N	t	\N
125	1751137266336	1751140266336	202000	1	\N	t	\N
121	1750920481071	1750923060071	1516000	2	\N	f	\N
126	1750488642129	1750490905129	221000	1	\N	f	\N
128	1750849406038	1750852405038	1138000	2	\N	t	message
122	1751227223950	1751230038950	168000	1	\N	t	message
185	1750749693314	1750752707314	560000	1	\N	f	\N
132	1750259111203	1750263866203	2881000	2	\N	t	message
177	1751348586106	1751352302106	1269000	2	\N	f	\N
184	1750536794826	1750539795826	806000	2	\N	f	\N
156	1750998073085	1751000427085	1470000	2	\N	t	\N
116	1750879091196	1750881419196	156000	2	\N	t	message
131	1750904218242	1750909146242	2077000	2	\N	f	\N
119	1750577609978	1750581377978	171000	1	\N	t	message
54	1751184331561	1751199208355	2336000	1	\N	t	message
167	1750364162410	1750368311410	1323000	2	\N	t	message
151	1750660921167	1750667989257	136000	1	\N	f	\N
142	1750496742108	1750500333108	1415000	2	\N	t	\N
170	1751046684023	1751057279238	2197000	2	\N	f	\N
168	1750239323454	1750242166454	156000	1	\N	t	\N
133	1751349580551	1751353949551	144000	1	\N	f	\N
144	1750670522240	1750674762240	1114000	1	\N	t	\N
127	1750605480460	1750609309460	2362000	1	\N	f	\N
148	1750875851497	1750878389497	1132000	1	\N	t	\N
198	1751342511731	1751346916731	2064000	1	\N	f	\N
145	1750487737307	1750491052307	1173000	2	\N	t	\N
123	1750530166770	1750534614770	2541000	2	\N	f	\N
159	1750477831854	1750482798854	1120000	2	\N	f	\N
157	1751202764866	1751205630866	1923000	1	\N	t	message
213	1751161255179	1751165828179	2023000	1	\N	f	\N
175	1750491479257	1750494224257	575000	1	\N	f	\N
14	1750476889639	1750483770262	2105000	1	\N	f	\N
194	1751027269642	1751035637041	2176000	1	\N	f	\N
171	1751207650809	1751210663809	1005000	1	\N	t	\N
154	1750704585124	1750706789124	2019000	1	\N	t	message
205	1750571307467	1750580591488	1464000	1	\N	f	\N
35	1750496351027	1750509620653	316000	1	\N	f	\N
182	1750612343649	1750615357649	1002000	1	\N	f	\N
149	1750228408634	1750230944634	1126000	2	\N	f	\N
187	1750836984978	1750844944979	1627000	2	\N	f	\N
188	1750564965408	1750568539079	1118000	1	\N	f	\N
158	1751077291357	1751081112357	338000	1	\N	t	message
209	1750239264981	1750242942981	1192000	2	\N	t	\N
219	1751093117439	1751096181439	910000	2	\N	f	\N
204	1751258676657	1751263489657	2027000	2	\N	f	\N
183	1751197434021	1751202840021	1683000	2	\N	t	message
190	1751314700128	1751317507128	188000	1	\N	f	\N
143	1751056149835	1751058810835	1992000	1	\N	t	\N
129	1750189495640	1750194962641	\N	2	\N	f	\N
214	1751312454930	1751316827930	1601000	2	\N	f	\N
192	1750662510210	1750666859210	1829000	2	\N	f	\N
152	1750988599896	1751000661843	2080000	1	\N	f	\N
197	1751374873063	1751377627063	394000	1	\N	f	\N
195	1750239619669	1750245200161	1940000	1	\N	f	\N
153	1750363555793	1750367769793	2235000	1	\N	f	\N
150	1750931256674	1750940290025	826000	2	\N	t	message
140	1750944216143	1750948174143	774000	2	\N	f	\N
181	1751273736110	1751278702110	355000	2	\N	t	message
162	1750420554716	1750428037772	1476000	2	\N	f	\N
134	1751178009450	1751194087057	1112000	1	\N	f	\N
199	1751383190770	1751386967770	99000	1	\N	f	\N
117	1750597908229	1750602291229	200000	2	\N	t	message
136	1750249334576	1750254084576	184000	2	\N	t	\N
169	1751219710307	1751222566307	1116000	1	\N	t	message
147	1750846710561	1750860253298	257000	1	\N	f	\N
191	1750686066687	1750694179591	2276000	2	\N	f	\N
138	1751358657425	1751361588425	1630000	1	\N	t	message
196	1751363787376	1751368076376	193000	1	\N	f	\N
176	1750954363236	1750956887236	1516000	2	\N	t	message
202	1750747631749	1750750323749	181000	2	\N	f	\N
186	1750587259215	1750589239215	1829000	2	\N	t	message
207	1751002919478	1751006360478	1383000	1	\N	f	\N
118	1750296636103	1750308260328	2004000	1	\N	f	\N
137	1750322772415	1750356265579	735000	1	\N	f	\N
206	1750754121765	1750759441421	996000	2	\N	f	\N
193	1750825712952	1750828259952	122000	1	\N	t	\N
172	1750781348076	1750784652076	1070000	2	\N	t	message
124	1750824636379	1750828801379	142000	2	\N	f	\N
212	1751141397292	1751144839292	1334000	1	\N	f	\N
203	1750755753424	1750759547424	287000	1	\N	t	message
85	1751093062149	1751112820433	348000	1	\N	f	\N
139	1751079798084	1751093062148	1878000	1	\N	f	\N
216	1751130720574	1751134757574	1961000	1	\N	f	\N
146	1750560143681	1750567455090	1295000	2	\N	f	\N
200	1750732876966	1750739264380	1356000	1	\N	f	\N
179	1750486807121	1750496804317	2036000	2	\N	f	\N
217	1750504518993	1750507554993	226000	2	\N	f	\N
174	1750773386034	1750778743034	2481000	1	\N	f	\N
201	1750258694619	1750264607619	286000	1	\N	t	\N
155	1750853890525	1750858463769	2342000	2	\N	f	\N
113	1750606807045	1750622384386	1989000	2	\N	f	\N
218	1750350372071	1750358663341	1193000	2	\N	f	\N
95	1751248544317	1751264427216	1370000	1	\N	f	\N
211	1751194087058	1751211111766	416000	1	\N	f	\N
180	1750532880492	1750538964720	1508000	1	\N	f	\N
52	1750249990901	1750255828901	1236000	1	\N	f	\N
215	1750250899323	1750255972766	1098000	2	\N	f	\N
86	1750686281947	1750696596551	1875000	1	\N	f	\N
221	1750780176442	1750783619442	1444000	1	\N	f	\N
141	1750344292720	1750347058720	1358000	2	\N	f	\N
222	1750329208255	1750333930255	1835000	2	\N	f	\N
73	1751301628443	1751307731844	1739000	1	\N	f	\N
210	1750399478967	1750407153291	1529000	2	\N	f	\N
173	1750510158082	1750522193984	1264000	2	\N	f	\N
90	1750273629156	1750278195156	180000	2	\N	f	\N
130	1751181788013	1751193393935	1541000	2	\N	f	\N
165	1750642576192	1750656402269	2640000	2	\N	f	\N
223	1751293774042	1751298452042	1599000	1	\N	f	\N
166	1750672147675	1750681050086	1808000	1	\N	f	\N
224	1750262765173	1750266237173	1638000	1	\N	f	\N
225	1751086631475	1751090771475	1995000	2	\N	f	\N
226	1750525179945	1750529954945	1483000	2	\N	f	\N
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

SELECT pg_catalog.setval('public.availability_id_seq', 30, true);


--
-- Name: booking_api_parameters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.booking_api_parameters_id_seq', 363, true);


--
-- Name: company_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.company_id_seq', 8, true);


--
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.event_id_seq', 726, true);


--
-- Name: journey_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.journey_id_seq', 1, false);


--
-- Name: request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.request_id_seq', 363, true);


--
-- Name: tour_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tour_id_seq', 226, true);


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

