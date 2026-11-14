import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/values/app_constants.dart';
import '../../../services/audio_player_service.dart';
import '../../../widgets/app_group.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/gradient_hero_card.dart';
import '../../../widgets/top_fade.dart';
import '../../player/views/widgets/sleep_timer_sheet.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final audio = AudioPlayerService.to;

    return Column(
      children: <Widget>[
        const AppHeader(title: 'Settings'),
        Expanded(
          child: TopFade(
            child: Obx(
              () => ListView(
                padding: EdgeInsets.only(top: 8 * scale, bottom: 24 * scale),
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: const GradientHeroCard(
                      icon: Icons.download_for_offline_rounded,
                      title: 'Download once, play anywhere',
                      message:
                          'Your videos and music are saved to your device so they play offline.',
                    ),
                  ),
                  SizedBox(height: 16 * scale),
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
                        value: 'Download/${AppConstants.downloadFolderName}',
                        onTap: controller.showFolder,
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
                      AppRow(
                        icon: Icons.account_circle_rounded,
                        tint: ColorConstants.siteYoutube,
                        label: 'YouTube account (age-restricted videos)',
                        value: controller.account.signedIn.value
                            ? 'Signed in'
                            : controller.account.expired.value
                                ? 'Expired'
                                : 'Sign in',
                        onTap: controller.youtubeAccount,
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Downloader',
                    rows: <Widget>[
                      AppRow(
                        icon: Icons.system_update_alt_rounded,
                        tint: ColorConstants.tileDownloads,
                        label: controller.ytdlp.updating.value ? 'Updating…' : 'yt-dlp engine',
                        value: controller.ytdlp.version.value ??
                            (controller.ytdlp.ready.value ? '?' : 'Starting…'),
                        onTap: controller.updateDownloader,
                      ),
                      AppRow(
                        icon: Icons.tune_rounded,
                        tint: ColorConstants.tileTheme,
                        label: 'Update channel',
                        value: controller.ytdlp.channel.value == 'nightly' ? 'Nightly' : 'Stable',
                        onTap: controller.pickUpdateChannel,
                      ),
                      AppRow(
                        icon: Icons.bug_report_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'Diagnostics',
                        value: 'Log',
                        onTap: controller.openDiagnostics,
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  AppGroup(
                    title: 'Video player',
                    rows: <Widget>[
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
                        icon: Icons.share_rounded,
                        tint: ColorConstants.tileShare,
                        label: 'Share Toomu',
                        onTap: controller.shareApp,
                      ),
                      AppRow(
                        icon: Icons.info_rounded,
                        tint: ColorConstants.tileAbout,
                        label: 'About',
                        value: 'v1.0.0',
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
