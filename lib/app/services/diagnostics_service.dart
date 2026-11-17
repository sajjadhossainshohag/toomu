import 'dart:async';

import 'package:flutter/foundation.dart';
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
    }
    return this;
  }

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
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
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
