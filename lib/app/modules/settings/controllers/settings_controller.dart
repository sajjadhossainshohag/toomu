import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/values/app_constants.dart';
import '../../../services/download_service.dart';
import '../../../services/floating_button_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/ytdlp_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/option_sheet.dart';
import '../../player/views/widgets/equalizer_sheet.dart';
import '../views/widgets/diagnostics_sheet.dart';

class SettingsController extends GetxController {
  final SettingsService settings = SettingsService.to;

  String get downloadFolder => DownloadService.to.downloadRoot;

  String get themeLabel => switch (settings.themeMode.value) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  bool get isDark => settings.themeMode.value == ThemeMode.dark;

  void toggleDark() =>
      settings.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);

  Future<void> pickTheme() async {
    final mode = await showOptionSheet<ThemeMode>(
      title: 'Appearance',
      selected: settings.themeMode.value,
      options: const <SheetOption<ThemeMode>>[
        SheetOption(value: ThemeMode.system, label: 'Follow system', icon: Icons.brightness_auto_rounded),
        SheetOption(value: ThemeMode.light, label: 'Light', icon: Icons.light_mode_rounded),
        SheetOption(value: ThemeMode.dark, label: 'Dark', icon: Icons.dark_mode_rounded),
      ],
    );
    if (mode != null) settings.setThemeMode(mode);
  }

  Future<void> pickConcurrent() async {
    final n = await showOptionSheet<int>(
      title: 'Parallel downloads',
      selected: settings.maxConcurrentDownloads.value,
      options: <SheetOption<int>>[
        for (var i = 1; i <= 5; i++)
          SheetOption(
            value: i,
            label: '$i at a time',
            subtitle: i == AppConstants.defaultMaxConcurrentDownloads ? 'Recommended' : null,
          ),
      ],
    );
    if (n != null) settings.setMaxConcurrentDownloads(n);
  }

  Future<void> pickConnections() async {
    final n = await showOptionSheet<int>(
      title: 'Connections per download',
      selected: settings.connectionsPerDownload.value,
      options: <SheetOption<int>>[
        for (final i in const [1, 2, 4, 6, 8])
          SheetOption(
            value: i,
            label: i == 1 ? '1 connection' : '$i connections',
            subtitle: i == AppConstants.defaultConnectionsPerDownload
                ? 'Recommended'
                : i == 1
                    ? 'Slowest, gentlest on the server'
                    : null,
          ),
      ],
    );
    if (n != null) settings.setConnectionsPerDownload(n);
  }

  void showFolder() => showNoticeDialog(
        title: 'Download location',
        message: downloadFolder,
      );

  Future<void> cleanTemporaryFiles() async {
    final freed = await DownloadService.to.cleanTemporaryFiles();
    Get.snackbar(
      freed > 0 ? 'Storage freed' : 'All clean',
      freed > 0 ? '${Formatters.bytes(freed)} of temporary files removed' : 'No leftover temporary files found',
      duration: const Duration(seconds: 2),
    );
  }

  YtDlpService get ytdlp => YtDlpService.to;
  FloatingButtonService get bubble => FloatingButtonService.to;

  void toggleBubble() => bubble.toggle();

  void explainShare() => showNoticeDialog(
        title: 'Download from the YouTube app',
        message: 'While watching in YouTube, tap Share under the video and pick '
            '"Download with Toomu". The download options open right away.\n\n'
            'Works from Chrome and other apps too.',
      );

  /// Updating yt-dlp while it runs downloads can break them, so wait.
  Future<void> updateDownloader() async {
    if (DownloadService.to.hasActiveDownloads) {
      Get.snackbar('Downloads running', 'Pause or finish downloads before updating the downloader.');
      return;
    }
    final status = await ytdlp.update();
    Get.snackbar('Downloader', status, duration: const Duration(seconds: 3));
  }

  Future<void> pickUpdateChannel() async {
    final picked = await showOptionSheet<String>(
      title: 'Downloader updates',
      selected: ytdlp.channel.value,
      options: const <SheetOption<String>>[
        SheetOption(value: 'stable', label: 'Stable', subtitle: 'Recommended'),
        SheetOption(value: 'nightly', label: 'Nightly', subtitle: 'Newest YouTube fixes first, less tested'),
      ],
    );
    if (picked == null || picked == ytdlp.channel.value) return;
    ytdlp.setChannel(picked);
    await updateDownloader();
  }

  void openDiagnostics() => Get.bottomSheet(const DiagnosticsSheet(), isScrollControlled: true);

  void openEqualizer() => Get.bottomSheet(const EqualizerSheet(), isScrollControlled: true);

  void shareApp() => SharePlus.instance.share(
        ShareParams(text: 'Download videos & music and play them offline with ${AppConstants.appName}.'),
      );

  void about() => showNoticeDialog(
        title: AppConstants.appName,
        message: 'Version 1.0.0\nYouTube downloader and music player.',
      );
}
