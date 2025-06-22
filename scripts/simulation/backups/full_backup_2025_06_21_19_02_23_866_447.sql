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
1	1750529351616	1750543200000	1
2	1750554000000	1750629600000	1
3	1750640400000	1750716000000	1
4	1750813200000	1750888800000	1
5	1750899600000	1750975200000	1
6	1750726800000	1750802400000	1
7	1750986000000	1751061600000	1
8	1751072400000	1751148000000	1
9	1751158800000	1751234400000	1
10	1751245200000	1751320800000	1
11	1751331600000	1751407200000	1
12	1751418000000	1751493600000	1
13	1751504400000	1751580000000	1
14	1751590800000	1751666400000	1
15	1751677200000	1751738951616	1
16	1750529351658	1750543200000	2
17	1750554000000	1750629600000	2
18	1750640400000	1750716000000	2
19	1750726800000	1750802400000	2
20	1750813200000	1750888800000	2
21	1750899600000	1750975200000	2
22	1750986000000	1751061600000	2
23	1751072400000	1751148000000	2
24	1751158800000	1751234400000	2
25	1751245200000	1751320800000	2
26	1751331600000	1751407200000	2
27	1751418000000	1751493600000	2
28	1751504400000	1751580000000	2
29	1751590800000	1751666400000	2
30	1751677200000	1751738951658	2
31	1750529367511	1750543200000	1
32	1750726800000	1750802400000	1
33	1750813200000	1750888800000	1
34	1750986000000	1751061600000	1
35	1750899600000	1750975200000	1
36	1750640400000	1750716000000	1
37	1750554000000	1750629600000	1
38	1751072400000	1751148000000	1
39	1751245200000	1751320800000	1
40	1751158800000	1751234400000	1
41	1751331600000	1751407200000	1
42	1751418000000	1751493600000	1
43	1751504400000	1751580000000	1
44	1751590800000	1751666400000	1
45	1751677200000	1751738967511	1
46	1750529367560	1750543200000	2
47	1750554000000	1750629600000	2
48	1750640400000	1750716000000	2
49	1750726800000	1750802400000	2
50	1750813200000	1750888800000	2
51	1750899600000	1750975200000	2
52	1750986000000	1751061600000	2
53	1751072400000	1751148000000	2
54	1751158800000	1751234400000	2
55	1751245200000	1751320800000	2
56	1751331600000	1751407200000	2
57	1751418000000	1751493600000	2
58	1751504400000	1751580000000	2
59	1751590800000	1751666400000	2
60	1751677200000	1751738967560	2
\.


--
-- Data for Name: booking_api_parameters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.booking_api_parameters (id, start_lat1, start_lng1, target_lat1, target_lng1, start_time1, target_time1, start_address1, target_address1, start_fixed1, start_lat2, start_lng2, target_lat2, target_lng2, start_time2, target_time2, start_address2, target_address2, start_fixed2, kids_zero_to_two, kids_three_to_four, kids_five_to_six, passengers, wheelchairs, bikes, luggage) FROM stdin;
1	51.53325	51.53325	51.3455	14.4871645	1751554811882	1751557375325	Mühlweg 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
2	51.544353	51.544353	51.54604	14.563206	1751464637669	1751466686948	Friedensstraße 62	Wake and Beach	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
3	51.529022	51.529022	51.525658	14.674166	1751647029610	1751648561239	Rohner Weg 13b	Krauschwitzer Weg 27	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
4	51.573074	51.573074	51.529625	14.523734	1750872682240	1750874471675	Schulstraße 25	Tischlereiweg 115a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
5	51.362946	51.362946	51.534534	14.523995	1751610802189	1751612102045	Körnerplatz	Neustädter Straße 7	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
6	51.527706	51.527706	51.56856	14.551886	1751600635525	1751602442109	Trebendorfer Weg 116b	Schützenverein Groß Düben	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
7	51.528664	51.528664	51.493687	14.51609	1751194089301	1751196650018	Rohner Weg 6	Die Protestantin	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
8	51.40764	51.40764	51.5446	14.535595	1751171151134	1751173908184	Körnerplatz	Schleife - Slepo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
9	51.473976	51.473976	51.5394	14.53161	1751357382116	1751360586833	Körnerplatz	Strugaaue 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
10	51.531254	51.531254	51.45097	14.713253	1750688320987	1750689987641	Dorfstraße 103	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
11	51.538887	51.538887	51.529022	14.529856	1751531892492	1751532818889	Zum Sportplatz 5	Rohner Weg 13b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
12	51.460445	51.460445	51.53411	14.53515	1751173311473	1751174904904	Körnerplatz	Schleifer Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
13	51.505684	51.505684	51.53841	14.525069	1751030956872	1751033615949	Körnerplatz	Jahnring 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
14	51.369408	51.369408	51.536358	14.529089	1751727143327	1751729468366	A16	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
15	51.323505	51.323505	51.544353	14.540508	1750692543560	1750694856195	Im Erlengrund 2	Friedensstraße 62	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
16	51.534534	51.534534	51.3591	14.653446	1751571696580	1751572903860	Neustädter Straße 7	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
17	51.534313	51.534313	51.46578	14.764196	1751135891153	1751138784925	Forstweg 78a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
18	51.432228	51.432228	51.540573	14.520827	1751351002166	1751352064403	Körnerplatz	Thälmann-Siedlung 25	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
19	51.549973	51.549973	51.534203	14.521786	1751075572584	1751078147766	Metallschleiferei Herbert Nikoleizig	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
20	51.529625	51.529625	51.34057	14.555876	1750849174570	1750850547037	Tischlereiweg 115a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
21	51.41371	51.41371	51.54269	14.530803	1751369614515	1751370870785	Körnerplatz	Hoyerswerdaer Straße 37	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
22	51.416073	51.416073	51.529236	14.521395	1751718125874	1751719747216	Merzdorfer Straße 38	Gefallenendenkmale Rohne	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
23	51.48654	51.48654	51.534534	14.523995	1750838499514	1750839916518	Körnerplatz	Neustädter Straße 7	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
24	51.535732	51.535732	51.462673	14.599626	1751112126683	1751115228443	Jahnring 13	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
25	51.39954	51.39954	51.534203	14.521786	1751650913222	1751652261600	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
26	51.54002	51.54002	51.567604	14.709137	1750861725924	1750863243883	Thälmann-Siedlung 8	Köbelner Straße 115	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
27	51.356236	51.356236	51.53053	14.532026	1751206424995	1751209489512	Körnerplatz	Rohner Weg 10	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
28	51.488773	51.488773	51.530224	14.525203	1751714128570	1751716660723	Körnerplatz	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
29	51.483776	51.483776	51.5446	14.535595	1750902679218	1750905809342	Körnerplatz	Schleife - Slepo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
30	51.43334	51.43334	51.538887	14.518962	1751566335495	1751567719028	Körnerplatz	Zum Sportplatz 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
31	51.53411	51.53411	51.470875	14.476694	1751335236537	1751337681891	Schleifer Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
32	51.344048	51.344048	51.536358	14.529089	1751345899120	1751348795632	Kascheler Wiese	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
33	51.45899	51.45899	51.535732	14.519293	1751342627897	1751344117437	Körnerplatz	Jahnring 13	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
34	51.36486	51.36486	51.539997	14.516031	1751463696151	1751465587097	Rotdornallee 21	Hoyerswerdaer Straße 90	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
35	51.532936	51.532936	51.360966	14.650531	1751644842674	1751647093713	Dorfstraße 106	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
36	51.534447	51.534447	51.54058	14.572735	1750919959922	1750922827710	Mulkwitzer Weg 10	Station 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
37	51.5394	51.5394	51.491993	14.519243	1751036791284	1751038691898	Strugaaue 2	Kohlebahnweg 86	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
38	51.489006	51.489006	51.532936	14.519677	1750882652667	1750884853987	Ausbauten 21	Dorfstraße 106	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
39	51.537445	51.537445	51.541637	14.528906	1750708685826	1750709992878	Kantweg 9	Lindenweg 20	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
40	51.569466	51.569466	51.535732	14.519293	1750771171979	1750774164815	Dorfstraße 20b	Jahnring 13	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
41	51.538887	51.538887	51.386826	14.52425	1750923827926	1750926171114	Zum Sportplatz 5	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
42	51.453247	51.453247	51.53531	14.528985	1751181097882	1751183590113	Körnerplatz	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
43	51.455578	51.455578	51.53429	14.533877	1750881113703	1750883210899	Körnerplatz	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
44	51.529022	51.529022	51.47089	14.720767	1751714665629	1751716833795	Rohner Weg 13b	Dorfstraße 29	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
45	51.545673	51.545673	51.50849	14.752451	1750754218996	1750756894038	Spremberger Straße 17	Winkelstraße 15	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
46	51.529022	51.529022	51.343174	14.597949	1751688247407	1751691630492	Rohner Weg 13b	Halbendorfer Straße 210	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
47	51.51916	51.51916	51.54356	14.529777	1751082707009	1751085044978	Körnerplatz	Alter Postweg 11	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
48	51.528763	51.528763	51.401985	14.607368	1751263872837	1751265165428	Trebendorfer Weg 116c	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
49	51.534004	51.534004	51.37235	14.621518	1751711292844	1751712621817	Dorfstraße 106a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
50	51.39961	51.39961	51.5446	14.535595	1751368732116	1751371959338	Straße der Freundschaft 26	Schleife - Slepo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
51	51.51109	51.51109	51.53016	14.524709	1751639112310	1751640551330	Friedhof Mulkwitz	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
52	51.532295	51.532295	51.415432	14.661176	1750681966222	1750684421628	Reinert Ranch	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
53	51.545673	51.545673	51.47458	14.800586	1751532066672	1751533581665	Spremberger Straße 17	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
54	51.49449	51.49449	51.53531	14.528985	1751610357082	1751611452512	Kindergartenweg 10	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
55	51.330833	51.330833	51.539997	14.516031	1750938179766	1750941458849	Feldteich	Hoyerswerdaer Straße 90	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
56	51.53536	51.53536	51.498013	14.686679	1751137906291	1751139339478	Werksweg 12	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
57	51.53016	51.53016	51.502956	14.571151	1751626102981	1751627638286	Tischlereiweg 113b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
58	51.534428	51.534428	51.490604	14.511671	1751470854134	1751472375870	Mühlroser Straße 3	Schulweg 39	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
59	51.534447	51.534447	51.465282	14.810628	1751179714973	1751182012013	Mulkwitzer Weg 10	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
60	51.53531	51.53531	51.49846	14.474469	1750838752255	1750841811145	Siedlung - Sydlišćo	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
61	51.54619	51.54619	51.531254	14.516953	1751453142236	1751456171408	Dorfstraße 38	Dorfstraße 103	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
62	51.53388	51.53388	51.468403	14.672477	1751371090932	1751372970198	Dorfstraße 105a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
63	51.54002	51.54002	51.532936	14.519677	1750708841495	1750711554949	Thälmann-Siedlung 8	Dorfstraße 106	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
64	51.528664	51.528664	51.53834	14.717415	1751539545547	1751541627800	Rohner Weg 6	Maiwiese	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
65	51.541637	51.541637	51.355827	14.497012	1751054878094	1751057945124	Lindenweg 20	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
66	51.475113	51.475113	51.53411	14.53515	1751356049146	1751359590686	Körnerplatz	Schleifer Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
67	51.53325	51.53325	51.341835	14.579535	1751276927860	1751277921814	Mühlweg 5b	Neudorfer Straße 401	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
68	51.50937	51.50937	51.528664	14.536682	1750841954546	1750843586724	Körnerplatz	Rohner Weg 6	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
69	51.462753	51.462753	51.53536	14.535053	1751486018810	1751489614427	Körnerplatz	Werksweg 12	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
70	51.524426	51.524426	51.541637	14.528906	1751101718083	1751104485003	Jagenstein Ortsgrenze Krauschwitz	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
71	51.539795	51.539795	51.406174	14.55094	1751002868336	1751005608428	Strugaaue 37	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
72	51.541874	51.541874	51.396976	14.564843	1751620961856	1751622309697	Friedensstraße 77a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
73	51.361755	51.361755	51.534004	14.521774	1751545140040	1751547464453	Lange Straße 14	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
74	51.513336	51.513336	51.53429	14.533877	1751208940364	1751210845281	Körnerplatz	Schleifer Straße 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
75	51.357853	51.357853	51.539997	14.516031	1751127119062	1751130128369	Am Waldrand 3	Hoyerswerdaer Straße 90	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
76	51.365387	51.365387	51.538887	14.518962	1750770580140	1750771832317	Hauptstraße 24	Zum Sportplatz 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
77	51.41332	51.41332	51.527706	14.524263	1751201877654	1751204159706	Körnerplatz	Trebendorfer Weg 116b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
78	51.53325	51.53325	51.380733	14.616125	1750918417391	1750920312405	Mühlweg 5b	Klittener Straße 14	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
79	51.500763	51.500763	51.529022	14.529856	1751037512173	1751040854332	Gutenbergstraße 33	Rohner Weg 13b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
80	51.533676	51.533676	51.533173	14.529221	1751447765205	1751448673372	Gartengemeinschaft Neißetal	Mühlroser Straße 8a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
81	51.53861	51.53861	51.547516	14.673697	1751608173269	1751611403557	Hoyerswerdaer Straße 91	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
82	51.45613	51.45613	51.53388	14.520264	1751347151697	1751350467882	Körnerplatz	Dorfstraße 105a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
83	51.536026	51.536026	51.33286	14.560823	1751696458119	1751698868835	Friedensstraße 1	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
84	51.5209	51.5209	51.53411	14.53515	1751436640630	1751439509233	Körnerplatz	Schleifer Straße 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
85	51.53016	51.53016	51.463272	14.942694	1750966913263	1750969472475	Tischlereiweg 113b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
86	51.39378	51.39378	51.535065	14.528915	1750924960875	1750926950951	Körnerplatz	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
87	51.534428	51.534428	51.366367	14.649183	1751214474713	1751217181017	Mühlroser Straße 3	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
88	51.4451	51.4451	51.5394	14.53161	1750914712868	1750916979710	Körnerplatz	Strugaaue 2	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
89	51.361717	51.361717	51.536407	14.524572	1751269155724	1751270325535	Körnerplatz	Jahnring 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
90	51.533836	51.533836	51.54356	14.529777	1751559781365	1751561623649	Schleifer Straße 5	Alter Postweg 11	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
91	51.53861	51.53861	51.34616	14.463032	1751385542480	1751388058880	Hoyerswerdaer Straße 91	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
92	51.527706	51.527706	51.501083	14.754876	1750918992511	1750921916928	Trebendorfer Weg 116b	Brandstraße 9	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
93	51.507206	51.507206	51.5394	14.53161	1751108021457	1751109986007	Sägewerk und Holzhandel Kopte	Strugaaue 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
94	51.52956	51.52956	51.531242	14.511581	1750855844418	1750857602176	Bautzener Straße 1a	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
95	51.545673	51.545673	51.496864	14.603415	1751654148976	1751656597308	Spremberger Straße 17	An der Rennbahn 52	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
96	51.529552	51.529552	51.303318	14.605337	1751431793597	1751432851993	Tischlereiweg 115a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
97	51.53388	51.53388	51.52078	14.720608	1751543074863	1751545706079	Dorfstraße 105a	Modell- und Formenbau Krahl	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
98	51.40779	51.40779	51.5446	14.535595	1751626022140	1751628697877	Friedhof Boxberg	Schleife - Slepo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
99	51.35887	51.35887	51.529552	14.524057	1751163177229	1751164830543	Körnerplatz	Tischlereiweg 115a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
100	51.49925	51.49925	51.534004	14.521774	1751729095859	1751730019923	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
101	51.536407	51.536407	51.346275	14.637767	1750944898252	1750947828663	Jahnring 5b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
102	51.53388	51.53388	51.52042	14.65481	1750906726643	1750910307851	Dorfstraße 105a	Fichte 1a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
103	51.53053	51.53053	51.36383	14.494116	1751625914205	1751627101132	Rohner Weg 10	Romanikteich	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
104	51.490925	51.490925	51.533836	14.536425	1750873392899	1750874307788	Dorfstraße 41	Schleifer Straße 5	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
105	51.424126	51.424126	51.54002	14.524071	1751048855165	1751051618296	Körnerplatz	Thälmann-Siedlung 8	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
106	51.541786	51.541786	51.364086	14.505642	1750750537243	1750752906155	Hoyerswerdaer Straße 50	Bahnhofstraße 4	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
107	51.460667	51.460667	51.532295	14.534533	1751017304260	1751019619256	Körnerplatz	Reinert Ranch	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
108	51.527905	51.527905	51.410896	14.607509	1751620670664	1751621645113	Trebendorfer Weg 81	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
109	51.52923	51.52923	51.541725	14.534854	1751382975004	1751386560230	Rohner Weg 3a	Gemeindeamt	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
110	51.47632	51.47632	51.53531	14.528985	1751553444560	1751555055014	Körnerplatz	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
111	51.329422	51.329422	51.534756	14.533946	1751393214743	1751395117964	Körnerplatz	Tiefbau-Service-Berton	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
112	51.541874	51.541874	51.401745	14.568081	1751087017389	1751090369071	Friedensstraße 77a	Am Sportplatz 8	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
113	51.541637	51.541637	51.416073	14.526874	1750826561225	1750827471565	Lindenweg 20	Merzdorfer Straße 38	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
114	51.547283	51.547283	51.541874	14.537528	1751454511415	1751457967127	Löwe	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
115	51.534756	51.534756	51.57553	14.703246	1751426390951	1751427815224	Tiefbau-Service-Berton	Zschorno 33	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
116	51.53531	51.53531	51.510338	14.518517	1751472795326	1751476081553	Siedlung - Sydlišćo	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
117	51.53411	51.53411	51.417385	14.608821	1751185227451	1751188768819	Schleifer Straße 3	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
118	51.53841	51.53841	51.328003	14.58419	1751286568393	1751289544430	Jahnring 21	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
119	51.53016	51.53016	51.44024	14.672051	1750935913375	1750939268962	Tischlereiweg 113b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
120	51.533173	51.533173	51.462868	14.816472	1751112567347	1751115519206	Mühlroser Straße 8a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
121	51.54356	51.54356	51.37792	14.492761	1750698546490	1750699794880	Alter Postweg 11	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
122	51.37162	51.37162	51.54269	14.530803	1751528594224	1751531748117	Jahnstraße 31	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
123	51.441063	51.441063	51.539795	14.538614	1751103008106	1751106190570	Körnerplatz	Strugaaue 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
124	51.541786	51.541786	51.536026	14.528657	1751528434343	1751530884556	Hoyerswerdaer Straße 50	Friedensstraße 1	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
125	51.5394	51.5394	51.321186	14.479721	1751301599030	1751304886230	Strugaaue 2	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
126	51.53536	51.53536	51.462315	14.80414	1751730366986	1751733460501	Werksweg 12	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
127	51.529625	51.529625	51.553658	14.637722	1751218261199	1751219459911	Tischlereiweg 115a	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
128	51.535732	51.535732	51.553055	14.50116	1750937469500	1750939482522	Jahnring 13	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
129	51.549496	51.549496	51.531925	14.52021	1751726432088	1751729583180	Uferweg 1	Dorfstraße 80	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
130	51.540085	51.540085	51.57203	14.713894	1751638677715	1751641247851	Hoyerswerdaer Straße 98	Lindenweg 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
131	51.396534	51.396534	51.531242	14.511581	1751374425216	1751377018590	Körnerplatz	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
132	51.527905	51.527905	51.353897	14.57267	1751091075823	1751092339971	Trebendorfer Weg 81	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
133	51.31989	51.31989	51.541874	14.537528	1751640328870	1751642883124	Körnerplatz	Friedensstraße 77a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
134	51.53861	51.53861	51.542698	14.727519	1750845190206	1750847774994	Hoyerswerdaer Straße 91	Grenzvorplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
135	51.532936	51.532936	51.501522	14.669929	1750923051240	1750925742135	Dorfstraße 106	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
136	51.532936	51.532936	51.537445	14.69878	1751561435154	1751564962054	Dorfstraße 106	Kantweg 9	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
137	51.52564	51.52564	51.53841	14.525069	1750759545812	1750761638708	Körnerplatz	Jahnring 21	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
138	51.540573	51.540573	51.50011	14.619553	1751395113658	1751396403341	Thälmann-Siedlung 25	Südpassage	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
139	51.533173	51.533173	51.528023	14.68363	1751119488523	1751122851328	Mühlroser Straße 8a	Siedlung 27	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
140	51.508972	51.508972	51.541637	14.528906	1751130558740	1751134040948	Görlitzer Straße 42	Lindenweg 20	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
141	51.53429	51.53429	51.52739	14.5192585	1750929575074	1750931978201	Schleifer Straße 2	Mulkwitzer Weg 83b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
142	51.536358	51.536358	51.59174	14.698549	1751121435304	1751123822842	Friedensstraße 1	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
143	51.45546	51.45546	51.53531	14.528985	1751440459088	1751442882271	Körnerplatz	Siedlung - Sydlišćo	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
144	51.543312	51.543312	51.513153	14.797428	1751702831086	1751703754770	Hoyerswerdaer Straße 33	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
145	51.449467	51.449467	51.527905	14.522943	1751226708894	1751228439565	Körnerplatz	Trebendorfer Weg 81	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
146	51.535065	51.535065	51.358196	14.626851	1750966875764	1750970264027	Siedlung - Sydlišćo	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
147	51.536026	51.536026	51.498413	14.49606	1751477136949	1751479110686	Friedensstraße 1	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
148	51.53973	51.53973	51.532536	14.484995	1751197739451	1751201050521	NORMA	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
149	51.529236	51.529236	51.53595	14.616368	1751098621855	1751101400376	Gefallenendenkmale Rohne	Katzenberg	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
150	51.528763	51.528763	51.393658	14.646281	1751716868136	1751719963002	Trebendorfer Weg 116c	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
151	51.544155	51.544155	51.528763	14.527925	1750919370706	1750922904674	Mozartweg 13	Trebendorfer Weg 116c	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
152	51.541637	51.541637	51.425713	14.7213545	1751011157200	1751012130575	Lindenweg 20	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
153	51.534004	51.534004	51.435787	14.575305	1751293289639	1751296889160	Dorfstraße 106a	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
154	51.365417	51.365417	51.53861	14.514816	1751206047978	1751209521104	Hauptstraße 21	Hoyerswerdaer Straße 91	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
155	51.51235	51.51235	51.5394	14.53161	1751623341313	1751624339656	Krauschwitz Erlebnisbad	Strugaaue 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
156	51.529022	51.529022	51.376175	14.634836	1751258491956	1751260429006	Rohner Weg 13b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
157	51.333622	51.333622	51.531242	14.511581	1751682957404	1751686168517	Bahnteich	Mühlweg 5b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
158	51.529236	51.529236	51.388245	14.684338	1751524241762	1751527514540	Gefallenendenkmale Rohne	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
159	51.38796	51.38796	51.529625	14.523734	1750958121150	1750959520217	Körnerplatz	Tischlereiweg 115a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
160	51.56794	51.56794	51.533836	14.536425	1750732061457	1750734742163	Neißestraße 9	Schleifer Straße 5	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
161	51.358303	51.358303	51.53325	14.514113	1750686887745	1750688279268	Körnerplatz	Mühlweg 5b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
162	51.508865	51.508865	51.529236	14.521395	1751222823875	1751226198373	Jahnstraße 83	Gefallenendenkmale Rohne	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
163	51.534756	51.534756	51.386284	14.659313	1751470105148	1751471099170	Tiefbau-Service-Berton	Schadendorfer Weg 3	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
164	51.474667	51.474667	51.53016	14.524709	1751272970907	1751273878575	Campingplatz Ruhlmühle	Tischlereiweg 113b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
165	51.51916	51.51916	51.530224	14.525203	1750779702327	1750782891300	Körnerplatz	Tischlereiweg 113b	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
166	51.339233	51.339233	51.527706	14.524263	1751606299741	1751609058788	Körnerplatz	Trebendorfer Weg 116b	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
167	51.49863	51.49863	51.539474	14.515927	1751175734167	1751178025106	Schillerstraße 29	Hoyerswerdaer Straße 94	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
168	51.529236	51.529236	51.498135	14.83177	1751077499597	1751078708893	Gefallenendenkmale Rohne	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
169	51.536358	51.536358	51.479206	14.825497	1750907265162	1750909806402	Friedensstraße 1	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
170	51.5446	51.5446	51.50338	14.604108	1751382887606	1751384799633	Schleife - Slepo	An der Rennbahn 25	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
171	51.393917	51.393917	51.545673	14.534669	1751485014640	1751486554952	Körnerplatz	Spremberger Straße 17	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
172	51.534447	51.534447	51.34718	14.574001	1751085161459	1751087436286	Mulkwitzer Weg 10	Wiesenweg 419a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
173	51.531925	51.531925	51.33762	14.585908	1750708832222	1750711318413	Dorfstraße 80	Kirchweg 218	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
174	51.508068	51.508068	51.541725	14.534854	1751380965874	1751382867115	Waldhausstraße 116	Gemeindeamt	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
175	51.53429	51.53429	51.463547	14.894235	1751398464452	1751401057393	Schleifer Straße 2	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
176	51.364944	51.364944	51.541786	14.524831	1750683418042	1750684976608	Schäferei 10	Hoyerswerdaer Straße 50	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
177	51.530224	51.530224	51.512974	14.482712	1751603527634	1751606725658	Tischlereiweg 113b	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
178	51.53861	51.53861	51.557198	14.527145	1750737395219	1750738480902	Hoyerswerdaer Straße 91	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
179	51.527706	51.527706	51.53971	14.505932	1751346551554	1751349074663	Trebendorfer Weg 116b	Hoyerswerdaer Straße 108	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
180	51.544353	51.544353	51.50967	14.672691	1751520843876	1751522502434	Friedensstraße 62	Waldhausstraße 118a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
181	51.54269	51.54269	51.576378	14.715798	1751187036443	1751189205670	Hoyerswerdaer Straße 37	Schulstraße 7a	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
182	51.556164	51.556164	51.534004	14.521774	1751396699678	1751398608989	Körnerplatz	Dorfstraße 106a	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
183	51.53053	51.53053	51.49854	14.635138	1751449349336	1751451942743	Rohner Weg 10	Bautzener Straße 16	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
184	51.506203	51.506203	51.53053	14.532026	1751176931869	1751179489745	August-Bebel-Straße 12	Rohner Weg 10	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
185	51.439697	51.439697	51.54269	14.530803	1751352039162	1751353277457	Körnerplatz	Hoyerswerdaer Straße 37	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
186	51.50737	51.50737	51.545673	14.534669	1751358935602	1751360693531	Wolfgangstraße 10	Spremberger Straße 17	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
187	51.48327	51.48327	51.53531	14.528985	1751607712125	1751609078444	Körnerplatz	Siedlung - Sydlišćo	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
188	51.539997	51.539997	51.53345	14.61383	1751535229407	1751537836952	Hoyerswerdaer Straße 90	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
189	51.427376	51.427376	51.5394	14.53161	1750745038943	1750747375049	Körnerplatz	Strugaaue 2	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
190	51.528664	51.528664	51.39522	14.51195	1750783153314	1750784559985	Rohner Weg 6	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
191	51.353355	51.353355	51.528763	14.527925	1751116533807	1751117977393	Platz der MTS 348	Trebendorfer Weg 116c	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
192	51.45632	51.45632	51.527905	14.522943	1751353539964	1751354801875	Podroscher Straße 43	Trebendorfer Weg 81	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
193	51.53016	51.53016	51.325294	14.476902	1751595330636	1751598517587	Tischlereiweg 113b	Körnerplatz	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
194	51.55784	51.55784	51.539997	14.516031	1751382134868	1751383983839	Körnerplatz	Hoyerswerdaer Straße 90	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	1	0	0	0
195	51.531925	51.531925	51.369003	14.610103	1751564534084	1751566409941	Dorfstraße 80	Körnerplatz	t	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
196	51.540573	51.540573	51.40342	14.570217	1750835268358	1750838174209	Thälmann-Siedlung 25	Hammerstraße 50 D	f	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	0	0	2	0	0	0
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
1	t	51.5332486	14.5141138	1751554211882	1751554811882	1751554211882	1041000	1661000		1	Mühlweg 5b	t
2	f	51.3455003	14.4871643	1751556472882	1751557072882	1751557072882	1661000	1659000		1	Körnerplatz	t
3	t	51.5443525	14.5405083	1751465911948	1751466511948	1751465911948	907000	175000		2	Friedensstraße 62	t
4	f	51.546039	14.5632061	1751466686948	1751467286948	1751467286948	175000	877000		2	Wake and Beach	t
13	t	51.5286634	14.5366817	1751195207018	1751195807018	1751195207018	976000	843000		7	Rohner Weg 6	t
14	f	51.4936881	14.5160904	1751196650018	1751197250018	1751197250018	843000	1527000		7	Die Protestantin	t
7	t	51.5730758	14.7236891	1750871540675	1750872140675	1750871540675	1668000	2331000		4	Schulstraße 25	t
8	f	51.5296246	14.5237337	1750874471675	1750875071675	1750875071675	2331000	1133000		4	Tischlereiweg 115a	t
29	t	51.3235055	14.6329012	1750692255195	1750692855195	1750692255195	1792000	2001000		15	Im Erlengrund 2	f
30	f	51.5443525	14.5405083	1750694856195	1750695456195	1750695456195	2001000	968000		15	Friedensstraße 62	f
27	t	51.3694061	14.5497853	1751726543327	1751727143327	1751726543327	1700000	1781000		14	A16	t
28	f	51.536356	14.5290886	1751728924327	1751729524327	1751729524327	1781000	978000		14	Friedensstraße 1	t
40	f	51.3405704	14.5558757	1750851437570	1750852037570	1750852037570	2263000	2070000		20	Körnerplatz	f
15	t	51.4076382	14.5034534	1751170551134	1751171151134	1751170551134	1533000	1798000		8	Körnerplatz	t
16	f	51.5446031	14.5355952	1751172949134	1751173549134	1751173549134	1798000	1068000		8	Schleife - Slepo	t
44	f	51.5292355	14.5213952	1751719096874	1751719696874	1751719696874	971000	1077000		22	Gefallenendenkmale Rohne	f
23	t	51.4604464	14.8775286	1751172229904	1751172829904	1751172229904	1276000	2075000		12	Körnerplatz	t
24	f	51.5341111	14.5351491	1751174904904	1751175504904	1751175504904	2075000	922000		12	Schleifer Straße 3	t
52	f	51.5676051	14.709137	1750863243883	1750863843883	1750863843883	1952000	1395000		26	Köbelner Straße 115	f
37	t	51.5499728	14.689144	1751076137766	1751076737766	1751076137766	918000	1410000		19	Metallschleiferei Herbert Nikoleizig	t
38	f	51.5342031	14.5217853	1751078147766	1751078747766	1751078747766	1410000	1007000		19	Dorfstraße 106a	t
11	t	51.5277052	14.5242631	1751600035525	1751600635525	1751600035525	965000	746000		6	Trebendorfer Weg 116b	t
69	t	51.5329343	14.5196775	1751644242674	1751644842674	1751644242674	270000	2384000		35	Dorfstraße 106	t
25	t	51.5056849	14.68697	1751031576949	1751032176949	1751031576949	536000	1439000		13	Körnerplatz	t
6	f	51.5256578	14.6741657	1751648561239	1751649161239	1751649161239	1143000	539000		3	Krauschwitzer Weg 27	t
5	t	51.5290227	14.5298561	1751646818239	1751647418239	1751646818239	2103000	1143000		3	Rohner Weg 13b	t
46	f	51.5345327	14.5239956	1750839916518	1750840516518	1750840516518	456000	1000000		23	Neustädter Straße 7	t
36	f	51.5405733	14.520827	1751352064403	1751352664403	1751352664403	207000	1123000		18	Thälmann-Siedlung 25	t
12	f	51.5685615	14.5518859	1751601381525	1751601981525	1751601981525	746000	1170000		6	Schützenverein Groß Düben	t
45	t	51.4865406	14.4795294	1750839346255	1750839460518	1750838860518	154000	456000		23	Körnerplatz	t
67	t	51.364859	14.4812117	1751463096151	1751463696151	1751463096151	1245000	1435000		34	Rotdornallee 21	t
53	t	51.3562352	14.6269485	1751205824995	1751206424995	1751205824995	1446000	1680000		27	Körnerplatz	t
54	f	51.5305303	14.5320261	1751208104995	1751208704995	1751208704995	1680000	947000		27	Rohner Weg 10	t
17	t	51.4739743	14.6915542	1751357854833	1751358454833	1751357854833	1256000	2132000		9	Körnerplatz	t
21	t	51.5388861	14.5189616	1751531292492	1751531892492	1751531292492	1027000	280000		11	Zum Sportplatz 5	t
22	f	51.5290227	14.5298561	1751532172492	1751532772492	1751532772492	280000	954000		11	Rohner Weg 13b	t
66	f	51.5357337	14.5192924	1751346815896	1751346815897	1751346815897	643000	278000		33	Jahnring 13	f
20	f	51.4509699	14.7132534	1750690960987	1750691560987	1750691560987	2686000	1789000		10	Körnerplatz	f
41	t	51.4137116	14.5998097	1751369264784	1751369264785	1751368664785	709000	1606000		21	Körnerplatz	f
42	f	51.5426918	14.5308026	1751370870785	1751371123338	1751371470785	1606000	236000		21	Hoyerswerdaer Straße 37	f
35	t	51.4322283	14.5877219	1751349808403	1751349808404	1751349808403	1314000	1536000		18	Körnerplatz	t
9	t	51.3629457	14.4866951	1751609934045	1751610534045	1751609934045	1513000	1568000		5	Körnerplatz	t
33	t	51.5343123	14.5136158	1751135891152	1751135891153	1751135291153	364000	2010000		17	Forstweg 78a	f
34	f	51.4657784	14.7641965	1751137901153	1751138058478	1751138501153	2010000	681000		17	Körnerplatz	f
70	f	51.3609653	14.6505306	1751647226674	1751647275600	1751647275600	2384000	2350000		35	Körnerplatz	t
10	f	51.5345327	14.5239956	1751612102045	1751612702045	1751612702045	1568000	1000000		5	Neustädter Straße 7	t
51	t	51.5400192	14.5240712	1750860691883	1750861291883	1750860691883	316000	1952000		26	Thälmann-Siedlung 8	f
65	t	51.4589867	14.6315217	1751342027897	1751342627897	1751342027897	1970000	3005000		33	Körnerplatz	f
48	f	51.4626715	14.5996253	1751115228443	1751115828443	1751115828443	2867000	2522000		24	Körnerplatz	t
47	t	51.5357337	14.5192924	1751111761443	1751112361443	1751111761443	189000	2867000		24	Jahnring 13	t
61	t	51.5341111	14.5351491	1751336008891	1751336608891	1751336008891	862000	1073000		31	Schleifer Straße 3	t
62	f	51.4708765	14.4766943	1751337681891	1751338281891	1751338281891	1073000	1875000		31	Körnerplatz	t
59	t	51.433339	14.961692	1751565735495	1751566335495	1751565735495	1632000	2596000		30	Körnerplatz	t
50	f	51.5342031	14.5217853	1751652261600	1751652861600	1751652861600	1863000	1007000		25	Dorfstraße 106a	t
49	t	51.3995396	14.492946	1751649798600	1751650398600	1751649798600	2523000	1863000		25	Körnerplatz	t
26	f	51.538412	14.5250691	1751033615949	1751034215949	1751034215949	1439000	113000		13	Jahnring 21	t
55	t	51.4887723	14.8272801	1751714043723	1751714643723	1751714043723	966000	2017000		28	Körnerplatz	t
18	f	51.5393992	14.5316092	1751360586833	1751361186833	1751361186833	2132000	999000		9	Strugaaue 2	t
57	t	51.4837769	14.8814557	1750903084342	1750903684342	1750903084342	1191000	2083000		29	Körnerplatz	t
32	f	51.3590998	14.6534461	1751572903860	1751573503860	1751573503860	2544000	2489000		16	Körnerplatz	t
39	t	51.5296246	14.5237337	1750848864994	1750849174570	1750848574570	1690000	2263000		20	Tischlereiweg 115a	f
56	f	51.5302251	14.5252029	1751716660723	1751716660723	1751716660723	2017000	1117000		28	Tischlereiweg 113b	t
43	t	51.4160738	14.5268735	1751718125873	1751718125874	1751717525874	1553000	971000		22	Merzdorfer Straße 38	f
31	t	51.5345327	14.5239956	1751569759860	1751570359860	1751569759860	182000	2544000		16	Neustädter Straße 7	t
60	f	51.5388861	14.5189616	1751568931495	1751569531495	1751569531495	2596000	1081000		30	Zum Sportplatz 5	t
19	t	51.5312531	14.516953	1750687720987	1750687720988	1750687720987	1520000	226000		10	Dorfstraße 103	f
68	f	51.5399955	14.5160315	1751465131151	1751465731151	1751465731151	1435000	1112000		34	Hoyerswerdaer Straße 90	t
74	f	51.4919921	14.5192428	1751038691898	1751039291898	1751039291898	676000	1567000		37	Kohlebahnweg 86	f
75	t	51.4890057	14.8092829	1750882052667	1750882652667	1750882052667	1053000	1949000		38	Ausbauten 21	f
76	f	51.5329343	14.5196775	1750884601667	1750885201667	1750885201667	1949000	1019000		38	Dorfstraße 106	f
80	f	51.5357337	14.5192924	1750774164815	1750774764815	1750774764815	576000	1042000		40	Jahnring 13	f
92	f	51.3431746	14.5979495	1751691630492	1751692230492	1751692230492	1675000	1528000		46	Halbendorfer Straße 210	f
71	t	51.5344465	14.5268116	1750919359922	1750919959922	1750919359922	939000	680000		36	Mulkwitzer Weg 10	t
99	t	51.3996098	14.5879542	1751367955784	1751368555784	1751367955784	946000	709000		50	Straße der Freundschaft 26	f
100	f	51.5446031	14.5355952	1751371359338	1751371959338	1751371959338	236000	1068000		50	Schleife - Slepo	f
129	t	51.5416387	14.5289058	1751054278094	1751054878094	1751054278094	977000	1816000		65	Lindenweg 20	t
95	t	51.528762	14.5279248	1751262357428	1751262957428	1751262357428	911000	2208000		48	Trebendorfer Weg 116c	t
96	f	51.4019842	14.6073685	1751265165428	1751265765428	1751265765428	2208000	2078000		48	Körnerplatz	t
106	f	51.47458	14.8005857	1751534176672	1751534776672	1751534776672	2110000	1298000		53	Körnerplatz	f
63	t	51.3440473	14.5789863	1751345899120	1751346499120	1751345899120	1502000	1644000		32	Kascheler Wiese	t
64	f	51.536356	14.5290886	1751351344404	1751351857403	1751351857403	1644000	978000		32	Friedensstraße 1	t
81	t	51.5388861	14.5189616	1750923227926	1750923827926	1750923227926	745000	2255000		41	Zum Sportplatz 5	t
82	f	51.3868253	14.5242503	1750926082926	1750926682926	1750926682926	2255000	2156000		41	Körnerplatz	t
102	f	51.5301599	14.5247083	1751640551330	1751641151330	1751641151330	467000	308000		51	Tischlereiweg 113b	t
112	f	51.498014	14.6866787	1751138739478	1751139339478	1751139339478	681000	454000		56	Körnerplatz	f
115	t	51.5344271	14.5295784	1751470892870	1751471492870	1751470892870	935000	883000		58	Mühlroser Straße 3	f
122	f	51.5312531	14.516953	1751453476236	1751454076236	1751454076236	334000	1035000		61	Dorfstraße 103	f
130	f	51.355828	14.4970125	1751056694094	1751057294094	1751057294094	1816000	1736000		65	Körnerplatz	t
91	t	51.5290227	14.5298561	1751689355492	1751689955492	1751689355492	283000	1675000		46	Rohner Weg 13b	f
134	f	51.3418354	14.5795346	1751278567860	1751279167860	1751279167860	1640000	1578000		67	Neudorfer Straße 401	f
137	t	51.4627524	14.7730235	1751485418810	1751486018810	1751485418810	991000	1855000		69	Körnerplatz	f
138	f	51.535357	14.5350536	1751487873810	1751488473810	1751488473810	1855000	986000		69	Werksweg 12	f
139	t	51.5244236	14.6788886	1751102734003	1751103334003	1751102734003	479000	1151000		70	Jagenstein Ortsgrenze Krauschwitz	f
116	f	51.4906038	14.5116709	1751472375870	1751472975870	1751472975870	883000	880000		58	Schulweg 39	f
121	t	51.5461874	14.5745595	1751452542236	1751453142236	1751452542236	312000	334000		61	Dorfstraße 38	f
94	f	51.5435594	14.5297765	1751085044978	1751085644978	1751085644978	1193000	1086000		47	Alter Postweg 11	t
97	t	51.5340052	14.5217744	1751710758817	1751711358817	1751710758817	948000	1263000		49	Dorfstraße 106a	t
72	f	51.5405799	14.5727348	1750920639922	1750921239922	1750921239922	680000	1223000		36	Station 2	t
83	t	51.4532458	14.9006663	1751181215112	1751181215113	1751180615113	2322000	2375000		42	Körnerplatz	f
123	t	51.5338793	14.5202632	1751368829198	1751369429198	1751368829198	955000	3541000		62	Dorfstraße 105a	t
131	t	51.4751115	14.9180471	1751356808686	1751357408686	1751356808686	1383000	2182000		66	Körnerplatz	t
132	f	51.5341111	14.5351491	1751359590686	1751360190686	1751360190686	2182000	922000		66	Schleifer Straße 3	t
73	t	51.5393992	14.5316092	1751037415898	1751038015898	1751037415898	939000	676000		37	Strugaaue 2	f
101	t	51.5110892	14.4895537	1751640084329	1751640084330	1751639484330	2172000	467000		51	Friedhof Mulkwitz	t
117	t	51.5344465	14.5268116	1751179171013	1751179771013	1751179171013	939000	2241000		59	Mulkwitzer Weg 10	t
118	f	51.4652829	14.8106275	1751182012013	1751182612013	1751182612013	2241000	1425000		59	Körnerplatz	t
84	f	51.5353088	14.5289849	1751183590113	1751184190113	1751184190113	2375000	139000		42	Siedlung - Sydlišćo	f
114	f	51.5029582	14.5711512	1751626832981	1751627432981	1751627432981	574000	589000		57	Körnerplatz	f
124	f	51.4684021	14.6724772	1751372970198	1751373570198	1751373570198	3541000	2822000		62	Körnerplatz	t
135	t	51.5093693	14.7432624	1750841354546	1750841954546	1750841354546	1125000	1577000		68	Körnerplatz	f
88	f	51.4708892	14.7207669	1751716572873	1751716572873	1751716572873	1666000	1553000		44	Dorfstraße 29	f
85	t	51.4555784	14.5985841	1750880086899	1750880686899	1750880086899	2069000	2524000		43	Körnerplatz	t
136	f	51.5286634	14.5366817	1750844040545	1750844040546	1750844040546	448000	1672000		68	Rohner Weg 6	f
86	f	51.5342917	14.5338773	1750883210899	1750883810899	1750883810899	2524000	932000		43	Schleifer Straße 2	t
109	t	51.3308331	14.4902652	1750938975849	1750939575849	1750938975849	1693000	1883000		55	Feldteich	t
127	t	51.5286634	14.5366817	1751539292800	1751539892800	1751539292800	976000	1735000		64	Rohner Weg 6	t
128	f	51.5383419	14.7174148	1751541627800	1751542227800	1751542227800	1735000	1049000		64	Maiwiese	t
90	f	51.5084913	14.752451	1750755882996	1750756482996	1750756482996	1664000	852000		45	Winkelstraße 15	t
89	t	51.5456749	14.5346691	1750753618996	1750754218996	1750753618996	1493000	1664000		45	Spremberger Straße 17	t
107	t	51.4944899	14.5075835	1751609757082	1751610357082	1751609757082	1835000	1005000		54	Kindergartenweg 10	t
108	f	51.5353088	14.5289849	1751611362082	1751611962082	1751611962082	1005000	1000000		54	Siedlung - Sydlišćo	t
111	t	51.535357	14.5350536	1751134927152	1751135527152	1751134927152	926000	364000		56	Werksweg 12	f
110	f	51.5399955	14.5160315	1750941458849	1750942058849	1750942058849	1883000	1112000		55	Hoyerswerdaer Straße 90	t
133	t	51.5332486	14.5141138	1751276327860	1751276927860	1751276327860	352000	1640000		67	Mühlweg 5b	f
119	t	51.5353088	14.5289849	1750838152255	1750838752255	1750838152255	940000	440000		60	Siedlung - Sydlišćo	t
120	f	51.4984594	14.4744692	1750839192255	1750839192255	1750839192255	440000	1330000		60	Körnerplatz	t
105	t	51.5456749	14.5346691	1751531466672	1751532066672	1751531466672	1899000	2110000		53	Spremberger Straße 17	f
125	t	51.5400192	14.5240712	1750710083826	1750710451825	1750710083826	1398000	148000		63	Thälmann-Siedlung 8	t
79	t	51.569467	14.5688701	1750772988815	1750773588815	1750772988815	1010000	576000		40	Dorfstraße 20b	f
93	t	51.5191595	14.6791933	1751083251978	1751083851978	1751083251978	1071000	1193000		47	Körnerplatz	t
126	f	51.5329343	14.5196775	1750710954949	1750711554949	1750711554949	166000	1019000		63	Dorfstraße 106	t
103	t	51.5322939	14.5345323	1750682075628	1750682145627	1750682075628	983000	1725000		52	Reinert Ranch	f
145	t	51.361755	14.5111854	1751545420453	1751546020453	1751545420453	1397000	1444000		73	Lange Straße 14	f
146	f	51.5340052	14.5217744	1751547464453	1751548064453	1751548064453	1444000	1008000		73	Dorfstraße 106a	f
149	t	51.3578526	14.5111414	1751127925369	1751128525369	1751127925369	1413000	1603000		75	Am Waldrand 3	f
150	f	51.5399955	14.5160315	1751130128369	1751130728369	1751130728369	1603000	1112000		75	Hoyerswerdaer Straße 90	f
169	t	51.5301599	14.5247083	1750966376475	1750966976475	1750966376475	1095000	2496000		85	Tischlereiweg 113b	t
153	t	51.4133176	14.5354593	1751202381706	1751202981706	1751202381706	1109000	1178000		77	Körnerplatz	f
157	t	51.5007642	14.6441052	1751036912173	1751037512173	1751036912173	362000	1079000		79	Gutenbergstraße 33	f
158	f	51.5290227	14.5298561	1751038591173	1751039191173	1751039191173	1079000	954000		79	Rohner Weg 13b	f
159	t	51.5336762	14.7286386	1751447165205	1751447765205	1751447165205	782000	1564000		80	Gartengemeinschaft Neißetal	f
160	f	51.533173	14.529221	1751449329205	1751449929205	1751449929205	1564000	312000		80	Mühlroser Straße 8a	f
154	f	51.5277052	14.5242631	1751204159706	1751204759706	1751204759706	1178000	1381000		77	Trebendorfer Weg 116b	f
141	t	51.5397943	14.5386138	1751002268336	1751002868336	1751002268336	972000	1057000		71	Strugaaue 37	t
142	f	51.4061725	14.5509392	1751003925336	1751004525336	1751004525336	1057000	939000		71	Körnerplatz	t
163	t	51.4561328	14.5072635	1751345632897	1751346172896	1751345632897	3005000	643000		82	Körnerplatz	f
165	t	51.5360245	14.5286573	1751695858119	1751696458119	1751695858119	921000	2084000		83	Friedensstraße 1	f
166	f	51.3328591	14.5608233	1751698542119	1751699142119	1751699142119	2084000	1915000		83	Körnerplatz	f
168	f	51.5341111	14.5351491	1751439509233	1751440109233	1751440109233	1062000	922000		84	Schleifer Straße 3	f
77	t	51.5374459	14.6987797	1750708085826	1750708685826	1750708085826	737000	1314000		39	Kantweg 9	t
78	f	51.5416387	14.5289058	1750710599825	1750710599826	1750710599826	1314000	1037000		39	Lindenweg 20	t
140	f	51.5416387	14.5289058	1751104485003	1751105085003	1751105085003	1151000	1037000		70	Lindenweg 20	f
176	f	51.5393992	14.5316092	1750916979710	1750917579710	1750917579710	1880000	999000		88	Strugaaue 2	f
193	t	51.5338793	14.5202632	1751543583079	1751544183079	1751543583079	955000	1523000		97	Dorfstraße 105a	f
194	f	51.5207784	14.7206078	1751545706079	1751546306079	1751546306079	1523000	688000		97	Modell- und Formenbau Krahl	f
183	t	51.5277052	14.5242631	1750917537390	1750918137390	1750917537390	965000	280000		92	Trebendorfer Weg 116b	f
184	f	51.5010823	14.7548758	1750921316928	1750921916928	1750921916928	1616000	931000		92	Brandstraße 9	f
155	t	51.5332486	14.5141138	1750918417390	1750918417391	1750917817391	280000	1213000		78	Mühlweg 5b	f
156	f	51.3807347	14.6161251	1750919630391	1750919700928	1750920230391	1213000	1616000		78	Klittener Straße 14	f
98	f	51.3723487	14.6215178	1751712621817	1751712943873	1751712943873	1263000	1363000		49	Körnerplatz	t
187	t	51.5295593	14.7036446	1750855573176	1750856173176	1750855573176	672000	1429000		94	Bautzener Straße 1a	f
188	f	51.5312432	14.5115818	1750857602176	1750858202176	1750858202176	1429000	316000		94	Mühlweg 5b	f
189	t	51.5456749	14.5346691	1751655047308	1751655647308	1751655047308	944000	950000		95	Spremberger Straße 17	f
190	f	51.4968654	14.6034148	1751656597308	1751657197308	1751657197308	950000	453000		95	An der Rennbahn 52	f
167	t	51.520902	14.6609333	1751437847233	1751438447233	1751437847233	2432000	1062000		84	Körnerplatz	f
192	f	51.3033164	14.6053368	1751434092597	1751434692597	1751434692597	2299000	2432000		96	Körnerplatz	f
197	t	51.3588733	14.5447366	1751162477543	1751163077543	1751162477543	1548000	1753000		99	Körnerplatz	f
198	f	51.5295517	14.5240575	1751164830543	1751165430543	1751165430543	1753000	1145000		99	Tischlereiweg 115a	f
201	t	51.5364085	14.524572	1750944298252	1750944898252	1750944298252	958000	1696000		101	Jahnring 5b	f
202	f	51.3462758	14.6377672	1750946594252	1750947194252	1750947194252	1696000	1560000		101	Körnerplatz	f
195	t	51.4077919	14.5664753	1751625422140	1751626022140	1751625422140	953000	1290000		98	Friedhof Boxberg	t
196	f	51.5446031	14.5355952	1751627312140	1751627912140	1751627912140	1290000	1068000		98	Schleife - Slepo	t
164	f	51.5338793	14.5202632	1751349867882	1751350467882	1751350467882	264000	1015000		82	Dorfstraße 105a	f
185	t	51.5072061	14.659666	1751107421457	1751108021457	1751107421457	463000	1153000		93	Sägewerk und Holzhandel Kopte	t
186	f	51.5393992	14.5316092	1751109174457	1751109774457	1751109774457	1153000	999000		93	Strugaaue 2	t
191	t	51.5295517	14.5240575	1751431193597	1751431793597	1751431193597	2364000	2299000		96	Tischlereiweg 115a	f
177	t	51.3617166	14.5982323	1751268555724	1751269155724	1751268555724	1339000	1521000		89	Körnerplatz	t
178	f	51.5364085	14.524572	1751270676724	1751271276724	1751271276724	1521000	229000		89	Jahnring 5b	t
203	t	51.5338793	14.5202632	1750905767342	1750906122341	1750905767342	2083000	287000		102	Dorfstraße 105a	t
204	f	51.520419	14.6548101	1750909707851	1750910307851	1750910307851	1110000	519000		102	Fichte 1a	t
58	f	51.5446031	14.5355952	1750906409341	1750906409342	1750906409342	287000	1110000		29	Schleife - Slepo	t
87	t	51.5290227	14.5298561	1751714306873	1751714906873	1751714306873	894000	1666000		44	Rohner Weg 13b	f
179	t	51.5338373	14.5364242	1751559181365	1751559781365	1751559181365	850000	245000		90	Schleifer Straße 5	t
180	f	51.5435594	14.5297765	1751560026365	1751560626365	1751560626365	245000	1086000		90	Alter Postweg 11	t
161	t	51.5386074	14.5148166	1751609469557	1751610069557	1751609469557	1067000	1334000		81	Hoyerswerdaer Straße 91	t
162	f	51.547516	14.6736975	1751611403557	1751612003557	1751612003557	1334000	1167000		81	Körnerplatz	t
175	t	51.4450987	14.7601171	1750914499710	1750915099710	1750914499710	1126000	1880000		88	Körnerplatz	f
170	f	51.4632726	14.9426941	1750969472475	1750970072475	1750970072475	2496000	1524000		85	Körnerplatz	t
143	t	51.5418744	14.537528	1751620617697	1751621217697	1751620617697	279000	1092000		72	Friedensstraße 77a	f
174	f	51.366367	14.6491832	1751217181017	1751217781017	1751217781017	2495000	2296000		87	Körnerplatz	f
144	f	51.396975	14.5648428	1751622309697	1751622828313	1751622909697	1092000	1113000		72	Körnerplatz	f
113	t	51.5301599	14.5247083	1751625502981	1751625502982	1751625502981	1543000	264000		57	Tischlereiweg 113b	f
151	t	51.3653879	14.5016774	1750769980140	1750770580140	1750769980140	1247000	1406000		76	Hauptstraße 24	t
152	f	51.5388861	14.5189616	1750771986140	1750772386815	1750772386815	1406000	602000		76	Zum Sportplatz 5	t
171	t	51.3937802	14.5894648	1750924360875	1750924960875	1750924360875	1243000	1413000		86	Körnerplatz	t
172	f	51.5350649	14.5289157	1750926373875	1750926973875	1750926973875	1413000	1006000		86	Siedlung - Sydlišćo	t
199	t	51.4992501	14.7881752	1751727631923	1751728231923	1751727631923	903000	1788000		100	Körnerplatz	t
200	f	51.5340052	14.5217744	1751730019923	1751730619923	1751730619923	1788000	1008000		100	Dorfstraße 106a	t
205	t	51.5305303	14.5320261	1751625314205	1751625914205	1751625314205	887000	1387000		103	Rohner Weg 10	f
206	f	51.363832	14.4941159	1751627301205	1751627901205	1751627901205	1387000	1274000		103	Romanikteich	f
207	t	51.4909266	14.5090665	1750872761788	1750873361788	1750872761788	1744000	946000		104	Dorfstraße 41	f
208	f	51.5338373	14.5364242	1750874307788	1750874907788	1750874907788	946000	910000		104	Schleifer Straße 5	f
214	f	51.5322939	14.5345323	1751019681260	1751020281260	1751020281260	2377000	1043000		107	Reinert Ranch	f
215	t	51.5279047	14.5229428	1751619336113	1751619936113	1751619336113	952000	1709000		108	Trebendorfer Weg 81	f
216	f	51.4108944	14.6075087	1751621645113	1751622245113	1751622245113	1709000	1376000		108	Körnerplatz	f
209	t	51.4241256	14.6861564	1751049289296	1751049889296	1751049289296	768000	1729000		105	Körnerplatz	t
217	t	51.5292289	14.5391334	1751386262230	1751386262230	1751386262230	382000	298000		109	Rohner Weg 3a	f
218	f	51.5417264	14.5348536	1751386560230	1751386560230	1751386560230	298000	1974000		109	Gemeindeamt	f
181	t	51.5386074	14.5148166	1751385471880	1751385880230	1751385471880	1067000	382000		91	Hoyerswerdaer Straße 91	f
182	f	51.3461596	14.4630317	1751388534230	1751388658880	1751388658880	1974000	1848000		91	Körnerplatz	f
219	t	51.476317	14.512214	1751553015014	1751553615014	1751553015014	2270000	1440000		110	Körnerplatz	f
220	f	51.5353088	14.5289849	1751555055014	1751555655014	1751555655014	1440000	1000000		110	Siedlung - Sydlišćo	f
223	t	51.5418744	14.537528	1751086470979	1751087070979	1751086470979	940000	1226000		112	Friedensstraße 77a	f
224	f	51.4017457	14.5680807	1751088296979	1751088896979	1751088896979	1226000	999000		112	Am Sportplatz 8	f
227	t	51.5472831	14.7246142	1751455764127	1751456364127	1751455764127	1072000	1603000		114	Löwe	f
228	f	51.5418744	14.537528	1751457967127	1751458567127	1751458567127	1603000	1001000		114	Friedensstraße 77a	f
229	t	51.5347542	14.5339465	1751424971224	1751425571224	1751424971224	878000	2244000		115	Tiefbau-Service-Berton	f
230	f	51.5755325	14.7032459	1751427815224	1751428415224	1751428415224	2244000	2364000		115	Zschorno 33	f
225	t	51.5416387	14.5289058	1750825961225	1750826561225	1750825961225	977000	1023000		113	Lindenweg 20	t
226	f	51.4160738	14.5268735	1750827584225	1750828184225	1750828184225	1023000	1123000		113	Merzdorfer Straße 38	t
231	t	51.5353088	14.5289849	1751475011553	1751475611553	1751475011553	880000	470000		116	Siedlung - Sydlišćo	f
232	f	51.5103364	14.5185168	1751476081553	1751476681553	1751476681553	470000	1360000		116	Körnerplatz	f
233	t	51.5341111	14.5351491	1751184627451	1751185227451	1751184627451	139000	1541000		117	Schleifer Straße 3	f
234	f	51.4173846	14.6088213	1751186768451	1751187368451	1751187368451	1541000	1165000		117	Körnerplatz	f
235	t	51.538412	14.5250691	1751287094430	1751287694430	1751287094430	966000	1850000		118	Jahnring 21	f
236	f	51.3280041	14.5841901	1751289544430	1751290144430	1751290144430	1850000	1721000		118	Körnerplatz	f
241	t	51.5435594	14.5297765	1750697872880	1750698472880	1750697872880	1025000	1322000		121	Alter Postweg 11	f
242	f	51.3779176	14.4927607	1750699794880	1750700394880	1750700394880	1322000	1184000		121	Körnerplatz	f
245	t	51.4410643	14.9402551	1751102408106	1751103008106	1751102408106	1598000	2497000		123	Körnerplatz	f
246	f	51.5397943	14.5386138	1751105505106	1751106105106	1751106105106	2497000	1033000		123	Strugaaue 37	f
237	t	51.5301599	14.5247083	1750937178962	1750937778962	1750937178962	1095000	1490000		119	Tischlereiweg 113b	t
238	f	51.4402384	14.6720513	1750939268962	1750939868962	1750939868962	1490000	490000		119	Körnerplatz	t
247	t	51.5417871	14.524831	1751527834343	1751528434343	1751527834343	1021000	172000		124	Hoyerswerdaer Straße 50	f
248	f	51.5360245	14.5286573	1751528606343	1751529206343	1751529206343	172000	981000		124	Friedensstraße 1	f
249	t	51.5393992	14.5316092	1751302392230	1751302992230	1751302392230	939000	1894000		125	Strugaaue 2	f
250	f	51.321187	14.4797212	1751304886230	1751305486230	1751305486230	1894000	1852000		125	Körnerplatz	f
255	t	51.5357337	14.5192924	1750936869500	1750937469500	1750936869500	982000	947000		128	Jahnring 13	f
256	f	51.5530562	14.5011595	1750938416500	1750939016500	1750939016500	947000	1701000		128	Körnerplatz	f
239	t	51.533173	14.529221	1751111967347	1751112567347	1751111967347	952000	2300000		120	Mühlroser Straße 8a	t
240	f	51.4628678	14.8164721	1751114867347	1751115467347	1751115467347	2300000	1471000		120	Körnerplatz	t
263	t	51.5279047	14.5229428	1751090475823	1751091075823	1751090475823	952000	1801000		132	Trebendorfer Weg 81	f
264	f	51.3538981	14.5726702	1751092876823	1751093476823	1751093476823	1801000	1712000		132	Körnerplatz	f
252	f	51.462315	14.8041402	1751732691986	1751733291986	1751733291986	2417000	1522000		126	Körnerplatz	f
257	t	51.5494948	14.7198935	1751726432088	1751727032088	1751726432088	934000	1551000		129	Uferweg 1	f
258	f	51.5319259	14.52021	1751730027987	1751730274986	1751730274986	261000	2417000		129	Dorfstraße 80	f
251	t	51.535357	14.5350536	1751729766986	1751729766987	1751729766986	1551000	261000		126	Werksweg 12	f
261	t	51.3965348	14.5068294	1751373825216	1751374425216	1751373825216	1020000	1062000		131	Körnerplatz	f
262	f	51.5312432	14.5115818	1751375487216	1751376087216	1751376087216	1062000	1084000		131	Mühlweg 5b	f
267	t	51.5386074	14.5148166	1750843531546	1750843592545	1750843531546	1577000	448000		134	Hoyerswerdaer Straße 91	f
268	f	51.5426988	14.7275189	1750847174994	1750847174994	1750847174994	1672000	1690000		134	Grenzvorplatz	f
270	f	51.5015226	14.6699289	1750925742135	1750926342135	1750926342135	1611000	775000		135	Körnerplatz	f
271	t	51.5329343	14.5196775	1751563027054	1751563627054	1751563027054	959000	1335000		136	Dorfstraße 106	f
272	f	51.5374459	14.6987797	1751564962054	1751565562054	1751565562054	1335000	797000		136	Kantweg 9	f
210	f	51.5400192	14.5240712	1751051618296	1751052218296	1751052218296	1729000	1122000		105	Thälmann-Siedlung 8	t
259	t	51.5400866	14.5128586	1751638500851	1751639100851	1751638500851	1094000	2147000		130	Hoyerswerdaer Straße 98	t
260	f	51.572029	14.7138936	1751641247851	1751641847851	1751641847851	2147000	2103000		130	Lindenweg 3	t
269	t	51.5329343	14.5196775	1750923531135	1750924131135	1750923531135	201000	1611000		135	Dorfstraße 106	f
253	t	51.5296246	14.5237337	1751217840911	1751218440911	1751217840911	1073000	1019000		127	Tischlereiweg 115a	t
243	t	51.3716203	14.6660856	1751527994224	1751528594224	1751527994224	1498000	1757000		122	Jahnstraße 31	t
244	f	51.5426918	14.5308026	1751530351224	1751530951224	1751530951224	1757000	235000		122	Hoyerswerdaer Straße 37	t
213	t	51.4606685	14.9385343	1751016704260	1751017304260	1751016704260	1457000	2377000		107	Körnerplatz	f
254	f	51.5536568	14.6377217	1751219459911	1751220059911	1751220059911	1019000	1053000		127	Körnerplatz	t
265	t	51.3198895	14.5711008	1751637312329	1751637912329	1751637312329	2256000	2450000		133	Körnerplatz	f
266	f	51.5418744	14.537528	1751642283124	1751642883124	1751642883124	2450000	1001000		133	Friedensstraße 77a	f
273	t	51.5256388	14.5896934	1750760146708	1750760746708	1750760146708	1011000	892000		137	Körnerplatz	f
274	f	51.538412	14.5250691	1750761638708	1750762238708	1750762238708	892000	1026000		137	Jahnring 21	f
275	t	51.5405733	14.520827	1751394513658	1751395113658	1751394513658	1063000	999000		138	Thälmann-Siedlung 25	f
276	f	51.5001088	14.6195524	1751396112658	1751396712658	1751396712658	999000	216000		138	Südpassage	f
277	t	51.533173	14.529221	1751121003328	1751121603328	1751121003328	952000	1248000		139	Mühlroser Straße 8a	f
278	f	51.5280219	14.6836302	1751122851328	1751123451328	1751123451328	1248000	622000		139	Siedlung 27	f
281	t	51.5342917	14.5338773	1750928975074	1750929575074	1750928975074	872000	242000		141	Schleifer Straße 2	f
282	f	51.5273903	14.5192582	1750929817074	1750930417074	1750930417074	242000	1045000		141	Mulkwitzer Weg 83b	f
285	t	51.4554602	14.8286936	1751439859088	1751440459088	1751439859088	1441000	2318000		143	Körnerplatz	f
286	f	51.5353088	14.5289849	1751442777088	1751443377088	1751443377088	2318000	1000000		143	Siedlung - Sydlišćo	f
287	t	51.5433114	14.5309437	1751702231086	1751702831086	1751702231086	987000	1792000		144	Hoyerswerdaer Straße 33	f
288	f	51.5131516	14.7974279	1751704623086	1751705223086	1751705223086	1792000	937000		144	Körnerplatz	f
211	t	51.5417871	14.524831	1750749937243	1750750537243	1750749937243	1021000	1475000		106	Hoyerswerdaer Straße 50	t
212	f	51.3640856	14.5056417	1750752012243	1750752125996	1750752125996	1475000	1351000		106	Bahnhofstraße 4	t
289	t	51.4494668	14.8058536	1751225778565	1751226378565	1751225778565	1171000	2061000		145	Körnerplatz	f
290	f	51.5279047	14.5229428	1751228439565	1751229039565	1751229039565	2061000	1012000		145	Trebendorfer Weg 81	f
291	t	51.5350649	14.5289157	1750966275764	1750966875764	1750966275764	946000	1594000		146	Siedlung - Sydlišćo	f
292	f	51.3581973	14.6268509	1750968469764	1750969069764	1750969069764	1594000	1485000		146	Körnerplatz	f
293	t	51.5360245	14.5286573	1751476536949	1751477136949	1751476536949	921000	662000		147	Friedensstraße 1	f
294	f	51.4984126	14.49606	1751477798949	1751478398949	1751478398949	662000	1486000		147	Körnerplatz	f
295	t	51.5397309	14.5335292	1751197139451	1751197739451	1751197139451	992000	475000		148	NORMA	f
296	f	51.5325373	14.484995	1751198214451	1751198814451	1751198814451	475000	1313000		148	Körnerplatz	f
279	t	51.5089716	14.7174184	1751132043948	1751132643948	1751132043948	486000	1397000		140	Görlitzer Straße 42	t
280	f	51.5416387	14.5289058	1751134040948	1751134640948	1751134640948	1397000	198000		140	Lindenweg 20	t
297	t	51.5292355	14.5213952	1751098021855	1751098621855	1751098021855	1017000	663000		149	Gefallenendenkmale Rohne	f
298	f	51.5359505	14.6163681	1751099284855	1751099884855	1751099884855	663000	746000		149	Katzenberg	f
299	t	51.528762	14.5279248	1751717672002	1751718272002	1751717672002	911000	1691000		150	Trebendorfer Weg 116c	f
300	f	51.3936574	14.6462811	1751719963002	1751720563002	1751720563002	1691000	1241000		150	Körnerplatz	f
283	t	51.536356	14.5290886	1751120851842	1751121451842	1751120851842	918000	2371000		142	Friedensstraße 1	t
284	f	51.5917388	14.6985494	1751123822842	1751124422842	1751124422842	2371000	1923000		142	Körnerplatz	t
301	t	51.5441549	14.707984	1750920781674	1750921381674	1750920781674	930000	1523000		151	Mozartweg 13	f
302	f	51.528762	14.5279248	1750922904674	1750923330135	1750923330135	1523000	201000		151	Trebendorfer Weg 116c	f
305	t	51.5340052	14.5217744	1751292689639	1751293289639	1751292689639	948000	2600000		153	Dorfstraße 106a	f
306	f	51.4357858	14.5753052	1751295889639	1751296489639	1751296489639	2600000	2360000		153	Körnerplatz	f
308	f	51.5386074	14.5148166	1751214419018	1751214686017	1751214686017	232000	2495000		154	Hoyerswerdaer Straße 91	f
325	t	51.5347542	14.5339465	1751468924170	1751469524170	1751468924170	878000	1575000		163	Tiefbau-Service-Berton	f
309	t	51.5123481	14.7184393	1751623941313	1751623941313	1751623941313	1113000	1543000		155	Krauschwitz Erlebnisbad	f
310	f	51.5393992	14.5316092	1751625766982	1751626258981	1751626258981	264000	574000		155	Strugaaue 2	f
311	t	51.5290227	14.5298561	1751257891956	1751258491956	1751257891956	894000	1520000		156	Rohner Weg 13b	f
312	f	51.3761735	14.6348363	1751260011956	1751260611956	1751260611956	1520000	1373000		156	Körnerplatz	f
313	t	51.333623	14.6446688	1751683270517	1751683870517	1751683270517	2195000	2298000		157	Bahnteich	f
314	f	51.5312432	14.5115818	1751686168517	1751686768517	1751686768517	2298000	283000		157	Mühlweg 5b	f
316	f	51.3882435	14.6843379	1751527514540	1751528114540	1751528114540	1785000	1899000		158	Körnerplatz	f
317	t	51.3879586	14.5866627	1750957085217	1750957685217	1750957085217	1581000	1835000		159	Körnerplatz	f
318	f	51.5296246	14.5237337	1750959520217	1750960120217	1750960120217	1835000	1133000		159	Tischlereiweg 115a	f
321	t	51.3583039	14.5209782	1750686287745	1750686887745	1750686287745	1395000	1457000		161	Körnerplatz	f
322	f	51.5332486	14.5141138	1750688344745	1750688944745	1750688944745	1457000	1101000		161	Mühlweg 5b	f
147	t	51.5133344	14.6928609	1751208729978	1751208870281	1751208270281	2082000	1975000		74	Körnerplatz	t
148	f	51.5342917	14.5338773	1751210845281	1751211445281	1751211445281	1975000	123000		74	Schleifer Straße 2	t
307	t	51.365419	14.5036073	1751206140706	1751206647978	1751206140706	1381000	1357000		154	Hauptstraße 21	f
173	t	51.5344271	14.5295784	1751214187017	1751214187018	1751214187017	1357000	232000		87	Mühlroser Straße 3	f
323	t	51.508867	14.6295514	1751224673373	1751225273373	1751224673373	290000	925000		162	Jahnstraße 83	f
324	f	51.5292355	14.5213952	1751226198373	1751226798373	1751226798373	925000	1077000		162	Gefallenendenkmale Rohne	f
326	f	51.3862821	14.6593136	1751471099170	1751471699170	1751471699170	1575000	1448000		163	Schadendorfer Weg 3	f
327	t	51.4746671	14.4797952	1751272359575	1751272959575	1751272359575	1578000	919000		164	Campingplatz Ruhlmühle	f
328	f	51.5301599	14.5247083	1751273878575	1751274478575	1751274478575	919000	352000		164	Tischlereiweg 113b	f
329	t	51.5191595	14.6791933	1750779102327	1750779702327	1750779102327	496000	1343000		165	Körnerplatz	f
330	f	51.5302251	14.5252029	1750781045327	1750781645327	1750781645327	1343000	1174000		165	Tischlereiweg 113b	f
332	f	51.5277052	14.5242631	1751609058788	1751609658788	1751609658788	1721000	279000		166	Trebendorfer Weg 116b	f
333	t	51.4986316	14.6440138	1751175134167	1751175734167	1751175134167	338000	1295000		167	Schillerstraße 29	f
337	t	51.536356	14.5290886	1750906665162	1750907265162	1750906665162	918000	1887000		169	Friedensstraße 1	f
338	f	51.4792079	14.8254971	1750909152162	1750909752162	1750909752162	1887000	1126000		169	Körnerplatz	f
335	t	51.5292355	14.5213952	1751076899597	1751077499597	1751076899597	1017000	1893000		168	Gefallenendenkmale Rohne	t
303	t	51.5416387	14.5289058	1751010557200	1751011157200	1751010557200	977000	2659000		152	Lindenweg 20	t
319	t	51.5679387	14.7137286	1750731461457	1750732061457	1750731461457	1410000	1980000		160	Neißestraße 9	t
320	f	51.5338373	14.5364242	1750734041457	1750734641457	1750734641457	1980000	910000		160	Schleifer Straße 5	t
331	t	51.3392317	14.5155895	1751606737788	1751607337788	1751606737788	1709000	1721000		166	Körnerplatz	f
315	t	51.5292355	14.5213952	1751525129540	1751525729540	1751525129540	1312000	1785000		158	Gefallenendenkmale Rohne	f
334	f	51.5394742	14.5159274	1751177029167	1751177337112	1751177629167	1295000	860000		167	Hoyerswerdaer Straße 94	f
339	t	51.5446031	14.5355952	1751382287606	1751382887606	1751382287606	1007000	1091000		170	Schleife - Slepo	f
340	f	51.5033791	14.6041078	1751383978606	1751384578606	1751384578606	1091000	531000		170	An der Rennbahn 25	f
341	t	51.3939185	14.6549939	1751484196952	1751484796952	1751484196952	1495000	1758000		171	Körnerplatz	f
342	f	51.5456749	14.5346691	1751486554952	1751487154952	1751487154952	1758000	1005000		171	Spremberger Straße 17	f
343	t	51.5344465	14.5268116	1751085080286	1751085680286	1751085080286	939000	1756000		172	Mulkwitzer Weg 10	f
344	f	51.3471793	14.5740014	1751087436286	1751088036286	1751088036286	1756000	1668000		172	Wiesenweg 419a	f
345	t	51.5319259	14.52021	1750709008413	1750709608413	1750709008413	1018000	1710000		173	Dorfstraße 80	f
346	f	51.3376206	14.5859082	1750711318413	1750711918413	1750711918413	1710000	1617000		173	Kirchweg 218	f
336	f	51.4981358	14.8317699	1751079392597	1751079992597	1751079992597	1893000	999000		168	Körnerplatz	t
351	t	51.3649445	14.6287751	1750683870627	1750683870627	1750683870627	1725000	1151000		176	Schäferei 10	f
352	f	51.5417871	14.524831	1750687946988	1750688274987	1750688274987	226000	2686000		176	Hoyerswerdaer Straße 50	f
104	f	51.4154337	14.6611758	1750685021627	1750685021628	1750685021628	1151000	1520000		52	Körnerplatz	f
304	f	51.4257135	14.7213543	1751013816200	1751013925260	1751013925260	2659000	2779000		152	Körnerplatz	t
354	f	51.5129751	14.4827117	1751604319634	1751604919634	1751604919634	792000	1709000		177	Körnerplatz	f
355	t	51.5386074	14.5148166	1750736795219	1750737395219	1750736795219	1067000	442000		178	Hoyerswerdaer Straße 91	f
356	f	51.5571993	14.5271456	1750737837219	1750738437219	1750738437219	442000	1139000		178	Körnerplatz	f
357	t	51.5277052	14.5242631	1751347093897	1751347093897	1751347093897	278000	421000		179	Trebendorfer Weg 116b	f
358	f	51.5397116	14.5059323	1751347514897	1751348114897	1751348114897	421000	264000		179	Hoyerswerdaer Straße 108	f
359	t	51.5443525	14.5405083	1751520243876	1751520843876	1751520243876	907000	1174000		180	Friedensstraße 62	f
360	f	51.5096717	14.672691	1751522017876	1751522617876	1751522617876	1174000	1312000		180	Waldhausstraße 118a	f
361	t	51.5426918	14.5308026	1751186436443	1751187036443	1751186436443	1027000	2060000		181	Hoyerswerdaer Straße 37	f
362	f	51.5763797	14.7157985	1751189096443	1751189696443	1751189696443	2060000	1560000		181	Schulstraße 7a	f
348	f	51.5417264	14.5348536	1751382730873	1751382730874	1751382730874	312000	289000		174	Gemeindeamt	f
350	f	51.4635472	14.8942348	1751400663452	1751401263452	1751401263452	2275000	1450000		175	Körnerplatz	f
363	t	51.5561647	14.4933556	1751395263963	1751395263963	1751395263963	2439000	454000		182	Körnerplatz	f
364	f	51.5340052	14.5217744	1751398008989	1751398388452	1751398388452	136000	2275000		182	Dorfstraße 106a	f
221	t	51.3294218	14.569829	1751392374964	1751392824963	1751392374964	1968000	2439000		111	Körnerplatz	f
389	t	51.5319259	14.52021	1751563934084	1751564534084	1751563934084	1018000	1313000		195	Dorfstraße 80	f
349	t	51.5342917	14.5338773	1751397864452	1751397872989	1751397864452	66000	136000		175	Schleifer Straße 2	f
222	f	51.5347542	14.5339465	1751395717963	1751395717964	1751395717964	454000	66000		111	Tiefbau-Service-Berton	f
365	t	51.5305303	14.5320261	1751450382743	1751450982743	1751450382743	887000	960000		183	Rohner Weg 10	f
366	f	51.4985383	14.6351373	1751451942743	1751452542743	1751452542743	960000	211000		183	Bautzener Straße 16	f
367	t	51.5062039	14.617033	1751178197112	1751178197112	1751178197112	860000	696000		184	August-Bebel-Straße 12	f
368	f	51.5305303	14.5320261	1751178893112	1751178893112	1751178893112	696000	2322000		184	Rohner Weg 10	f
369	t	51.4396975	14.5351562	1751351439162	1751352039162	1751351439162	1073000	911000		185	Körnerplatz	f
370	f	51.5426918	14.5308026	1751352950162	1751353550162	1751353550162	911000	1088000		185	Hoyerswerdaer Straße 37	f
371	t	51.5073703	14.649172	1751358335602	1751358935602	1751358335602	381000	1063000		186	Wolfgangstraße 10	f
372	f	51.5456749	14.5346691	1751359998602	1751360598602	1751360598602	1063000	1005000		186	Spremberger Straße 17	f
373	t	51.4832703	14.732597	1751606869444	1751607469444	1751606869444	731000	1609000		187	Körnerplatz	f
374	f	51.5353088	14.5289849	1751609078444	1751609678444	1751609678444	1609000	1000000		187	Siedlung - Sydlišćo	f
375	t	51.5399955	14.5160315	1751536554952	1751537154952	1751536554952	1058000	682000		188	Hoyerswerdaer Straße 90	f
376	f	51.5334503	14.6138292	1751537836952	1751538436952	1751538436952	682000	753000		188	Körnerplatz	f
377	t	51.4273748	14.5252141	1750744438943	1750745038943	1750744438943	1009000	827000		189	Körnerplatz	f
378	f	51.5393992	14.5316092	1750745865943	1750746465943	1750746465943	827000	999000		189	Strugaaue 2	f
379	t	51.5286634	14.5366817	1750782595328	1750783195328	1750782595328	976000	1346000		190	Rohner Weg 6	f
380	f	51.3952216	14.5119496	1750784541328	1750785141328	1750785141328	1346000	1097000		190	Körnerplatz	f
381	t	51.353354	14.5969374	1751115933807	1751116533807	1751115933807	1458000	1649000		191	Platz der MTS 348	f
382	f	51.528762	14.5279248	1751118182807	1751118782807	1751118782807	1649000	971000		191	Trebendorfer Weg 116c	f
383	t	51.4563228	14.9487929	1751352939964	1751353539964	1751352939964	1490000	2379000		192	Podroscher Straße 43	f
384	f	51.5279047	14.5229428	1751355918964	1751356518964	1751356518964	2379000	1012000		192	Trebendorfer Weg 81	f
353	t	51.5302251	14.5252029	1751602927634	1751603527634	1751602927634	1978000	792000		177	Tischlereiweg 113b	f
385	t	51.5301599	14.5247083	1751595958587	1751596558587	1751595958587	1095000	1959000		193	Tischlereiweg 113b	f
386	f	51.3252942	14.4769016	1751598517587	1751599117587	1751599117587	1959000	1978000		193	Körnerplatz	f
347	t	51.5080674	14.6671174	1751380365874	1751380965874	1751380365874	475000	1309000		174	Waldhausstraße 116	f
387	t	51.5578381	14.5475697	1751382274874	1751382418873	1751382274874	1309000	312000		194	Körnerplatz	f
388	f	51.5399955	14.5160315	1751383383839	1751383983839	1751383983839	289000	1112000		194	Hoyerswerdaer Straße 90	f
390	f	51.3690022	14.6101025	1751565847084	1751566447084	1751566447084	1313000	1220000		195	Körnerplatz	f
391	t	51.5405733	14.520827	1750836333209	1750836933209	1750836333209	1063000	1241000		196	Thälmann-Siedlung 25	f
392	f	51.4034182	14.5702169	1750838174209	1750838774209	1750838774209	1241000	1125000		196	Hammerstraße 50 D	f
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
2024-07-01	2025-06-21T18:09:06.467Z
2025-03-24	2025-06-21T18:09:06.468Z
2025-04-07	2025-06-21T18:09:06.469Z
2025-04-24-json-and-latlng-precision	2025-06-21T18:09:06.483Z
2025-04-30	2025-06-21T18:09:06.523Z
2025-05-21	2025-06-21T18:09:06.524Z
2025-06-06-update-scheduled-times	2025-06-21T18:09:06.525Z
2025-06-11-update-direct-durations	2025-06-21T18:09:06.527Z
2025-06-12-reconstructable-requests	2025-06-21T18:09:06.541Z
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
1	1	0	0	0	0	0	0	1	1	dde463b1880e7127da94095eb8c3c317	f	t	300
2	2	0	0	0	0	0	0	2	1	f35dbc174b870ecc4df1f7c5b53dd0fe	f	t	600
7	2	0	0	0	0	0	0	7	1	9f00395e3afdc788aac7a6bcaf94a8a5	f	t	600
4	1	0	0	0	0	0	0	4	1	bd85178f729c6d36fce86cad7b1c40c5	f	t	300
15	2	0	0	0	0	0	0	15	1	5beed1db7d40dda7f9438e8823102629	f	f	600
14	2	0	0	0	0	0	0	14	1	c2e5043c345945ff48caeefa4b3b7b69	f	t	600
17	1	0	0	0	0	0	0	17	1	52f022274f9937ff385b63c76669eb0c	f	f	300
21	1	0	0	0	0	0	0	21	1	0d41a732a85757612c755b6d9b8d9456	f	f	300
8	2	0	0	0	0	0	0	8	1	0417dd02b66faf109414f929ea373a64	f	t	600
22	1	0	0	0	0	0	0	22	1	8334c5ec0eddd8ff4f1544ff512cee46	f	f	300
12	2	0	0	0	0	0	0	12	1	f06416e07f50c71c7e35fca4d3dd89a4	f	t	600
26	1	0	0	0	0	0	0	26	1	8936e6832a35ca412dd17e44ffe53d04	f	f	300
19	2	0	0	0	0	0	0	19	1	bb8b83d1e6b65eb4c47fd88177d55eaa	f	t	600
33	1	0	0	0	0	0	0	30	1	762b7b1295c8497cb3bc043bede72357	f	f	300
43	1	0	0	0	0	0	0	37	1	cbc87af35550581d4d94301249ea37b0	f	t	300
6	1	0	0	0	0	0	0	6	1	4b694bf8179aaa8add309e66210cec18	f	t	300
34	1	0	0	0	0	0	0	31	1	854f537e7b9ae50c7cff7ee194161b5b	f	t	300
27	1	0	0	0	0	0	0	27	1	fa8848cad8e1a8e914dd668af7898c3f	f	t	300
37	2	0	0	0	0	0	0	13	1	f8819359275f34ae7a07ef78fb56bd35	f	f	600
38	2	0	0	0	0	0	0	33	1	7ef38fdb9a2efa6104147d72341505de	f	f	600
11	2	0	0	0	0	0	0	11	1	fb03d5099a3a8324dc83b3a767b29794	f	t	600
40	2	0	0	0	0	0	0	35	1	2131c0fd58b5236a9298d3d03639a9cd	f	f	600
32	2	0	0	0	0	0	0	18	1	800aec46de045225de4e726f36941dfa	f	t	600
42	2	0	0	0	0	0	0	36	1	b9dfc9c9005721422c62e1a1efaddeb2	f	f	600
44	2	0	0	0	0	0	0	22	1	9447e6671300b601e309d2a774d02df3	f	f	600
46	2	0	0	0	0	0	0	39	1	015a3a278f026f256503a6026d23aeff	f	f	600
50	1	0	0	0	0	0	0	21	1	f4a2d33d6db30d6b0a795149f49f69db	f	f	300
18	1	0	0	0	0	0	0	18	1	e6c3f340a76b4c79e4aa39464aad8d95	f	t	300
47	1	0	0	0	0	0	0	40	1	c388eb04ef4a9c99ddb9772688d790a7	f	t	300
52	1	0	0	0	0	0	0	42	1	cb25036d26c76ed53e0aadca35662f93	f	f	300
53	1	0	0	0	0	0	0	43	1	ecdf0292bdd5dc98bfe566967df8c1b3	f	f	300
41	2	0	0	0	0	0	0	32	1	32b9d6f0933ea3fbf1823e44625ebb01	f	t	600
56	1	0	0	0	0	0	0	17	1	af44e658326f78da18d7f6c6701f3aa1	f	f	300
57	2	0	0	0	0	0	0	46	1	4e3f7974123c4e031739186cb3c292a2	f	f	600
58	1	0	0	0	0	0	0	47	1	4f67585d5059f4fa06682e774d38eb23	f	f	300
61	1	0	0	0	0	0	0	49	1	1e1581af2f482f8fa349e5e1803ce116	f	f	300
74	1	0	0	0	0	0	0	59	1	33a21934ff103b7f36deb178de20cefe	f	t	300
5	1	0	0	0	0	0	0	5	1	94749b1942b3ccc7fcc1197e39dc1c43	f	t	300
48	2	0	0	0	0	0	0	41	1	9e9d0a0041a50bc9e33852966e6dfe1f	f	t	600
67	1	0	0	0	0	0	0	54	1	848f116e34e1b5557b343ea5367f6dbe	f	f	300
68	1	0	0	0	0	0	0	55	1	92090a41a7368299c1feccf777934e7a	f	f	300
69	2	0	0	0	0	0	0	56	1	75be0683aac3f2866838461713286e86	f	f	600
70	1	0	0	0	0	0	0	24	1	cce138f5f47803e0bfb99aeb0706c028	f	f	300
72	1	0	0	0	0	0	0	46	1	bacd092d47466aef637707828739da3a	f	f	300
73	1	0	0	0	0	0	0	58	1	2574c7c868caae8d2992abf1b29ae515	f	f	300
24	2	0	0	0	0	0	0	24	1	4de6279ff4f677336dd57fac256e04a7	f	t	600
49	2	0	0	0	0	0	0	22	1	7275eec5336891abc73d81fea8e3d204	f	t	600
36	2	0	0	0	0	0	0	32	1	5807f9246bd6147cc1a1b7c431c500e9	f	t	600
31	1	0	0	0	0	0	0	29	1	ca8a4ac51724f64a785292b0d2b83fb5	f	t	300
51	1	0	0	0	0	0	0	25	1	44d0d4a22a880eaad5dc513e9e71340b	f	t	300
65	2	0	0	0	0	0	0	52	1	91b35d6f5529e5af1c6d2a2440e99049	f	t	600
25	2	0	0	0	0	0	0	25	1	d001d500102900c4a1f9ef4b66105227	f	t	600
3	2	0	0	0	0	0	0	3	1	97c653bebd7d7470f6002eae54ddcf32	f	t	600
62	2	0	0	0	0	0	0	50	1	9f95c7b09dd1e1810c8e1c06c3e6f593	f	t	600
13	1	0	0	0	0	0	0	13	1	a0d7168c9e418a4c5f8a19d72711c008	f	t	300
9	1	0	0	0	0	0	0	9	1	ea9690f160a8dd24ca9de2b3f82da82f	f	t	300
59	2	0	0	0	0	0	0	48	1	a7c2de5c43f16cb5fd4c6a263df2917a	f	t	600
29	1	0	0	0	0	0	0	28	1	db6d31759e8c013fdeb21889c088d5f9	f	t	300
30	2	0	0	0	0	0	0	16	1	985e3aa0e0a28d60425c8aff3f603c7d	f	t	600
20	1	0	0	0	0	0	0	55	1	0411c06189cfca9ea0ae616424e39bb3	f	f	300
28	1	0	0	0	0	0	0	22	1	f431b48bb1eae592d6e2e8cbff366091	f	t	300
64	1	0	0	0	0	0	0	51	1	de19b6ad936e9ed8a313a81d383cde99	f	t	300
45	1	0	0	0	0	0	0	38	1	a40c699dc3ea519675d9f526bcbae592	f	t	300
66	1	0	0	0	0	0	0	53	1	771175d96ef43783e5d4c2cc74d4b5a5	f	t	300
54	1	0	0	0	0	0	0	44	1	0a476aec3a582555fb4d88cceab5ee80	f	t	300
55	1	0	0	0	0	0	0	45	1	0c854a71d731ad17cc24f1583ee489f4	f	t	300
60	2	0	0	0	0	0	0	23	1	312dbc86c28ae9b9ae36ee8dc7ecb2df	f	t	600
35	2	0	0	0	0	0	0	25	1	955b1e2d1c74cb8d8f42a802f2721fa9	f	t	600
16	1	0	0	0	0	0	0	16	1	3d2b508b91cbc6f73cc2aac8ef4629a1	f	t	300
10	1	0	0	0	0	0	0	42	1	3c6e02c9b89fee55e11912790f840ac0	f	f	300
39	1	0	0	0	0	0	0	34	1	89e5643e7c47d36b74614efea21f7567	f	t	300
75	2	0	0	0	0	0	0	60	1	1192fc8d616f6676d2cf55fd9cdfea3b	f	f	600
77	2	0	0	0	0	0	0	59	1	df8775a1b748d16b96c9d740f41ad03a	f	f	600
78	1	0	0	0	0	0	0	61	1	4c68f79f9b5a0b3efda31a3d11114478	f	f	300
79	1	0	0	0	0	0	0	62	1	1f4b88db7c3567419c45f2bccffea4a5	f	f	300
80	2	0	0	0	0	0	0	49	1	ba5ad6b6672ae2c4bcba873daa7c3b94	f	f	600
71	2	0	0	0	0	0	0	57	1	1ed629938a95f5f9888797743780df73	f	t	600
82	1	0	0	0	0	0	0	30	1	bdc1bf7a725d71ef226c1eafc97c1a7a	f	f	300
83	1	0	0	0	0	0	0	63	1	c5ef1cdea648eb9a3bb419821e47c557	f	f	300
84	2	0	0	0	0	0	0	64	1	5cda244a0169e5ce12594f94d55641ee	f	f	600
127	2	0	0	0	0	0	0	96	1	9041e60cd77a25c5591f9fdc341422f0	f	t	600
88	2	0	0	0	0	0	0	68	1	2eb23cccf2ebf10034ff66e5b5cc17a6	f	f	600
91	1	0	0	0	0	0	0	70	1	d0765f90b3c0f2dd68710eb32d2b8ecc	f	f	300
92	1	0	0	0	0	0	0	61	1	bba0b467f3d18ebe58e4468dd11b9fb1	f	f	300
94	2	0	0	0	0	0	0	26	1	f48770c249e312ebf9de7e638645015e	f	f	600
95	1	0	0	0	0	0	0	72	1	1eec6b444610bf27b62e2b29bc1b6bca	f	f	300
96	1	0	0	0	0	0	0	64	1	567589fd53898ddd65cd3eb482f2d88b	f	f	300
97	2	0	0	0	0	0	0	73	1	4ad953f096f90bc4afb73a569a920c1f	f	f	600
99	2	0	0	0	0	0	0	75	1	469d1c57a9ef3f6d0d1f7cff8ea4dcfe	f	f	600
101	1	0	0	0	0	0	0	77	1	fd73e6f83a4283769ea3a66203e0fcf0	f	f	300
98	2	0	0	0	0	0	0	74	1	126203ce0f05e5e6251c7f0d1fa71867	f	t	600
100	1	0	0	0	0	0	0	76	1	c9cf31ff08a6b2d5dc31b0aaa6d0e839	f	t	300
103	2	0	0	0	0	0	0	78	1	07e7bd4aa162d7485c358fdf461bed8f	f	f	600
104	1	0	0	0	0	0	0	79	1	90f46881938b14eab7ebbe94a222f7a6	f	f	300
107	1	0	0	0	0	0	0	81	1	7380bcbc91a4d962fac19c4652d1b893	f	f	300
108	2	0	0	0	0	0	0	82	1	92fee88574e478199aabcfba7cc48aeb	f	f	600
109	2	0	0	0	0	0	0	70	1	21ab527ff90053abbba262c42692ebad	f	f	600
110	1	0	0	0	0	0	0	83	1	88bbd6ae7f2740ce6784bacaf6d77e69	f	f	300
111	1	0	0	0	0	0	0	84	1	cdefb1037a3d287b61e92cf39e03fb3c	f	f	300
112	1	0	0	0	0	0	0	85	1	5780398ee3726dd3b9e50b8f5f06d267	f	f	300
93	2	0	0	0	0	0	0	71	1	59e258b7fc381df917cf4ef4be020659	f	t	600
114	1	0	0	0	0	0	0	87	1	321175a227a4d1a7326220f0d25ed787	f	f	300
115	2	0	0	0	0	0	0	64	1	7a9c3321f59fc64755c0bb1a71c0d7c6	f	f	600
89	1	0	0	0	0	0	0	54	1	f92693bdd804dbc9db56ed316f7a9b6a	f	t	300
113	2	0	0	0	0	0	0	86	1	3ec75463d40826ab99fba3cefc94bbb7	f	t	600
116	1	0	0	0	0	0	0	47	1	81a8d41426b04434a99a7cefb510c6f9	f	f	300
117	2	0	0	0	0	0	0	36	1	c0d88de2a59a0f2afcdb28e1bce065be	f	f	600
118	1	0	0	0	0	0	0	88	1	438f99c90f476275527e8f92740a1a78	f	f	300
121	1	0	0	0	0	0	0	91	1	5d5db200cf26784b464208fc21f946ae	f	f	300
102	2	0	0	0	0	0	0	28	1	85b7ecae91d933ba56237c2fa2333dbb	f	t	600
123	2	0	0	0	0	0	0	92	1	f0b15e26802e075776fe7afe9b199d1d	f	f	600
119	2	0	0	0	0	0	0	89	1	603c3d05f84e3a515995c96720cbbee9	f	t	600
124	2	0	0	0	0	0	0	93	1	84c33e36651a34d7c13730706e695c22	f	f	600
125	2	0	0	0	0	0	0	94	1	f226c22cc203b20db818c0dc8862d16f	f	f	600
126	1	0	0	0	0	0	0	95	1	6dde0f8d7357a418e2a3707c868d2c40	f	f	300
128	1	0	0	0	0	0	0	97	1	47a5bfa24331a12678bad98d525d511d	f	f	300
120	2	0	0	0	0	0	0	90	1	1b8cbfb707c4c01a64fd0aaf1cbeb564	f	t	600
129	2	0	0	0	0	0	0	95	1	e33d4cb6cdd1e8f5d8566fefc5970e26	f	f	600
131	1	0	0	0	0	0	0	98	1	52318e7995c92646621b6f282e91539d	f	f	300
132	2	0	0	0	0	0	0	99	1	222203cb1f2c07ce48cec1104900a46f	f	f	600
133	1	0	0	0	0	0	0	25	1	485332e2ac54958d6f7b348e4fb0bf53	f	f	300
134	1	0	0	0	0	0	0	55	1	c111281dc90dbf8065ac7a060f8c7025	f	f	300
135	2	0	0	0	0	0	0	100	1	f1348576df96406dc3359ea572fad69b	f	f	600
136	2	0	0	0	0	0	0	101	1	1e924ef5fdbfe981a530e69962f769c9	f	f	600
137	2	0	0	0	0	0	0	102	1	e025d081dfa4813b44b47f1a07529ef9	f	f	600
90	1	0	0	0	0	0	0	69	1	5e9d2dce6bc31b8042d48cfaa47db25f	f	t	300
138	2	0	0	0	0	0	0	103	1	a0e002ba8f84506de20cb6f509a2ee0e	f	f	600
139	1	0	0	0	0	0	0	104	1	6884bc1fefd8a96da6f64ee3819eeddc	f	f	300
141	1	0	0	0	0	0	0	105	1	379387011025c5635a94999f84e29913	f	f	300
143	2	0	0	0	0	0	0	107	1	e82c8df5c1906a4bbdea0c18422d86b4	f	f	600
144	1	0	0	0	0	0	0	108	1	322361f67736ec1637c95a96a89b1b47	f	f	300
106	1	0	0	0	0	0	0	38	1	509c4f161b0319a08a846447007713e2	f	t	300
105	1	0	0	0	0	0	0	80	1	4fc73b734fa4947d1eaf1245d1ac73ca	f	t	300
130	2	0	0	0	0	0	0	3	1	93f9db9c9d75bc4ae68171fd21803ba1	f	t	600
145	2	0	0	0	0	0	0	109	1	a57cfd2a5e12579f42e2683ec7f6fc0c	f	f	600
146	1	0	0	0	0	0	0	110	1	1ccd58567f80e2c746fb7dd3b1bdf27e	f	f	300
147	2	0	0	0	0	0	0	111	1	7e61f289034b62b218e6ec5af2181209	f	f	600
148	2	0	0	0	0	0	0	112	1	16d96d4678221798753323e9377bf1d1	f	f	600
140	2	0	0	0	0	0	0	17	1	7924461ee229f1315d447cd84b1261a3	f	t	600
142	1	0	0	0	0	0	0	106	1	e69bc8b5623e9eef85329bc1d3607eed	f	t	300
122	2	0	0	0	0	0	0	43	1	1ca20baa25d4c480d4d0b9728354df7c	f	t	600
87	1	0	0	0	0	0	0	59	1	f215bebacb35257916cb0d28b699bc5c	f	f	300
76	2	0	0	0	0	0	0	35	1	e44748f64c2985f1fee28ea5cf4deaae	f	t	600
86	1	0	0	0	0	0	0	66	1	9d2446ba7f24017ee5c4f85d8a5706c0	f	t	300
81	2	0	0	0	0	0	0	46	1	3a8c5c376a32a885385bcb363eebeac8	f	t	600
149	1	0	0	0	0	0	0	113	1	cdcd149e202dedf994f6c78eb7723770	f	f	300
150	2	0	0	0	0	0	0	114	1	8950fa46c6de40a991fde1b6570de457	f	f	600
151	2	0	0	0	0	0	0	100	1	916361ac849785e1e6abc419487cfe7f	f	f	600
153	2	0	0	0	0	0	0	115	1	faf24159eccfa48368f56e3f7fe86043	f	f	600
154	2	0	0	0	0	0	0	59	1	3f4679054ac4cbf27137bd1c71ed0ba2	f	f	600
155	1	0	0	0	0	0	0	46	1	6be99a8a1bda9a3b6bfe20fd1d42e9e9	f	f	300
23	1	0	0	0	0	0	0	23	1	10269f0671d5e22008dbb0874cfddff8	f	t	300
156	1	0	0	0	0	0	0	116	1	84c0269d9db77f8f5dc1eaa161b12ec0	f	f	300
157	2	0	0	0	0	0	0	39	1	57530b6b59f690ec0e0fa5572c6a6caf	f	f	600
158	1	0	0	0	0	0	0	43	1	e63f26cfc40ab19e154b0b5435860a81	f	f	300
159	1	0	0	0	0	0	0	117	1	8a3f5c189a3365e2996fc99dac51140a	f	f	300
161	2	0	0	0	0	0	0	119	1	52d37f007d1a02107d0a65092f8c6fb6	f	f	600
162	1	0	0	0	0	0	0	120	1	b8d0f3048b64543d8f0be9e017d5617f	f	f	300
85	2	0	0	0	0	0	0	65	1	9dddae3413cbc37f964f2ecf734efe83	f	t	600
163	1	0	0	0	0	0	0	121	1	91d6e21d59a171860da2ac0641ca27be	f	f	300
164	1	0	0	0	0	0	0	54	1	a79a38571564be4eb27de6467a7e71eb	f	f	300
165	2	0	0	0	0	0	0	122	1	1ac08720cbc1c0aebcc6aab0ba0fafd4	f	f	600
166	1	0	0	0	0	0	0	46	1	be6196ad6f9c749b3ef8fa5cf46bd1dd	f	f	300
167	2	0	0	0	0	0	0	36	1	9b55299d32263011a128dbe949c70675	f	f	600
169	2	0	0	0	0	0	0	68	1	3e3dde40673e84b0391b0f7b7d608dd6	f	f	600
170	1	0	0	0	0	0	0	123	1	4f01caaf0f4ab960a0502265aa3bb6e3	f	f	300
171	2	0	0	0	0	0	0	124	1	1e8e002780282c227dd72cccca1d9e55	f	f	600
172	2	0	0	0	0	0	0	125	1	1349be674c8ee80981ea6bff4aff0915	f	f	600
173	1	0	0	0	0	0	0	126	1	23779199d32dec0b0c85717a8535c251	f	f	300
174	1	0	0	0	0	0	0	127	1	59617aa1612108007ca539faf96da720	f	f	300
168	1	0	0	0	0	0	0	40	1	90539c90fa7de02777f66aa9b87c0df1	f	t	300
176	2	0	0	0	0	0	0	42	1	0bd8d0a1bb3b82fe609c9d5522485423	f	f	600
63	1	0	0	0	0	0	0	34	1	f6c34cd56f6f9b3b6629485a0478f733	f	t	300
152	2	0	0	0	0	0	0	81	1	b1bd40cc0509708f338668ebfce7a956	f	t	600
160	2	0	0	0	0	0	0	118	1	ecf93df1bf636491165982e85aea7609	f	t	600
177	1	0	0	0	0	0	0	46	1	1a63f31389b98c70c6ee2dee885b9b93	f	f	300
178	1	0	0	0	0	0	0	129	1	2b60f6942acb5b5172451f66f31d9112	f	f	300
179	1	0	0	0	0	0	0	30	1	3bf80aa227e38980fd8671655cafdabc	f	f	300
180	2	0	0	0	0	0	0	43	1	626f39bb1ddb3200e125efbc1653f418	f	f	600
181	2	0	0	0	0	0	0	130	1	875c2e31a1d8db6c667ba15f654e3f72	f	f	600
175	1	0	0	0	0	0	0	84	1	ab507bb18b6a20d81244352056fac429	f	f	300
182	1	0	0	0	0	0	0	84	1	0b1f9efefab08b3a70cb0bacdddd741e	f	f	300
183	2	0	0	0	0	0	0	131	1	9d2c417bb71e02fb154eee437759b982	f	f	600
184	2	0	0	0	0	0	0	36	1	08482ff4550bc0f27696b7857169a005	f	f	600
185	1	0	0	0	0	0	0	132	1	f5d1cb08c76f82770849373901a28080	f	f	300
186	1	0	0	0	0	0	0	133	1	72bb849e2e6e68a79c7682b186f7670e	f	f	300
187	1	0	0	0	0	0	0	134	1	1e62f4858d78c0b2b055b92980b642e0	f	f	300
188	2	0	0	0	0	0	0	135	1	7147cd1e151621d7058d919b03a9b365	f	f	600
189	1	0	0	0	0	0	0	136	1	df2706ba689e3acaaa29cb19e6733bd7	f	f	300
190	2	0	0	0	0	0	0	137	1	66d2b81fdda906058a1d383b769afa95	f	f	600
191	1	0	0	0	0	0	0	138	1	39ff01e01272bc7281c30ece8885449b	f	f	300
192	2	0	0	0	0	0	0	139	1	b36330739ff96016e9afd5a9446baa47	f	f	600
193	1	0	0	0	0	0	0	46	1	8e190be65ba797fdca0b3c4a6c05b6cf	f	f	300
194	1	0	0	0	0	0	0	127	1	43aae1325e28a5e1e56a6e17dd11e772	f	f	300
195	2	0	0	0	0	0	0	140	1	ebaa4c3ed9b7f17c7657e39930d7905b	f	f	600
196	2	0	0	0	0	0	0	55	1	65a2d700b2076a5922773c6fe41a9c9a	f	f	600
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
1	1751553770882	1751558131882	\N	1	\N	t	message
2	1751465604948	1751467563948	\N	1	\N	t	message
57	1751001896336	1751004864336	281000	1	\N	t	\N
91	1750697447880	1750700978880	2681000	1	\N	f	\N
7	1751194831018	1751198177018	489000	1	\N	t	message
34	1750707948826	1750711973949	1822000	1	\N	t	message
4	1750870472675	1750875604675	\N	1	\N	t	\N
14	1751725443327	1751729902327	2161000	1	\N	t	message
18	1751344997120	1751353187403	1734000	1	\N	t	\N
9	1751357198833	1751361585833	2428000	1	\N	t	\N
89	1750936683962	1750939758962	271000	2	\N	t	message
8	1751169618134	1751174017134	2140000	1	\N	t	\N
29	1751335746891	1751339556891	1710000	1	\N	t	message
12	1751171553904	1751175826904	\N	2	\N	t	\N
63	1751695537119	1751700457119	1697000	1	\N	f	\N
49	1751446983205	1751454511236	1511000	1	\N	f	\N
106	1751120533842	1751125745842	159000	2	\N	t	message
19	1751075819766	1751079154766	1408000	1	\N	t	message
6	1751599670525	1751602551525	2611000	1	\N	t	message
83	1751551345014	1751556055014	1384000	1	\N	f	\N
44	1751608522082	1751612362082	2210000	2	\N	t	\N
31	1751462451151	1751466243151	\N	1	\N	t	message
27	1751204978995	1751209051995	1953000	1	\N	t	message
11	1751530865492	1751533126492	234000	1	\N	t	message
5	1751609021045	1751613102045	1672000	1	\N	t	message
74	1751625069140	1751628380140	1128000	2	\N	t	message
25	1751635656329	1751643284124	1361000	2	\N	f	\N
88	1751286728430	1751291265430	1707000	1	\N	f	\N
41	1751262046428	1751267243428	166000	1	\N	t	\N
37	1750878617899	1750884142899	\N	2	\N	t	\N
99	1751090123823	1751094588823	1170000	1	\N	f	\N
51	1751538916800	1751542676800	2151000	1	\N	t	\N
53	1751356025686	1751360512686	2275000	2	\N	t	\N
30	1751340657897	1751350882882	3654000	2	\N	f	\N
73	1751543228079	1751546394079	106000	2	\N	f	\N
76	1751727328923	1751731027923	1857000	1	\N	t	message
24	1751102855003	1751117750443	642000	1	\N	f	\N
52	1751053901094	1751058430094	714000	1	\N	t	\N
71	1751107558457	1751110173457	1127000	2	\N	t	\N
17	1751132157948	1751139193478	279000	1	\N	f	\N
60	1751127112369	1751131240369	1957000	1	\N	f	\N
70	1751384813230	1751390382230	1150000	1	\N	f	\N
32	1750919020922	1750928238926	108000	1	\N	t	\N
69	1751558931365	1751561112365	150000	1	\N	t	\N
21	1751367609784	1751372427338	1209000	1	\N	f	\N
75	1751161529543	1751165975543	1596000	1	\N	f	\N
33	1750881599667	1750885620667	1840000	1	\N	f	\N
79	1750871617788	1750875217788	2672000	1	\N	f	\N
3	1751638006851	1751649100239	729000	1	\N	t	message
80	1751049121296	1751052740296	1706000	1	\N	t	message
109	1751225207565	1751229451565	2591000	1	\N	f	\N
78	1751625027205	1751628575205	1793000	2	\N	f	\N
93	1751527413343	1751529587343	251000	2	\N	f	\N
13	1751031640949	1751040258898	249000	1	\N	f	\N
87	1751455292127	1751458968127	1701000	1	\N	f	\N
40	1751076482597	1751086130978	662000	1	\N	t	\N
62	1751037150173	1751039545173	1699000	2	\N	f	\N
86	1750825584225	1750828707225	189000	1	\N	t	message
56	1751485027810	1751488859810	2228000	1	\N	f	\N
47	1751470557870	1751477441553	148000	1	\N	f	\N
48	1751178832013	1751183437013	198000	2	\N	t	message
28	1750902493342	1750910226851	2087000	1	\N	t	message
35	1750769333140	1750775206815	541000	1	\N	f	\N
22	1751710410817	1751720173874	1708000	1	\N	f	\N
90	1751111615347	1751116338347	197000	2	\N	t	\N
95	1751726098088	1751734213986	1585000	1	\N	f	\N
50	1751368474198	1751375792198	154000	2	\N	t	\N
16	1751564703495	1751575392860	2509000	1	\N	t	message
98	1751373405216	1751376571216	1285000	1	\N	f	\N
26	1750855501176	1750864638883	2498000	1	\N	f	\N
39	1751681675517	1751693158492	2608000	1	\N	f	\N
23	1750837812255	1750840916518	152000	1	\N	t	message
101	1751562668054	1751565759054	1524000	2	\N	f	\N
61	1750917172390	1750922247928	281000	2	\N	f	\N
104	1751120651328	1751123473328	159000	1	\N	f	\N
45	1750937882849	1750942570849	1749000	1	\N	t	message
105	1750928703074	1750930862074	1524000	1	\N	f	\N
107	1751439018088	1751443777088	1553000	2	\N	f	\N
108	1751701844086	1751705560086	2085000	1	\N	f	\N
102	1750759735708	1750762664708	840000	1	\N	f	\N
38	1750749516243	1750756734996	107000	1	\N	t	message
15	1750691063195	1750695824195	1915000	2	\N	f	\N
72	1751654703308	1751657050308	674000	1	\N	f	\N
110	1750965929764	1750969954764	911000	2	\N	f	\N
96	1751217367911	1751220512911	2166000	2	\N	t	message
112	1751196747451	1751199527451	1564000	1	\N	f	\N
77	1750943940252	1750948154252	288000	1	\N	f	\N
64	1751424693224	1751440431233	2205000	1	\N	f	\N
100	1750920451674	1750926517135	1403000	1	\N	f	\N
94	1751302053230	1751306738230	2654000	1	\N	f	\N
111	1751476215949	1751479284949	1617000	2	\N	f	\N
36	1751175396167	1751187933451	1323000	1	\N	f	\N
65	1750965881475	1750970996475	178000	1	\N	t	message
54	1751271381575	1751280145860	1307000	1	\N	f	\N
92	1751101410106	1751106538106	2860000	2	\N	f	\N
58	1751544623453	1751548472453	1975000	1	\N	f	\N
42	1750681162627	1750692749987	\N	1	\N	f	\N
68	1750906347162	1750917978710	107000	1	\N	f	\N
46	1751595463587	1751627421981	1435000	1	\N	f	\N
85	1751086130979	1751089295979	720000	1	\N	f	\N
103	1751394050658	1751396328658	111000	2	\N	f	\N
43	1751519936876	1751535474672	206000	1	\N	f	\N
84	1751390856963	1751402113452	1698000	1	\N	f	\N
66	1750923717875	1750927379875	1768000	2	\N	t	\N
97	1750936487500	1750940117500	1790000	2	\N	f	\N
55	1750835870209	1750853507570	1238000	1	\N	f	\N
113	1751097604855	1751100030855	1800000	1	\N	f	\N
115	1751292341639	1751298249639	1768000	1	\N	f	\N
59	1751201872706	1751219477017	1280000	1	\N	f	\N
116	1751257597956	1751261384956	118000	1	\N	f	\N
117	1750956104217	1750960653217	1198000	1	\N	f	\N
119	1750685492745	1750689445745	\N	2	\N	f	\N
114	1751717361002	1751721204002	225000	2	\N	f	\N
122	1750779206327	1750782219327	1212000	1	\N	f	\N
123	1751381880606	1751384509606	356000	1	\N	f	\N
124	1751483301952	1751487559952	1677000	2	\N	f	\N
125	1751084741286	1751089104286	198000	2	\N	f	\N
126	1750708590413	1750712935413	233000	2	\N	f	\N
81	1751010180200	1751020724260	2467000	1	\N	f	\N
118	1750730651457	1750734951457	2188000	1	\N	t	\N
129	1750736328219	1750738976219	1323000	1	\N	f	\N
121	1751468646170	1751472547170	951000	2	\N	f	\N
131	1751450095743	1751452153743	180000	2	\N	f	\N
120	1751224983373	1751227275373	1471000	2	\N	f	\N
132	1751350966162	1751354038162	1221000	1	\N	f	\N
133	1751358554602	1751361003602	1147000	1	\N	f	\N
82	1751618984113	1751623021113	207000	2	\N	f	\N
134	1751606738444	1751610078444	953000	2	\N	f	\N
135	1751536096952	1751538589952	2233000	1	\N	f	\N
136	1750744029943	1750746864943	1061000	1	\N	f	\N
137	1750782219328	1750785638328	491000	1	\N	f	\N
130	1751186009443	1751190656443	279000	2	\N	f	\N
138	1751115075807	1751119153807	1697000	2	\N	f	\N
139	1751352049964	1751356930964	2382000	2	\N	f	\N
127	1751380490874	1751384495839	1197000	2	\N	f	\N
140	1751563516084	1751567067084	188000	1	\N	f	\N
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

SELECT pg_catalog.setval('public.availability_id_seq', 60, true);


--
-- Name: booking_api_parameters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.booking_api_parameters_id_seq', 196, true);


--
-- Name: company_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.company_id_seq', 8, true);


--
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.event_id_seq', 392, true);


--
-- Name: journey_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.journey_id_seq', 1, false);


--
-- Name: request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.request_id_seq', 196, true);


--
-- Name: tour_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tour_id_seq', 140, true);


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

