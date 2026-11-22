import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/services/crash_report_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

/// Crash reports: saved at once, scrubbed, sent to the crash relay (a local fake here).
void main() {
  late Directory dir;
  late HttpServer relay;
  late List<({Map<String, dynamic> body, String? key})> received;
  var answer = 200;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('toomu_crash_');
    received = [];
    answer = 200;
    relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((req) async {
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      received.add((body: body, key: req.headers.value('x-toomu-key')));
      req.response.statusCode = answer;
      await req.response.close();
    });
  });

  tearDown(() async {
    await relay.close(force: true);
    await dir.delete(recursive: true);
  });

  CrashReporter reporter({String? endpoint}) => CrashReporter(
        dir: Directory('${dir.path}/crash_reports'),
        endpoint: endpoint ?? 'http://127.0.0.1:${relay.port}/report',
        appKey: 'key-1',
        version: 'v2026.11.22-2242',
        build: 'b7',
        platform: 'android',
        os: 'Android 14',
        device: 'Samsung SM-S918B',
      );

  StackTrace stack(String frame) => StackTrace.fromString('#0      $frame\n#1      _rootRun (dart:async/zone.dart:1399:13)');

  test('a crash is saved the moment it happens and sent with the app and phone details', () async {
    final r = reporter();
    final file = r.save('dart', StateError('Bad state: no element'), stack('Foo.bar (package:toomu/app/foo.dart:12:3)'));
    expect(file!.existsSync(), isTrue, reason: 'on disk before anything async: the app may be dying');
    expect(await r.sendPending({}), 1);
    final got = received.single;
    expect(got.key, 'key-1');
    expect(got.body, containsPair('kind', 'dart'));
    expect(got.body, containsPair('platform', 'android'));
    expect(got.body, containsPair('version', 'v2026.11.22-2242'));
    expect(got.body, containsPair('device', 'Samsung SM-S918B'));
    expect(got.body['message'], 'Bad state: Bad state: no element');
    expect(got.body['stack'], contains('package:toomu/app/foo.dart:12:3'));
    expect(r.pending(), isEmpty);
  });

  test('reports carry no links, file paths or e-mail addresses', () {
    final text = CrashReporter.scrub(
      "PathNotFoundException: Cannot open file, path = '/storage/emulated/0/Download/Toomu/Video/My holiday clip.mp4' "
      'while fetching https://rr3.googlevideo.com/videoplayback?id=abc from C:\\Users\\Rahim\\Downloads\\Toomu\\x.mp4 '
      'for rahim@example.com at /storage/emulated/0/Movies/secret.mkv',
    );
    expect(text, isNot(contains('holiday')));
    expect(text, isNot(contains('googlevideo')));
    expect(text, isNot(contains('Rahim')));
    expect(text, isNot(contains('rahim@')));
    expect(text, isNot(contains('secret')));
    expect(text, contains("path = '<path>'"));
    expect(CrashReporter.scrub('#3 Foo.bar (package:toomu/app/foo.dart:12:3)'), '#3 Foo.bar (package:toomu/app/foo.dart:12:3)');
  });

  test('network errors and pictures that failed to load are not reported', () {
    final r = reporter();
    expect(r.save('dart', const SocketException('Connection refused'), null), isNull);
    expect(r.save('dart', TimeoutException('slow'), null), isNull);
    expect(r.save('dart', DioException(requestOptions: RequestOptions()), null), isNull);
    expect(r.save('flutter', Exception('404'), null, library: 'image resource service'), isNull);
    expect(r.pending(), isEmpty);
  });

  test("offline or a busy relay keeps the report for next time; one the relay refused is dropped", () async {
    final offline = reporter(endpoint: 'http://127.0.0.1:9/report');
    offline.save('dart', StateError('a'), null);
    expect(await offline.sendPending({}), 0);
    expect(offline.pending(), hasLength(1));

    answer = 503;
    final r = reporter();
    expect(await r.sendPending({}), 0);
    expect(r.pending(), hasLength(1), reason: 'the relay was busy');

    answer = 400;
    expect(await r.sendPending({}), 0);
    expect(r.pending(), isEmpty, reason: 'a bad report would be refused forever');
  });

  test('the same error is sent once per version', () async {
    final r = reporter();
    final sent = <String>{};
    r.save('dart', StateError('same'), stack('Foo.bar (package:toomu/app/foo.dart:12:3)'));
    await r.sendPending(sent);
    r.save('dart', StateError('same'), stack('Foo.bar (package:toomu/app/foo.dart:12:3)'));
    expect(await r.sendPending(sent), 0);
    expect(received, hasLength(1));
    expect(r.pending(), isEmpty);
  });

  test('an error in a loop fills at most a few files', () {
    final r = reporter();
    for (var i = 0; i < 50; i++) {
      r.save('dart', StateError('loop $i'), null);
    }
    expect(r.pending(), hasLength(CrashReporter.maxPending));
  });

  test("Android's native crash files are sent too, scrubbed", () async {
    final r = reporter();
    Directory('${dir.path}/crash_reports').createSync();
    // As CrashFile.kt writes them.
    File('${dir.path}/crash_reports/1700000000000-native.json').writeAsStringSync(jsonEncode({
      'kind': 'native',
      'message': "java.io.FileNotFoundException: '/storage/emulated/0/Download/Toomu/a b.mp4'",
      'stack': 'java.io.FileNotFoundException\n\tat io.github.toomu.MainActivity.onCreate(MainActivity.kt:12)',
      'time': 1700000000000,
    }));
    File('${dir.path}/crash_reports/1700000000001-native.json').writeAsStringSync('{"kind":"nat'); // cut off by the crash
    expect(await r.sendPending({}), 1);
    expect(received.single.body['kind'], 'native');
    expect(received.single.body['message'], "java.io.FileNotFoundException: '<path>'");
    expect(r.pending(), isEmpty);
  });

  test('turning crash reports off in Settings drops what was waiting', () {
    final r = reporter();
    r.save('dart', StateError('x'), null);
    r.dropPending();
    expect(r.pending(), isEmpty);
    expect(received, isEmpty);
  });

  test('crash reports are sent without asking: on by default for a new install', () async {
    final storageDir = await useTempStorageDir();
    addTearDown(() async {
      await Get.deleteAll(force: true);
      await deleteTempStorageDir(storageDir);
    });
    Get.put(StorageService(await tempBox('crash_default', storageDir)));
    final settings = Get.put(SettingsService().init());
    expect(settings.crashReports.value, isTrue);
    settings.setCrashReports(false);
    expect(SettingsService().init().crashReports.value, isFalse, reason: 'turning it off is remembered');
  });
}
