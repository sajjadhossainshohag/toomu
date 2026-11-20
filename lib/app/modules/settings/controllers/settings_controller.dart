import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/host_os.dart';
import '../../../core/utils/shell_open.dart';
import '../../../core/values/app_constants.dart';
import '../../../routes/app_pages.dart';
import '../../../services/download_service.dart';
import '../../../services/floating_button_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/update_service.dart';
import '../../../services/youtube_account_service.dart';
import '../../../services/ytdlp_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/option_sheet.dart';
import '../../player/views/widgets/equalizer_sheet.dart';
import '../views/widgets/diagnostics_sheet.dart';
import '../views/youtube_sign_in_page.dart';
import '../../../widgets/app_snackbar.dart';

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
        for (final i in const [1, 2, 4, 6, 8, 12, 16])
          SheetOption(
            value: i,
            label: i == 1 ? '1 connection' : '$i connections',
            subtitle: i == AppConstants.defaultConnectionsPerDownload
                ? 'Recommended'
                : i == 1
                    ? 'Slowest, gentlest on the server'
                    : i > AppConstants.defaultConnectionsPerDownload
                        ? 'Faster on slow servers; some refuse this many'
                        : null,
          ),
      ],
    );
    if (n != null) settings.setConnectionsPerDownload(n);
  }

  void showFolder() => HostOs.isWindows
      ? unawaited(openInExplorer(downloadFolder))
      : showNoticeDialog(title: 'Download location', message: downloadFolder);

  Future<void> cleanTemporaryFiles() async {
    final freed = await DownloadService.to.cleanTemporaryFiles();
    showSnack(
      freed > 0 ? 'Storage freed' : 'All clean',
      freed > 0 ? '${Formatters.bytes(freed)} of temporary files removed' : 'No leftover temporary files found',
      duration: const Duration(seconds: 2),
    );
  }

  YtDlpService get ytdlp => YtDlpService.to;
  FloatingButtonService get bubble => FloatingButtonService.to;

  final YoutubeAccountService account = YoutubeAccountService.to;

  /// Settings → YouTube account: sign in, or sign out.
  Future<void> youtubeAccount() async {
    if (!account.signedIn.value || account.expired.value) {
      await YoutubeSignInPage.open();
      return;
    }
    final out = await showConfirmDialog(
      title: 'Sign out of YouTube?',
      message: "Home goes back to general videos, and age-restricted videos won't play or download until you sign in again.",
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (out) await account.signOut();
  }

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
      showSnack('Downloads running', 'Pause or finish downloads before updating the downloader.');
      return;
    }
    final status = await ytdlp.update();
    showSnack('Downloader', status, duration: const Duration(seconds: 3));
  }

  void openDiagnostics() => Get.bottomSheet(const DiagnosticsSheet(), isScrollControlled: true);

  void openEqualizer() => Get.bottomSheet(const EqualizerSheet(), isScrollControlled: true);

  /// Toomu's official YouTube channel, in the app's own browser.
  Future<void> openYoutubeChannel() => openInBrowser(AppConstants.youtubeChannelUrl);

  @visibleForTesting
  Future<void> openInBrowser(String url) async => Get.toNamed<void>(Routes.browser, arguments: url);

  void shareApp() => SharePlus.instance.share(
        ShareParams(
          text: 'Download videos & music and play them offline with ${AppConstants.appName}.\n\n'
              'Get the latest version: ${AppConstants.latestDownload(windows: HostOs.isWindows)}',
        ),
      );

  void about() => showNoticeDialog(
        title: AppConstants.appName,
        message: 'Version ${UpdateService.versionLabel}\n\n'
            '${AppConstants.appName} downloads videos and music from YouTube, TikTok and almost any website, '
            'and plays them offline.\n\n'
            '• Watch YouTube without ads, with background play and picture-in-picture\n'
            '• The built-in browser finds the videos on any page you open\n'
            '• Fast downloads over several connections that pick up again after you lose signal\n'
            '• A music player with playlists, an equalizer and a sleep timer',
      );
}
