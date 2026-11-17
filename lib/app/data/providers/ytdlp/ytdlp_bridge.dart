import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:flutter/services.dart';

import '../../../core/utils/host_os.dart';
import 'windows_ytdlp.dart';

/// Result of one yt-dlp run.
class YtDlpResult {
  const YtDlpResult({required this.exitCode, required this.out, required this.err, this.canceled = false});

  final int exitCode;
  final String out;
  final String err;
  final bool canceled;

  bool get ok => exitCode == 0 && !canceled;
}

/// yt-dlp failed; [message] is its last `ERROR:` line.
/// A failure on this phone rather than at YouTube — the file can't be
/// written — as a message the user can act on; null otherwise. Other
/// links, YouTube clients or downloaders can't fix these, so downloads stop
/// at once instead of retrying.
String? localFileProblem(String err) {
  final e = err.toLowerCase();
  if (e.contains('errno 36') || e.contains('file name too long')) {
    return "The file name is too long for this phone's storage.";
  }
  if (e.contains('errno 28') || e.contains('no space left')) return 'Not enough free storage on the phone.';
  if (e.contains('errno 30') || e.contains('read-only file system')) {
    return "The download folder can't be written to (read-only storage).";
  }
  if (e.contains('errno 13') || e.contains('permission denied')) {
    return "Toomu isn't allowed to write to the download folder.";
  }
  return null;
}

class YtDlpException implements Exception {
  YtDlpException(String stderr) : message = _lastError(stderr);

  final String message;

  static String _lastError(String err) {
    final lines = err.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final error = lines.lastWhere((l) => l.startsWith('ERROR:'), orElse: () => lines.isEmpty ? 'yt-dlp failed' : lines.last);
    return error.replaceFirst(RegExp(r'^ERROR:\s*(\[[^\]]+\]\s*)?([\w-]{11}:\s*)?'), '');
  }

  @override
  String toString() => 'YtDlpException: $message';
}

/// The run was stopped on purpose (nobody needed the result).
class YtDlpCanceled implements Exception {
  const YtDlpCanceled();

  @override
  String toString() => 'yt-dlp run canceled';
}

/// Thin Dart side of android/.../YtDlpBridge.kt (youtubedl-android); on
/// Windows, [WindowsYtDlp] runs yt-dlp.exe itself.
abstract class YtDlpBridge {
  static const _methods = MethodChannel('toomu/ytdlp');
  static const _events = EventChannel('toomu/ytdlp/progress');

  static final Stream<Map<dynamic, dynamic>> _progress =
      _events.receiveBroadcastStream().cast<Map<dynamic, dynamic>>();

  /// Unpacks Python/FFmpeg on first launch; returns the yt-dlp version.
  static Future<String?> init() =>
      HostOs.isWindows ? _windows.init() : _methods.invokeMethod<String>('init');

  static Future<String?> version() =>
      HostOs.isWindows ? _windows.version() : _methods.invokeMethod<String>('version');

  static WindowsYtDlp get _windows => WindowsYtDlp.instance;

  /// True while the bundled yt-dlp runs (no update has succeeded yet: first
  /// launch, or restored after an interrupted update).
  static Future<bool> needsUpdate() async => HostOs.isWindows
      ? _windows.needsUpdate()
      : await _methods.invokeMethod<bool>('needsUpdate') ?? false;

  /// Downloads the latest yt-dlp release from GitHub ("stable"/"nightly").
  static Future<String?> update(String channel) => HostOs.isWindows
      ? _windows.update(channel)
      : _methods.invokeMethod<String>('update', {'channel': channel});

  /// Runs yt-dlp; the last element of [args] must be the URL.
  /// Output lines arrive on [onLine] while it runs.
  static Future<YtDlpResult> run(String id, List<String> args, {void Function(String line)? onLine}) async {
    if (HostOs.isWindows) {
      final sub = onLine == null ? null : _windows.lines.where((e) => e.id == id).listen((e) => onLine(e.line));
      try {
        return await _windows.run(id, args);
      } on ProcessException catch (e) {
        throw YtDlpException(e.message);
      } finally {
        await sub?.cancel();
      }
    }
    StreamSubscription<Map<dynamic, dynamic>>? sub;
    if (onLine != null) {
      sub = _progress.where((e) => e['id'] == id).listen((e) => onLine('${e['line']}'));
    }
    try {
      final r = await _methods.invokeMapMethod<String, dynamic>('run', {'id': id, 'args': args});
      return YtDlpResult(
        exitCode: (r?['exitCode'] as int?) ?? -1,
        out: (r?['out'] as String?) ?? '',
        err: (r?['err'] as String?) ?? '',
        canceled: (r?['canceled'] as bool?) ?? false,
      );
    } on PlatformException catch (e) {
      throw YtDlpException(e.message ?? e.code);
    } finally {
      await sub?.cancel();
    }
  }

  static Future<bool> cancel(String id) async => HostOs.isWindows
      ? _windows.cancel(id)
      : (await _methods.invokeMethod<bool>('cancel', {'id': id})) ?? false;
}
