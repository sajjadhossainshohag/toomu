import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

import '../../../services/audio_player_service.dart';
import '../../../services/video_session_service.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/shorts_controller.dart';

class ShortsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ShortsController>(() {
      final yt = Get.find<YoutubeController>();
      final session = VideoSessionService.to;
      return ShortsController(
        Get.arguments as ShortsArgs,
        resolve: (v) => yt.resolveStream(v.id.value, v.title, duration: v.duration),
        play: (item) async {
          // Music and video shouldn't play at once.
          await AudioPlayerService.to.pause();
          session.attach(VideoPlaylist([item], 0), (_) {});
          await session.player.setPlaylistMode(PlaylistMode.single);
          await session.openItem(item);
        },
        stop: () async {
          if (session.hasPlayer) await session.player.setPlaylistMode(PlaylistMode.none);
          await session.detach(keepPlaying: false);
        },
      );
    });
  }
}
