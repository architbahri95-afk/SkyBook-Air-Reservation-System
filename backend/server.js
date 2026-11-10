const express = require('express');
const oracledb = require('oracledb');
const path = require('path');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

const cfg = {
  user: process.env.DB_USER || 'system',
  password: process.env.DB_PASSWORD || 'oracle',
  connectString: process.env.DB_CONNECT || 'localhost:1521/XEPDB1'
};
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, '../frontend')));

const lower = rows => rows.map(r => Object.fromEntries(Object.entries(r).map(([k, v]) => [k.toLowerCase(), v])));
const run = async fn => { const c = await oracledb.getConnection(cfg); try { return await fn(c); } finally { await c.close(); } };
const cursor = async rc => { const rows = await rc.getRows(500); await rc.close(); return lower(rows); };
const fail = (res, e) => {
  const m = /ORA-200\d\d: ([^\n]*)/.exec(e.message);
  res.status(m ? 400 : 500).json({ error: m ? m[1] : 'Server error: ' + e.message });
};
const OUT_RC = { dir: oracledb.BIND_OUT, type: oracledb.CURSOR };

const crypto = require('crypto');
const SECRET = process.env.AUTH_SECRET || crypto.randomBytes(32).toString('hex');   // set AUTH_SECRET so sessions survive restarts
const sign = u => {
  const p = Buffer.from(JSON.stringify({ ...u, exp: Date.now() + 7 * 864e5 })).toString('base64url');
  return p + '.' + crypto.createHmac('sha256', SECRET).update(p).digest('base64url');
};
function verify(t) {
  try {
    const [p, s] = t.split('.');
    const e = crypto.createHmac('sha256', SECRET).update(p).digest('base64url');
    if (!s || s.length !== e.length || !crypto.timingSafeEqual(Buffer.from(s), Buffer.from(e))) return null;
    const u = JSON.parse(Buffer.from(p, 'base64url'));
    return u.exp > Date.now() ? u : null;
  } catch { return null; }
}
app.use((req, res, next) => { req.user = verify((req.headers.authorization || '').replace('Bearer ', '')); next(); });
function needAuth(req, res, next) { req.user ? next() : res.status(401).json({ error: 'Please log in to continue' }); }
function needAdmin(req, res, next) { req.user && req.user.role === 'ADMIN' ? next() : res.status(403).json({ error: 'Admin access only' }); }

app.post('/api/register', async (req, res) => {
  const { name, email, password } = req.body;
  try {
    res.json(await run(async c => {
      const r = await c.execute(`BEGIN pkg_auth.register_user(:n,:e,:p,:id); END;`,
        { n: name, e: email, p: password, id: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER } });
      const user = { id: r.outBinds.id, name: name.trim(), email: email.toLowerCase(), role: 'USER' };
      return { user, token: sign(user) };
    }));
  } catch (e) { fail(res, e); }
});

app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    res.json(await run(async c => {
      const r = await c.execute(`BEGIN pkg_auth.login_user(:e,:p,:id,:n,:role); END;`,
        { e: email, p: password, id: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
          n: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 100 },
          role: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 } });
      const user = { id: r.outBinds.id, name: r.outBinds.n, email: email.toLowerCase(), role: r.outBinds.role };
      return { user, token: sign(user) };
    }));
  } catch (e) { fail(res, e); }
});

app.get('/api/me', needAuth, (req, res) => { const { id, name, email, role } = req.user; res.json({ id, name, email, role }); });

app.get('/api/my-bookings', needAuth, async (req, res) => {
  try {
    res.json(await run(async c => {
      const r = await c.execute(`BEGIN pkg_auth.my_bookings(:u, :rc); END;`, { u: req.user.id, rc: OUT_RC });
      return cursor(r.outBinds.rc);
    }));
  } catch (e) { fail(res, e); }
});


app.get('/api/airports', async (_, res) => {
  try { res.json(await run(async c => lower((await c.execute('SELECT code, city, name FROM airports ORDER BY city')).rows))); }
  catch (e) { fail(res, e); }
});

app.get('/api/flights', async (req, res) => {
  const { from, to, date } = req.query;
  try {
    res.json(await run(async c => {
      const r = await c.execute(
        `BEGIN pkg_airline.search_flights(:f, :t, TO_DATE(:d,'YYYY-MM-DD'), :rc); END;`,
        { f: from, t: to, d: date, rc: OUT_RC });
      return cursor(r.outBinds.rc);
    }));
  } catch (e) { fail(res, e); }
});

app.post('/api/book', async (req, res) => {
  const { flightId, name, email, phone } = req.body;
  try {
    res.json(await run(async c => {
      const r = await c.execute(
        `BEGIN pkg_airline.book_ticket(:id,:n,:e,:p,:pnr,:seat,:fare); END;`,
        { id: flightId, n: name, e: email, p: phone || null,
          pnr: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 },
          seat: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 },
          fare: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER } });
      return r.outBinds;
    }));
  } catch (e) { fail(res, e); }
});

app.get('/api/booking/:pnr', async (req, res) => {
  try {
    const rows = await run(async c => {
      const r = await c.execute(`BEGIN pkg_airline.get_booking(:p, :rc); END;`, { p: req.params.pnr, rc: OUT_RC });
      return cursor(r.outBinds.rc);
    });
    rows.length ? res.json(rows[0]) : res.status(404).json({ error: 'PNR not found' });
  } catch (e) { fail(res, e); }
});

app.post('/api/cancel/:pnr', async (req, res) => {
  try {
    res.json(await run(async c => {
      const r = await c.execute(`BEGIN pkg_airline.cancel_ticket(:p, :rf); END;`,
        { p: req.params.pnr, rf: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER } });
      return { refund: r.outBinds.rf };
    }));
  } catch (e) { fail(res, e); }
});

app.get('/api/seats/:id', async (req, res) => {
  try {
    res.json(await run(async c => {
      const r = await c.execute(`BEGIN get_seats(:id, :rc); END;`, { id: req.params.id, rc: OUT_RC });
      return (await cursor(r.outBinds.rc)).map(x => x.seat_no);
    }));
  } catch (e) { fail(res, e); }
});

app.post('/api/book2', needAuth, async (req, res) => {
  const b = req.body;
  try {
    res.json(await run(async c => {
      const r = await c.execute(
        `BEGIN book_seat(:id,:n,:e,:p,:cls,:bag,:meal,:seat,:pnr,:fare);
         UPDATE bookings SET user_id = :uid WHERE pnr = :pnr; COMMIT; END;`,
        { id: b.flightId, n: b.name, e: b.email, p: b.phone || null, cls: b.cls || 'ECONOMY',
          uid: req.user.id, bag: b.bag || 15, meal: b.meal || 'NONE',
          seat: { dir: oracledb.BIND_INOUT, type: oracledb.STRING, val: b.seat || null, maxSize: 10 },
          pnr:  { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 },
          fare: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER } });
      return r.outBinds;
    }));
  } catch (e) { fail(res, e); }
});

app.get('/api/stats', needAuth, needAdmin, async (_, res) => {
  try {
    res.json(await run(async c => lower((await c.execute(
      `SELECT * FROM v_flight_revenue WHERE tickets_sold > 0 ORDER BY revenue DESC FETCH FIRST 10 ROWS ONLY`)).rows)));
  } catch (e) { fail(res, e); }
});

app.listen(3000, () => console.log('SkyBook running at http://localhost:3000'));
