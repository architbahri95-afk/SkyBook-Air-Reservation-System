-- Run as your Oracle user (12c+): @01_schema.sql
CREATE TABLE airports (
  code VARCHAR2(3) PRIMARY KEY,
  city VARCHAR2(50) NOT NULL,
  name VARCHAR2(100) NOT NULL
);
CREATE TABLE flights (
  flight_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  flight_no       VARCHAR2(10) NOT NULL,
  origin          VARCHAR2(3) NOT NULL REFERENCES airports(code),
  destination     VARCHAR2(3) NOT NULL REFERENCES airports(code),
  dep_time        DATE NOT NULL,
  arr_time        DATE NOT NULL,
  price           NUMBER(10,2) NOT NULL CHECK (price > 0),
  total_seats     NUMBER(4) NOT NULL,
  available_seats NUMBER(4) NOT NULL,
  CONSTRAINT chk_route CHECK (origin <> destination),
  CONSTRAINT chk_seats CHECK (available_seats BETWEEN 0 AND total_seats)
);
CREATE TABLE passengers (
  passenger_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name    VARCHAR2(100) NOT NULL,
  email        VARCHAR2(100) NOT NULL UNIQUE,
  phone        VARCHAR2(20)
);
CREATE TABLE bookings (
  booking_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pnr          VARCHAR2(6) NOT NULL UNIQUE,
  flight_id    NUMBER NOT NULL REFERENCES flights(flight_id),
  passenger_id NUMBER NOT NULL REFERENCES passengers(passenger_id),
  seat_no      VARCHAR2(4) NOT NULL,
  fare         NUMBER(10,2) NOT NULL,
  status       VARCHAR2(10) DEFAULT 'CONFIRMED' CHECK (status IN ('CONFIRMED','CANCELLED')),
  refund       NUMBER(10,2) DEFAULT 0,
  booked_on    DATE DEFAULT SYSDATE
);
CREATE TABLE audit_log (
  log_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pnr        VARCHAR2(6),
  action     VARCHAR2(20),
  logged_on  TIMESTAMP DEFAULT SYSTIMESTAMP
);
CREATE INDEX idx_flights_route ON flights(origin, destination, dep_time);
CREATE INDEX idx_bookings_flight ON bookings(flight_id, status);
