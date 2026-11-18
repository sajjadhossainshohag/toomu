import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../downloads/controllers/downloads_controller.dart';
import '../../music/controllers/music_controller.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../tiktok/controllers/tiktok_controller.dart';
import '../../tiktok/controllers/tiktok_actions.dart';
import '../../tiktok/controllers/tiktok_feeds.dart';
import '../../tiktok/views/tiktok_sign_in_page.dart';
import '../../../data/providers/tiktok/tiktok_video_page.dart';
import '../../../widgets/app_snackbar.dart';
import '../../tiktok/tiktok_playback.dart';
import '../../tiktok/tiktok_prefetch.dart';
import '../../../services/tiktok_account_service.dart';
import '../../../services/tiktok_service.dart';
import '../../videos/controllers/videos_controller.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../../../data/providers/tiktok/tiktok_feed.dart';
import '../controllers/home_controller.dart';
import '../home_tabs.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // fenix: the tabs' controllers can be made again after GetX deletes
    // them. A pushed page that first used one (the browser's downloads
    // button) owned it, and closing that page deleted it for good: the
    // next Get.find threw and the browser's top bar turned into a grey box.
    Get.lazyPut<HomeController>(HomeController.new, fenix: true);
    Get.lazyPut<YoutubeController>(YoutubeController.new, fenix: true);
    Get.lazyPut<DownloadsController>(DownloadsController.new, fenix: true);
    Get.lazyPut<MusicController>(MusicController.new, fenix: true);
    Get.lazyPut<VideosController>(VideosController.new, fenix: true);
    // TikTok: "Following | For You", one feed (own page, player hand-off
    // and downloads ahead) each.
    Get.lazyPut<TiktokFeeds>(
      () => TiktokFeeds(signedIn: TiktokAccountService.to.signedIn),
      fenix: true,
    );
    TiktokController tiktokFeed(
      String tag,
      WebTiktokFeedSource source,
      RxBool shown,
    ) {
      final prefetch = TiktokPrefetch(
        folder: () async => Directory(
          '${(await getTemporaryDirectory()).path}/tiktok_ahead/$tag',
        ),
        headers: TiktokService.playHeaders,
      );
      return TiktokController(
        source: source,
        playback: SessionTiktokPlayback(prefetch: prefetch),
        prefetch: prefetch,
        tabIndex: Get.find<HomeController>().tabIndex,
        tab: HomeTabs.indexOf(HomeTabs.tiktok),
        selected: shown,
        account: TiktokAccountService.to.signedIn,
      );
    }

    void noteUser(TiktokUser? u) => TiktokAccountService.to.noteUser(u);
    Get.lazyPut<TiktokActions>(
      () => TiktokActions(
        page: WebTiktokVideoPage(),
        signedIn: TiktokAccountService.to.signedIn,
        signIn: TiktokSignInPage.open,
        onProblem: (t, m) =>
            showSnack(t, m, duration: const Duration(seconds: 3)),
      ),
      fenix: true,
    );
    Get.lazyPut<TiktokController>(
      () => tiktokFeed(
        TiktokFeeds.forYouTag,
        WebTiktokFeedSource.forYou(onUser: noteUser),
        Get.find<TiktokFeeds>().forYouShown,
      ),
      tag: TiktokFeeds.forYouTag,
      fenix: true,
    );
    Get.lazyPut<TiktokController>(
      () => tiktokFeed(
        TiktokFeeds.followingTag,
        WebTiktokFeedSource.following(onUser: noteUser),
        Get.find<TiktokFeeds>().followingShown,
      ),
      tag: TiktokFeeds.followingTag,
      fenix: true,
    );
    Get.lazyPut<SettingsController>(SettingsController.new, fenix: true);
  }
}
