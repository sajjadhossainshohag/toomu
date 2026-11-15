import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'storage_service.dart';

/// In-app log of the last few hundred diagnostic lines. Some phones (Honor,
/// Huawei…) hide app logs from `adb logcat`, so failures are recorded here
/// and shown in Settings → Diagnostics with a Copy button.
///
/// Captures everything passed to [debugPrint] (all `[yt-dlp]`, `[Download]`,
/// `[YouTube]`… lines) by wrapping it once at startup.
class DiagnosticsService extends GetxService {
  static DiagnosticsService get to => Get.find();

  static const _key = 'diagnostics_log';
  static const _max = 300;

  final _storage = StorageService.to;
  final lines = <String>[].obs;
  Timer? _saveTimer;

  DiagnosticsService init() {
    lines.assignAll((_storage.read<List>(_key) ?? const []).cast<String>());
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) add(message);
    };
    // Which build is running (set by tool/build_release.sh).
    const build = String.fromEnvironment('TOOMU_BUILD', defaultValue: 'dev build');
    add('— app started ($build) —');
    if (Platform.isAndroid) {
      unawaited(DeviceInfoPlugin().androidInfo.then(
        (i) => add('device: ${i.manufacturer} ${i.model}, Android ${i.version.release} '
            '(SDK ${i.version.sdkInt}), ${i.supportedAbis.join('/')}'),
        onError: (_) {},
      ));
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
      _storage.write(_key, lines.toList());
    });
  }

  String get text => lines.join('\n');

  void clear() {
    lines.clear();
    _storage.remove(_key);
  }
}
