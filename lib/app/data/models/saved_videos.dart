import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Watch history and Watch later, kept on the phone: just what a row shows.
abstract class SavedVideos {
  static const cap = 200;

  static Map<String, dynamic> toJson(Video v) => {
    'id': v.id.value,
    't': v.title,
    'a': v.author,
    'c': v.channelId.value,
    if (v.duration != null) 'd': v.duration!.inSeconds,
    'v': v.engagement.viewCount,
  };

  static Video? fromJson(Object? json) {
    try {
      final m = json! as Map;
      final id = m['id'] as String;
      final seconds = m['d'] as int?;
      return Video(
        VideoId(id),
        m['t'] as String,
        m['a'] as String,
        ChannelId(m['c'] as String),
        null,
        null,
        null,
        '',
        seconds == null ? null : Duration(seconds: seconds),
        ThumbnailSet(id),
        null,
        Engagement((m['v'] as int?) ?? 0, null, null),
        false,
      );
    } catch (_) {
      return null; // one bad entry doesn't hide the rest
    }
  }

  static List<Video> read(Object? list) => list is List ? [for (final e in list) ?fromJson(e)] : const [];

  static List<Map<String, dynamic>> write(List<Video> list) => [for (final v in list) toJson(v)];

  static List<Video> add(List<Video> list, Video v) => [v, ...list.where((x) => x.id != v.id)].take(cap).toList();
}
