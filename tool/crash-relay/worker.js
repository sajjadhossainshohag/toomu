// Toomu crash relay and user count (Cloudflare Worker).
//
// POST /report  a crash report → a GitHub issue on the repo, or a comment on the issue already
//               open for the same crash. The GitHub token lives here as a secret (GITHUB_TOKEN),
//               never in the app: anything shipped in an APK can be read.
// POST /ping    the app's once-a-day "used today" ping, with no ID of any kind: just the platform,
//               the version and whether it's its first ping this week / month. Counted in D1, so
//               daily, weekly and monthly users are sums, not lookups of anyone.
// GET  /stats   those counts (public: totals only).
//
// Settings (wrangler.toml / dashboard):
//   GITHUB_TOKEN  secret: fine-grained token, this repo only, Issues: read and write
//   REPO          "owner/name"
//   APP_KEY       the key the app sends in X-Toomu-Key (not a secret: it only keeps out
//                 random traffic; the size limits and rate limits do the rest)
//   DB            D1 database binding for the user count (its table is created on first use)

const MAX_BODY = 32 * 1024;
const PER_IP_PER_HOUR = 20;
const MAX_COMMENTS = 30; // a crash seen this often needs no more "again" comments
const KINDS = { flutter: 'Flutter error', dart: 'Uncaught Dart error', native: 'Android crash (Kotlin/Java)' };
const PLATFORMS = ['android', 'windows'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/' && request.method === 'GET') return json({ ok: true, service: 'toomu crash relay' });
    if (url.pathname === '/stats' && request.method === 'GET') return stats(env, url);
    if (url.pathname === '/ping') return ping(request, env);
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

    const sig = await signature(report);
    const gh = github(env);
    const known = (await recall(sig)) ?? (await gh.find(sig));
    if (known) {
      if (known.comments < MAX_COMMENTS) await gh.comment(known.number, againText(report));
      return json({ ok: true, issue: known.number, url: known.html_url, duplicate: true });
    }
    const issue = await gh.create(title(report, sig), body(report, sig));
    await remember(sig, issue);
    return json({ ok: true, issue: issue.number, url: issue.html_url });
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

const fence = (t) => t.replace(/```/g, 'ʼʼʼ');
const where = (r) => [r.platform === 'android' ? 'Android' : 'Windows', r.os, r.device].filter(Boolean).join(' · ');

export function title(r, sig) {
  const first = r.message.split('\n')[0].replace(/\s+/g, ' ').trim();
  const short = first.length > 90 ? `${first.slice(0, 89)}…` : first;
  return `Crash: ${short} [${sig}]`;
}

export function body(r, sig) {
  const lines = r.stack.split('\n');
  const stack = lines.length > 60 ? [...lines.slice(0, 60), `… ${lines.length - 60} more lines`].join('\n') : r.stack;
  return [
    `**Toomu ${r.version}**${r.build ? ` (${r.build})` : ''} on ${where(r)}`,
    `**Kind:** ${KINDS[r.kind]}`,
    '',
    '**Error**',
    '```text',
    fence(r.message),
    '```',
    ...(stack ? ['', '**Stack**', '```text', fence(stack), '```'] : []),
    '',
    `<sub>Sent by the app's crash reporter. Same crash again → a comment here. Signature \`${sig}\`.</sub>`,
  ].join('\n');
}

export const againText = (r) => `Again in **${r.version}** on ${where(r)}.`;


// ------------------------------------------------------------------ user count (D1)

const PINGS_PER_IP_PER_HOUR = 30; // a household or office shares one address

const SCHEMA = `CREATE TABLE IF NOT EXISTS usage (
  day TEXT NOT NULL, platform TEXT NOT NULL, version TEXT NOT NULL,
  daily INTEGER NOT NULL DEFAULT 0, weekly INTEGER NOT NULL DEFAULT 0, monthly INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, platform, version))`;

let schemaReady = false;
async function db(env) {
  if (!env.DB) return null;
  if (!schemaReady) {
    await env.DB.prepare(SCHEMA).run();
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
  };
  return new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'cache-control': 'max-age=300' },
  });
}

// ------------------------------------------------------------------ GitHub

function github(env) {
  const api = async (path, init = {}) => {
    const res = await fetch(`https://api.github.com${path}`, {
      ...init,
      headers: {
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        accept: 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        'user-agent': 'toomu-crash-relay',
        ...(init.body ? { 'content-type': 'application/json' } : {}),
      },
    });
    if (!res.ok) throw new Error(`GitHub ${res.status} on ${path}: ${(await res.text()).slice(0, 200)}`);
    return res.json();
  };
  return {
    async find(sig) {
      const q = encodeURIComponent(`${sig} in:title repo:${env.REPO} is:issue`);
      const r = await api(`/search/issues?q=${q}&per_page=1`);
      return r.items?.[0] ?? null;
    },
    create: (t, b) => api(`/repos/${env.REPO}/issues`, { method: 'POST', body: JSON.stringify({ title: t, body: b, labels: ['crash'] }) }),
    comment: (n, b) => api(`/repos/${env.REPO}/issues/${n}/comments`, { method: 'POST', body: JSON.stringify({ body: b }) }),
  };
}

// ------------------------------------------------------------------ small edge memory (Cache API)
// GitHub's search lags a minute or so behind a new issue: the issue is remembered here too,
// so a burst of the same crash doesn't open duplicates. Also holds the rate-limit counters.

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

async function recall(sig) {
  const hit = await cache()?.match(new Request(memoUrl(`sig/${sig}`)));
  return hit ? hit.json() : null;
}

async function remember(sig, issue) {
  await cache()?.put(
    new Request(memoUrl(`sig/${sig}`)),
    new Response(JSON.stringify({ number: issue.number, html_url: issue.html_url, comments: 0 }), {
      headers: { 'cache-control': 'max-age=86400', 'content-type': 'application/json' },
    }),
  );
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
}
