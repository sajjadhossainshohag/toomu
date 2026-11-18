import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/host_os.dart';
import 'package:toomu/app/data/providers/ytdlp/windows_ytdlp.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';

/// A stand-in yt-dlp.exe: a shell script that prints its version [tag],
/// echoes its arguments, writes a warning to stderr, hangs on `--hang` and
/// fails on `--fail`. [broken] never starts.
String fakeYtDlp(String tag, {bool broken = false}) => broken
    ? '#!/bin/sh\n# a release that crashes on start\nexit 1\n'
    : '''#!/bin/sh
if [ "\$1" = "--version" ]; then echo "$tag"; exit 0; fi
for a in "\$@"; do
  [ "\$a" = "--hang" ] && exec sleep 30
  [ "\$a" = "--fail" ] && { echo "ERROR: [youtube] abc: refused" >&2; exit 2; }
done
echo "ran: \$*"
echo "[download]  50.0% of 10MiB"
echo "WARNING: from stderr" >&2
exit 0
''';

/// github.com and the FFmpeg/Deno downloads, on 127.0.0.1.
class FakeGitHub {
  late HttpServer _server;
  String latest = '2026.10.26';
  bool latestBroken = false;
  final binaries = <String, String>{};
  int ffmpegStatus = 200;
  Completer<void>? holdFfmpeg;
  late List<int> ffmpegZip;
  late List<int> denoZip;
  final requests = <String>[];

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start(Directory tmp) async {
    ffmpegZip = await _zip(tmp, 'ffmpeg', {
      'ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe': 'ffmpeg',
      'ffmpeg-master-latest-win64-gpl/bin/ffprobe.exe': 'ffprobe',
      'ffmpeg-master-latest-win64-gpl/LICENSE.txt': 'GPL',
    });
    denoZip = await _zip(tmp, 'deno', {'deno.exe': 'deno'});
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  static Future<List<int>> _zip(Directory tmp, String name, Map<String, String> files) async {
    final src = await Directory('${tmp.path}/zip-$name').create();
    for (final e in files.entries) {
      final f = File('${src.path}/${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    final r = await Process.run('zip', ['-qr', '../$name.zip', '.'], workingDirectory: src.path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return File('${tmp.path}/$name.zip').readAsBytes();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requests.add('${req.method} $path');
    final res = req.response;
    if (path.endsWith('/releases/latest')) {
      if (latestBroken) {
        res.statusCode = 500;
      } else {
        res.statusCode = 302;
        res.headers.set('location', '$base/yt-dlp/yt-dlp/releases/tag/$latest');
      }
    } else if (path.contains('/releases/download/') && path.endsWith('/yt-dlp.exe')) {
      final tag = path.split('/')[path.split('/').length - 2];
      final body = binaries[tag];
      if (body == null) {
        res.statusCode = 404;
      } else {
        res.write(body);
      }
    } else if (path == '/ffmpeg.zip') {
      await holdFfmpeg?.future;
      res.statusCode = ffmpegStatus;
      if (ffmpegStatus == 200) res.add(ffmpegZip);
    } else if (path == '/deno.zip') {
      res.add(denoZip);
    } else {
      res.statusCode = 404;
    }
    await res.close();
  }

  int count(String what) => requests.where((r) => r.contains(what)).length;

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory tmp;
  late String tools;
  late FakeGitHub github;
  final made = <WindowsYtDlp>[];

  WindowsYtDlp bridge() {
    final y = WindowsYtDlp(
      toolsDir: () async => tools,
      github: github.base,
      ffmpegZip: github.base.resolve('/ffmpeg.zip'),
      denoZip: github.base.resolve('/deno.zip'),
      launch: (exe, args) => Process.start('sh', [exe, ...args]),
      unzip: (zip, out) async {
        final r = await Process.run('unzip', ['-q', zip, '-d', out]);
        if (r.exitCode != 0) throw ToolInstallException('${r.stderr}');
      },
      killTree: (p) async => p.kill(),
      minBinaryBytes: 20,
    );
    made.add(y);
    return y;
  }

  /// Waits until FFmpeg and Deno are in place (they install in the background).
  Future<void> extrasInstalled() async {
    for (var i = 0; i < 200; i++) {
      if (File('$tools/ffmpeg/ffmpeg.exe').existsSync() && File('$tools/deno.exe').existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('FFmpeg / Deno never installed');
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('winytdlp');
    tools = '${tmp.path}/tools';
    github = FakeGitHub();
    await github.start(tmp);
    github.binaries['2026.10.26'] = fakeYtDlp('2026.10.26');
  });

  tearDown(() async {
    final hold = github.holdFfmpeg;
    if (hold != null && !hold.isCompleted) hold.complete();
    for (final y in made) {
      await y.backgroundWork;
    }
    made.clear();
    await github.stop();
    tmp.deleteSync(recursive: true);
  });

  group('first launch', () {
    test('downloads the latest yt-dlp.exe and reports its version', () async {
      final y = bridge();
      expect(await y.init(), '2026.10.26');
      expect(File('$tools/yt-dlp.exe').existsSync(), isTrue);
      expect(github.count('GET /yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp.exe'), 1);
      // Installed from a known release: no catch-up update needed.
      expect(await y.needsUpdate(), isFalse);
    });

    test('FFmpeg and Deno follow in the background, unpacked from their zips', () async {
      final y = bridge();
      await y.init();
      // Not just until the files appear: the unpack folder is deleted after they are moved in.
      await y.backgroundWork;
      expect(File('$tools/ffmpeg/ffmpeg.exe').readAsStringSync(), 'ffmpeg');
      expect(File('$tools/ffmpeg/ffprobe.exe').readAsStringSync(), 'ffprobe');
      expect(File('$tools/deno.exe').readAsStringSync(), 'deno');
      // Only what's needed is kept; the unpack folder is gone.
      expect(File('$tools/ffmpeg/LICENSE.txt').existsSync(), isFalse);
      expect(Directory(tools).listSync().where((e) => e.path.contains('unpack-')), isEmpty);
    });

    test('a second launch uses the installed tools without downloading again', () async {
      await bridge().init();
      await extrasInstalled();
      github.requests.clear();
      expect(await bridge().init(), '2026.10.26');
      expect(github.requests, isEmpty);
    });

    test('offline on first launch: the next try installs it', () async {
      github.latestBroken = true;
      final y = bridge();
      await expectLater(y.init(), throwsA(isA<ToolInstallException>()));
      github.latestBroken = false;
      expect(await y.init(), '2026.10.26');
    });

    test('an error page instead of yt-dlp.exe is not installed', () async {
      github.binaries['2026.10.26'] = 'Not Found';
      await expectLater(bridge().init(), throwsA(isA<ToolInstallException>()));
      expect(File('$tools/yt-dlp.exe').existsSync(), isFalse);
    });

    test('an update cut short mid-swap gets the previous yt-dlp.exe back', () async {
      Directory(tools).createSync(recursive: true);
      File('$tools/yt-dlp.exe.old').writeAsStringSync(fakeYtDlp('2026.09.01'));
      expect(await bridge().init(), '2026.09.01');
      expect(github.count('yt-dlp.exe'), 0);
      expect(File('$tools/yt-dlp.exe').existsSync(), isTrue);
    });
  });

  group('runs', () {
    test('passes FFmpeg, Deno and the URL; output lines arrive while it runs', () async {
      final y = bridge();
      await y.init();
      await extrasInstalled();
      final lines = <String>[];
      final sub = y.lines.where((e) => e.id == 'a').listen((e) => lines.add(e.line));
      final r = await y.run('a', ['-f', 'ba', '--toomu-aria2c=8', 'https://youtu.be/x']);
      await sub.cancel();
      expect(r.ok, isTrue);
      expect(r.out, contains('--ffmpeg-location $tools/ffmpeg'));
      expect(r.out, contains('--js-runtimes deno:$tools/deno.exe'));
      expect(r.out, contains('-f ba https://youtu.be/x'));
      expect(r.out, isNot(contains('aria2c')));
      expect(r.err, contains('WARNING: from stderr'));
      expect(lines, containsAll(['[download]  50.0% of 10MiB', 'WARNING: from stderr']));
    });

    test('a failed run hands back its exit code and error text', () async {
      final y = bridge();
      await y.init();
      final r = await y.run('f', ['--skip-download', '--fail', 'u']);
      expect(r.ok, isFalse);
      expect(r.exitCode, 2);
      expect(r.err, contains('ERROR: [youtube] abc: refused'));
    });

    test('cancel stops a running yt-dlp and the run reports it as canceled', () async {
      final y = bridge();
      await y.init();
      await extrasInstalled();
      final run = y.run('h', ['--hang', 'u']);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await y.cancel('h'), isTrue);
      final r = await run.timeout(const Duration(seconds: 5));
      expect(r.canceled, isTrue);
      expect(await y.cancel('h'), isFalse); // nothing left to stop
    });

    test('a download canceled while FFmpeg is still downloading never starts', () async {
      github.holdFfmpeg = Completer<void>();
      var launches = 0;
      final y = WindowsYtDlp(
        toolsDir: () async => tools,
        github: github.base,
        ffmpegZip: github.base.resolve('/ffmpeg.zip'),
        denoZip: github.base.resolve('/deno.zip'),
        launch: (exe, args) {
          if (!args.contains('--version')) launches++;
          return Process.start('sh', [exe, ...args]);
        },
        unzip: (zip, out) async {
          final r = await Process.run('unzip', ['-q', zip, '-d', out]);
          if (r.exitCode != 0) throw ToolInstallException('${r.stderr}');
        },
        killTree: (p) async => p.kill(),
        minBinaryBytes: 20,
      );
      made.add(y);
      await y.init();
      final run = y.run('w', ['-f', 'bv+ba', 'u']);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await y.cancel('w'), isTrue, reason: 'it is waiting: the cancel is kept');
      github.holdFfmpeg!.complete();
      final r = await run.timeout(const Duration(seconds: 10));
      expect(r.canceled, isTrue);
      expect(launches, 0, reason: 'yt-dlp was never started');
    });

    test('a cancel when nothing runs does not stop the next run', () async {
      final y = bridge();
      await y.init();
      expect(await y.cancel('later'), isFalse);
      final r = await y.run('later', ['--skip-download', 'u']);
      expect(r.ok, isTrue);
    });

    test('a lookup does not wait for FFmpeg to download; a download does', () async {
      github.holdFfmpeg = Completer<void>();
      final y = bridge();
      await y.init();
      final lookup = await y
          .run('l', ['--dump-single-json', '--skip-download', 'u'])
          .timeout(const Duration(seconds: 5));
      expect(lookup.ok, isTrue);
      expect(lookup.out, isNot(contains('--ffmpeg-location')));

      var done = false;
      final download = y.run('d', ['-f', 'bv+ba', 'u']).whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(done, isFalse, reason: 'merging needs FFmpeg');
      github.holdFfmpeg!.complete();
      final r = await download.timeout(const Duration(seconds: 10));
      expect(r.out, contains('--ffmpeg-location'));
    });

    test('FFmpeg download failed: downloads still run, and the next one tries again', () async {
      github.ffmpegStatus = 404;
      final y = bridge();
      await y.init();
      final first = await y.run('d1', ['-f', 'ba', 'u']);
      expect(first.ok, isTrue);
      expect(first.out, isNot(contains('--ffmpeg-location')));

      github.ffmpegStatus = 200;
      final second = await y.run('d2', ['-f', 'ba', 'u']);
      expect(second.out, contains('--ffmpeg-location'));
      expect(github.count('/ffmpeg.zip'), greaterThanOrEqualTo(2));
    });
  });

  group('updates', () {
    test('same release as installed: already up to date, nothing downloaded', () async {
      final y = bridge();
      await y.init();
      github.requests.clear();
      expect(await y.update('stable'), 'ALREADY_UP_TO_DATE');
      expect(github.count('yt-dlp.exe'), 0);
    });

    test('a new release is downloaded and swapped in', () async {
      final y = bridge();
      await y.init();
      github.latest = '2026.11.15';
      github.binaries['2026.11.15'] = fakeYtDlp('2026.11.15');
      expect(await y.update('stable'), 'DONE');
      expect(await y.version(), '2026.11.15');
      expect(File('$tools/yt-dlp.exe.old').existsSync(), isFalse);
    });

    test('nightly updates come from the nightly builds repo', () async {
      final y = bridge();
      await y.init();
      github.latest = '2026.11.16.232901';
      github.binaries['2026.11.16.232901'] = fakeYtDlp('2026.11.16.232901');
      expect(await y.update('nightly'), 'DONE');
      expect(github.count('GET /yt-dlp/yt-dlp-nightly-builds/releases/download/'), 1);
    });

    test('a new yt-dlp that does not start is rolled back to the working one', () async {
      final y = bridge();
      await y.init();
      github.latest = '2026.11.15';
      github.binaries['2026.11.15'] = fakeYtDlp('2026.11.15', broken: true);
      await expectLater(y.update('stable'), throwsA(isA<ToolInstallException>()));
      expect(await y.version(), '2026.10.26');
      final r = await y.run('after', ['--skip-download', 'u']);
      expect(r.ok, isTrue, reason: 'the previous yt-dlp still runs');
      // The failed release isn't recorded, so the next check tries again.
      github.binaries['2026.11.15'] = fakeYtDlp('2026.11.15');
      expect(await y.update('stable'), 'DONE');
    });
  });

  group('the app on Windows', () {
    late WindowsYtDlp saved;
    setUp(() {
      saved = WindowsYtDlp.instance;
      HostOs.override = 'windows';
    });
    tearDown(() {
      WindowsYtDlp.instance = saved;
      HostOs.override = null;
    });

    test('YtDlpBridge runs yt-dlp.exe instead of the Android channel', () async {
      WindowsYtDlp.instance = bridge();
      expect(await YtDlpBridge.init(), '2026.10.26');
      expect(await YtDlpBridge.version(), '2026.10.26');
      expect(await YtDlpBridge.needsUpdate(), isFalse);
      expect(await YtDlpBridge.update('stable'), 'ALREADY_UP_TO_DATE');

      final lines = <String>[];
      final r = await YtDlpBridge.run('b', ['--skip-download', 'u'], onLine: lines.add);
      expect(r.ok, isTrue);
      expect(lines, contains('[download]  50.0% of 10MiB'));
      // Only this run's lines: another run's output doesn't leak in.
      await YtDlpBridge.run('other', ['--skip-download', 'u2']);
      expect(lines.where((l) => l.contains('u2')), isEmpty);
    });

    test('YtDlpBridge.cancel stops a Windows run', () async {
      WindowsYtDlp.instance = bridge();
      await YtDlpBridge.init();
      final run = YtDlpBridge.run('c', ['--skip-download', '--hang', 'u']);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await YtDlpBridge.cancel('c'), isTrue);
      expect((await run.timeout(const Duration(seconds: 5))).canceled, isTrue);
    });

    test('yt-dlp.exe that cannot be started shows as a yt-dlp error, not a crash', () async {
      final y = bridge();
      await y.init();
      final broken = WindowsYtDlp(
        toolsDir: () async => tools,
        github: github.base,
        ffmpegZip: github.base.resolve('/ffmpeg.zip'),
        denoZip: github.base.resolve('/deno.zip'),
        launch: (exe, args) => throw ProcessException(exe, args, 'The system cannot find the file specified.'),
      );
      made.add(broken);
      WindowsYtDlp.instance = broken;
      await expectLater(
        YtDlpBridge.run('x', ['--skip-download', 'u']),
        throwsA(isA<YtDlpException>().having((e) => e.message, 'message', contains('cannot find the file'))),
      );
    });
  });
}
