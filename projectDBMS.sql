--
-- PostgreSQL database dump
--

-- Dumped from database version 12.10 (Ubuntu 12.10-1.pgdg20.04+1)
-- Dumped by pg_dump version 14.2 (Ubuntu 14.2-1.pgdg20.04+1)

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
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: book_checking(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.book_checking() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
	if exists (select * from users where user_id = new.user_id) then
		if exists (select * from train_runs where train_no = new.train_no and train_start = new.start_date) then 
			return new;
		else
			raise exception 'Given train does not exists';
		end if;
	else
		raise exception 'Not a valid user. Create account to continue booking';
	end if;
end;
$$;


ALTER FUNCTION public.book_checking() OWNER TO postgres;

--
-- Name: book_checks(character varying, integer, character, character varying, integer, integer, integer, date, integer, date, character varying, character, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.book_checks(pass_name character varying, pass_age integer, pass_gender character, pass_mobile character varying, userid integer, source integer, dest integer, doj date, trainno integer, trainstart date, coachtype character varying, accountno character, procedure_pay character varying)
    LANGUAGE plpgsql
    AS $$
begin
	if exists (select * from users where user_id = userid) then
		if exists (select * from train_runs where train_no = trainno and train_start = trainstart) then 
			call booking(pass_name,pass_age,pass_gender,pass_mobile, userid ,source ,dest,doj, trainno,trainstart, coachtype, accountno, procedure_pay);
		else
			raise notice 'Given train doesnot exists';
		end if;
	else
		raise notice 'Not a valid user. Create account to continue booking';
	end if;
end;
$$;


ALTER PROCEDURE public.book_checks(pass_name character varying, pass_age integer, pass_gender character, pass_mobile character varying, userid integer, source integer, dest integer, doj date, trainno integer, trainstart date, coachtype character varying, accountno character, procedure_pay character varying) OWNER TO postgres;

--
-- Name: booking(character varying, integer, character, character varying, integer, integer, integer, date, integer, date, character varying, character, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.booking(pass_name character varying, pass_age integer, pass_gender character, pass_mobile character varying, user_id integer, source integer, dest integer, doj date, trainno integer, trainstart date, coachtype character varying, accountno character, procedure_pay character varying)
    LANGUAGE plpgsql
    AS $$
Declare seat int;
Declare coach varchar(3);
declare pay_id uuid;
declare jour_fare numeric(10,5);	
declare newpass int;
declare curr_wl int;
Begin
	insert into passenger(name,age,gender,contact_no) values(pass_name, pass_age, pass_gender, pass_mobile);
	SELECT currval('passenger_passenger_id_seq') into newpass ;
	select * into pay_id from uuid_generate_v4();
	if exists (select * from seats_available(trainno, trainstart, coachtype, source,dest)) then
		Select * into seat, coach from seats_available(trainno, trainstart, coachtype, source,dest) limit 1;
		select * into jour_fare from compute_fare(trainno, trainstart, source, dest);
		insert into ticket_books(user_id, passenger_id, doj, source_stat, dest_stat, payment_id, status, wl_no, book_date, coach_no, seat_no, coach_type, train_no,start_date, fare) values (user_id, newpass,doj, source, dest, pay_id,'CN',null,now(),coach, seat, coachtype, trainno,trainstart, jour_fare);
		insert into payment values(pay_id, jour_fare, accountno, 'SBI',procedure_pay);
		commit;
	else
		select * into curr_wl from current_wl(trainno, trainstart, source, dest, coachtype);
		if (curr_wl < 3) then
			select * into jour_fare from compute_fare(trainno, trainstart, source, dest);
			insert into ticket_books(user_id, passenger_id, doj, source_stat, dest_stat, payment_id, status, wl_no, book_date, coach_no, seat_no, coach_type, train_no,start_date, fare) values (user_id, newpass, doj, source, dest, pay_id,'WL',curr_wl+1,now(), null, null, coachtype, trainno,trainstart, jour_fare);
			insert into payment values(pay_id, jour_fare, accountno, 'SBI',procedure_pay);
			commit;
		else
			raise notice 'Maximum WL Reached! Please try booking for other train';
			rollback;
		end if;
	end if;	
end;
$$;


ALTER PROCEDURE public.booking(pass_name character varying, pass_age integer, pass_gender character, pass_mobile character varying, user_id integer, source integer, dest integer, doj date, trainno integer, trainstart date, coachtype character varying, accountno character, procedure_pay character varying) OWNER TO postgres;

--
-- Name: cancel_ticket(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_ticket(pass_pnr integer)
    LANGUAGE plpgsql
    AS $$
	declare curr_pass_stat varchar(3);
	declare curr_trainno int;
	declare curr_trainstart date;
	declare curr_source int;
	declare curr_dest int;
	declare curr_coach varchar(3);
	declare promoted_pass int;
	declare seat int;
	declare coach varchar(3);
	declare wait int;
	declare passenger int;
begin
	select train_no, start_date, source_stat, dest_stat, coach_type, status, wl_no into curr_trainno, curr_trainstart, curr_source, curr_dest, curr_coach, curr_pass_stat, wait from ticket_books where pnr = pass_pnr;
	raise notice '%',wait;
	UPDATE ticket_books SET status = 'NC', wl_no = null, seat_no = null, coach_no = null WHERE pnr = pass_pnr;
	if (curr_pass_stat = 'CN') then
		select pass_id into promoted_pass from curr_wl_pass(curr_trainno, curr_trainstart, curr_source, curr_dest, curr_coach) where wait_no = 1;
		Select * into seat, coach from seats_available(trainno, trainstart, coachtype, source,dest) limit 1;
		update ticket_books set status = 'CN', wl_no = null, coach_no = coach, seat_no = seat where passenger_id = promoted_pass;
		for passenger in select pass_id from current_wl_pass(curr_trainno, curr_trainstart, curr_source, curr_dest, curr_coach)
		loop
			update ticket_books set wl_no = wl_no - 1 where passenger_id = passenger;
		end loop;
		commit;
	elsif (curr_pass_stat = 'WL') then
		for passenger in select pass_id from current_wl_pass(curr_trainno, curr_trainstart, curr_source, curr_dest, curr_coach)
		loop
			raise notice 'Hello';
			update ticket_books set wl_no = wl_no - 1 where passenger_id = passenger and wl_no > wait;
		end loop;
		commit;
	end if;
end;
$$;


ALTER PROCEDURE public.cancel_ticket(pass_pnr integer) OWNER TO postgres;

--
-- Name: check_pnr_stat(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_pnr_stat(given_pnr integer) RETURNS TABLE(pass_id integer, pass_status character)
    LANGUAGE plpgsql
    AS $$
begin
return query
select passenger_id, status from
ticket_books where pnr = given_pnr;
end;
$$;


ALTER FUNCTION public.check_pnr_stat(given_pnr integer) OWNER TO postgres;

--
-- Name: compute_fare(integer, date, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.compute_fare(trainno integer, trainstart date, source integer, dest integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare source_dist numeric(10,5);
declare dest_dist numeric(10,5);
declare fare_final numeric(10,5);
begin
	select * into source_dist from distance(trainno, trainstart, source);
	select * into dest_dist from distance(trainno, trainstart, dest);
	fare_final = (dest_dist - source_dist) * (select price_per_km/10 from train_runs where train_no = trainno and train_start = trainstart);
	raise notice 'hi';
	return fare_final;
end; 
$$;


ALTER FUNCTION public.compute_fare(trainno integer, trainstart date, source integer, dest integer) OWNER TO postgres;

--
-- Name: current_wl(integer, date, integer, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.current_wl(trainno integer, trainstart date, source integer, dest integer, coachtype character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare wl int;
begin
	select count(*) into wl from current_wl_pass(trainno, trainstart, source, dest, coachtype);
	return wl;
end;
$$;


ALTER FUNCTION public.current_wl(trainno integer, trainstart date, source integer, dest integer, coachtype character varying) OWNER TO postgres;

--
-- Name: current_wl_pass(integer, date, integer, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.current_wl_pass(trainno integer, trainstart date, source integer, dest integer, coachtype character varying) RETURNS TABLE(pass_id integer, wait_no integer)
    LANGUAGE plpgsql
    AS $$
begin
	return query 
	select passenger_id, wl_no from ticket_books where 
		distance(trainno,trainstart,dest_stat) > distance(trainno,trainstart,source) and train_no = trainno and start_date = trainstart and coach_type = coachtype and status = 'WL'
	union
	select passenger_id, wl_no from ticket_books where 
		distance(trainno,trainstart,source_stat) < distance(trainno,trainstart,dest) and train_no = trainno and start_date = trainstart and coach_type = coachtype and status = 'WL';
end;
$$;


ALTER FUNCTION public.current_wl_pass(trainno integer, trainstart date, source integer, dest integer, coachtype character varying) OWNER TO postgres;

--
-- Name: distance(integer, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.distance(train integer, start date, code integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
   dist numeric(10,5);
begin
   select dist_from_source
   into dist
   from stops
   where train_no = train and start_date = start and station_code = code;
   return dist;
end;
$$;


ALTER FUNCTION public.distance(train integer, start date, code integer) OWNER TO postgres;

--
-- Name: seats_available(integer, date, character varying, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seats_available(trainno integer, trainstart date, category character varying, source integer, dest integer) RETURNS TABLE(seat integer, coach character varying)
    LANGUAGE plpgsql
    AS $$
	Begin
		Return query 
		(Select seat_no, coach_no  from seats where coach_type = category and train_no = trainno and start_date = trainstart)

	Except all

	( (  select seat_no, coach_no from ticket_books where 
		distance(trainno,trainstart,dest_stat) > distance(trainno,trainstart,source) and train_no = trainno and start_date = trainstart and status = 'CN')

	union

	( select seat_no, coach_no from ticket_books where 
		distance(trainno,trainstart,source_stat) <= distance(trainno,trainstart,dest) and train_no = trainno and start_date = trainstart and status = 'CN') );
End;
$$;


ALTER FUNCTION public.seats_available(trainno integer, trainstart date, category character varying, source integer, dest integer) OWNER TO postgres;

--
-- Name: timetable(integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.timetable(train integer, date date) RETURNS TABLE(station integer, arrival timestamp without time zone, departure timestamp without time zone, distance numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
	SELECT
        station_code,
		arrival_time,
		dept_time,
		dist_from_source 
    FROM
        stops
    WHERE
        train_no = train and start_date = date
	ORDER BY
		dept_time;
END;
$$;


ALTER FUNCTION public.timetable(train integer, date date) OWNER TO postgres;

--
-- Name: train_stop_check(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.train_stop_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
	if exists(select * from stops where train_no = new.train_no and start_date = new.start_date and station_code = new.source_stat and arrival_time::date = new.doj) then
		if exists(select * from stops where train_no = new.train_no and start_date = new.start_date and station_code = new.dest_stat) then
			return new;
		else
			raise exception 'Train does not go to specified destination';
		end if;
	else
		raise exception 'Train does not pass through source specified';
	end if;
end;
$$;


ALTER FUNCTION public.train_stop_check() OWNER TO postgres;

--
-- Name: train_through_given_station(integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.train_through_given_station(code integer, doj date) RETURNS TABLE(train_number integer, trainname character varying, arrive timestamp without time zone, dept timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
	SELECT
        train_no, train_name, arrival_time, dept_time
	 FROM
        stops natural join train_type
    WHERE
    	station_code = code and (dept_time :: DATE) = doj;
END; $$;


ALTER FUNCTION public.train_through_given_station(code integer, doj date) OWNER TO postgres;

--
-- Name: trains_between_stats(integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trains_between_stats(source integer, dest integer, doj date) RETURNS TABLE(name_train character varying, train_code integer, arrival timestamp without time zone, dept timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
begin
return query
	select train_name, a.train_no,a.arrival_time,a.dept_time from stops a join
	stops p
	on a.train_no = p.train_no and
	a.start_date = p.start_date and
	a.station_code = source and p.station_code = dest and
	a.dist_from_source < p.dist_from_source and a.dept_time :: date = doj
	join train_runs on
	a.train_no = train_runs.train_no and a.start_date = train_runs.train_start join
	train_type on
	train_runs.train_no = train_type.train_no ;
END; 
$$;


ALTER FUNCTION public.trains_between_stats(source integer, dest integer, doj date) OWNER TO postgres;

--
-- Name: user_prevent(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_prevent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
	if (new.user_id != old.user_id) then
		raise exception 'User_id cannot be modified';
	else
		return new;
	end if;
end;
$$;


ALTER FUNCTION public.user_prevent() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: seats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.seats (
    coach_no character varying(5) NOT NULL,
    seat_no integer NOT NULL,
    train_no integer NOT NULL,
    start_date date NOT NULL,
    coach_type character varying(3) NOT NULL,
    CONSTRAINT seats_coach_type_check CHECK (((coach_type)::text = ANY ((ARRAY['SL'::character varying, '3A'::character varying, '2A'::character varying])::text[]))),
    CONSTRAINT seats_seat_no_check CHECK (((seat_no <= 5) AND (seat_no > 0)))
);


ALTER TABLE public.seats OWNER TO postgres;

--
-- Name: ac_2_coaches; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.ac_2_coaches AS
 SELECT DISTINCT ON (seats.train_no, seats.start_date, seats.coach_no) seats.train_no,
    seats.start_date,
    seats.coach_no
   FROM public.seats
  WHERE ((seats.coach_type)::text = '2A'::text);


ALTER TABLE public.ac_2_coaches OWNER TO postgres;

--
-- Name: ac_3_coaches; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.ac_3_coaches AS
 SELECT DISTINCT ON (seats.train_no, seats.start_date, seats.coach_no) seats.train_no,
    seats.start_date,
    seats.coach_no
   FROM public.seats
  WHERE ((seats.coach_type)::text = '3A'::text);


ALTER TABLE public.ac_3_coaches OWNER TO postgres;

--
-- Name: payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment (
    pay_id uuid NOT NULL,
    amount numeric(10,5) NOT NULL,
    account_no character(17) NOT NULL,
    bank character varying(100) NOT NULL,
    payment_procedure character varying(40) NOT NULL,
    CONSTRAINT payment_account_no_check CHECK ((account_no ~ similar_escape('[0-9A-Z]{17}'::text, NULL::text))),
    CONSTRAINT payment_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payment_check CHECK ((((bank)::text = 'SBI'::text) AND (((payment_procedure)::text = 'UPI'::text) OR ((payment_procedure)::text = 'debit card'::text) OR ((payment_procedure)::text = 'credit card'::text))))
);


ALTER TABLE public.payment OWNER TO postgres;

--
-- Name: credit_card_payments; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.credit_card_payments AS
 SELECT payment.pay_id,
    payment.amount,
    payment.account_no,
    payment.bank,
    payment.payment_procedure
   FROM public.payment
  WHERE ((payment.payment_procedure)::text = 'credit card'::text);


ALTER TABLE public.credit_card_payments OWNER TO postgres;

--
-- Name: debit_card_payments; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.debit_card_payments AS
 SELECT payment.pay_id,
    payment.amount,
    payment.account_no,
    payment.bank,
    payment.payment_procedure
   FROM public.payment
  WHERE ((payment.payment_procedure)::text = 'debit card'::text);


ALTER TABLE public.debit_card_payments OWNER TO postgres;

--
-- Name: passenger; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.passenger (
    passenger_id integer NOT NULL,
    name character varying(50) NOT NULL,
    age integer NOT NULL,
    gender character(1) NOT NULL,
    contact_no character(10) NOT NULL,
    CONSTRAINT passenger_age_check CHECK ((age > 0)),
    CONSTRAINT passenger_contact_no_check CHECK ((contact_no ~ similar_escape('\d{10}'::text, NULL::text))),
    CONSTRAINT passenger_gender_check CHECK ((gender = ANY (ARRAY['M'::bpchar, 'F'::bpchar])))
);


ALTER TABLE public.passenger OWNER TO postgres;

--
-- Name: passenger_passenger_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.passenger_passenger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.passenger_passenger_id_seq OWNER TO postgres;

--
-- Name: passenger_passenger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.passenger_passenger_id_seq OWNED BY public.passenger.passenger_id;


--
-- Name: sl_coaches; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.sl_coaches AS
 SELECT DISTINCT ON (seats.train_no, seats.start_date, seats.coach_no) seats.train_no,
    seats.start_date,
    seats.coach_no
   FROM public.seats
  WHERE ((seats.coach_type)::text = 'SL'::text);


ALTER TABLE public.sl_coaches OWNER TO postgres;

--
-- Name: station; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.station (
    station_code integer NOT NULL,
    name character varying(100) NOT NULL,
    area character varying(50) NOT NULL,
    city character varying(50) NOT NULL,
    district character varying(50) NOT NULL,
    state character varying(50) NOT NULL,
    platforms integer NOT NULL,
    pin_code character(6) NOT NULL,
    contact_no character(10) NOT NULL,
    CONSTRAINT station_contact_no_check CHECK ((contact_no ~ similar_escape('\d{10}'::text, NULL::text))),
    CONSTRAINT station_pin_code_check CHECK ((pin_code ~ similar_escape('\d{1,6}'::text, NULL::text))),
    CONSTRAINT station_platforms_check CHECK ((platforms > 0)),
    CONSTRAINT station_station_code_check CHECK ((station_code > 0))
);


ALTER TABLE public.station OWNER TO postgres;

--
-- Name: stops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stops (
    train_no integer NOT NULL,
    start_date date NOT NULL,
    station_code integer NOT NULL,
    arrival_time timestamp without time zone,
    dept_time timestamp without time zone,
    dist_from_source numeric(10,5) NOT NULL,
    CONSTRAINT stops_check CHECK ((arrival_time > start_date)),
    CONSTRAINT stops_check1 CHECK ((dept_time > arrival_time)),
    CONSTRAINT stops_dist_from_source_check CHECK ((dist_from_source >= (0)::numeric))
);


ALTER TABLE public.stops OWNER TO postgres;

--
-- Name: ticket_books; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ticket_books (
    user_id integer NOT NULL,
    passenger_id integer NOT NULL,
    pnr integer NOT NULL,
    doj date NOT NULL,
    source_stat integer NOT NULL,
    dest_stat integer NOT NULL,
    payment_id uuid NOT NULL,
    status character(2) NOT NULL,
    wl_no integer,
    book_date timestamp without time zone NOT NULL,
    coach_no character varying(5),
    seat_no integer,
    coach_type character varying(3) NOT NULL,
    train_no integer NOT NULL,
    start_date date NOT NULL,
    fare numeric(10,5) NOT NULL,
    CONSTRAINT ticket_books_coach_type_check CHECK (((coach_type)::text = ANY ((ARRAY['SL'::character varying, '3A'::character varying, '2A'::character varying])::text[]))),
    CONSTRAINT ticket_books_status_check CHECK ((status = ANY (ARRAY['CN'::bpchar, 'NC'::bpchar, 'WL'::bpchar]))),
    CONSTRAINT ticket_books_wl_no_check CHECK (((wl_no <= 3) AND (wl_no > 0)))
);


ALTER TABLE public.ticket_books OWNER TO postgres;

--
-- Name: ticket_books_pnr_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ticket_books_pnr_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.ticket_books_pnr_seq OWNER TO postgres;

--
-- Name: ticket_books_pnr_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ticket_books_pnr_seq OWNED BY public.ticket_books.pnr;


--
-- Name: train_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.train_runs (
    train_no integer NOT NULL,
    train_start date NOT NULL,
    price_per_km numeric(5,3) NOT NULL,
    current_delay time without time zone NOT NULL,
    CONSTRAINT train_runs_price_per_km_check CHECK ((price_per_km > (0)::numeric))
);


ALTER TABLE public.train_runs OWNER TO postgres;

--
-- Name: train_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.train_type (
    train_no integer NOT NULL,
    train_type character varying(20) NOT NULL,
    train_name character varying(20) NOT NULL,
    CONSTRAINT train_type_train_no_check CHECK ((train_no > 0)),
    CONSTRAINT train_type_train_type_check CHECK (((train_type)::text = ANY ((ARRAY['SF'::character varying, 'EXP'::character varying, 'PASS'::character varying])::text[])))
);


ALTER TABLE public.train_type OWNER TO postgres;

--
-- Name: upi_payments; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.upi_payments AS
 SELECT payment.pay_id,
    payment.amount,
    payment.account_no,
    payment.bank,
    payment.payment_procedure
   FROM public.payment
  WHERE ((payment.payment_procedure)::text = 'UPI'::text);


ALTER TABLE public.upi_payments OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    name character varying(100) NOT NULL,
    age integer NOT NULL,
    gender character(1) NOT NULL,
    email_id character varying(200) NOT NULL,
    contact_no character(10) NOT NULL,
    password character varying(100) NOT NULL,
    identity_no character(12) NOT NULL,
    CONSTRAINT users_age_check CHECK ((age > 0)),
    CONSTRAINT users_contact_no_check CHECK ((contact_no ~ similar_escape('\d{10}'::text, NULL::text))),
    CONSTRAINT users_gender_check CHECK ((gender = ANY (ARRAY['M'::bpchar, 'F'::bpchar]))),
    CONSTRAINT users_identity_no_check CHECK ((identity_no ~ similar_escape('\d{12}'::text, NULL::text)))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_user_id_seq OWNER TO postgres;

--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: passenger passenger_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.passenger ALTER COLUMN passenger_id SET DEFAULT nextval('public.passenger_passenger_id_seq'::regclass);


--
-- Name: ticket_books pnr; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books ALTER COLUMN pnr SET DEFAULT nextval('public.ticket_books_pnr_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Data for Name: passenger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.passenger (passenger_id, name, age, gender, contact_no) FROM stdin;
1	John Smith	18	M	8798319833
2	Penelope Decker	45	F	8472309857
3	Alice Judy	6	F	8374928347
4	Mary James	36	F	9328475275
5	Gary Frank	32	M	9845293824
6	Mitchel Johnson	23	M	9872346502
7	Olivia Hughes	14	F	7187562374
8	Bobbi David	56	M	8485729825
9	John Kennedy	39	M	7923845295
10	Lily Kate	24	F	9938457918
11	Penny Diaz	9	F	8734295097
12	Erik Johnson	51	M	9923485789
13	Randy Gilmore	68	M	7398452757
14	Cliff Jones	7	M	8587239477
15	Ira Sawyer	50	F	9394857273
16	Jennifer Tyler	20	F	7394857295
17	Betsy Smith	19	F	9934872983
18	Martin Ackerman	62	M	7239487298
19	Glenn Menard	18	M	8279458772
20	Mary Elizabeth	70	F	7948572984
21	Stefen Salvatore	17	M	8897966530
22	Damon Salvatore	23	M	6573456548
23	Caroline Forbes	24	F	9330996666
24	Elena Gilbert	45	F	8989675687
25	Bonnie Bennet	26	F	7561120000
46	Yagnesh	21	M	9908183474
57	Yagnesh	21	M	9908183474
58	Yagnesh	21	M	9908183474
59	Yagnesh	21	M	9908183474
60	Yagnesh	21	M	9908183474
61	Yagnesh	21	M	9908183474
63	Charan	20	M	6301722155
\.


--
-- Data for Name: payment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payment (pay_id, amount, account_no, bank, payment_procedure) FROM stdin;
568e39eb-3e00-48fe-a931-0e232de26151	277.23850	132435924242SEPA2	SBI	UPI
85c02453-1d09-41c4-a031-e569fdf19a24	340.19125	63728464783420845	SBI	debit card
a1676059-7b56-4e73-9ea1-bed0ea743965	340.00000	34548455798245834	SBI	credit card
4d438d88-64a5-4b45-aa00-02f9f407939f	510.00000	55401268395738937	SBI	credit card
cce1f157-37b6-491b-934a-dbb96f10ec41	1530.00000	87365289397824576	SBI	credit card
4c567d9e-7e74-4ab2-b265-4530a5659fd0	6272.92600	12874589210098675	SBI	UPI
413c2000-501d-4271-acf7-7f6f4d3aedcb	6272.92600	94639723075894645	SBI	debit card
583dc45d-7100-478f-a0b0-b4152bf6dd56	1100.19000	85674787539734563	SBI	UPI
fbb86291-51b0-4877-8ea5-d8a1dfcc4572	1142.89875	45728496201907034	SBI	debit card
8f07a90c-cd6b-420f-bff8-c3a6b4ffdc8c	1610.15750	32806059245670534	SBI	credit card
b27615a5-cd62-4984-8805-dc3ceea70053	1610.15750	59000278091484567	SBI	debit card
87b0b542-1db6-4edb-a951-99fc8e4bdcc0	1254.58520	132435924242SEPA2	SBI	UPI
fc0eb0cf-2a96-4ece-b5c0-f06c3e24c29c	1254.58520	132435924242SEPA2	SBI	UPI
fba12075-2f6f-42db-94c7-1c087bf9d425	1254.58520	132435924242SEPA2	SBI	UPI
63ad15e9-e48a-404b-a140-e27f39d92ad2	1254.58520	132435924242SEPA2	SBI	UPI
ef88c8bd-989e-43de-a7ee-7fb37583eef5	1254.58520	132435924242SEPA2	SBI	UPI
8ea8b839-52a0-4946-993b-ccc45965fd61	275.04750	132435924242SEPA2	SBI	UPI
\.


--
-- Data for Name: seats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.seats (coach_no, seat_no, train_no, start_date, coach_type) FROM stdin;
S1	1	17326	2022-03-12	SL
S1	2	17326	2022-03-12	SL
S1	3	17326	2022-03-12	SL
S1	4	17326	2022-03-12	SL
S1	5	17326	2022-03-12	SL
S2	1	17326	2022-03-12	SL
S2	2	17326	2022-03-12	SL
S2	3	17326	2022-03-12	SL
S2	4	17326	2022-03-12	SL
S2	5	17326	2022-03-12	SL
D1	1	17326	2022-03-12	3A
D1	2	17326	2022-03-12	3A
D1	3	17326	2022-03-12	3A
D1	4	17326	2022-03-12	3A
D1	5	17326	2022-03-12	3A
A1	1	17326	2022-03-12	2A
A1	2	17326	2022-03-12	2A
A1	3	17326	2022-03-12	2A
A1	4	17326	2022-03-12	2A
A1	5	17326	2022-03-12	2A
S1	1	17326	2022-03-13	SL
S1	2	17326	2022-03-13	SL
S1	3	17326	2022-03-13	SL
S1	4	17326	2022-03-13	SL
S1	5	17326	2022-03-13	SL
S2	1	17326	2022-03-13	SL
S2	2	17326	2022-03-13	SL
S2	3	17326	2022-03-13	SL
S2	4	17326	2022-03-13	SL
S2	5	17326	2022-03-13	SL
D1	1	17326	2022-03-13	3A
D1	2	17326	2022-03-13	3A
D1	3	17326	2022-03-13	3A
D1	4	17326	2022-03-13	3A
D1	5	17326	2022-03-13	3A
A1	1	17326	2022-03-13	2A
A1	2	17326	2022-03-13	2A
A1	3	17326	2022-03-13	2A
A1	4	17326	2022-03-13	2A
A1	5	17326	2022-03-13	2A
S1	1	17326	2022-03-14	SL
S1	2	17326	2022-03-14	SL
S1	3	17326	2022-03-14	SL
S1	4	17326	2022-03-14	SL
S1	5	17326	2022-03-14	SL
S2	1	17326	2022-03-14	SL
S2	2	17326	2022-03-14	SL
S2	3	17326	2022-03-14	SL
S2	4	17326	2022-03-14	SL
S2	5	17326	2022-03-14	SL
D1	1	17326	2022-03-14	3A
D1	2	17326	2022-03-14	3A
D1	3	17326	2022-03-14	3A
D1	4	17326	2022-03-14	3A
D1	5	17326	2022-03-14	3A
A1	1	17326	2022-03-14	2A
A1	2	17326	2022-03-14	2A
A1	3	17326	2022-03-14	2A
A1	4	17326	2022-03-14	2A
A1	5	17326	2022-03-14	2A
S1	1	17326	2022-03-15	SL
S1	2	17326	2022-03-15	SL
S1	3	17326	2022-03-15	SL
S1	4	17326	2022-03-15	SL
S1	5	17326	2022-03-15	SL
S2	1	17326	2022-03-15	SL
S2	2	17326	2022-03-15	SL
S2	3	17326	2022-03-15	SL
S2	4	17326	2022-03-15	SL
S2	5	17326	2022-03-15	SL
D1	1	17326	2022-03-15	3A
D1	2	17326	2022-03-15	3A
D1	3	17326	2022-03-15	3A
D1	4	17326	2022-03-15	3A
D1	5	17326	2022-03-15	3A
A1	1	17326	2022-03-15	2A
A1	2	17326	2022-03-15	2A
A1	3	17326	2022-03-15	2A
A1	4	17326	2022-03-15	2A
A1	5	17326	2022-03-15	2A
S1	1	17326	2022-03-16	SL
S1	2	17326	2022-03-16	SL
S1	3	17326	2022-03-16	SL
S1	4	17326	2022-03-16	SL
S1	5	17326	2022-03-16	SL
S2	1	17326	2022-03-16	SL
S2	2	17326	2022-03-16	SL
S2	3	17326	2022-03-16	SL
S2	4	17326	2022-03-16	SL
S2	5	17326	2022-03-16	SL
D1	1	17326	2022-03-16	3A
D1	2	17326	2022-03-16	3A
D1	3	17326	2022-03-16	3A
D1	4	17326	2022-03-16	3A
D1	5	17326	2022-03-16	3A
A1	1	17326	2022-03-16	2A
A1	2	17326	2022-03-16	2A
A1	3	17326	2022-03-16	2A
A1	4	17326	2022-03-16	2A
A1	5	17326	2022-03-16	2A
S1	1	17326	2022-03-17	SL
S1	2	17326	2022-03-17	SL
S1	3	17326	2022-03-17	SL
S1	4	17326	2022-03-17	SL
S1	5	17326	2022-03-17	SL
S2	1	17326	2022-03-17	SL
S2	2	17326	2022-03-17	SL
S2	3	17326	2022-03-17	SL
S2	4	17326	2022-03-17	SL
S2	5	17326	2022-03-17	SL
D1	1	17326	2022-03-17	3A
D1	2	17326	2022-03-17	3A
D1	3	17326	2022-03-17	3A
D1	4	17326	2022-03-17	3A
D1	5	17326	2022-03-17	3A
A1	1	17326	2022-03-17	2A
A1	2	17326	2022-03-17	2A
A1	3	17326	2022-03-17	2A
A1	4	17326	2022-03-17	2A
A1	5	17326	2022-03-17	2A
S1	1	17326	2022-03-18	SL
S1	2	17326	2022-03-18	SL
S1	3	17326	2022-03-18	SL
S1	4	17326	2022-03-18	SL
S1	5	17326	2022-03-18	SL
S2	1	17326	2022-03-18	SL
S2	2	17326	2022-03-18	SL
S2	3	17326	2022-03-18	SL
S2	4	17326	2022-03-18	SL
S2	5	17326	2022-03-18	SL
D1	1	17326	2022-03-18	3A
D1	2	17326	2022-03-18	3A
D1	3	17326	2022-03-18	3A
D1	4	17326	2022-03-18	3A
D1	5	17326	2022-03-18	3A
A1	1	17326	2022-03-18	2A
A1	2	17326	2022-03-18	2A
A1	3	17326	2022-03-18	2A
A1	4	17326	2022-03-18	2A
A1	5	17326	2022-03-18	2A
S1	1	17327	2022-03-12	SL
S1	2	17327	2022-03-12	SL
S1	3	17327	2022-03-12	SL
S1	4	17327	2022-03-12	SL
S1	5	17327	2022-03-12	SL
S2	1	17327	2022-03-12	SL
S2	2	17327	2022-03-12	SL
S2	3	17327	2022-03-12	SL
S2	4	17327	2022-03-12	SL
S2	5	17327	2022-03-12	SL
D1	1	17327	2022-03-12	3A
D1	2	17327	2022-03-12	3A
D1	3	17327	2022-03-12	3A
D1	4	17327	2022-03-12	3A
D1	5	17327	2022-03-12	3A
A1	1	17327	2022-03-12	2A
A1	2	17327	2022-03-12	2A
A1	3	17327	2022-03-12	2A
A1	4	17327	2022-03-12	2A
A1	5	17327	2022-03-12	2A
S1	1	17327	2022-03-13	SL
S1	2	17327	2022-03-13	SL
S1	3	17327	2022-03-13	SL
S1	4	17327	2022-03-13	SL
S1	5	17327	2022-03-13	SL
S2	1	17327	2022-03-13	SL
S2	2	17327	2022-03-13	SL
S2	3	17327	2022-03-13	SL
S2	4	17327	2022-03-13	SL
S2	5	17327	2022-03-13	SL
D1	1	17327	2022-03-13	3A
D1	2	17327	2022-03-13	3A
D1	3	17327	2022-03-13	3A
D1	4	17327	2022-03-13	3A
D1	5	17327	2022-03-13	3A
A1	1	17327	2022-03-13	2A
A1	2	17327	2022-03-13	2A
A1	3	17327	2022-03-13	2A
A1	4	17327	2022-03-13	2A
A1	5	17327	2022-03-13	2A
S1	1	17327	2022-03-14	SL
S1	2	17327	2022-03-14	SL
S1	3	17327	2022-03-14	SL
S1	4	17327	2022-03-14	SL
S1	5	17327	2022-03-14	SL
S2	1	17327	2022-03-14	SL
S2	2	17327	2022-03-14	SL
S2	3	17327	2022-03-14	SL
S2	4	17327	2022-03-14	SL
S2	5	17327	2022-03-14	SL
D1	1	17327	2022-03-14	3A
D1	2	17327	2022-03-14	3A
D1	3	17327	2022-03-14	3A
D1	4	17327	2022-03-14	3A
D1	5	17327	2022-03-14	3A
A1	1	17327	2022-03-14	2A
A1	2	17327	2022-03-14	2A
A1	3	17327	2022-03-14	2A
A1	4	17327	2022-03-14	2A
A1	5	17327	2022-03-14	2A
S1	1	17327	2022-03-15	SL
S1	2	17327	2022-03-15	SL
S1	3	17327	2022-03-15	SL
S1	4	17327	2022-03-15	SL
S1	5	17327	2022-03-15	SL
S2	1	17327	2022-03-15	SL
S2	2	17327	2022-03-15	SL
S2	3	17327	2022-03-15	SL
S2	4	17327	2022-03-15	SL
S2	5	17327	2022-03-15	SL
D1	1	17327	2022-03-15	3A
D1	2	17327	2022-03-15	3A
D1	3	17327	2022-03-15	3A
D1	4	17327	2022-03-15	3A
D1	5	17327	2022-03-15	3A
A1	1	17327	2022-03-15	2A
A1	2	17327	2022-03-15	2A
A1	3	17327	2022-03-15	2A
A1	4	17327	2022-03-15	2A
A1	5	17327	2022-03-15	2A
S1	1	17327	2022-03-16	SL
S1	2	17327	2022-03-16	SL
S1	3	17327	2022-03-16	SL
S1	4	17327	2022-03-16	SL
S1	5	17327	2022-03-16	SL
S2	1	17327	2022-03-16	SL
S2	2	17327	2022-03-16	SL
S2	3	17327	2022-03-16	SL
S2	4	17327	2022-03-16	SL
S2	5	17327	2022-03-16	SL
D1	1	17327	2022-03-16	3A
D1	2	17327	2022-03-16	3A
D1	3	17327	2022-03-16	3A
D1	4	17327	2022-03-16	3A
D1	5	17327	2022-03-16	3A
A1	1	17327	2022-03-16	2A
A1	2	17327	2022-03-16	2A
A1	3	17327	2022-03-16	2A
A1	4	17327	2022-03-16	2A
A1	5	17327	2022-03-16	2A
S1	1	17327	2022-03-17	SL
S1	2	17327	2022-03-17	SL
S1	3	17327	2022-03-17	SL
S1	4	17327	2022-03-17	SL
S1	5	17327	2022-03-17	SL
S2	1	17327	2022-03-17	SL
S2	2	17327	2022-03-17	SL
S2	3	17327	2022-03-17	SL
S2	4	17327	2022-03-17	SL
S2	5	17327	2022-03-17	SL
D1	1	17327	2022-03-17	3A
D1	2	17327	2022-03-17	3A
D1	3	17327	2022-03-17	3A
D1	4	17327	2022-03-17	3A
D1	5	17327	2022-03-17	3A
A1	1	17327	2022-03-17	2A
A1	2	17327	2022-03-17	2A
A1	3	17327	2022-03-17	2A
A1	4	17327	2022-03-17	2A
A1	5	17327	2022-03-17	2A
S1	1	17327	2022-03-18	SL
S1	2	17327	2022-03-18	SL
S1	3	17327	2022-03-18	SL
S1	4	17327	2022-03-18	SL
S1	5	17327	2022-03-18	SL
S2	1	17327	2022-03-18	SL
S2	2	17327	2022-03-18	SL
S2	3	17327	2022-03-18	SL
S2	4	17327	2022-03-18	SL
S2	5	17327	2022-03-18	SL
D1	1	17327	2022-03-18	3A
D1	2	17327	2022-03-18	3A
D1	3	17327	2022-03-18	3A
D1	4	17327	2022-03-18	3A
D1	5	17327	2022-03-18	3A
A1	1	17327	2022-03-18	2A
A1	2	17327	2022-03-18	2A
A1	3	17327	2022-03-18	2A
A1	4	17327	2022-03-18	2A
A1	5	17327	2022-03-18	2A
S1	1	15231	2022-03-16	SL
S1	2	15231	2022-03-16	SL
S1	3	15231	2022-03-16	SL
S1	4	15231	2022-03-16	SL
S1	5	15231	2022-03-16	SL
S2	1	15231	2022-03-16	SL
S2	2	15231	2022-03-16	SL
S2	3	15231	2022-03-16	SL
S2	4	15231	2022-03-16	SL
S2	5	15231	2022-03-16	SL
D1	1	15231	2022-03-16	3A
D1	2	15231	2022-03-16	3A
D1	3	15231	2022-03-16	3A
D1	4	15231	2022-03-16	3A
D1	5	15231	2022-03-16	3A
B1	1	15231	2022-03-16	2A
B1	2	15231	2022-03-16	2A
B1	3	15231	2022-03-16	2A
B1	4	15231	2022-03-16	2A
B1	5	15231	2022-03-16	2A
S1	1	15232	2022-03-18	SL
S1	2	15232	2022-03-18	SL
S1	3	15232	2022-03-18	SL
S1	4	15232	2022-03-18	SL
S1	5	15232	2022-03-18	SL
S2	1	15232	2022-03-18	SL
S2	2	15232	2022-03-18	SL
S2	3	15232	2022-03-18	SL
S2	4	15232	2022-03-18	SL
S2	5	15232	2022-03-18	SL
D1	1	15232	2022-03-18	3A
D1	2	15232	2022-03-18	3A
D1	3	15232	2022-03-18	3A
D1	4	15232	2022-03-18	3A
D1	5	15232	2022-03-18	3A
B1	1	15232	2022-03-18	2A
B1	2	15232	2022-03-18	2A
B1	3	15232	2022-03-18	2A
B1	4	15232	2022-03-18	2A
B1	5	15232	2022-03-18	2A
S1	1	16846	2022-03-12	SL
S1	2	16846	2022-03-12	SL
S1	3	16846	2022-03-12	SL
S1	4	16846	2022-03-12	SL
S1	5	16846	2022-03-12	SL
S2	1	16846	2022-03-12	SL
S2	2	16846	2022-03-12	SL
S2	3	16846	2022-03-12	SL
S2	4	16846	2022-03-12	SL
S2	5	16846	2022-03-12	SL
B1	1	16846	2022-03-12	3A
B1	2	16846	2022-03-12	3A
B1	3	16846	2022-03-12	3A
B1	4	16846	2022-03-12	3A
B1	5	16846	2022-03-12	3A
A1	1	16846	2022-03-12	2A
A1	2	16846	2022-03-12	2A
A1	3	16846	2022-03-12	2A
A1	4	16846	2022-03-12	2A
A1	5	16846	2022-03-12	2A
S1	1	16846	2022-03-13	SL
S1	2	16846	2022-03-13	SL
S1	3	16846	2022-03-13	SL
S1	4	16846	2022-03-13	SL
S1	5	16846	2022-03-13	SL
S2	1	16846	2022-03-13	SL
S2	2	16846	2022-03-13	SL
S2	3	16846	2022-03-13	SL
S2	4	16846	2022-03-13	SL
S2	5	16846	2022-03-13	SL
B1	1	16846	2022-03-13	3A
B1	2	16846	2022-03-13	3A
B1	3	16846	2022-03-13	3A
B1	4	16846	2022-03-13	3A
B1	5	16846	2022-03-13	3A
A1	1	16846	2022-03-13	2A
A1	2	16846	2022-03-13	2A
A1	3	16846	2022-03-13	2A
A1	4	16846	2022-03-13	2A
A1	5	16846	2022-03-13	2A
S1	1	16846	2022-03-14	SL
S1	2	16846	2022-03-14	SL
S1	3	16846	2022-03-14	SL
S1	4	16846	2022-03-14	SL
S1	5	16846	2022-03-14	SL
S2	1	16846	2022-03-14	SL
S2	2	16846	2022-03-14	SL
S2	3	16846	2022-03-14	SL
S2	4	16846	2022-03-14	SL
S2	5	16846	2022-03-14	SL
B1	1	16846	2022-03-14	3A
B1	2	16846	2022-03-14	3A
B1	3	16846	2022-03-14	3A
B1	4	16846	2022-03-14	3A
B1	5	16846	2022-03-14	3A
A1	1	16846	2022-03-14	2A
A1	2	16846	2022-03-14	2A
A1	3	16846	2022-03-14	2A
A1	4	16846	2022-03-14	2A
A1	5	16846	2022-03-14	2A
S1	1	16846	2022-03-15	SL
S1	2	16846	2022-03-15	SL
S1	3	16846	2022-03-15	SL
S1	4	16846	2022-03-15	SL
S1	5	16846	2022-03-15	SL
S2	1	16846	2022-03-15	SL
S2	2	16846	2022-03-15	SL
S2	3	16846	2022-03-15	SL
S2	4	16846	2022-03-15	SL
S2	5	16846	2022-03-15	SL
B1	1	16846	2022-03-15	3A
B1	2	16846	2022-03-15	3A
B1	3	16846	2022-03-15	3A
B1	4	16846	2022-03-15	3A
B1	5	16846	2022-03-15	3A
A1	1	16846	2022-03-15	2A
A1	2	16846	2022-03-15	2A
A1	3	16846	2022-03-15	2A
A1	4	16846	2022-03-15	2A
A1	5	16846	2022-03-15	2A
S1	1	16846	2022-03-16	SL
S1	2	16846	2022-03-16	SL
S1	3	16846	2022-03-16	SL
S1	4	16846	2022-03-16	SL
S1	5	16846	2022-03-16	SL
S2	1	16846	2022-03-16	SL
S2	2	16846	2022-03-16	SL
S2	3	16846	2022-03-16	SL
S2	4	16846	2022-03-16	SL
S2	5	16846	2022-03-16	SL
B1	1	16846	2022-03-16	3A
B1	2	16846	2022-03-16	3A
B1	3	16846	2022-03-16	3A
B1	4	16846	2022-03-16	3A
B1	5	16846	2022-03-16	3A
A1	1	16846	2022-03-16	2A
A1	2	16846	2022-03-16	2A
A1	3	16846	2022-03-16	2A
A1	4	16846	2022-03-16	2A
A1	5	16846	2022-03-16	2A
S1	1	16846	2022-03-17	SL
S1	2	16846	2022-03-17	SL
S1	3	16846	2022-03-17	SL
S1	4	16846	2022-03-17	SL
S1	5	16846	2022-03-17	SL
S2	1	16846	2022-03-17	SL
S2	2	16846	2022-03-17	SL
S2	3	16846	2022-03-17	SL
S2	4	16846	2022-03-17	SL
S2	5	16846	2022-03-17	SL
B1	1	16846	2022-03-17	3A
B1	2	16846	2022-03-17	3A
B1	3	16846	2022-03-17	3A
B1	4	16846	2022-03-17	3A
B1	5	16846	2022-03-17	3A
A1	1	16846	2022-03-17	2A
A1	2	16846	2022-03-17	2A
A1	3	16846	2022-03-17	2A
A1	4	16846	2022-03-17	2A
A1	5	16846	2022-03-17	2A
S1	1	16846	2022-03-18	SL
S1	2	16846	2022-03-18	SL
S1	3	16846	2022-03-18	SL
S1	4	16846	2022-03-18	SL
S1	5	16846	2022-03-18	SL
S2	1	16846	2022-03-18	SL
S2	2	16846	2022-03-18	SL
S2	3	16846	2022-03-18	SL
S2	4	16846	2022-03-18	SL
S2	5	16846	2022-03-18	SL
B1	1	16846	2022-03-18	3A
B1	2	16846	2022-03-18	3A
B1	3	16846	2022-03-18	3A
B1	4	16846	2022-03-18	3A
B1	5	16846	2022-03-18	3A
A1	1	16846	2022-03-18	2A
A1	2	16846	2022-03-18	2A
A1	3	16846	2022-03-18	2A
A1	4	16846	2022-03-18	2A
A1	5	16846	2022-03-18	2A
S1	1	16845	2022-03-12	SL
S1	2	16845	2022-03-12	SL
S1	3	16845	2022-03-12	SL
S1	4	16845	2022-03-12	SL
S1	5	16845	2022-03-12	SL
S2	1	16845	2022-03-12	SL
S2	2	16845	2022-03-12	SL
S2	3	16845	2022-03-12	SL
S2	4	16845	2022-03-12	SL
S2	5	16845	2022-03-12	SL
B1	1	16845	2022-03-12	3A
B1	2	16845	2022-03-12	3A
B1	3	16845	2022-03-12	3A
B1	4	16845	2022-03-12	3A
B1	5	16845	2022-03-12	3A
A1	1	16845	2022-03-12	2A
A1	2	16845	2022-03-12	2A
A1	3	16845	2022-03-12	2A
A1	4	16845	2022-03-12	2A
A1	5	16845	2022-03-12	2A
S1	1	16845	2022-03-13	SL
S1	2	16845	2022-03-13	SL
S1	3	16845	2022-03-13	SL
S1	4	16845	2022-03-13	SL
S1	5	16845	2022-03-13	SL
S2	1	16845	2022-03-13	SL
S2	2	16845	2022-03-13	SL
S2	3	16845	2022-03-13	SL
S2	4	16845	2022-03-13	SL
S2	5	16845	2022-03-13	SL
B1	1	16845	2022-03-13	3A
B1	2	16845	2022-03-13	3A
B1	3	16845	2022-03-13	3A
B1	4	16845	2022-03-13	3A
B1	5	16845	2022-03-13	3A
A1	1	16845	2022-03-13	2A
A1	2	16845	2022-03-13	2A
A1	3	16845	2022-03-13	2A
A1	4	16845	2022-03-13	2A
A1	5	16845	2022-03-13	2A
S1	1	16845	2022-03-14	SL
S1	2	16845	2022-03-14	SL
S1	3	16845	2022-03-14	SL
S1	4	16845	2022-03-14	SL
S1	5	16845	2022-03-14	SL
S2	1	16845	2022-03-14	SL
S2	2	16845	2022-03-14	SL
S2	3	16845	2022-03-14	SL
S2	4	16845	2022-03-14	SL
S2	5	16845	2022-03-14	SL
B1	1	16845	2022-03-14	3A
B1	2	16845	2022-03-14	3A
B1	3	16845	2022-03-14	3A
B1	4	16845	2022-03-14	3A
B1	5	16845	2022-03-14	3A
A1	1	16845	2022-03-14	2A
A1	2	16845	2022-03-14	2A
A1	3	16845	2022-03-14	2A
A1	4	16845	2022-03-14	2A
A1	5	16845	2022-03-14	2A
S1	1	16845	2022-03-15	SL
S1	2	16845	2022-03-15	SL
S1	3	16845	2022-03-15	SL
S1	4	16845	2022-03-15	SL
S1	5	16845	2022-03-15	SL
S2	1	16845	2022-03-15	SL
S2	2	16845	2022-03-15	SL
S2	3	16845	2022-03-15	SL
S2	4	16845	2022-03-15	SL
S2	5	16845	2022-03-15	SL
B1	1	16845	2022-03-15	3A
B1	2	16845	2022-03-15	3A
B1	3	16845	2022-03-15	3A
B1	4	16845	2022-03-15	3A
B1	5	16845	2022-03-15	3A
A1	1	16845	2022-03-15	2A
A1	2	16845	2022-03-15	2A
A1	3	16845	2022-03-15	2A
A1	4	16845	2022-03-15	2A
A1	5	16845	2022-03-15	2A
S1	1	16845	2022-03-16	SL
S1	2	16845	2022-03-16	SL
S1	3	16845	2022-03-16	SL
S1	4	16845	2022-03-16	SL
S1	5	16845	2022-03-16	SL
S2	1	16845	2022-03-16	SL
S2	2	16845	2022-03-16	SL
S2	3	16845	2022-03-16	SL
S2	4	16845	2022-03-16	SL
S2	5	16845	2022-03-16	SL
B1	1	16845	2022-03-16	3A
B1	2	16845	2022-03-16	3A
B1	3	16845	2022-03-16	3A
B1	4	16845	2022-03-16	3A
B1	5	16845	2022-03-16	3A
A1	1	16845	2022-03-16	2A
A1	2	16845	2022-03-16	2A
A1	3	16845	2022-03-16	2A
A1	4	16845	2022-03-16	2A
A1	5	16845	2022-03-16	2A
S1	1	16845	2022-03-17	SL
S1	2	16845	2022-03-17	SL
S1	3	16845	2022-03-17	SL
S1	4	16845	2022-03-17	SL
S1	5	16845	2022-03-17	SL
S2	1	16845	2022-03-17	SL
S2	2	16845	2022-03-17	SL
S2	3	16845	2022-03-17	SL
S2	4	16845	2022-03-17	SL
S2	5	16845	2022-03-17	SL
B1	1	16845	2022-03-17	3A
B1	2	16845	2022-03-17	3A
B1	3	16845	2022-03-17	3A
B1	4	16845	2022-03-17	3A
B1	5	16845	2022-03-17	3A
A1	1	16845	2022-03-17	2A
A1	2	16845	2022-03-17	2A
A1	3	16845	2022-03-17	2A
A1	4	16845	2022-03-17	2A
A1	5	16845	2022-03-17	2A
S1	1	16845	2022-03-18	SL
S1	2	16845	2022-03-18	SL
S1	3	16845	2022-03-18	SL
S1	4	16845	2022-03-18	SL
S1	5	16845	2022-03-18	SL
S2	1	16845	2022-03-18	SL
S2	2	16845	2022-03-18	SL
S2	3	16845	2022-03-18	SL
S2	4	16845	2022-03-18	SL
S2	5	16845	2022-03-18	SL
B1	1	16845	2022-03-18	3A
B1	2	16845	2022-03-18	3A
B1	3	16845	2022-03-18	3A
B1	4	16845	2022-03-18	3A
B1	5	16845	2022-03-18	3A
A1	1	16845	2022-03-18	2A
A1	2	16845	2022-03-18	2A
A1	3	16845	2022-03-18	2A
A1	4	16845	2022-03-18	2A
A1	5	16845	2022-03-18	2A
S1	1	19753	2022-03-14	SL
S1	2	19753	2022-03-14	SL
S1	3	19753	2022-03-14	SL
S1	4	19753	2022-03-14	SL
S1	5	19753	2022-03-14	SL
S2	1	19753	2022-03-14	SL
S2	2	19753	2022-03-14	SL
S2	3	19753	2022-03-14	SL
S2	4	19753	2022-03-14	SL
S2	5	19753	2022-03-14	SL
B1	1	19753	2022-03-14	3A
B1	2	19753	2022-03-14	3A
B1	3	19753	2022-03-14	3A
B1	4	19753	2022-03-14	3A
B1	5	19753	2022-03-14	3A
A1	1	19753	2022-03-14	2A
A1	2	19753	2022-03-14	2A
A1	3	19753	2022-03-14	2A
A1	4	19753	2022-03-14	2A
A1	5	19753	2022-03-14	2A
S1	1	19753	2022-03-16	SL
S1	2	19753	2022-03-16	SL
S1	3	19753	2022-03-16	SL
S1	4	19753	2022-03-16	SL
S1	5	19753	2022-03-16	SL
S2	1	19753	2022-03-16	SL
S2	2	19753	2022-03-16	SL
S2	3	19753	2022-03-16	SL
S2	4	19753	2022-03-16	SL
S2	5	19753	2022-03-16	SL
B1	1	19753	2022-03-16	3A
B1	2	19753	2022-03-16	3A
B1	3	19753	2022-03-16	3A
B1	4	19753	2022-03-16	3A
B1	5	19753	2022-03-16	3A
A1	1	19753	2022-03-16	2A
A1	2	19753	2022-03-16	2A
A1	3	19753	2022-03-16	2A
A1	4	19753	2022-03-16	2A
A1	5	19753	2022-03-16	2A
S1	1	19754	2022-03-15	SL
S1	2	19754	2022-03-15	SL
S1	3	19754	2022-03-15	SL
S1	4	19754	2022-03-15	SL
S1	5	19754	2022-03-15	SL
S2	1	19754	2022-03-15	SL
S2	2	19754	2022-03-15	SL
S2	3	19754	2022-03-15	SL
S2	4	19754	2022-03-15	SL
S2	5	19754	2022-03-15	SL
B1	1	19754	2022-03-15	3A
B1	2	19754	2022-03-15	3A
B1	3	19754	2022-03-15	3A
B1	4	19754	2022-03-15	3A
B1	5	19754	2022-03-15	3A
A1	1	19754	2022-03-15	2A
A1	2	19754	2022-03-15	2A
A1	3	19754	2022-03-15	2A
A1	4	19754	2022-03-15	2A
A1	5	19754	2022-03-15	2A
S1	1	19754	2022-03-17	SL
S1	2	19754	2022-03-17	SL
S1	3	19754	2022-03-17	SL
S1	4	19754	2022-03-17	SL
S1	5	19754	2022-03-17	SL
S2	1	19754	2022-03-17	SL
S2	2	19754	2022-03-17	SL
S2	3	19754	2022-03-17	SL
S2	4	19754	2022-03-17	SL
S2	5	19754	2022-03-17	SL
B1	1	19754	2022-03-17	3A
B1	2	19754	2022-03-17	3A
B1	3	19754	2022-03-17	3A
B1	4	19754	2022-03-17	3A
B1	5	19754	2022-03-17	3A
A1	1	19754	2022-03-17	2A
A1	2	19754	2022-03-17	2A
A1	3	19754	2022-03-17	2A
A1	4	19754	2022-03-17	2A
A1	5	19754	2022-03-17	2A
\.


--
-- Data for Name: station; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.station (station_code, name, area, city, district, state, platforms, pin_code, contact_no) FROM stdin;
101	Rajahmundry	Alcot Gardens	Rajahmundry	Rajahmundry	Andhra Pradesh	7	533101	9190244523
102	Visakhapatnam	Railway New Colony	Visakhapatnam	Visakhapatnam	Andhra Pradesh	10	530004	9294563104
103	Hyderabad	Nampally	Hyderabad	Hyderabad	Telangana	6	500025	8235018754
104	Warangal	Shiva Nagar	Warangal	Warangal	Telangana	4	506002	9102445345
105	Vijayawada Junction	Winchipeta	Vijayawada	Krishna	Andhra Pradesh	12	520001	9510345894
106	Chennai Central	Periyampet	Chennai	Chennai	Tamil Nadu	17	600003	8369514398
107	Coimbatore Junction	Gopalapuram	Coimbatore	Coimbatore	Tamil Nadu	7	641001	8835019273
108	Chandigarh	Daria	Chandigarh	Chandigarh	Orissa	5	160102	7987098274
109	Ongole	Santhapet	Ongole	Ongole	Andhra Pradesh	8	523001	8273598109
110	Old Delhi Junction	Chandini Chowk	Old Delhi	Delhi	Delhi	16	110006	9834509345
\.


--
-- Data for Name: stops; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stops (train_no, start_date, station_code, arrival_time, dept_time, dist_from_source) FROM stdin;
16845	2022-03-12	105	2022-03-12 07:30:00	2022-03-12 07:45:00	200.45000
16845	2022-03-12	109	2022-03-12 09:30:00	2022-03-12 09:45:00	400.45000
16845	2022-03-12	106	2022-03-12 12:30:00	2022-03-12 12:45:00	800.45000
16845	2022-03-13	105	2022-03-13 07:30:00	2022-03-13 07:45:00	200.45000
16845	2022-03-13	109	2022-03-13 09:30:00	2022-03-13 09:45:00	400.45000
16845	2022-03-13	106	2022-03-13 12:30:00	2022-03-13 12:45:00	800.45000
16845	2022-03-14	105	2022-03-14 07:30:00	2022-03-14 07:45:00	200.45000
16845	2022-03-14	109	2022-03-14 09:30:00	2022-03-14 09:45:00	400.45000
16845	2022-03-14	106	2022-03-14 12:30:00	2022-03-14 12:45:00	800.45000
16845	2022-03-15	105	2022-03-15 07:30:00	2022-03-15 07:45:00	200.45000
16845	2022-03-15	109	2022-03-15 09:30:00	2022-03-15 09:45:00	400.45000
16845	2022-03-15	106	2022-03-15 12:30:00	2022-03-15 12:45:00	800.45000
16845	2022-03-16	105	2022-03-16 07:30:00	2022-03-16 07:45:00	200.45000
16845	2022-03-16	109	2022-03-16 09:30:00	2022-03-16 09:45:00	400.45000
16845	2022-03-16	106	2022-03-16 12:30:00	2022-03-16 12:45:00	800.45000
16845	2022-03-17	105	2022-03-17 08:40:00	2022-03-17 08:55:00	200.45000
16845	2022-03-17	109	2022-03-17 10:40:00	2022-03-17 10:55:00	400.45000
16845	2022-03-17	106	2022-03-17 13:40:00	2022-03-17 13:55:00	800.45000
16845	2022-03-18	105	2022-03-18 08:40:00	2022-03-18 08:55:00	200.45000
16845	2022-03-18	109	2022-03-18 10:40:00	2022-03-18 10:55:00	400.45000
16845	2022-03-18	106	2022-03-18 13:40:00	2022-03-18 13:55:00	800.45000
16846	2022-03-12	106	2022-03-12 21:30:00	2022-03-12 21:45:00	800.00000
16846	2022-03-12	109	2022-03-12 01:30:00	2022-03-12 01:45:00	1200.00000
16846	2022-03-12	105	2022-03-12 03:30:00	2022-03-12 03:45:00	1400.00000
16846	2022-03-13	106	2022-03-13 21:30:00	2022-03-13 21:45:00	800.00000
16846	2022-03-13	109	2022-03-13 01:30:00	2022-03-13 01:45:00	1200.00000
16846	2022-03-13	105	2022-03-13 03:30:00	2022-03-13 03:45:00	1400.00000
16846	2022-03-14	106	2022-03-14 21:30:00	2022-03-14 21:45:00	800.00000
16846	2022-03-14	109	2022-03-14 01:30:00	2022-03-14 01:45:00	1200.00000
16846	2022-03-14	105	2022-03-14 03:30:00	2022-03-14 03:45:00	1400.00000
16846	2022-03-15	106	2022-03-15 21:30:00	2022-03-15 21:45:00	800.00000
16846	2022-03-15	109	2022-03-15 01:30:00	2022-03-15 01:45:00	1200.00000
16846	2022-03-15	105	2022-03-15 03:30:00	2022-03-15 03:45:00	1400.00000
16846	2022-03-16	106	2022-03-16 21:30:00	2022-03-16 21:45:00	800.00000
16846	2022-03-16	109	2022-03-16 01:30:00	2022-03-16 01:45:00	1200.00000
16846	2022-03-16	105	2022-03-16 03:30:00	2022-03-16 03:45:00	1400.00000
16846	2022-03-17	106	2022-03-17 00:30:00	2022-03-17 00:45:00	800.00000
16846	2022-03-17	109	2022-03-17 03:30:00	2022-03-17 03:45:00	1200.00000
16846	2022-03-17	105	2022-03-17 05:30:00	2022-03-17 05:45:00	1400.00000
16846	2022-03-18	106	2022-03-18 00:30:00	2022-03-18 00:45:00	800.00000
16846	2022-03-18	109	2022-03-18 03:30:00	2022-03-18 03:45:00	1200.00000
16846	2022-03-18	105	2022-03-18 05:30:00	2022-03-18 05:45:00	1400.00000
17326	2022-03-12	104	2022-03-12 13:45:00	2022-03-12 13:55:00	265.30000
17326	2022-03-13	104	2022-03-13 13:45:00	2022-03-13 13:55:00	265.30000
17326	2022-03-14	104	2022-03-14 13:45:00	2022-03-14 13:55:00	265.30000
17326	2022-03-15	104	2022-03-15 13:45:00	2022-03-15 13:55:00	265.30000
17326	2022-03-16	104	2022-03-16 13:45:00	2022-03-16 13:55:00	265.30000
17326	2022-03-17	104	2022-03-17 13:45:00	2022-03-17 13:55:00	265.30000
17326	2022-03-18	104	2022-03-18 13:45:00	2022-03-18 13:55:00	265.30000
17326	2022-03-12	108	2022-03-13 16:50:00	2022-03-13 17:00:00	1000.56000
17326	2022-03-13	108	2022-03-14 16:50:00	2022-03-14 17:00:00	1000.56000
17326	2022-03-14	108	2022-03-15 16:50:00	2022-03-15 17:00:00	1000.56000
17326	2022-03-15	108	2022-03-16 16:50:00	2022-03-16 17:00:00	1000.56000
17326	2022-03-16	108	2022-03-17 16:50:00	2022-03-17 17:00:00	1000.56000
17326	2022-03-17	108	2022-03-18 16:50:00	2022-03-18 17:00:00	1000.56000
17326	2022-03-18	108	2022-03-19 16:50:00	2022-03-19 17:00:00	1000.56000
17327	2022-03-12	108	2022-03-12 23:00:00	2022-03-12 23:30:00	200.00000
17327	2022-03-13	108	2022-03-13 23:00:00	2022-03-13 23:30:00	200.00000
17327	2022-03-14	108	2022-03-14 23:00:00	2022-03-14 23:30:00	200.00000
17327	2022-03-15	108	2022-03-15 23:00:00	2022-03-15 23:30:00	200.00000
17327	2022-03-16	108	2022-03-16 23:00:00	2022-03-16 23:30:00	200.00000
17327	2022-03-17	108	2022-03-17 23:00:00	2022-03-17 23:30:00	200.00000
17327	2022-03-18	108	2022-03-18 23:00:00	2022-03-18 23:30:00	200.00000
17327	2022-03-12	104	2022-03-13 04:20:00	2022-03-13 04:50:00	935.26000
17327	2022-03-13	104	2022-03-14 04:20:00	2022-03-14 04:50:00	935.26000
17327	2022-03-14	104	2022-03-15 04:20:00	2022-03-15 04:50:00	935.26000
17327	2022-03-15	104	2022-03-16 04:20:00	2022-03-16 04:50:00	935.26000
17327	2022-03-16	104	2022-03-17 04:20:00	2022-03-17 04:50:00	935.26000
17327	2022-03-17	104	2022-03-18 04:20:00	2022-03-18 04:50:00	935.26000
17327	2022-03-18	104	2022-03-19 04:20:00	2022-03-19 04:50:00	935.26000
15231	2022-03-16	101	2022-03-16 03:55:00	2022-03-16 04:00:00	150.34000
15232	2022-03-18	101	2022-03-18 08:45:00	2022-03-18 09:00:00	164.00000
19753	2022-03-14	105	2022-03-15 04:05:00	2022-03-15 04:15:00	160.45000
19753	2022-03-14	103	2022-03-15 10:25:00	2022-03-15 10:35:00	435.39000
19753	2022-03-16	105	2022-03-17 04:05:00	2022-03-17 04:15:00	160.45000
19753	2022-03-16	103	2022-03-17 10:25:00	2022-03-17 10:35:00	435.39000
19754	2022-03-15	103	2022-03-16 06:00:00	2022-03-16 06:15:00	1500.36000
19754	2022-03-15	105	2022-03-16 12:25:00	2022-03-16 12:35:00	1748.45000
19754	2022-03-17	103	2022-03-18 04:05:00	2022-03-18 04:15:00	160.45000
19754	2022-03-17	105	2022-03-18 10:25:00	2022-03-18 10:35:00	435.39000
17326	2022-03-12	102	\N	2022-03-12 07:45:00	0.00000
17326	2022-03-13	102	\N	2022-03-13 07:45:00	0.00000
17326	2022-03-14	102	\N	2022-03-14 07:45:00	0.00000
17326	2022-03-15	102	\N	2022-03-15 07:45:00	0.00000
17326	2022-03-16	102	\N	2022-03-16 07:45:00	0.00000
17326	2022-03-17	102	\N	2022-03-17 07:45:00	0.00000
17326	2022-03-18	102	\N	2022-03-18 07:45:00	0.00000
17326	2022-03-12	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-13	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-14	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-15	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-16	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-17	110	2022-03-19 18:50:00	\N	1200.56000
17326	2022-03-18	110	2022-03-19 18:50:00	\N	1200.56000
17327	2022-03-12	110	\N	2022-03-12 21:00:00	0.00000
17327	2022-03-13	110	\N	2022-03-13 21:00:00	0.00000
17327	2022-03-14	110	\N	2022-03-14 21:00:00	0.00000
17327	2022-03-15	110	\N	2022-03-15 21:00:00	0.00000
17327	2022-03-16	110	\N	2022-03-16 21:00:00	0.00000
17327	2022-03-17	110	\N	2022-03-17 21:00:00	0.00000
17327	2022-03-18	110	\N	2022-03-18 21:00:00	0.00000
17327	2022-03-12	102	2022-03-13 06:20:00	\N	1200.56000
17327	2022-03-13	102	2022-03-14 06:20:00	\N	1200.56000
17327	2022-03-14	102	2022-03-15 06:20:00	\N	1200.56000
17327	2022-03-15	102	2022-03-16 06:20:00	\N	1200.56000
17327	2022-03-16	102	2022-03-17 06:20:00	\N	1200.56000
17327	2022-03-17	102	2022-03-18 06:20:00	\N	1200.56000
17327	2022-03-18	102	2022-03-19 06:20:00	\N	1200.56000
16845	2022-03-12	103	\N	2022-03-12 05:30:00	0.00000
16845	2022-03-13	103	\N	2022-03-13 05:30:00	0.00000
16845	2022-03-14	103	\N	2022-03-14 05:30:00	0.00000
16845	2022-03-15	103	\N	2022-03-15 05:30:00	0.00000
16845	2022-03-16	103	\N	2022-03-16 05:30:00	0.00000
16845	2022-03-17	103	\N	2022-03-17 06:40:00	0.00000
16845	2022-03-18	103	\N	2022-03-18 06:40:00	0.00000
16845	2022-03-12	107	2022-03-12 19:30:00	\N	1600.45000
16845	2022-03-13	107	2022-03-13 19:30:00	\N	1600.45000
16845	2022-03-14	107	2022-03-14 19:30:00	\N	1600.45000
16845	2022-03-15	107	2022-03-15 19:30:00	\N	1600.45000
16845	2022-03-16	107	2022-03-16 19:30:00	\N	1600.45000
16845	2022-03-17	107	2022-03-17 20:30:00	\N	1600.45000
16845	2022-03-18	107	2022-03-18 20:40:00	\N	1600.45000
16846	2022-03-12	107	\N	2022-03-12 14:30:00	0.00000
16846	2022-03-13	107	\N	2022-03-13 14:30:00	0.00000
16846	2022-03-14	107	\N	2022-03-14 14:30:00	0.00000
16846	2022-03-15	107	\N	2022-03-15 14:30:00	0.00000
16846	2022-03-16	107	\N	2022-03-16 14:30:00	0.00000
16846	2022-03-17	107	\N	2022-03-17 16:30:00	0.00000
16846	2022-03-18	107	\N	2022-03-18 16:30:00	0.00000
16846	2022-03-12	103	2022-03-12 05:30:00	\N	1600.45000
16846	2022-03-13	103	2022-03-13 05:30:00	\N	1600.45000
16846	2022-03-14	103	2022-03-14 05:30:00	\N	1600.45000
16846	2022-03-15	103	2022-03-15 05:30:00	\N	1600.45000
16846	2022-03-16	103	2022-03-16 05:30:00	\N	1600.45000
16846	2022-03-17	103	2022-03-17 07:30:00	\N	1600.45000
16846	2022-03-18	103	2022-03-18 07:30:00	\N	1600.45000
15231	2022-03-16	105	\N	2022-03-16 02:30:00	0.00000
15232	2022-03-18	102	\N	2022-03-18 06:00:00	0.00000
15231	2022-03-16	102	2022-03-16 05:30:00	\N	314.34000
15232	2022-03-18	105	2022-03-18 10:20:00	\N	314.34000
19753	2022-03-14	101	\N	2022-03-14 22:50:00	0.00000
19753	2022-03-16	101	\N	2022-03-16 22:50:00	0.00000
19754	2022-03-15	108	\N	2022-03-15 17:50:00	0.00000
19754	2022-03-17	108	\N	2022-03-17 17:50:00	0.00000
19753	2022-03-14	108	2022-03-15 22:50:00	\N	2000.63000
19753	2022-03-16	108	2022-03-17 22:50:00	\N	2000.63000
19754	2022-03-15	101	2022-03-16 18:00:00	\N	1900.23000
19754	2022-03-17	101	2022-03-18 10:50:00	\N	2000.63000
\.


--
-- Data for Name: ticket_books; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ticket_books (user_id, passenger_id, pnr, doj, source_stat, dest_stat, payment_id, status, wl_no, book_date, coach_no, seat_no, coach_type, train_no, start_date, fare) FROM stdin;
2	1	4	2022-03-12	103	106	85c02453-1d09-41c4-a031-e569fdf19a24	CN	\N	2022-03-10 09:45:54	S1	1	SL	16845	2022-03-12	340.19125
2	2	5	2022-03-12	106	107	a1676059-7b56-4e73-9ea1-bed0ea743965	CN	\N	2022-03-10 09:55:54	S1	1	SL	16845	2022-03-12	340.00000
2	3	6	2022-03-12	109	107	4d438d88-64a5-4b45-aa00-02f9f407939f	CN	\N	2022-03-11 18:55:54	S1	2	SL	16845	2022-03-12	510.00000
3	4	7	2022-03-12	109	107	cce1f157-37b6-491b-934a-dbb96f10ec41	CN	\N	2022-03-11 12:55:54	S1	3	SL	16845	2022-03-12	510.00000
3	5	8	2022-03-12	109	107	cce1f157-37b6-491b-934a-dbb96f10ec41	CN	\N	2022-03-11 12:55:54	S1	4	SL	16845	2022-03-12	510.00000
3	6	9	2022-03-12	109	107	cce1f157-37b6-491b-934a-dbb96f10ec41	CN	\N	2022-03-11 12:55:54	S1	5	SL	16845	2022-03-12	510.00000
3	7	10	2022-03-14	101	103	fbb86291-51b0-4877-8ea5-d8a1dfcc4572	CN	\N	2022-03-11 02:55:54	B1	1	3A	19753	2022-03-14	380.96625
3	8	11	2022-03-14	101	103	fbb86291-51b0-4877-8ea5-d8a1dfcc4572	CN	\N	2022-03-11 02:55:54	B1	2	3A	19753	2022-03-14	380.96625
3	9	12	2022-03-14	101	103	fbb86291-51b0-4877-8ea5-d8a1dfcc4572	CN	\N	2022-03-11 02:55:54	B1	3	3A	19753	2022-03-14	380.96625
3	10	13	2022-03-14	105	108	8f07a90c-cd6b-420f-bff8-c3a6b4ffdc8c	CN	\N	2022-03-13 18:25:17	B1	4	3A	19753	2022-03-14	1610.15750
3	11	14	2022-03-14	105	108	b27615a5-cd62-4984-8805-dc3ceea70053	CN	\N	2022-03-11 16:18:04	B1	5	3A	19753	2022-03-14	1610.15750
3	12	19	2022-03-16	105	102	583dc45d-7100-478f-a0b0-b4152bf6dd56	CN	\N	2022-03-14 02:55:54	D1	1	3A	15231	2022-03-16	275.04750
3	13	20	2022-03-16	105	102	583dc45d-7100-478f-a0b0-b4152bf6dd56	CN	\N	2022-03-14 02:55:54	D1	2	3A	15231	2022-03-16	275.04750
3	14	21	2022-03-16	105	102	583dc45d-7100-478f-a0b0-b4152bf6dd56	CN	\N	2022-03-14 02:55:54	D1	3	3A	15231	2022-03-16	275.04750
3	15	22	2022-03-16	105	102	583dc45d-7100-478f-a0b0-b4152bf6dd56	CN	\N	2022-03-14 02:55:54	D1	4	3A	15231	2022-03-16	275.04750
4	16	28	2022-03-15	102	110	413c2000-501d-4271-acf7-7f6f4d3aedcb	CN	\N	2022-03-14 02:55:54	S1	1	SL	17326	2022-03-15	1254.58520
4	17	29	2022-03-15	102	110	413c2000-501d-4271-acf7-7f6f4d3aedcb	CN	\N	2022-03-14 02:55:54	S1	2	SL	17326	2022-03-15	1254.58520
4	18	30	2022-03-15	102	110	413c2000-501d-4271-acf7-7f6f4d3aedcb	CN	\N	2022-03-14 02:55:54	S1	3	SL	17326	2022-03-15	1254.58520
4	19	31	2022-03-15	102	110	413c2000-501d-4271-acf7-7f6f4d3aedcb	CN	\N	2022-03-14 02:55:54	S1	4	SL	17326	2022-03-15	1254.58520
4	20	32	2022-03-15	102	110	413c2000-501d-4271-acf7-7f6f4d3aedcb	CN	\N	2022-03-14 02:55:54	S1	5	SL	17326	2022-03-15	1254.58520
4	21	33	2022-03-15	102	110	4c567d9e-7e74-4ab2-b265-4530a5659fd0	CN	\N	2022-03-13 14:57:23	S2	1	SL	17326	2022-03-15	1254.58520
4	22	34	2022-03-15	102	110	4c567d9e-7e74-4ab2-b265-4530a5659fd0	CN	\N	2022-03-13 14:57:23	S2	2	SL	17326	2022-03-15	1254.58520
4	23	35	2022-03-15	102	110	4c567d9e-7e74-4ab2-b265-4530a5659fd0	CN	\N	2022-03-13 14:57:23	S2	3	SL	17326	2022-03-15	1254.58520
4	24	36	2022-03-15	102	110	4c567d9e-7e74-4ab2-b265-4530a5659fd0	CN	\N	2022-03-13 14:57:23	S2	4	SL	17326	2022-03-15	1254.58520
4	25	37	2022-03-15	102	110	4c567d9e-7e74-4ab2-b265-4530a5659fd0	CN	\N	2022-03-13 14:57:23	S2	5	SL	17326	2022-03-15	1254.58520
2	59	47	2022-03-15	102	110	fba12075-2f6f-42db-94c7-1c087bf9d425	WL	1	2022-04-25 01:35:59.323175	\N	\N	SL	17326	2022-03-15	1254.58520
2	60	48	2022-03-15	102	110	63ad15e9-e48a-404b-a140-e27f39d92ad2	WL	2	2022-04-25 01:43:25.294955	\N	\N	SL	17326	2022-03-15	1254.58520
3	61	49	2022-03-15	102	110	ef88c8bd-989e-43de-a7ee-7fb37583eef5	WL	3	2022-04-25 01:45:29.444866	\N	\N	SL	17326	2022-03-15	1254.58520
4	63	50	2022-03-16	105	102	8ea8b839-52a0-4946-993b-ccc45965fd61	CN	\N	2022-04-25 01:52:20.831117	B1	2	2A	15231	2022-03-16	275.04750
2	57	44	2022-03-15	102	110	87b0b542-1db6-4edb-a951-99fc8e4bdcc0	NC	\N	2022-04-25 00:29:37.365216	\N	\N	SL	17326	2022-03-15	1254.58520
2	58	45	2022-03-15	102	110	fc0eb0cf-2a96-4ece-b5c0-f06c3e24c29c	NC	\N	2022-04-25 00:29:40.196505	\N	\N	SL	17326	2022-03-15	1254.58520
2	46	2	2022-03-13	102	104	568e39eb-3e00-48fe-a931-0e232de26151	NC	\N	2022-04-21 23:35:03.494603	\N	\N	SL	17326	2022-03-12	277.23850
\.


--
-- Data for Name: train_runs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.train_runs (train_no, train_start, price_per_km, current_delay) FROM stdin;
17326	2022-03-12	10.450	00:00:00
17326	2022-03-13	10.450	00:00:00
17326	2022-03-14	10.450	00:00:00
17326	2022-03-15	10.450	00:00:00
17326	2022-03-16	10.450	00:00:00
17326	2022-03-17	10.450	00:00:00
17326	2022-03-18	10.450	00:00:00
17327	2022-03-12	10.450	00:00:00
17327	2022-03-13	10.450	00:00:00
17327	2022-03-14	10.450	00:00:00
17327	2022-03-15	10.450	00:00:00
17327	2022-03-16	10.450	00:00:00
17327	2022-03-17	10.450	00:00:00
17327	2022-03-18	10.450	00:00:00
16845	2022-03-12	4.250	00:00:00
16845	2022-03-13	4.250	00:00:00
16845	2022-03-14	4.250	00:00:00
16845	2022-03-15	4.250	00:00:00
16845	2022-03-16	4.250	00:00:00
16845	2022-03-17	4.250	00:00:00
16845	2022-03-18	4.250	00:00:00
16846	2022-03-12	4.250	00:00:00
16846	2022-03-13	4.250	00:00:00
16846	2022-03-14	4.250	00:00:00
16846	2022-03-15	4.250	00:00:00
16846	2022-03-16	4.250	00:00:00
16846	2022-03-17	4.250	00:00:00
16846	2022-03-18	4.250	00:00:00
19753	2022-03-14	8.750	00:00:00
19753	2022-03-16	8.750	00:00:00
19754	2022-03-15	8.750	00:00:00
19754	2022-03-17	8.750	00:00:00
15231	2022-03-16	8.750	00:00:00
15232	2022-03-18	8.750	00:00:00
\.


--
-- Data for Name: train_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.train_type (train_no, train_type, train_name) FROM stdin;
17326	SF	Delhi SF
17327	SF	VSKP SF
16845	PASS	cbe pass
16846	PASS	hyd pass
19753	EXP	chandigarh exp
19754	EXP	raj exp
15231	EXP	VSKP Rat Exp
15232	EXP	Bza Rat exp
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (user_id, name, age, gender, email_id, contact_no, password, identity_no) FROM stdin;
3	Yagnesh	20	M	yagnesh@gmail.com	9987564135	Yagnesh158	823636493209
4	Manikanta	20	M	mani@gmail.com	7954126542	Manikanta234	976414871139
2	Rahul	21	M	rahul6@gmail.com	8642652578	rahul123	254963261887
\.


--
-- Name: passenger_passenger_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.passenger_passenger_id_seq', 71, true);


--
-- Name: ticket_books_pnr_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ticket_books_pnr_seq', 56, true);


--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_user_id_seq', 4, true);


--
-- Name: passenger passenger_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.passenger
    ADD CONSTRAINT passenger_pkey PRIMARY KEY (passenger_id);


--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (pay_id);


--
-- Name: seats seats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seats
    ADD CONSTRAINT seats_pkey PRIMARY KEY (coach_no, seat_no, train_no, start_date);


--
-- Name: station station_contact_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.station
    ADD CONSTRAINT station_contact_no_key UNIQUE (contact_no);


--
-- Name: station station_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.station
    ADD CONSTRAINT station_name_key UNIQUE (name);


--
-- Name: station station_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.station
    ADD CONSTRAINT station_pkey PRIMARY KEY (station_code);


--
-- Name: stops stops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops
    ADD CONSTRAINT stops_pkey PRIMARY KEY (train_no, start_date, station_code);


--
-- Name: ticket_books ticket_books_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_pkey PRIMARY KEY (passenger_id, pnr);


--
-- Name: train_runs train_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.train_runs
    ADD CONSTRAINT train_runs_pkey PRIMARY KEY (train_no, train_start);


--
-- Name: train_type train_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.train_type
    ADD CONSTRAINT train_type_pkey PRIMARY KEY (train_no);


--
-- Name: users users_contact_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_contact_no_key UNIQUE (contact_no);


--
-- Name: users users_email_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_id_key UNIQUE (email_id);


--
-- Name: users users_identity_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_identity_no_key UNIQUE (identity_no);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: station_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX station_index ON public.station USING btree (name);


--
-- Name: train_tickets; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX train_tickets ON public.ticket_books USING btree (train_no) INCLUDE (start_date);


--
-- Name: type_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX type_index ON public.train_type USING btree (train_type);


--
-- Name: ticket_books booking_conditions; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER booking_conditions BEFORE INSERT ON public.ticket_books FOR EACH ROW EXECUTE FUNCTION public.book_checking();


--
-- Name: users prevent_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_update BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.user_prevent();


--
-- Name: ticket_books train_pass; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER train_pass BEFORE INSERT ON public.ticket_books FOR EACH ROW EXECUTE FUNCTION public.train_stop_check();


--
-- Name: seats seats_train_no_start_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seats
    ADD CONSTRAINT seats_train_no_start_date_fkey FOREIGN KEY (train_no, start_date) REFERENCES public.train_runs(train_no, train_start);


--
-- Name: stops stops_station_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops
    ADD CONSTRAINT stops_station_code_fkey FOREIGN KEY (station_code) REFERENCES public.station(station_code);


--
-- Name: stops stops_train_no_start_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops
    ADD CONSTRAINT stops_train_no_start_date_fkey FOREIGN KEY (train_no, start_date) REFERENCES public.train_runs(train_no, train_start);


--
-- Name: ticket_books ticket_books_coach_no_seat_no_train_no_start_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_coach_no_seat_no_train_no_start_date_fkey FOREIGN KEY (coach_no, seat_no, train_no, start_date) REFERENCES public.seats(coach_no, seat_no, train_no, start_date);


--
-- Name: ticket_books ticket_books_dest_stat_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_dest_stat_fkey FOREIGN KEY (dest_stat) REFERENCES public.station(station_code);


--
-- Name: ticket_books ticket_books_passenger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_passenger_id_fkey FOREIGN KEY (passenger_id) REFERENCES public.passenger(passenger_id);


--
-- Name: ticket_books ticket_books_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payment(pay_id);


--
-- Name: ticket_books ticket_books_source_stat_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_source_stat_fkey FOREIGN KEY (source_stat) REFERENCES public.station(station_code);


--
-- Name: ticket_books ticket_books_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ticket_books
    ADD CONSTRAINT ticket_books_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: train_runs train_runs_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.train_runs
    ADD CONSTRAINT train_runs_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train_type(train_no);


--
-- Name: users account; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY account ON public.users TO account_users USING ((user_id = (CURRENT_USER)::integer));


--
-- Name: ticket_books; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ticket_books ENABLE ROW LEVEL SECURITY;

--
-- Name: ticket_books tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tickets ON public.ticket_books TO account_users USING ((user_id = (CURRENT_USER)::integer));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: FUNCTION check_pnr_stat(given_pnr integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.check_pnr_stat(given_pnr integer) TO account_users;


--
-- Name: FUNCTION compute_fare(trainno integer, trainstart date, source integer, dest integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.compute_fare(trainno integer, trainstart date, source integer, dest integer) TO account_users;
GRANT ALL ON FUNCTION public.compute_fare(trainno integer, trainstart date, source integer, dest integer) TO non_users;


--
-- Name: FUNCTION distance(train integer, start date, code integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.distance(train integer, start date, code integer) TO account_users;
GRANT ALL ON FUNCTION public.distance(train integer, start date, code integer) TO non_users;


--
-- Name: FUNCTION timetable(train integer, date date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.timetable(train integer, date date) TO account_users;
GRANT ALL ON FUNCTION public.timetable(train integer, date date) TO non_users;


--
-- Name: FUNCTION trains_between_stats(source integer, dest integer, doj date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trains_between_stats(source integer, dest integer, doj date) TO account_users;
GRANT ALL ON FUNCTION public.trains_between_stats(source integer, dest integer, doj date) TO non_users;


--
-- Name: TABLE credit_card_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.credit_card_payments TO credit;


--
-- Name: TABLE debit_card_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.debit_card_payments TO debit;


--
-- Name: TABLE station; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.station TO non_users;
GRANT SELECT ON TABLE public.station TO account_users;


--
-- Name: TABLE stops; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.stops TO non_users;
GRANT SELECT ON TABLE public.stops TO account_users;


--
-- Name: TABLE ticket_books; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.ticket_books TO account_users;


--
-- Name: TABLE train_runs; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.train_runs TO non_users;
GRANT SELECT ON TABLE public.train_runs TO account_users;


--
-- Name: TABLE train_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.train_type TO non_users;
GRANT SELECT ON TABLE public.train_type TO account_users;


--
-- Name: TABLE upi_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.upi_payments TO upi;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,UPDATE ON TABLE public.users TO account_users;


--
-- PostgreSQL database dump complete
--

