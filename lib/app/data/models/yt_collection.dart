import 'video_meta.dart';

class YtCollection {
  const YtCollection({required this.title, required this.author, required this.videos});

  final String title;
  final String author;
  final List<VideoMeta> videos;

  factory YtCollection.fromFlatJson(Map<String, dynamic> j) {
    final author = '${j['channel'] ?? j['uploader'] ?? ''}';
    var title = '${j['title'] ?? ''}';
    // yt-dlp names a channel's uploads after the tab: "<channel> - Videos".
    if (author.isNotEmpty && title == '$author - Videos') title = author;
    final entries = j['entries'];
    return YtCollection(
      title: title.isEmpty ? author : title,
      author: author,
      videos: [
        if (entries is List)
          for (final e in entries.whereType<Map>())
            // No duration: deleted, private or live, none of which can be downloaded.
            if (e['ie_key'] == 'Youtube' && e['id'] is String && e['duration'] is num && (e['duration'] as num) > 0)
              VideoMeta(
                id: e['id'] as String,
                title: '${e['title'] ?? ''}',
                author: author,
                thumbnailUrl: 'https://i.ytimg.com/vi/${e['id']}/mqdefault.jpg',
                duration: Duration(milliseconds: ((e['duration'] as num) * 1000).round()),
              ),
      ],
    );
  }
}
