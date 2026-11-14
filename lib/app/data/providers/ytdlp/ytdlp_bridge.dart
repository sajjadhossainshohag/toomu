import 'dart:async';

import 'package:flutter/services.dart';

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

/// Thin Dart side of android/.../YtDlpBridge.kt (youtubedl-android).
abstract class YtDlpBridge {
  static const _methods = MethodChannel('toomu/ytdlp');
  static const _events = EventChannel('toomu/ytdlp/progress');

  static final Stream<Map<dynamic, dynamic>> _progress =
      _events.receiveBroadcastStream().cast<Map<dynamic, dynamic>>();

  /// Unpacks Python/FFmpeg on first launch; returns the yt-dlp version.
  static Future<String?> init() => _methods.invokeMethod<String>('init');

  static Future<String?> version() => _methods.invokeMethod<String>('version');

  /// Downloads the latest yt-dlp release from GitHub ("stable"/"nightly").
  static Future<String?> update(String channel) =>
      _methods.invokeMethod<String>('update', {'channel': channel});

  /// Runs yt-dlp; the last element of [args] must be the URL.
  /// Output lines arrive on [onLine] while it runs.
  static Future<YtDlpResult> run(String id, List<String> args, {void Function(String line)? onLine}) async {
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

  static Future<bool> cancel(String id) async =>
      (await _methods.invokeMethod<bool>('cancel', {'id': id})) ?? false;
}
