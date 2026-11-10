-- User accounts: run after 01-04
CREATE TABLE users (
  user_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name     VARCHAR2(100) NOT NULL,
  email         VARCHAR2(100) NOT NULL UNIQUE,
  salt          VARCHAR2(32)  NOT NULL,
  password_hash VARCHAR2(64)  NOT NULL,
  role          VARCHAR2(10) DEFAULT 'USER' CHECK (role IN ('USER','ADMIN')),
  created_on    DATE DEFAULT SYSDATE
);
ALTER TABLE bookings ADD (user_id NUMBER REFERENCES users(user_id));
CREATE INDEX idx_bookings_user ON bookings(user_id);

CREATE OR REPLACE PACKAGE pkg_auth AS
  PROCEDURE register_user(p_name VARCHAR2, p_email VARCHAR2, p_password VARCHAR2, p_id OUT NUMBER);
  PROCEDURE login_user(p_email VARCHAR2, p_password VARCHAR2, p_id OUT NUMBER, p_name OUT VARCHAR2, p_role OUT VARCHAR2);
  PROCEDURE my_bookings(p_user_id NUMBER, p_rc OUT SYS_REFCURSOR);
END pkg_auth;
/
CREATE OR REPLACE PACKAGE BODY pkg_auth AS
  FUNCTION hash_pw(p_salt VARCHAR2, p_pw VARCHAR2) RETURN VARCHAR2 IS
    v_h VARCHAR2(64);
  BEGIN
    -- STANDARD_HASH is a SQL function, so it must be called through a query
    SELECT LOWER(RAWTOHEX(STANDARD_HASH(p_salt || p_pw, 'SHA256'))) INTO v_h FROM dual;   -- salted SHA-256
    RETURN v_h;
  END;

  PROCEDURE register_user(p_name VARCHAR2, p_email VARCHAR2, p_password VARCHAR2, p_id OUT NUMBER) IS
    v_salt VARCHAR2(32) := DBMS_RANDOM.STRING('X', 16);
    v_cnt  PLS_INTEGER;
    v_hash VARCHAR2(64);
  BEGIN
    IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 2 THEN RAISE_APPLICATION_ERROR(-20024,'Enter your full name'); END IF;
    IF NOT REGEXP_LIKE(p_email, '^[^@ ]+@[^@ ]+\.[^@ ]+$') THEN RAISE_APPLICATION_ERROR(-20022,'Invalid e-mail address'); END IF;
    IF LENGTH(p_password) < 8 OR NOT REGEXP_LIKE(p_password,'[0-9]') OR NOT REGEXP_LIKE(p_password,'[A-Za-z]') THEN
      RAISE_APPLICATION_ERROR(-20023,'Password needs 8+ characters with letters and numbers');
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM users WHERE email = LOWER(p_email);
    IF v_cnt > 0 THEN RAISE_APPLICATION_ERROR(-20020,'An account with this e-mail already exists'); END IF;
    v_hash := hash_pw(v_salt, p_password);   -- compute in PL/SQL: private functions can't be called inside SQL
    INSERT INTO users(full_name, email, salt, password_hash)
    VALUES (TRIM(p_name), LOWER(p_email), v_salt, v_hash)
    RETURNING user_id INTO p_id;
    COMMIT;
  END;

  PROCEDURE login_user(p_email VARCHAR2, p_password VARCHAR2, p_id OUT NUMBER, p_name OUT VARCHAR2, p_role OUT VARCHAR2) IS
    v_u users%ROWTYPE;
  BEGIN
    SELECT * INTO v_u FROM users WHERE email = LOWER(p_email);
    IF hash_pw(v_u.salt, p_password) <> v_u.password_hash THEN RAISE NO_DATA_FOUND; END IF;
    p_id := v_u.user_id; p_name := v_u.full_name; p_role := v_u.role;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20021, 'Invalid email or password');   -- same message: no account enumeration
  END;

  PROCEDURE my_bookings(p_user_id NUMBER, p_rc OUT SYS_REFCURSOR) IS
  BEGIN
    OPEN p_rc FOR
      SELECT b.pnr, b.seat_no, b.fare, b.status, b.refund, b.travel_class, p.full_name,
             f.flight_no, f.origin, f.destination,
             TO_CHAR(f.dep_time,'YYYY-MM-DD"T"HH24:MI') dep_time,
             TO_CHAR(f.arr_time,'YYYY-MM-DD"T"HH24:MI') arr_time
      FROM bookings b JOIN flights f ON f.flight_id = b.flight_id
                      JOIN passengers p ON p.passenger_id = b.passenger_id
      WHERE b.user_id = p_user_id ORDER BY b.booked_on DESC;
  END;
END pkg_auth;
/
-- Default administrator (CHANGE THE PASSWORD after first login)
DECLARE v_id NUMBER;
BEGIN
  pkg_auth.register_user('Administrator','admin@skybook.com','Admin@123',v_id);
  UPDATE users SET role='ADMIN' WHERE user_id = v_id; COMMIT;
END;
/
