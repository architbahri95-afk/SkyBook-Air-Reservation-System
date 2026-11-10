-- Triggers -----------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_flight_validate
BEFORE INSERT OR UPDATE ON flights FOR EACH ROW
BEGIN
  IF :NEW.arr_time <= :NEW.dep_time THEN
    RAISE_APPLICATION_ERROR(-20010, 'Arrival must be after departure');
  END IF;
END;
/
CREATE OR REPLACE TRIGGER trg_booking_audit
AFTER INSERT OR UPDATE OF status ON bookings FOR EACH ROW
BEGIN
  INSERT INTO audit_log(pnr, action) VALUES (:NEW.pnr, CASE WHEN INSERTING THEN 'BOOKED' ELSE :NEW.status END);
END;
/
-- Reporting view -----------------------------------------------------
CREATE OR REPLACE VIEW v_flight_revenue AS
SELECT f.flight_no, f.origin, f.destination,
       COUNT(CASE WHEN b.status='CONFIRMED' THEN 1 END) AS tickets_sold,
       NVL(SUM(CASE WHEN b.status='CONFIRMED' THEN b.fare END),0) AS revenue
FROM flights f LEFT JOIN bookings b ON b.flight_id = f.flight_id
GROUP BY f.flight_no, f.origin, f.destination;

-- Package ------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_airline AS
  PROCEDURE search_flights(p_from VARCHAR2, p_to VARCHAR2, p_date DATE, p_rc OUT SYS_REFCURSOR);
  PROCEDURE book_ticket(p_flight_id NUMBER, p_name VARCHAR2, p_email VARCHAR2, p_phone VARCHAR2,
                        p_pnr OUT VARCHAR2, p_seat OUT VARCHAR2, p_fare OUT NUMBER);
  PROCEDURE cancel_ticket(p_pnr VARCHAR2, p_refund OUT NUMBER);
  PROCEDURE get_booking(p_pnr VARCHAR2, p_rc OUT SYS_REFCURSOR);
  FUNCTION  refund_amount(p_fare NUMBER, p_dep DATE) RETURN NUMBER;
END pkg_airline;
/
CREATE OR REPLACE PACKAGE BODY pkg_airline AS

  FUNCTION refund_amount(p_fare NUMBER, p_dep DATE) RETURN NUMBER IS
    v_hours NUMBER := (p_dep - SYSDATE) * 24;
  BEGIN
    RETURN ROUND(CASE WHEN v_hours > 24 THEN p_fare*0.9
                      WHEN v_hours > 2  THEN p_fare*0.5
                      ELSE 0 END, 2);
  END;

  PROCEDURE search_flights(p_from VARCHAR2, p_to VARCHAR2, p_date DATE, p_rc OUT SYS_REFCURSOR) IS
  BEGIN
    OPEN p_rc FOR
      SELECT f.flight_id, f.flight_no, f.origin, f.destination,
             TO_CHAR(f.dep_time,'YYYY-MM-DD"T"HH24:MI') dep_time,
             TO_CHAR(f.arr_time,'YYYY-MM-DD"T"HH24:MI') arr_time,
             f.price, f.available_seats,
             a1.city origin_city, a2.city dest_city
      FROM flights f
      JOIN airports a1 ON a1.code = f.origin
      JOIN airports a2 ON a2.code = f.destination
      WHERE f.origin = UPPER(p_from) AND f.destination = UPPER(p_to)
        AND TRUNC(f.dep_time) = TRUNC(p_date) AND f.dep_time > SYSDATE
      ORDER BY f.dep_time;
  END;

  PROCEDURE book_ticket(p_flight_id NUMBER, p_name VARCHAR2, p_email VARCHAR2, p_phone VARCHAR2,
                        p_pnr OUT VARCHAR2, p_seat OUT VARCHAR2, p_fare OUT NUMBER) IS
    v_flight flights%ROWTYPE;
    v_pax    passengers.passenger_id%TYPE;
    v_n      PLS_INTEGER := 0;
    v_taken  PLS_INTEGER;
  BEGIN
    SELECT * INTO v_flight FROM flights WHERE flight_id = p_flight_id FOR UPDATE;  -- row lock = no double booking
    IF v_flight.dep_time <= SYSDATE THEN
      RAISE_APPLICATION_ERROR(-20002, 'Flight has already departed');
    END IF;
    IF v_flight.available_seats <= 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Flight is fully booked');
    END IF;

    BEGIN
      SELECT passenger_id INTO v_pax FROM passengers WHERE email = LOWER(p_email);
    EXCEPTION WHEN NO_DATA_FOUND THEN
      INSERT INTO passengers(full_name, email, phone) VALUES (p_name, LOWER(p_email), p_phone)
      RETURNING passenger_id INTO v_pax;
    END;

    -- lowest free seat (6 per row: 1A..1F, 2A...)
    LOOP
      v_n := v_n + 1;
      p_seat := CEIL(v_n/6) || CHR(64 + MOD(v_n-1,6) + 1);
      SELECT COUNT(*) INTO v_taken FROM bookings
       WHERE flight_id = p_flight_id AND seat_no = p_seat AND status = 'CONFIRMED';
      EXIT WHEN v_taken = 0;
    END LOOP;

    p_pnr  := DBMS_RANDOM.STRING('X', 6);
    p_fare := v_flight.price;
    INSERT INTO bookings(pnr, flight_id, passenger_id, seat_no, fare)
    VALUES (p_pnr, p_flight_id, v_pax, p_seat, p_fare);
    UPDATE flights SET available_seats = available_seats - 1 WHERE flight_id = p_flight_id;
    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN ROLLBACK; RAISE_APPLICATION_ERROR(-20003, 'Flight not found');
    WHEN OTHERS THEN ROLLBACK; RAISE;
  END;

  PROCEDURE cancel_ticket(p_pnr VARCHAR2, p_refund OUT NUMBER) IS
    v_b   bookings%ROWTYPE;
    v_dep DATE;
  BEGIN
    SELECT * INTO v_b FROM bookings WHERE pnr = UPPER(p_pnr) FOR UPDATE;
    IF v_b.status = 'CANCELLED' THEN
      RAISE_APPLICATION_ERROR(-20004, 'Ticket already cancelled');
    END IF;
    SELECT dep_time INTO v_dep FROM flights WHERE flight_id = v_b.flight_id FOR UPDATE;
    IF v_dep <= SYSDATE THEN
      RAISE_APPLICATION_ERROR(-20002, 'Flight has already departed');
    END IF;
    p_refund := refund_amount(v_b.fare, v_dep);
    UPDATE bookings SET status='CANCELLED', refund=p_refund WHERE booking_id = v_b.booking_id;
    UPDATE flights  SET available_seats = available_seats + 1 WHERE flight_id = v_b.flight_id;
    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN ROLLBACK; RAISE_APPLICATION_ERROR(-20005, 'PNR not found');
    WHEN OTHERS THEN ROLLBACK; RAISE;
  END;

  PROCEDURE get_booking(p_pnr VARCHAR2, p_rc OUT SYS_REFCURSOR) IS
  BEGIN
    OPEN p_rc FOR
      SELECT b.pnr, b.seat_no, b.fare, b.status, b.refund,
             p.full_name, p.email, f.flight_no, f.origin, f.destination,
             TO_CHAR(f.dep_time,'YYYY-MM-DD"T"HH24:MI') dep_time,
             TO_CHAR(f.arr_time,'YYYY-MM-DD"T"HH24:MI') arr_time
      FROM bookings b JOIN passengers p ON p.passenger_id=b.passenger_id
                      JOIN flights f ON f.flight_id=b.flight_id
      WHERE b.pnr = UPPER(p_pnr);
  END;
END pkg_airline;
/
