import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:get/get.dart';

import '../../../core/utils/host_os.dart';
import '../../private_folder/controllers/private_folder_controller.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/values/app_constants.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/update_service.dart';
import '../../../widgets/app_group.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/outline_pill.dart';
import '../../../widgets/top_fade.dart';
import '../../player/views/widgets/sleep_timer_sheet.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({this.onBack, super.key});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final audio = AudioPlayerService.to;

    return Column(
      children: <Widget>[
        Obx(
          () => AppHeader(
            title: 'Settings',
            onBack: onBack,
            actions: <Widget>[
              if (controller.account.signedIn.value && !controller.account.expired.value)
                HeaderAction(
                  icon: Iconsax.profile_circle_copy,
                  tooltip: 'Google account',
                  onTap: controller.youtubeAccount,
                )
              else
                OutlinePill(
                  label: controller.account.expired.value ? 'Sign in again' : 'Sign in',
                  icon: Iconsax.login_copy,
                  compact: true,
                  height: 36,
                  onTap: controller.youtubeAccount,
                ),
            ],
          ),
        ),
        Expanded(
          child: TopFade(
            child: Obx(
              () => ListView(
                padding: EdgeInsets.only(top: 8 * scale, bottom: 24 * scale),
                children: <Widget>[
                  AppGroup(
                    title: 'Appearance',
                    rows: <Widget>[
                      AppRow(
                        icon: Icons.dark_mode_rounded,
                        tint: ColorConstants.tileTheme,
                        label: 'Dark mode',
                        toggled: controller.isDark,
                        onTap: controller.toggleDark,
                      ),
                      AppRow(
                        icon: Icons.palette_rounded,
                        tint: ColorConstants.tilePrivacy,
                        label: 'Theme',
                        value: controller.themeLabel,
                        onTap: controller.pickTheme,
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Downloads',
                    rows: <Widget>[
                      AppRow(
                        icon: Icons.layers_rounded,
                        tint: ColorConstants.tileDownloads,
                        label: 'Parallel downloads',
                        value: '${controller.settings.maxConcurrentDownloads.value}',
                        onTap: controller.pickConcurrent,
                      ),
                      AppRow(
                        icon: Icons.travel_explore_rounded,
                        tint: ColorConstants.tileVideo,
                        label: 'Detect media in browser',
                        toggled: controller.settings.captureMedia.value,
                        onTap: () => controller.settings
                            .setCaptureMedia(!controller.settings.captureMedia.value),
                      ),
                      AppRow(
                        icon: Icons.block_rounded,
                        tint: ColorConstants.tileVideo,
                        label: 'Block popups & redirects',
                        toggled: controller.settings.blockRedirects.value,
                        onTap: () => controller.settings
                            .setBlockRedirects(!controller.settings.blockRedirects.value),
                      ),
                      AppRow(
                        icon: Icons.shield_rounded,
                        tint: ColorConstants.tileVideo,
                        label: 'Block ads in browser',
                        toggled: controller.settings.blockAds.value,
                        onTap: () => controller.settings
                            .setBlockAds(!controller.settings.blockAds.value),
                      ),
                      AppRow(
                        icon: Icons.content_paste_search_rounded,
                        tint: ColorConstants.tileShare,
                        label: 'Detect copied links',
                        toggled: controller.settings.clipboardLinks.value,
                        onTap: () => controller.settings
                            .setClipboardLinks(!controller.settings.clipboardLinks.value),
                      ),
                      if (HostOs.hasYtDlp) ...[
                      AppRow(
                        icon: Icons.call_split_rounded,
                        tint: ColorConstants.tileEqualizer,
                        label: 'Connections per download',
                        value: '${controller.settings.connectionsPerDownload.value}',
                        onTap: controller.pickConnections,
                      ),
                      AppRow(
                        icon: Icons.folder_rounded,
                        tint: ColorConstants.tileStorage,
                        label: 'Download location',
                        value: HostOs.downloadFolderLabel,
                        onTap: controller.showFolder,
                      ),
                      ],
                      const AppRow(
                        icon: Icons.lock_rounded,
                        tint: ColorConstants.tileFolder,
                        label: 'Private folder',
                        onTap: openPrivateFolder,
                      ),
                      AppRow(
                        icon: Icons.cleaning_services_rounded,
                        tint: ColorConstants.tileFolder,
                        label: 'Clean temporary files',
                        onTap: controller.cleanTemporaryFiles,
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'YouTube app',
                    rows: <Widget>[
                      if (Platform.isAndroid) ...[
                      AppRow(
                        icon: Icons.bubble_chart_rounded,
                        tint: ColorConstants.siteYoutube,
                        label: 'Floating download button',
                        toggled: controller.bubble.enabled.value,
                        onTap: controller.toggleBubble,
                      ),
                      AppRow(
                        icon: Icons.touch_app_rounded,
                        tint: ColorConstants.tileTimer,
                        label: 'One-tap download from bubble',
                        value: controller.bubble.nowPlayingAccess.value ? 'On' : 'Off',
                        onTap: controller.bubble.requestNowPlayingAccess,
                      ),
                      AppRow(
                        icon: Icons.ios_share_rounded,
                        tint: ColorConstants.tileShare,
                        label: 'Share to download',
                        value: 'How',
                        onTap: controller.explainShare,
                      ),
                      ],
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Downloader',
                    rows: <Widget>[
                      if (HostOs.hasYtDlp) ...[
                      AppRow(
                        icon: Icons.system_update_alt_rounded,
                        tint: ColorConstants.tileDownloads,
                        label: controller.ytdlp.updating.value ? 'Updating…' : 'Downloader Engine',
                        value: controller.ytdlp.version.value ??
                            (controller.ytdlp.ready.value ? '?' : 'Starting…'),
                        onTap: controller.updateDownloader,
                      ),
                      ],
                      AppRow(
                        icon: Icons.bug_report_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'Diagnostics',
                        value: 'Log',
                        onTap: controller.openDiagnostics,
                      ),
                      AppRow(
                        icon: Icons.report_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'Send crash reports',
                        toggled: controller.settings.crashReports.value,
                        onTap: () => controller.settings
                            .setCrashReports(!controller.settings.crashReports.value),
                      ),
                      AppRow(
                        icon: Icons.people_alt_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'Anonymous usage count',
                        toggled: controller.settings.usageCount.value,
                        onTap: () => controller.settings.setUsageCount(!controller.settings.usageCount.value),
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Video player',
                    rows: <Widget>[
                      if (Platform.isAndroid)
                      AppRow(
                        icon: Icons.picture_in_picture_alt_rounded,
                        tint: ColorConstants.tileVideo,
                        label: 'Picture-in-picture on Home',
                        toggled: controller.settings.videoAutoPip.value,
                        onTap: () => controller.settings
                            .setVideoAutoPip(!controller.settings.videoAutoPip.value),
                      ),
                      AppRow(
                        icon: Icons.headphones_rounded,
                        tint: ColorConstants.tileAudio,
                        label: 'Background play',
                        toggled: controller.settings.videoBackgroundPlay.value,
                        onTap: () => controller.settings
                            .setVideoBackgroundPlay(!controller.settings.videoBackgroundPlay.value),
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Player',
                    rows: <Widget>[
                      if (Platform.isAndroid)
                      AppRow(
                        icon: Icons.equalizer_rounded,
                        tint: ColorConstants.tileEqualizer,
                        label: 'Equalizer',
                        value: audio.equalizerEnabled.value ? 'On' : 'Off',
                        onTap: controller.openEqualizer,
                      ),
                      AppRow(
                        icon: Icons.bedtime_rounded,
                        tint: ColorConstants.tileTimer,
                        label: 'Sleep timer',
                        value: audio.sleepMode.value == SleepMode.off ? 'Off' : 'On',
                        onTap: showSleepTimerSheet,
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'About',
                    rows: <Widget>[
                      AppRow(
                        icon: Icons.smart_display_rounded,
                        tint: ColorConstants.siteYoutube,
                        label: 'YouTube channel',
                        value: '@toomuapp',
                        onTap: controller.openYoutubeChannel,
                      ),
                      AppRow(
                        icon: Icons.share_rounded,
                        tint: ColorConstants.tileShare,
                        label: 'Share Toomu',
                        onTap: controller.shareApp,
                      ),
                      AppRow(
                        icon: Icons.system_update_rounded,
                        tint: ColorConstants.tileDownloads,
                        label: UpdateService.to.checking.value ? 'Checking…' : 'Check for updates',
                        value: UpdateService.currentTag.isEmpty ? 'Dev build' : UpdateService.currentTag,
                        onTap: UpdateService.to.checkNow,
                      ),
                      AppRow(
                        icon: Icons.info_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'About',
                        value: Platform.isAndroid ? null : UpdateService.versionLabel,
                        onTap: controller.about,
                      ),
                    ],
                  ),
                  SizedBox(height: 24 * scale),
                  Center(
                    child: Text(
                      '© ${DateTime.now().year} ${AppConstants.appName}',
                      style: TextStyle(
                        fontSize: 14 * scale,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500,
                        color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
