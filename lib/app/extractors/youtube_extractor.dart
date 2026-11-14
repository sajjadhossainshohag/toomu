import 'package:get/get.dart';

import '../core/utils/link_parser.dart';
import '../modules/youtube/controllers/youtube_controller.dart';
import 'media_extractor.dart';

/// youtube.com / m.youtube.com / music.youtube.com / youtu.be — watch
/// pages, Shorts, live. Opens the existing format sheet.
class YoutubeExtractor extends MediaExtractor {
  const YoutubeExtractor();

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  bool canHandle(Uri uri) => LinkParser.youtubeVideoId(uri.toString()) != null;

  @override
  Future<void> openDownload(Uri uri) async {
    final id = LinkParser.youtubeVideoId(uri.toString());
    if (id == null) return;
    await Get.find<YoutubeController>().openVideo(id);
  }
}
