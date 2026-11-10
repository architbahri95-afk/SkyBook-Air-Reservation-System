-- Run after 01-03. Adds seat selection, travel class, baggage, meals, 12% tax.
ALTER TABLE bookings ADD (travel_class VARCHAR2(10) DEFAULT 'ECONOMY', baggage_kg NUMBER(3) DEFAULT 15, meal VARCHAR2(10) DEFAULT 'NONE');

CREATE OR REPLACE PROCEDURE get_seats(p_flight_id NUMBER, p_rc OUT SYS_REFCURSOR) IS
BEGIN
  OPEN p_rc FOR SELECT seat_no FROM bookings WHERE flight_id = p_flight_id AND status = 'CONFIRMED';
END;
/
CREATE OR REPLACE PROCEDURE book_seat(
  p_flight_id NUMBER, p_name VARCHAR2, p_email VARCHAR2, p_phone VARCHAR2,
  p_class VARCHAR2, p_baggage NUMBER, p_meal VARCHAR2,
  p_seat IN OUT VARCHAR2, p_pnr OUT VARCHAR2, p_fare OUT NUMBER) IS
  v_f flights%ROWTYPE; v_pax NUMBER; v_n PLS_INTEGER; v_taken PLS_INTEGER; v_row PLS_INTEGER;
  v_base NUMBER; v_extra NUMBER;
BEGIN
  SELECT * INTO v_f FROM flights WHERE flight_id = p_flight_id FOR UPDATE;   -- serialises bookings per flight
  IF v_f.dep_time <= SYSDATE THEN RAISE_APPLICATION_ERROR(-20002,'Flight has already departed'); END IF;
  IF v_f.available_seats <= 0 THEN RAISE_APPLICATION_ERROR(-20001,'Flight is fully booked'); END IF;

  BEGIN SELECT passenger_id INTO v_pax FROM passengers WHERE email = LOWER(p_email);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    INSERT INTO passengers(full_name,email,phone) VALUES (p_name,LOWER(p_email),p_phone) RETURNING passenger_id INTO v_pax;
  END;

  IF p_seat IS NOT NULL THEN                      -- requested seat: validate class + availability
    v_row := TO_NUMBER(REGEXP_SUBSTR(p_seat,'\d+'));
    IF (p_class='BUSINESS' AND v_row>2) OR (p_class<>'BUSINESS' AND v_row<=2) THEN
      RAISE_APPLICATION_ERROR(-20006,'Seat '||p_seat||' is not in your travel class'); END IF;
    SELECT COUNT(*) INTO v_taken FROM bookings WHERE flight_id=p_flight_id AND seat_no=p_seat AND status='CONFIRMED';
    IF v_taken > 0 THEN RAISE_APPLICATION_ERROR(-20007,'Seat '||p_seat||' was just taken'); END IF;
  ELSE                                            -- auto-assign lowest free seat in class
    v_n := CASE WHEN p_class='BUSINESS' THEN 0 ELSE 12 END;
    LOOP
      v_n := v_n + 1;
      p_seat := CEIL(v_n/6)||CHR(64+MOD(v_n-1,6)+1);
      SELECT COUNT(*) INTO v_taken FROM bookings WHERE flight_id=p_flight_id AND seat_no=p_seat AND status='CONFIRMED';
      EXIT WHEN v_taken = 0;
    END LOOP;
  END IF;

  v_base  := v_f.price * CASE WHEN p_class='BUSINESS' THEN 2.2 ELSE 1 END;
  v_extra := (p_baggage-15)*40 + CASE p_meal WHEN 'VEG' THEN 350 WHEN 'NONVEG' THEN 400 ELSE 0 END;
  p_fare  := ROUND((v_base + v_extra) * 1.12, 2);          -- 12% taxes & fees
  p_pnr   := DBMS_RANDOM.STRING('X',6);
  INSERT INTO bookings(pnr,flight_id,passenger_id,seat_no,fare,travel_class,baggage_kg,meal)
  VALUES (p_pnr,p_flight_id,v_pax,p_seat,p_fare,p_class,p_baggage,p_meal);
  UPDATE flights SET available_seats = available_seats - 1 WHERE flight_id = p_flight_id;
  COMMIT;
EXCEPTION
  WHEN NO_DATA_FOUND THEN ROLLBACK; RAISE_APPLICATION_ERROR(-20003,'Flight not found');
  WHEN OTHERS THEN ROLLBACK; RAISE;
END;
/
