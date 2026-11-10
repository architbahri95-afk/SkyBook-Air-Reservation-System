INSERT INTO airports VALUES ('DEL','Delhi','Indira Gandhi International');
INSERT INTO airports VALUES ('BOM','Mumbai','Chhatrapati Shivaji Maharaj Intl');
INSERT INTO airports VALUES ('BLR','Bengaluru','Kempegowda International');
INSERT INTO airports VALUES ('MAA','Chennai','Chennai International');
INSERT INTO airports VALUES ('CCU','Kolkata','Netaji Subhas Chandra Bose Intl');
INSERT INTO airports VALUES ('HYD','Hyderabad','Rajiv Gandhi International');
INSERT INTO airports VALUES ('GOI','Goa','Manohar International');
INSERT INTO airports VALUES ('AMD','Ahmedabad','Sardar Vallabhbhai Patel Intl');

INSERT INTO flights(flight_no,origin,destination,dep_time,arr_time,price,total_seats,available_seats)
SELECT 'SB'||TO_CHAR(100+MOD(ORA_HASH(a.code||b.code),800)+h.n), a.code, b.code,
       TRUNC(SYSDATE)+d.n+h.hr/24,
       TRUNC(SYSDATE)+d.n+h.hr/24+(75+MOD(ORA_HASH(a.code||b.code),150)+h.n*10)/1440,
       2800+MOD(ORA_HASH(a.code||b.code),50)*90+h.n*300, 60, 60
FROM airports a JOIN airports b ON a.code<>b.code
CROSS JOIN (SELECT LEVEL-1 n FROM dual CONNECT BY LEVEL<=21) d
CROSS JOIN (SELECT 1 n,6 hr FROM dual UNION ALL SELECT 2,10 FROM dual
            UNION ALL SELECT 3,15 FROM dual UNION ALL SELECT 4,20 FROM dual) h;
COMMIT;
