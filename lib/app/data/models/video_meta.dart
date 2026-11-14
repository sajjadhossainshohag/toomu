import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'yt_info.dart';

/// What the download sheet shows about a video, from either a search
/// result (youtube_explode) or yt-dlp's info.
class VideoMeta {
  const VideoMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.duration,
  });

  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration? duration;

  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  factory VideoMeta.fromVideo(Video v) => VideoMeta(
        id: v.id.value,
        title: v.title,
        author: v.author,
        thumbnailUrl: v.thumbnails.mediumResUrl,
        duration: v.duration,
      );

  factory VideoMeta.fromInfo(YtInfo i) => VideoMeta(
        id: i.id,
        title: i.title,
        author: i.uploader,
        thumbnailUrl: i.thumbnail ?? 'https://i.ytimg.com/vi/${i.id}/mqdefault.jpg',
        duration: i.duration,
      );
}
