import 'package:get/get.dart';

import '../core/utils/device_profile.dart';
import '../modules/browser/bindings/browser_binding.dart';
import '../modules/browser/views/browser_view.dart';
import '../modules/channel/bindings/channel_binding.dart';
import '../modules/channel/views/channel_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/music/bindings/collection_binding.dart';
import '../modules/music/views/collection_view.dart';
import '../modules/player/bindings/player_binding.dart';
import '../modules/player/views/player_view.dart';
import '../modules/shorts/bindings/shorts_binding.dart';
import '../modules/shorts/views/shorts_view.dart';
import '../modules/video_player/bindings/video_player_binding.dart';
import '../modules/video_player/views/video_player_view.dart';
import '../modules/videos/bindings/videos_binding.dart';
import '../modules/videos/views/video_folder_view.dart';

part 'app_routes.dart';

/// Route table. A new feature module adds its GetPage here (and, if it is a
/// main tab, an entry in `modules/home/home_tabs.dart`).
class AppPages {
  AppPages._();

  static const initial = Routes.home;

  static Transition motion(Transition t) => DeviceProfile.reduceMotion ? Transition.noTransition : t;

  static final routes = <GetPage<dynamic>>[
    GetPage(
      name: _Paths.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: _Paths.player,
      page: () => const PlayerView(),
      binding: PlayerBinding(),
      transition: motion(Transition.downToUp),
      fullscreenDialog: true,
    ),
    GetPage(
      name: _Paths.browser,
      page: () => const BrowserView(),
      binding: BrowserBinding(),
      transition: motion(Transition.downToUp),
    ),
    GetPage(
      name: _Paths.videoPlayer,
      page: () => const VideoPlayerView(),
      binding: VideoPlayerBinding(),
      // No fade: the screen turns to landscape as the player opens, and
      // during a fade the page behind is on screen too, so the whole app was
      // laid out again mid-animation. Shown at once, only the player is.
      transition: Transition.noTransition,
    ),
    GetPage(
      name: _Paths.videoFolder,
      page: () => const VideoFolderView(),
      binding: VideosBinding(),
    ),
    GetPage(
      name: _Paths.musicCollection,
      page: () => const CollectionView(),
      binding: CollectionBinding(),
    ),
    GetPage(
      name: _Paths.channel,
      page: () => const ChannelView(),
      binding: ChannelBinding(),
    ),
    GetPage(
      name: _Paths.shorts,
      page: () => const ShortsView(),
      binding: ShortsBinding(),
    ),
  ];
}
