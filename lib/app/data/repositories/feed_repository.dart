import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/values/app_constants.dart';
import '../../services/storage_service.dart';

/// The home feed's first page, kept on disk so a cold start shows videos at
/// once while the fresh page loads.
class FeedRepository {
  FeedRepository(this._storage);

  final StorageService _storage;

  static const maxAge = Duration(hours: 12);
  static const _maxVideos = 30;

  List<Video>? load(String category, {DateTime? now}) {
    final saved = _storage.read<Map>(AppConstants.kFeedCache);
    if (saved == null || saved['category'] != category) return null;
    final at = DateTime.fromMillisecondsSinceEpoch((saved['at'] as num? ?? 0).toInt());
    if ((now ?? DateTime.now()).difference(at) > maxAge) return null;
    final videos = <Video>[];
    for (final m in (saved['videos'] as List? ?? const []).whereType<Map>()) {
      try {
        videos.add(_fromJson(m));
      } catch (_) {
        // One unreadable entry must not cost the rest.
      }
    }
    return videos.isEmpty ? null : videos;
  }

  Future<void> save(String category, Iterable<Video> videos, {DateTime? now}) =>
      _storage.write(AppConstants.kFeedCache, {
        'category': category,
        'at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        'videos': [for (final v in videos.take(_maxVideos)) _toJson(v)],
      });

  static Map<String, dynamic> _toJson(Video v) => {
        'id': v.id.value,
        'title': v.title,
        'author': v.author,
        'channelId': v.channelId.value,
        'age': v.uploadDateRaw,
        'durationMs': v.duration?.inMilliseconds,
        'views': v.engagement.viewCount,
      };

  static Video _fromJson(Map<dynamic, dynamic> m) {
    final id = m['id'] as String;
    return Video(
      VideoId(id),
      m['title'] as String,
      m['author'] as String,
      ChannelId(m['channelId'] as String),
      null,
      m['age'] as String?,
      null,
      '',
      m['durationMs'] == null ? null : Duration(milliseconds: (m['durationMs'] as num).toInt()),
      ThumbnailSet(id),
      null,
      Engagement((m['views'] as num? ?? 0).toInt(), null, null),
      false,
    );
  }
}
