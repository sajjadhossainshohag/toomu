// node --test tool/crash-relay
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import worker, { signature, keyFrames, errorType, title } from './worker.js';

// Workers have Web Crypto globally; Node 18 keeps it in node:crypto.
globalThis.crypto ??= webcrypto;

const env = { APP_KEY: 'k' };
const report = (extra = {}) => ({
  kind: 'dart',
  platform: 'android',
  version: 'v2026.11.22-2242',
  os: 'Android 14',
  device: 'Samsung SM-S918B',
  message: "PathNotFoundException: Cannot open file, path = '<path>'",
  stack: '#0      DownloadService._downloadYtDlp (package:toomu/app/services/download_service.dart:1093:5)\n#1      DownloadService._start (package:toomu/app/services/download_service.dart:705:9)',
  ...extra,
});
const post = (data, headers = { 'x-toomu-key': 'k' }, e = env) =>
  worker.fetch(new Request('https://relay.example/report', { method: 'POST', headers, body: typeof data === 'string' ? data : JSON.stringify(data) }), e);

let calls;
beforeEach(() => {
  calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return Response.json({});
  };
});

test('a new crash is stored in D1 with its signature, title and device; nothing goes over the network', async () => {
  const e = { ...env, DB: fakeD1() };
  const res = await post(report(), undefined, e);
  assert.equal(res.status, 200);
  const out = await res.json();
  assert.equal(out.duplicate, false);
  assert.match(out.id, /^[0-9a-f]{10}$/);
  const row = e.DB.crashes.get(out.id);
  assert.match(row.title, /^PathNotFoundException: Cannot open file/);
  assert.equal(row.count, 1);
  assert.equal(row.first_version, 'v2026.11.22-2242');
  assert.equal(row.last_where, 'Android · Android 14 · Samsung SM-S918B');
  assert.equal(calls.length, 0);
});

test('the same crash again bumps its count and last version instead of adding a row', async () => {
  const e = { ...env, DB: fakeD1() };
  await post(report(), undefined, e);
  const res = await post(report({ version: 'v2026.12.01-1000', stack: report().stack.replace(':1093:5', ':1200:9') }), undefined, e);
  assert.equal((await res.json()).duplicate, true);
  assert.equal(e.DB.crashes.size, 1);
  const [row] = e.DB.crashes.values();
  assert.equal(row.count, 2);
  assert.equal(row.first_version, 'v2026.11.22-2242');
  assert.equal(row.last_version, 'v2026.12.01-1000');
});

test('without the app key, oversized or malformed reports are refused and nothing is stored', async () => {
  const e = { ...env, DB: fakeD1() };
  assert.equal((await post(report(), {}, e)).status, 403);
  assert.equal((await post('x'.repeat(40 * 1024), undefined, e)).status, 413);
  assert.equal((await post('{nope', undefined, e)).status, 400);
  assert.equal((await post(report({ kind: 'other' }), undefined, e)).status, 400);
  assert.equal((await post(report({ message: '' }), undefined, e)).status, 400);
  assert.equal(e.DB.crashes.size, 0);
});

test('without a database a report is refused for now (the app keeps it for the next start)', async () => {
  assert.equal((await post(report())).status, 503);
});

test('line numbers and versions do not change the signature; a different error does', async () => {
  const a = await signature(report());
  const moved = await signature(report({ stack: report().stack.replace(':1093:5', ':1200:9'), version: 'v2' }));
  const other = await signature(report({ message: 'StateError: Bad state: no element' }));
  assert.equal(a, moved);
  assert.notEqual(a, other);
});

test("the app's own frames identify a crash; error types are read from the message", () => {
  const stack = '#0 dart:async _rootRun\n#1 MyWidget.build (package:toomu/a.dart:3:1)\nat io.github.toomu.MainActivity.onCreate(MainActivity.kt:12)';
  assert.deepEqual(keyFrames(stack), ['MyWidget.build (package:toomu/a.dart)', 'at io.github.toomu.MainActivity.onCreate(MainActivity.kt)']);
  assert.equal(errorType('java.lang.IllegalStateException: boom'), 'java.lang.IllegalStateException');
  assert.equal(errorType("Null check operator used on a null value"), 'Null');
  assert.ok(title({ message: 'x'.repeat(200) }).length <= 90);
});

// ------------------------------------------------------------------ user count

/** Just enough of D1 for the usage and crashes tables. */
function fakeD1() {
  const rows = new Map();
  const crashes = new Map();
  return {
    rows,
    crashes,
    async batch(stmts) {
      return Promise.all(stmts.map((s) => s.run()));
    },
    prepare(sql) {
      const stmt = (args = []) => ({
        bind: (...a) => stmt(a),
        async first() {
          if (!sql.trim().startsWith('INSERT INTO crashes')) return null;
          const [sig, kind, platform, title, message, stack, version, now, where, build] = args;
          const old = crashes.get(sig);
          const r = old
            ? { ...old, count: old.count + 1, last_version: version, last_seen: now, last_where: where, build }
            : { sig, kind, platform, title, message, stack, first_version: version, last_version: version, first_seen: now, last_seen: now, count: 1, last_where: where, build };
          crashes.set(sig, r);
          return { count: r.count };
        },
        async run() {
          if (!sql.startsWith('INSERT INTO usage')) return {};
          const [day, platform, version, week, month] = args;
          const k = `${day}|${platform}|${version}`;
          const r = rows.get(k) ?? { day, platform, version, daily: 0, weekly: 0, monthly: 0 };
          r.daily += 1; r.weekly += week; r.monthly += month;
          rows.set(k, r);
          return {};
        },
        async all() {
          return { results: [...rows.values()].filter((r) => r.day >= args[0]) };
        },
      });
      return stmt();
    },
  };
}

const ping = (e, data, headers = { 'x-toomu-key': 'k' }) =>
  worker.fetch(new Request('https://relay.example/ping', { method: 'POST', headers, body: JSON.stringify(data) }), e);

test('daily pings are counted without any ID: users today, this week and this month', async () => {
  const e = { ...env, DB: fakeD1() };
  await ping(e, { platform: 'android', version: 'v1', week: true, month: true }); // first use this month
  await ping(e, { platform: 'android', version: 'v1', week: false, month: false }); // someone back again
  await ping(e, { platform: 'windows', version: 'v1', week: true, month: false });
  const s = await (await worker.fetch(new Request('https://relay.example/stats'), e)).json();
  assert.equal(s.today, 3);
  assert.equal(s.week, 2);
  assert.equal(s.month, 1);
  assert.deepEqual(s.platforms, { android: 2, windows: 1 });
  assert.deepEqual(s.versionsToday, { 'android v1': 2, 'windows v1': 1 });
});

test('pings without the app key or with junk are refused and not counted', async () => {
  const e = { ...env, DB: fakeD1() };
  assert.equal((await ping(e, { platform: 'android', version: 'v1' }, {})).status, 403);
  assert.equal((await ping(e, { platform: 'mac', version: 'v1' })).status, 400);
  assert.equal((await ping(e, { platform: 'android' })).status, 400);
  assert.equal(e.DB.rows.size, 0);
});
