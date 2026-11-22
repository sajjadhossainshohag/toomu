// Toomu crash relay and user count (Cloudflare Worker).
//
// POST /report  a crash report → a row in D1's `crashes` table, one per distinct crash (its
//               signature): the same crash again only bumps its count, last version and device.
//               Private: read them in the Cloudflare dashboard (D1 → toomu-usage → Console), e.g.
//               SELECT sig, title, count, last_version, last_seen FROM crashes ORDER BY last_seen DESC
// POST /ping    the app's once-a-day "used today" ping, with no ID of any kind: just the platform,
//               the version, the OS version, the phone model and whether it's its first ping
//               this week / month. Counted in D1, so
//               daily, weekly and monthly users are sums, not lookups of anyone.
// GET  /stats   those counts (public: totals only).
// GET  /crashes the stored crashes, newest first, for the website's stats page. Needs the
//               X-Admin-Key header to match ADMIN_KEY (a secret): crash reports are private.
//
// Settings (wrangler.toml / dashboard):
//   APP_KEY       the key the app sends in X-Toomu-Key (not a secret: it only keeps out
//                 random traffic; the size limits and rate limits do the rest)
//   ADMIN_KEY     secret: the key the stats page sends to read /crashes (unset: /crashes is off)
//   DB            D1 database binding for crashes and the user count (tables created on first use)

const MAX_BODY = 32 * 1024;
const PER_IP_PER_HOUR = 20;
const KINDS = { flutter: 'Flutter error', dart: 'Uncaught Dart error', native: 'Android crash (Kotlin/Java)' };
const PLATFORMS = ['android', 'windows'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/' && request.method === 'GET') return json({ ok: true, service: 'toomu crash relay' });
    if (url.pathname === '/stats' && request.method === 'GET') return stats(env, url);
    if (url.pathname === '/ping') return ping(request, env);
    if (url.pathname === '/crashes') return crashes(request, env);
    if (url.pathname !== '/report') return json({ error: 'not found' }, 404);
    if (request.method !== 'POST') return json({ error: 'POST only' }, 405);
    if (!env.APP_KEY || request.headers.get('x-toomu-key') !== env.APP_KEY) return json({ error: 'forbidden' }, 403);

    const text = await request.text();
    if (text.length > MAX_BODY) return json({ error: 'too large' }, 413);
    let report;
    try {
      report = validate(JSON.parse(text));
    } catch (e) {
      return json({ error: `bad report: ${e.message}` }, 400);
    }

    const ip = request.headers.get('cf-connecting-ip') || 'unknown';
    if (await overLimit(`ip/${ip}`, PER_IP_PER_HOUR, 3600)) return json({ error: 'slow down' }, 429);

    const d = await db(env);
    if (!d) return json({ error: 'no database' }, 503);
    const sig = await signature(report);
    const now = new Date().toISOString();
    const row = await d
      .prepare(
        `INSERT INTO crashes (sig, kind, platform, title, message, stack, first_version, last_version,
           first_seen, last_seen, count, last_where, build)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, ?8, ?8, 1, ?9, ?10)
         ON CONFLICT (sig) DO UPDATE SET count = count + 1, last_version = excluded.last_version,
           last_seen = excluded.last_seen, last_where = excluded.last_where, build = excluded.build
         RETURNING count`,
      )
      .bind(sig, report.kind, report.platform, title(report), report.message, report.stack, report.version, now, where(report), report.build)
      .first();
    return json({ ok: true, id: sig, duplicate: (row?.count ?? 1) > 1 });
  },
};

// ------------------------------------------------------------------ report

function str(v, name, max, { required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) throw new Error(`${name} missing`);
    return '';
  }
  if (typeof v !== 'string') throw new Error(`${name} must be text`);
  return v.length > max ? `${v.slice(0, max)}…` : v;
}

export function validate(r) {
  if (!r || typeof r !== 'object') throw new Error('not an object');
  if (!KINDS[r.kind]) throw new Error('unknown kind');
  if (!PLATFORMS.includes(r.platform)) throw new Error('unknown platform');
  return {
    kind: r.kind,
    platform: r.platform,
    message: str(r.message, 'message', 2000),
    stack: str(r.stack, 'stack', 16000, { required: false }),
    version: str(r.version, 'version', 40),
    build: str(r.build, 'build', 60, { required: false }),
    os: str(r.os, 'os', 80, { required: false }),
    device: str(r.device, 'device', 80, { required: false }),
  };
}

/** Frames that identify the crash: the app's own first (line numbers dropped, they move between versions). */
export function keyFrames(stack) {
  const frames = stack
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('#') || l.startsWith('at '))
    .map((l) => l.replace(/^#\d+\s+/, '').replace(/:\d+(:\d+)?/g, '').replace(/\s+/g, ' '));
  const own = frames.filter((l) => /package:toomu\/|io\.github\.toomu\./.test(l));
  return (own.length ? own : frames).slice(0, 6);
}

/** The error's type: "PathNotFoundException: Cannot open…" → "PathNotFoundException". */
export function errorType(message) {
  const first = message.split('\n')[0];
  const m = first.match(/^([A-Za-z_$][\w$.]*?(?:Exception|Error|Throwable|Failure)|[A-Z][\w$.]+)(?=[:(\s]|$)/);
  return m ? m[1] : first.replace(/['"].*?['"]/g, '').replace(/\d+/g, '').slice(0, 60);
}

export async function signature(r) {
  const basis = [r.kind, errorType(r.message), ...keyFrames(r.stack)].join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(basis));
  return [...new Uint8Array(digest)].slice(0, 5).map((b) => b.toString(16).padStart(2, '0')).join('');
}

const where = (r) => [r.platform === 'android' ? 'Android' : 'Windows', r.os, r.device].filter(Boolean).join(' · ');

/** The error's first line, short: "PathNotFoundException: Cannot open file…". */
export function title(r) {
  const first = r.message.split('\n')[0].replace(/\s+/g, ' ').trim();
  return first.length > 90 ? `${first.slice(0, 89)}…` : first;
}

// ------------------------------------------------------------------ D1: crashes and user count

const PINGS_PER_IP_PER_HOUR = 30; // a household or office shares one address

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS usage (
    day TEXT NOT NULL, platform TEXT NOT NULL, version TEXT NOT NULL,
    daily INTEGER NOT NULL DEFAULT 0, weekly INTEGER NOT NULL DEFAULT 0, monthly INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day, platform, version))`,
  `CREATE TABLE IF NOT EXISTS usage_devices (
    day TEXT NOT NULL, platform TEXT NOT NULL, os TEXT NOT NULL, device TEXT NOT NULL,
    daily INTEGER NOT NULL DEFAULT 0, monthly INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day, platform, os, device))`,
  `CREATE TABLE IF NOT EXISTS crashes (
    sig TEXT PRIMARY KEY, kind TEXT NOT NULL, platform TEXT NOT NULL, title TEXT NOT NULL,
    message TEXT NOT NULL, stack TEXT NOT NULL, first_version TEXT NOT NULL, last_version TEXT NOT NULL,
    first_seen TEXT NOT NULL, last_seen TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 1,
    last_where TEXT NOT NULL, build TEXT NOT NULL DEFAULT '')`,
];

let schemaReady = false;
async function db(env) {
  if (!env.DB) return null;
  if (!schemaReady) {
    await env.DB.batch(SCHEMA.map((sql) => env.DB.prepare(sql)));
    schemaReady = true;
  }
  return env.DB;
}

export const today = (now = new Date()) => now.toISOString().slice(0, 10);

async function ping(request, env) {
  if (request.method !== 'POST') return json({ error: 'POST only' }, 405);
  if (!env.APP_KEY || request.headers.get('x-toomu-key') !== env.APP_KEY) return json({ error: 'forbidden' }, 403);
  const text = await request.text();
  if (text.length > 1024) return json({ error: 'too large' }, 413);
  let p;
  try {
    p = JSON.parse(text);
    if (!PLATFORMS.includes(p.platform)) throw new Error('unknown platform');
    p.version = str(p.version, 'version', 40);
    p.os = str(p.os, 'os', 80, { required: false });
    p.device = str(p.device, 'device', 80, { required: false });
  } catch (e) {
    return json({ error: `bad ping: ${e.message}` }, 400);
  }
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (await overLimit(`ping/${ip}`, PINGS_PER_IP_PER_HOUR, 3600)) return json({ error: 'slow down' }, 429);
  const d = await db(env);
  if (!d) return json({ error: 'no database' }, 503);
  await d
    .prepare(
      `INSERT INTO usage (day, platform, version, daily, weekly, monthly) VALUES (?1, ?2, ?3, 1, ?4, ?5)
       ON CONFLICT (day, platform, version) DO UPDATE SET
         daily = daily + 1, weekly = weekly + excluded.weekly, monthly = monthly + excluded.monthly`,
    )
    .bind(today(), p.platform, p.version, p.week ? 1 : 0, p.month ? 1 : 0)
    .run();
  await d
    .prepare(
      `INSERT INTO usage_devices (day, platform, os, device, daily, monthly) VALUES (?1, ?2, ?3, ?4, 1, ?5)
       ON CONFLICT (day, platform, os, device) DO UPDATE SET daily = daily + 1, monthly = monthly + excluded.monthly`,
    )
    .bind(today(), p.platform, p.os, p.device, p.month ? 1 : 0)
    .run();
  return json({ ok: true });
}

/** Daily users for the last 30 days; this week's and this month's users; today's by version. */
async function stats(env, url) {
  const d = await db(env);
  if (!d) return json({ error: 'no database' }, 503);
  const now = new Date();
  const since = today(new Date(now.getTime() - 29 * 86400000));
  const monday = new Date(now);
  monday.setUTCDate(now.getUTCDate() - ((now.getUTCDay() + 6) % 7));
  const rows = (await d.prepare('SELECT day, platform, version, daily, weekly, monthly FROM usage WHERE day >= ?1').bind(since).all()).results;
  const sum = (list, field) => list.reduce((n, r) => n + r[field], 0);
  const days = {};
  for (const r of rows) days[r.day] = (days[r.day] ?? 0) + r.daily;
  const thisDay = today(now);
  const versions = {};
  for (const r of rows.filter((r) => r.day === thisDay)) versions[`${r.platform} ${r.version}`] = (versions[`${r.platform} ${r.version}`] ?? 0) + r.daily;
  const body = {
    today: days[thisDay] ?? 0,
    week: sum(rows.filter((r) => r.day >= today(monday)), 'weekly'),
    month: sum(rows.filter((r) => r.day.slice(0, 7) === thisDay.slice(0, 7)), 'monthly'),
    platforms: {
      android: sum(rows.filter((r) => r.day === thisDay && r.platform === 'android'), 'daily'),
      windows: sum(rows.filter((r) => r.day === thisDay && r.platform === 'windows'), 'daily'),
    },
    versionsToday: versions,
    days,
    ...(await deviceStats(d, thisDay)),
  };
  return new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'cache-control': 'no-store' },
  });
}

/** Users by phone model and by OS version: today, and this month (first ping of the month). */
async function deviceStats(d, thisDay) {
  const rows = (
    await d.prepare('SELECT day, platform, os, device, daily, monthly FROM usage_devices WHERE day >= ?1').bind(`${thisDay.slice(0, 7)}-01`).all()
  ).results;
  const group = (keyOf) => {
    const m = new Map();
    for (const r of rows) {
      const k = keyOf(r);
      const g = m.get(k) ?? { name: k, platform: r.platform, today: 0, month: 0 };
      if (r.day === thisDay) g.today += r.daily;
      g.month += r.monthly;
      m.set(k, g);
    }
    return [...m.values()].sort((a, b) => b.month - a.month || b.today - a.today || a.name.localeCompare(b.name)).slice(0, 50);
  };
  return {
    devices: group((r) => r.device || (r.platform === 'windows' ? 'Windows PC' : 'Unknown')),
    osVersions: group((r) => r.os || 'Unknown'),
  };
}

// ------------------------------------------------------------------ crash list (stats page)

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, OPTIONS',
  'access-control-allow-headers': 'x-admin-key',
  'access-control-max-age': '86400',
};

/** Equal-time string compare, so the key can't be guessed a character at a time. */
function sameKey(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function crashes(request, env) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (request.method !== 'GET') return json({ error: 'GET only' }, 405, CORS);
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (await overLimit(`admin/${ip}`, 60, 3600)) return json({ error: 'slow down' }, 429, CORS);
  if (!env.ADMIN_KEY || !sameKey(request.headers.get('x-admin-key'), env.ADMIN_KEY)) return json({ error: 'forbidden' }, 403, CORS);
  const d = await db(env);
  if (!d) return json({ error: 'no database' }, 503, CORS);
  const rows = (
    await d
      .prepare(
        `SELECT sig, kind, platform, title, message, stack, first_version, last_version, first_seen, last_seen,
           count, last_where, build FROM crashes ORDER BY last_seen DESC LIMIT 200`,
      )
      .all()
  ).results;
  return json({ crashes: rows.map((r) => ({ ...r, kindLabel: KINDS[r.kind] ?? r.kind })) }, 200, { ...CORS, 'cache-control': 'no-store' });
}

// ------------------------------------------------------------------ rate limits (Cache API)

const cache = () => globalThis.caches?.default ?? null;
const memoUrl = (k) => `https://toomu-crash-relay.internal/${k}`;

async function overLimit(key, max, seconds) {
  const c = cache();
  if (!c) return false;
  const bucket = Math.floor(Date.now() / 1000 / seconds);
  const req = new Request(memoUrl(`${key}/${bucket}`));
  const hit = await c.match(req);
  const count = hit ? Number(await hit.text()) || 0 : 0;
  if (count >= max) return true;
  await c.put(req, new Response(String(count + 1), { headers: { 'cache-control': `max-age=${seconds}` } }));
  return false;
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', ...headers } });
}
