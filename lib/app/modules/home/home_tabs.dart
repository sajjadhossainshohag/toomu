import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../widgets/app_bottom_nav.dart';
import '../downloads/views/downloads_view.dart';
import '../music/views/music_view.dart';
import '../settings/views/settings_view.dart';
import '../videos/views/videos_view.dart';
import '../youtube/views/youtube_view.dart';

/// Feature registry for the main shell.
///
/// To add a new feature tab (e.g. Browser, Video player, Instagram):
///   1. create `modules/<feature>/{bindings,controllers,views}`
///   2. register its controller in [HomeBinding]
///   3. add a [HomeTab] below.
class HomeTab {
  const HomeTab({required this.id, required this.nav, required this.builder});

  final String id;
  final AppNavItem nav;
  final WidgetBuilder builder;
}

abstract class HomeTabs {
  static const youtube = 'youtube';
  static const downloads = 'downloads';
  static const videos = 'videos';
  static const music = 'music';
  static const settings = 'settings';

  static final List<HomeTab> all = <HomeTab>[
    HomeTab(
      id: youtube,
      nav: const AppNavItem(
        label: 'Home',
        icon: Iconsax.home_2_copy,
        activeIcon: Iconsax.home_2,
      ),
      builder: (_) => const YoutubeView(),
    ),
    HomeTab(
      id: downloads,
      nav: const AppNavItem(
        label: 'Downloads',
        icon: Iconsax.document_download_copy,
        activeIcon: Iconsax.document_download,
      ),
      builder: (_) => const DownloadsView(),
    ),
    HomeTab(
      id: videos,
      nav: const AppNavItem(
        label: 'Videos',
        icon: Iconsax.video_play_copy,
        activeIcon: Iconsax.video_play,
      ),
      builder: (_) => const VideosView(),
    ),
    HomeTab(
      id: music,
      nav: const AppNavItem(
        label: 'Music',
        icon: Iconsax.music_copy,
        activeIcon: Iconsax.music,
      ),
      builder: (_) => const MusicView(),
    ),
    HomeTab(
      id: settings,
      nav: const AppNavItem(
        label: 'Settings',
        icon: Iconsax.setting_2_copy,
        activeIcon: Iconsax.setting_2,
      ),
      builder: (_) => const SettingsView(),
    ),
  ];

  static int indexOf(String id) => all.indexWhere((t) => t.id == id);
}
