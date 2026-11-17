import 'dart:io';

import 'package:flutter/foundation.dart';

/// The OS Toomu runs on, for the Android/Windows differences. Tests run on
/// a macOS/Linux host and set [override] to check either platform's path.
abstract final class HostOs {
  /// `Platform.operatingSystem` name to pretend to be (tests only).
  @visibleForTesting
  static String? override;

  static String get name => override ?? Platform.operatingSystem;
  static bool get isAndroid => name == 'android';
  static bool get isWindows => name == 'windows';

  /// yt-dlp is there: bundled on Android, yt-dlp.exe on Windows.
  static bool get hasYtDlp => isAndroid || isWindows;

  /// Media notification + lock-screen controls (just_audio_background).
  static bool get usesAudioNotification => isAndroid;

  /// just_audio has no Windows player of its own: media_kit (libmpv) plays.
  static bool get usesMediaKitAudio => isWindows;

  /// audio_session has no Windows side.
  static bool get usesAudioSession => isAndroid;

  /// Download/Toomu on Android, Downloads\Toomu on Windows.
  static String get downloadFolderLabel => isWindows ? r'Downloads\Toomu' : 'Download/Toomu';
}
