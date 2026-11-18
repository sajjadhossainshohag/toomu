import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../core/utils/device_profile.dart';
import 'storage_service.dart';

/// In-app log of the last few hundred diagnostic lines. Some phones (Honor,
/// Huawei…) hide app logs from `adb logcat`, so failures are recorded here
/// and shown in Settings → Diagnostics with a Copy button.
///
/// Captures everything passed to [debugPrint] (all `[yt-dlp]`, `[Download]`,
/// `[YouTube]`… lines) by wrapping it once at startup.
class DiagnosticsService extends GetxService {
  static DiagnosticsService get to => Get.find();

  static const key = 'diagnostics_log';
  static const _max = 300;

  final _storage = StorageService.logs;
  final lines = <String>[].obs;
  Timer? _saveTimer;

  DiagnosticsService init() {
    lines.assignAll((_storage.read<List>(key) ?? const []).cast<String>());
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) add(message);
    };
    // Which build is running (set by tool/build_release.sh).
    const build = String.fromEnvironment('TOOMU_BUILD', defaultValue: 'dev build');
    add('— app started ($build) —');
    final i = DeviceProfile.android;
    if (i != null) {
      add('device: ${i.manufacturer} ${i.model}, Android ${i.version.release} '
          '(SDK ${i.version.sdkInt}), ${i.supportedAbis.join('/')}, '
          '${i.physicalRamSize} MB RAM${DeviceProfile.lowEnd ? ' (low-end mode)' : ''}');
      unawaited(_logExits());
    }
    return this;
  }

  static const _channel = MethodChannel('toomu/diagnostics');
  static const _exitsSeenKey = 'diagnostics_exits_seen';

  Future<void> _logExits() async {
    try {
      final since = _storage.read<int>(_exitsSeenKey) ?? 0;
      final exits = (await _channel.invokeListMethod<Map>('exitsSince', {'since': since})) ?? const [];
      for (final e in exits.reversed) {
        add(exitLine(e));
      }
      if (exits.isNotEmpty) {
        await _storage.write(_exitsSeenKey, exits.map((e) => e['time'] as int).reduce(max));
      }
    } catch (e) {
      add('[Exit] unknown: $e');
    }
  }

  static Future<String> heatNow() async {
    try {
      return heat(await _channel.invokeMethod<int>('thermal') ?? -1);
    } catch (_) {
      return heat(-1);
    }
  }

  // Android's ApplicationExitInfo reason codes.
  static const _reasons = {
    1: 'the app closed itself',
    2: 'stopped by a signal',
    3: 'out of memory (killed by Android)',
    4: 'crash',
    5: 'native crash',
    6: 'froze (not responding)',
    7: 'failed to start',
    9: 'too much CPU or battery (killed by Android)',
    10: 'closed by the user',
    11: 'stopped by the user',
    12: 'a part it needs died',
    13: 'ended by Android',
    14: 'frozen by Android',
    16: 'updated',
  };

  static const _signals = {6: 'SIGABRT', 7: 'SIGBUS', 9: 'SIGKILL', 11: 'SIGSEGV'};

  static String exitLine(Map e) {
    final at = DateTime.fromMillisecondsSinceEpoch(e['time'] as int);
    String two(int n) => n.toString().padLeft(2, '0');
    final reason = e['reason'] as int;
    final status = e['status'] as int? ?? 0;
    final signal = reason == 5 || reason == 2 ? ' (signal $status${_signals[status] == null ? '' : ', ${_signals[status]}'})' : '';
    // ActivityManager importance: 100 = foreground, up to 300 = visible/service, more = background.
    final where = (e['importance'] as int? ?? 1000) <= 200 ? 'in front' : 'in background';
    final mb = ((e['rssKb'] as int? ?? 0) / 1024).round();
    final description = e['description'] as String?;
    return '[Exit] last run ended ${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}: '
        '${_reasons[reason] ?? 'reason $reason'}$signal, $where, $mb MB'
        '${description == null || description.isEmpty ? '' : ' — $description'}';
  }

  static String heat(int status) => switch (status) {
    0 => 'normal',
    1 => 'warm (light)',
    2 => 'hot (moderate)',
    3 => 'very hot (severe, slowed down)',
    >= 4 => 'critical (heavily slowed down)',
    _ => 'unknown',
  };

  void add(String message) {
    final now = DateTime.now();
    final time = '${now.month}-${now.day} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    for (final line in message.split('\n')) {
      if (line.trim().isEmpty) continue;
      lines.add('$time $line');
    }
    if (lines.length > _max) lines.removeRange(0, lines.length - _max);
    // Short: a crash or a kill right after a line would otherwise lose it (seen: a video opening, then nothing).
    _saveTimer ??= Timer(const Duration(milliseconds: 500), () {
      _saveTimer = null;
      _storage.write(key, lines.toList());
    });
  }

  String get text => lines.join('\n');

  void clear() {
    lines.clear();
    _storage.remove(key);
  }
}
