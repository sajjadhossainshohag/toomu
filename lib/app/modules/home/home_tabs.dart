import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../services/download_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../downloads/views/downloads_view.dart';
import '../music/views/music_view.dart';
import '../tiktok/views/tiktok_view.dart';
import '../videos/views/videos_view.dart';
import '../youtube/views/youtube_view.dart';
import 'views/home_hub_view.dart';

/// Feature registry for the main shell.
///
/// To add a new feature tab (e.g. Browser, Video player, Instagram):
///   1. create `modules/<feature>/{bindings,controllers,views}`
///   2. register its controller in [HomeBinding]
///   3. add a [HomeTab] below.
class HomeTab {
  const HomeTab({required this.id, required this.nav, required this.builder, this.badge});

  final String id;
  final AppNavItem nav;
  final WidgetBuilder builder;
  final int Function()? badge;
}

/// TikTok's note (Simple Icons' path, 24×24).
const tiktokLogo =
    'M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03'
    'c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94'
    '-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49'
    '.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37'
    '-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61'
    '.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z';

abstract class HomeTabs {
  static const home = 'home';
  static const youtube = 'youtube';
  static const tiktok = 'tiktok';
  static const downloads = 'downloads';
  static const videos = 'videos';
  static const music = 'music';

  static final List<HomeTab> all = <HomeTab>[
    HomeTab(
      id: home,
      nav: const AppNavItem(
        label: 'Home',
        icon: Iconsax.home_2_copy,
        activeIcon: Iconsax.home_2,
      ),
      builder: (_) => const HomeHubView(),
    ),
    HomeTab(
      id: youtube,
      nav: const AppNavItem(
        label: 'YouTube',
        icon: Iconsax.youtube_copy,
        activeIcon: Iconsax.youtube,
      ),
      builder: (_) => const YoutubeView(),
    ),
    HomeTab(
      id: tiktok,
      nav: const AppNavItem(
        label: 'TikTok',
        icon: Iconsax.video_vertical_copy,
        activeIcon: Iconsax.video_vertical,
        logoPath: tiktokLogo,
      ),
      builder: (_) => const TiktokView(),
    ),
    HomeTab(
      id: downloads,
      nav: const AppNavItem(
        label: 'Downloads',
        icon: Iconsax.document_download_copy,
        activeIcon: Iconsax.document_download,
      ),
      builder: (_) => const DownloadsView(),
      badge: () => DownloadService.to.tasks.where((t) => t.isActive).length,
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
  ];

  static int indexOf(String id) => all.indexWhere((t) => t.id == id);
}
