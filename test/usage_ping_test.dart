import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/services/usage_ping.dart';

/// The anonymous daily user-count ping.
void main() {
  late HttpServer relay;
  late List<Map<String, dynamic>> pings;
  var answer = 200;

  setUp(() async {
    pings = [];
    answer = 200;
    relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((req) async {
      pings.add({'key': req.headers.value('x-toomu-key'), ...jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>});
      req.response.statusCode = answer;
      await req.response.close();
    });
  });
  tearDown(() => relay.close(force: true));

  UsagePing pinger(Map<String, String> store, {String? endpoint}) => UsagePing(
        endpoint: endpoint ?? 'http://127.0.0.1:${relay.port}/ping',
        appKey: 'key-1',
        platform: 'android',
        version: 'v2026.11.22-2242',
        os: 'Android 14',
        device: 'Samsung SM-S918B',
        lastDay: () => store['day'],
        saveDay: (d) => store['day'] = d,
      );

  test('one ping a day, with no ID: platform, version, OS, phone model and what is new this week and month', () async {
    final store = <String, String>{};
    final p = pinger(store);
    expect(await p.sendIfDue(DateTime.utc(2026, 11, 23, 9)), isTrue); // a Monday
    expect(await p.sendIfDue(DateTime.utc(2026, 11, 23, 20)), isFalse, reason: 'already counted today');
    expect(pings.single, {
      'key': 'key-1',
      'platform': 'android',
      'version': 'v2026.11.22-2242',
      'os': 'Android 14',
      'device': 'Samsung SM-S918B',
      'week': true,
      'month': true,
    });
    expect(pings.single.keys, isNot(contains('id')));
    expect(store['day'], '2026-11-23');
  });

  test('the next day in the same week and month counts as daily only', () {
    expect(UsagePing.plan(DateTime.utc(2026, 11, 24), '2026-11-23'), (due: true, week: false, month: false));
    expect(UsagePing.plan(DateTime.utc(2026, 11, 30), '2026-11-29'), (due: true, week: true, month: false)); // Sunday → Monday
    expect(UsagePing.plan(DateTime.utc(2026, 12, 1), '2026-11-30'), (due: true, week: false, month: true)); // same week, new month
    expect(UsagePing.plan(DateTime.utc(2026, 11, 24), '2026-11-24'), (due: false, week: false, month: false));
  });

  test("offline or refused: not marked as sent, so it's tried on the next start", () async {
    final store = <String, String>{};
    expect(await pinger(store, endpoint: 'http://127.0.0.1:9/ping').sendIfDue(DateTime.utc(2026, 11, 23)), isFalse);
    answer = 503;
    expect(await pinger(store).sendIfDue(DateTime.utc(2026, 11, 23)), isFalse);
    expect(store, isEmpty);
  });
}
