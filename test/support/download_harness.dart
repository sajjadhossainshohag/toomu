import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/models/yt_info.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/media_scanner_service.dart';
import 'package:toomu/app/services/permission_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/stream_proxy.dart';
import 'package:toomu/app/services/ytdlp_service.dart';

import 'temp_storage.dart';

/// The byte at offset [i] of every file the [FileServer] serves (so a wrong offset shows up).
int byteAt(int i) => (i * 31 + (i >> 11)) & 0xff;

/// A file server with ranges, like a CDN: [bytesPerSecond] slows it so a test can pause mid-download, and
/// [status] makes every request fail (an expired link answers 403).
class FileServer {
  FileServer(this.length, {this.bytesPerSecond});

  final int length;
  int? bytesPerSecond;
  int? status;
  int requests = 0;
  late HttpServer _server;

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/movie.mp4');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _serve(HttpRequest req) async {
    requests++;
    final res = req.response;
    try {
      if (status != null) {
        res.statusCode = status!;
        await res.close();
        return;
      }
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers.value('range') ?? '');
      final from = m == null ? 0 : int.parse(m[1]!);
      final asked = m == null || m[2]!.isEmpty ? length - 1 : int.parse(m[2]!);
      final to = asked < length ? asked : length - 1;
      res
        ..statusCode = m == null ? 200 : 206
        ..contentLength = to - from + 1
        ..headers.set('accept-ranges', 'bytes');
      if (m != null) res.headers.set('content-range', 'bytes $from-$to/$length');
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      const step = 64 * 1024;
      for (var at = from; at <= to; at += step) {
        final end = at + step - 1 < to ? at + step - 1 : to;
        res.add(Uint8List.fromList([for (var i = at; i <= end; i++) byteAt(i)]));
        final rate = bytesPerSecond;
        if (rate != null) {
          await res.flush();
          await Future<void>.delayed(Duration(microseconds: (end - at + 1) * 1000000 ~/ rate));
        }
      }
      await res.close();
    } catch (_) {
      // The client hung up (pause, delete).
    }
  }
}

/// Records what would be added to the phone's gallery (the real one only runs on Android).
class _Scanner extends MediaScannerService {
  _Scanner(this.scanned);

  final List<String> scanned;

  @override
  Future<void> scan(String path) async => scanned.add(path);
}

/// One yt-dlp run the fake was asked for.
class YtDlpCall {
  YtDlpCall(this.kind, this.id, this.args, this.url);

  /// 'withoutUrl' (saved info JSON), 'url' (a site's page) or 'fallback' (YouTube clients in turn).
  final String kind;
  final String id;
  final List<String> args;
  final String url;

  bool get aria2c => args.any((a) => a.startsWith('--toomu-aria2c'));
  String? option(String name) {
    final i = args.indexOf(name);
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  /// `-P home:<dir>` / `-P temp:<dir>`.
  String path(String kind) {
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == '-P' && args[i + 1].startsWith('$kind:')) return args[i + 1].substring(kind.length + 1);
    }
    throw StateError('no -P $kind:');
  }

  /// The finished file's path for extension [ext] (from `-o '<base>.%(ext)s'`).
  String output(String ext) => '${path('home')}/${option('-o')!.replaceAll('%%', '%').replaceAll('%(ext)s', ext)}';
}

/// What a yt-dlp run does in a test: return how it ended. [run] gives the call, a progress line sink and a
/// future that completes when the run is cancelled (pause / delete).
typedef FakeRun = Future<YtDlpResult> Function(YtDlpCall call, void Function(String line) progress, Future<void> canceled);

/// yt-dlp without Python: each run goes to [onRun]; lookups come from [infoJson].
class FakeYtDlp extends YtDlpService {
  FakeYtDlp(String workRoot) {
    this.workRoot = workRoot;
  }

  final calls = <YtDlpCall>[];
  final _cancels = <String, Completer<void>>{};
  final canceledIds = <String>[];

  FakeRun onRun = (call, _, _) async => ok(call);

  /// yt-dlp's own lookup of a YouTube video (null: none).
  String? infoJson;
  int lookups = 0;

  @override
  Future<void> get whenReady => Future.value();

  /// A finished run: writes the output file ([bytes] long) like yt-dlp's last rename.
  static YtDlpResult ok(YtDlpCall call, {String ext = 'mp4', int bytes = 1000}) {
    File(call.output(ext))
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List(bytes));
    return const YtDlpResult(exitCode: 0, out: '', err: '');
  }

  static YtDlpResult failed(String err) => YtDlpResult(exitCode: 1, out: '', err: err);

  /// Called through the mocked `toomu/ytdlp` channel, as the real bridge's cancel.
  void cancel(String id) {
    canceledIds.add(id);
    final c = _cancels[id];
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<YtDlpResult> _run(YtDlpCall call, void Function(String line)? onLine) async {
    calls.add(call);
    final canceled = _cancels[call.id] = Completer<void>();
    final r = await onRun(call, onLine ?? (_) {}, canceled.future);
    return canceled.isCompleted ? const YtDlpResult(exitCode: -1, out: '', err: '', canceled: true) : r;
  }

  @override
  Future<YtDlpResult> runWithoutUrl(String id, List<String> args, {void Function(String line)? onLine}) =>
      _run(YtDlpCall('withoutUrl', id, args, ''), onLine);

  @override
  Future<YtDlpResult> runUrl(String id, List<String> args, String url, {void Function(String line)? onLine}) =>
      _run(YtDlpCall('url', id, args, url), onLine);

  @override
  Future<YtDlpResult> runWithFallback(
    String id,
    List<String> args,
    String url, {
    void Function(String line)? onLine,
    bool Function()? stopped,
    String? youtubeArgs,
    Duration? attemptLimit,
    bool Function(YtDlpResult result)? accept,
    Set<String?> skip = const {},
  }) => _run(YtDlpCall('fallback', id, args, url), onLine);

  @override
  String? savedInfoJson(String url) => null;

  @override
  Future<String?> infoJsonFor(String url) async => lookups > 0 ? infoJson : null;

  @override
  Future<YtInfo> info(String url) async {
    lookups++;
    if (infoJson == null) throw YtDlpException('ERROR: lookup failed');
    return YtInfo.fromJson(const {'id': 'x', 'title': 'x'});
  }
}

/// Everything the download service needs, in a temp folder, with no phone: storage, settings, a fake yt-dlp,
/// and the native channels answered (notification, media scanner, yt-dlp cancel).
class DownloadHarness {
  late Directory dir;
  late FakeYtDlp ytdlp;
  late DownloadService service;
  late StorageService downloads;
  late GetStorage _downloadsBox;
  final notifications = <MethodCall>[];
  final scanned = <String>[];
  /// GetStorage keeps one box per name in memory: each test gets new names.
  static int _boxes = 0;

  String get root => '${dir.path}/Toomu';

  Future<void> setUp({int maxConcurrent = 2, int connections = 4}) async {
    dir = await useTempStorageDir();
    // The test binding answers every HTTP request with 400; these tests talk to a local server.
    HttpOverrides.global = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('toomu/download_notify'), (call) async {
      notifications.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('toomu/ytdlp'), (call) async {
      if (call.method == 'cancel') ytdlp.cancel('${(call.arguments as Map)['id']}');
      return true;
    });

    Get.testMode = true;
    Get.put(StorageService(await tempBox('main_${_boxes++}', dir)));
    _downloadsBox = await tempBox('downloads_${_boxes++}', dir);
    downloads = StorageService(_downloadsBox);
    Get.put(downloads, tag: StorageService.downloadsBox);
    final settings = Get.put(SettingsService().init());
    settings.maxConcurrentDownloads.value = maxConcurrent;
    settings.connectionsPerDownload.value = connections;
    Get.put(PermissionService());
    Get.put<MediaScannerService>(_Scanner(scanned));
    Get.put(StreamProxy());
    ytdlp = Get.put<YtDlpService>(FakeYtDlp('${dir.path}/ytdlp-work')) as FakeYtDlp;
    DownloadService.fastInfoJson = (_) async => null;
    DownloadService.saveSubtitles = (_) async {};
    DownloadService.retryBackoff = const Duration(milliseconds: 20);
    await start();
  }

  /// A download service as at app start (a second call is a restart: it reads the saved list).
  Future<DownloadService> start() async {
    if (Get.isRegistered<DownloadService>()) Get.delete<DownloadService>(force: true);
    // <DownloadService> spelled out: in an async function the type would be FutureOr<DownloadService>.
    return service = Get.put<DownloadService>(await DownloadService().init());
  }

  Future<void> tearDown() async {
    for (final t in service.tasks.where((t) => t.isActive).toList()) {
      service.pause(t);
    }
    // Every run fully stopped: one still ending would use the services reset below.
    await service.whenIdle().timeout(const Duration(seconds: 10));
    await flushBox(_downloadsBox);
    Get.reset();
    await deleteTempStorageDir(dir);
  }

  /// Waits until [done] is true (checked every 20 ms), failing after [limit].
  static Future<void> until(bool Function() done, {Duration limit = const Duration(seconds: 15), String? what}) async {
    final end = DateTime.now().add(limit);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for ${what ?? 'the condition'}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  static Future<void> status(DownloadTask t, DownloadStatus s, {Duration limit = const Duration(seconds: 15)}) =>
      until(() => t.status.value == s, limit: limit, what: '${t.title} to be ${s.name} (is ${t.status.value.name})');
}
