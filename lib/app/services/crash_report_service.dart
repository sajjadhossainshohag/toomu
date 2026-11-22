import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/device_profile.dart';
import '../core/values/app_constants.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'update_service.dart';
import 'usage_ping.dart';

/// Crashes and errors → the crash relay (`tool/crash-relay`, a Cloudflare Worker that keeps them
/// privately in its D1 database, one row per distinct crash).
///
/// Each error is written to `<app support>/crash_reports/` the moment it happens (the app may be
/// about to die); Android's native crashes land there too (`CrashFile.kt`). Reports are sent
/// automatically (unless turned off in Settings → Send crash reports), only from
/// release builds, and with links, file paths and e-mail addresses removed. The diagnostics log
/// isn't sent: its lines name downloads.
class CrashReporter {
  CrashReporter({
    required this.dir,
    required this.endpoint,
    required this.appKey,
    required this.version,
    required this.platform,
    this.build = '',
    this.os = '',
    this.device = '',
  });

  final Directory dir;
  final String endpoint;
  final String appKey;
  final String version;
  final String build;
  final String platform;
  final String os;
  final String device;

  /// More waiting than this: the rest is dropped (an error in a loop mustn't fill the disk).
  static const maxPending = 5;

  /// Errors that aren't bugs: no connection, a picture that didn't load.
  static bool shouldReport(Object error, {String? library}) {
    if (library == 'image resource service') return false;
    if (error is SocketException ||
        error is HttpException ||
        error is TlsException ||
        error is TimeoutException ||
        error is DioException) {
      return false;
    }
    return !const {'ClientException', 'NetworkImageLoadException'}.contains(error.runtimeType.toString());
  }

  /// Without what could identify the user or their downloads.
  static String scrub(String text) => text
      .replaceAllMapped(RegExp(r'''(['"])([^'"\n]*[/\\][^'"\n]*)\1'''), (m) => '${m[1]}<path>${m[1]}')
      .replaceAll(RegExp(r'''\b[a-z][a-z0-9+.-]*://[^\s'")\]]+''', caseSensitive: false), '<link>')
      .replaceAll(RegExp(r'(?:/storage|/sdcard|/mnt)/\S+'), '<path>')
      .replaceAll(RegExp(r'\b[A-Za-z]:\\\S+'), '<path>')
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '<email>');

  /// One line per distinct error, to send each only once per version.
  static String keyOf(Map<String, dynamic> r) {
    final stack = '${r['stack'] ?? ''}';
    final frame = stack.split('\n').firstWhere(
          (l) => l.contains('package:toomu/') || l.contains('io.github.toomu.'),
          orElse: () => stack.split('\n').first,
        );
    return [r['kind'], '${r['message']}'.split('\n').first, frame.replaceAll(RegExp(r':\d+'), '').trim()].join('|');
  }

  /// Saves the error at once, synchronously. Null when it isn't reported or too many wait.
  File? save(String kind, Object error, StackTrace? stack, {String? library}) {
    if (!shouldReport(error, library: library)) return null;
    try {
      dir.createSync(recursive: true);
      if (pending().length >= maxPending) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/$now-$kind.json');
      file.writeAsStringSync(jsonEncode({
        'kind': kind,
        'message': scrub('$error'),
        'stack': scrub('${stack ?? ''}'),
        'time': now,
      }));
      return file;
    } catch (_) {
      return null; // a full disk mustn't turn one error into two
    }
  }

  List<File> pending() {
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  void dropPending() {
    for (final f in pending()) {
      _delete(f);
    }
  }

  /// Sends what's waiting; [sent] (keys of errors already sent from this version) is updated.
  /// A report the relay accepted or refused for good is deleted; one that couldn't get through
  /// (offline, the relay busy) stays for the next start.
  Future<int> sendPending(Set<String> sent) async {
    var count = 0;
    for (final f in pending()) {
      Map<String, dynamic> r;
      try {
        r = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        _delete(f); // half-written when the app died
        continue;
      }
      final key = keyOf(r);
      if (sent.contains(key)) {
        _delete(f);
        continue;
      }
      final status = await _post({
        'kind': r['kind'],
        'platform': platform,
        'version': version,
        'build': build,
        'os': os,
        'device': device,
        // Native reports were written by Kotlin: scrubbed here.
        'message': scrub('${r['message'] ?? ''}'),
        'stack': scrub('${r['stack'] ?? ''}'),
      });
      if (status == null || status == 429 || status >= 500) break; // try again next start
      _delete(f);
      if (status < 300) {
        sent.add(key);
        count++;
      }
    }
    return count;
  }

  Future<int?> _post(Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers
        ..contentType = ContentType.json
        ..set('x-toomu-key', appKey);
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      return res.statusCode;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void _delete(File f) {
    try {
      f.deleteSync();
    } catch (_) {}
  }
}

/// Installs the error hooks and sends reports automatically (unless off in Settings).
class CrashReportService extends GetxService {
  static CrashReportService get to => Get.find();

  static const _sentKey = 'crash_reports_sent';

  late final CrashReporter reporter;
  Timer? _sendSoon;

  /// Release builds with a release tag and a relay to send to (dev builds would only add noise).
  static bool get enabled =>
      !kDebugMode && UpdateService.currentTag.isNotEmpty && AppConstants.relayUrl.isNotEmpty;

  Future<CrashReportService> init() async {
    final support = await getApplicationSupportDirectory();
    final android = DeviceProfile.android;
    reporter = CrashReporter(
      dir: Directory('${support.path}/crash_reports'),
      endpoint: '${AppConstants.relayUrl}/report',
      appKey: AppConstants.crashReportKey,
      version: UpdateService.currentTag,
      build: const String.fromEnvironment('TOOMU_BUILD'),
      platform: Platform.isWindows ? 'windows' : 'android',
      os: android != null ? 'Android ${android.version.release}' : Platform.operatingSystemVersion,
      device: android != null ? '${android.manufacturer} ${android.model}' : '',
    );
    _install();
    if (enabled && reporter.pending().isNotEmpty) _handlePending(delay: const Duration(seconds: 3));
    if (enabled) _pingLater();
    return this;
  }

  /// The day's anonymous user-count ping, after start-up has settled.
  void _pingLater() {
    final storage = StorageService.to;
    final usage = UsagePing(
      endpoint: '${AppConstants.relayUrl}/ping',
      appKey: AppConstants.crashReportKey,
      platform: reporter.platform,
      version: reporter.version,
      lastDay: () => storage.read<String>(AppConstants.kUsagePingDay),
      saveDay: (day) => storage.write(AppConstants.kUsagePingDay, day),
    );
    Timer(const Duration(seconds: 10), () {
      if (SettingsService.to.usageCount.value) unawaited(usage.sendIfDue());
    });
  }

  void _install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      if (!details.silent) _record('flutter', details.exception, details.stack, library: details.library);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _record('dart', error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  void _record(String kind, Object error, StackTrace? stack, {String? library}) {
    if (!enabled) return;
    if (reporter.save(kind, error, stack, library: library) == null) return;
    _handlePending(delay: const Duration(seconds: 2));
  }

  /// Sends, or drops if crash reports are off in Settings (several errors at once: one send).
  void _handlePending({required Duration delay}) {
    _sendSoon?.cancel();
    _sendSoon = Timer(delay, () async {
      if (!SettingsService.to.crashReports.value) return reporter.dropPending();
      await sendNow();
    });
  }

  Future<int> sendNow() async {
    final storage = StorageService.to;
    final saved = storage.read<Map>(_sentKey);
    // Errors already sent are remembered per version: a new version reports them again.
    final sent = saved?['version'] == reporter.version
        ? {...(saved?['keys'] as List? ?? const []).cast<String>()}
        : <String>{};
    final count = await reporter.sendPending(sent);
    await storage.write(_sentKey, {'version': reporter.version, 'keys': sent.take(100).toList()});
    if (count > 0) debugPrint('[Crash] sent $count report${count == 1 ? '' : 's'}');
    return count;
  }

  @override
  void onClose() {
    _sendSoon?.cancel();
    super.onClose();
  }
}
