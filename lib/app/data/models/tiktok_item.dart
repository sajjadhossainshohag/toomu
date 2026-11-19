/// One TikTok video, from a video page's details (`itemStruct`).
class TiktokItem {
  const TiktokItem({
    required this.id,
    required this.authorId,
    this.pageUrl,
    this.caption = '',
    this.coverUrl,
  });

  final String id;

  /// The link to download from, when known better than [webUrl] (e.g. the
  /// address a shared short link led to).
  final String? pageUrl;

  /// "@name" without the @.
  final String authorId;
  final String caption;
  final String? coverUrl;

  /// The video's page (what yt-dlp downloads from).
  String get webUrl => pageUrl ?? 'https://www.tiktok.com/@$authorId/video/$id';

  /// A video, or null for photo slideshows and incomplete data.
  static TiktokItem? fromJson(Map<String, dynamic> j) {
    if (j['imagePost'] != null) return null;
    final id = j['id'];
    final video = j['video'];
    if (id is! String || video is! Map) return null;
    final author = j['author'] is Map ? j['author'] as Map : const {};
    final authorId = author['uniqueId'];
    if (authorId is! String || authorId.isEmpty) return null;
    return TiktokItem(
      id: id,
      authorId: authorId,
      caption: (j['desc'] as String?) ?? '',
      coverUrl: (video['cover'] ?? video['originCover']) as String?,
    );
  }
}
