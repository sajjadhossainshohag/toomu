// node --test tool/crash-relay
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import worker, { signature, keyFrames, errorType, title } from './worker.js';

// Workers have Web Crypto globally; Node 18 keeps it in node:crypto.
globalThis.crypto ??= webcrypto;

const env = { APP_KEY: 'k', REPO: 'me/toomu', GITHUB_TOKEN: 't' };
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
const post = (data, headers = { 'x-toomu-key': 'k' }) =>
  worker.fetch(new Request('https://relay.example/report', { method: 'POST', headers, body: typeof data === 'string' ? data : JSON.stringify(data) }), env);

let calls;
let searchItems;
beforeEach(() => {
  calls = [];
  searchItems = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), method: init.method ?? 'GET', body: init.body ? JSON.parse(init.body) : null, auth: init.headers?.authorization });
    if (String(url).includes('/search/issues')) return Response.json({ items: searchItems });
    if (String(url).endsWith('/comments')) return Response.json({ id: 1 });
    return Response.json({ number: 42, html_url: 'https://github.com/me/toomu/issues/42' });
  };
});

test('a new crash opens an issue with the token, labelled crash', async () => {
  const res = await post(report());
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, issue: 42, url: 'https://github.com/me/toomu/issues/42' });
  const create = calls.find((c) => c.method === 'POST');
  assert.equal(create.url, 'https://api.github.com/repos/me/toomu/issues');
  assert.equal(create.auth, 'Bearer t');
  assert.deepEqual(create.body.labels, ['crash']);
  assert.match(create.body.title, /^Crash: PathNotFoundException: Cannot open file.* \[[0-9a-f]{10}\]$/);
  assert.match(create.body.body, /Toomu v2026\.11\.22-2242.*Android · Android 14 · Samsung SM-S918B/);
});

test('the same crash again is a comment on its issue, not a new issue', async () => {
  searchItems = [{ number: 7, html_url: 'https://github.com/me/toomu/issues/7', comments: 2 }];
  const res = await post(report({ version: 'v2026.12.01-1000' }));
  assert.equal((await res.json()).duplicate, true);
  assert.equal(calls.filter((c) => c.url.endsWith('/issues')).length, 0);
  const comment = calls.find((c) => c.url.endsWith('/issues/7/comments'));
  assert.match(comment.body.body, /Again in \*\*v2026\.12\.01-1000\*\*/);
});

test('a crash already commented on many times gets no more comments', async () => {
  searchItems = [{ number: 7, html_url: 'u', comments: 30 }];
  await post(report());
  assert.equal(calls.filter((c) => c.method === 'POST').length, 0);
});

test('without the app key, oversized or malformed reports are refused and nothing reaches GitHub', async () => {
  assert.equal((await post(report(), {})).status, 403);
  assert.equal((await post('x'.repeat(40 * 1024))).status, 413);
  assert.equal((await post('{nope')).status, 400);
  assert.equal((await post(report({ kind: 'other' }))).status, 400);
  assert.equal((await post(report({ message: '' }))).status, 400);
  assert.equal(calls.length, 0);
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
  assert.ok(title({ message: 'x'.repeat(200) }, 'abc').length < 110);
});

// ------------------------------------------------------------------ user count

/** Just enough of D1 for the usage table. */
function fakeD1() {
  const rows = new Map();
  return {
    rows,
    prepare(sql) {
      const stmt = (args = []) => ({
        bind: (...a) => stmt(a),
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
