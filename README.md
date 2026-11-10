# SkyBook – Air Reservation System (Oracle PL/SQL + Node.js + Web UI)

Browser (HTML/CSS/JS) -> Express REST API (`backend/`) -> Oracle PL/SQL package `pkg_airline` (`database/`).
All business rules (seat allocation, locking, refunds, validation) live in PL/SQL; Node only calls procedures.

## PL/SQL features
- Tables: identity PKs, FKs, CHECK constraints, indexes
- Package `pkg_airline`: search_flights, book_ticket, cancel_ticket, get_booking, refund_amount
- `SELECT ... FOR UPDATE` row locking prevents double booking
- Custom errors via RAISE_APPLICATION_ERROR (-20001..-20010), COMMIT/ROLLBACK handling
- Triggers: flight time validation, automatic audit log; view `v_flight_revenue`; REF CURSORs

## Setup
1. Install Oracle 12c+ (or Oracle XE) and Node.js 18+.
2. In SQL*Plus / SQL Developer run in order:
   @database/01_schema.sql, @database/02_plsql.sql, @database/03_seed.sql, @database/04_upgrade.sql, @database/05_auth.sql
3. Backend:
   cd backend && npm install
   set DB_USER=youruser DB_PASSWORD=yourpwd DB_CONNECT=localhost:1521/XEPDB1   (Linux/Mac: export ...)
   npm start
4. Open http://localhost:3000

## Refund policy
>24h before departure: 90% | 2-24h: 50% | <2h: 0%

## Handy queries
SELECT * FROM v_flight_revenue;
SELECT * FROM audit_log ORDER BY log_id DESC;

## Demo mode
Open frontend/index.html directly (or run the server without a database): the UI detects that the API is unavailable and runs on a built-in demo data set, so airports and flights always appear.

## Features
One-way / round-trip, 1-6 travellers, Economy/Business, date strip, sort & time filters, interactive seat map, baggage & meal add-ons, 12% tax, card payment form (mock), printable boarding passes, PNR management & cancellation with refund rules, admin revenue dashboard.

## Login & accounts
- Users register/sign in on the Login page; passwords are salted + SHA-256 hashed inside Oracle (`pkg_auth`), never stored in plain text.
- The API issues an HMAC-signed 7-day token. Set `AUTH_SECRET` in the environment so sessions survive restarts, and serve over HTTPS in production.
- Booking requires login; bookings are linked to the account and listed under **My trips**.
- Default admin (created by 05_auth.sql): `admin@skybook.com` / `Admin@123` - change it. Only admins see the Admin dashboard.
- Demo mode has the same admin account and stores demo users in the browser.

If `05_auth.sql` reports `PLS-00201: STANDARD_HASH` (older script), run `database/05b_fix_auth.sql` instead of re-running 05.
