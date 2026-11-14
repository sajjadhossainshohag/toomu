/// One TikTok video, from TikTok's website data (`itemStruct`: the feed's
/// items and a video page's details have the same shape).
class TiktokItem {
  const TiktokItem({
    required this.id,
    required this.authorId,
    this.playUrl = '',
    this.pageUrl,
    this.authorName = '',
    this.avatarUrl,
    this.caption = '',
    this.coverUrl,
    this.music,
    this.width = 0,
    this.height = 0,
    this.duration = Duration.zero,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.plays = 0,
  });

  final String id;

  /// The video file, if TikTok's data had it (downloads don't need it:
  /// yt-dlp reads the page itself).
  final String playUrl;

  /// The link to download from, when known better than [webUrl] (e.g. the
  /// address a shared short link led to).
  final String? pageUrl;

  /// "@name" without the @.
  final String authorId;
  final String authorName;
  final String? avatarUrl;
  final String caption;
  final String? coverUrl;
  final String? music;
  final int width;
  final int height;
  final Duration duration;
  final int likes;
  final int comments;
  final int shares;
  final int plays;

  /// The video's page (what yt-dlp downloads from).
  String get webUrl => pageUrl ?? 'https://www.tiktok.com/@$authorId/video/$id';

  /// A video, or null for ads, photo slideshows and incomplete data.
  static TiktokItem? fromJson(Map<String, dynamic> j) {
    if (isAd(j) || j['imagePost'] != null) return null;
    final id = j['id'];
    final video = j['video'];
    if (id is! String || video is! Map) return null;
    final play = video['playAddr'];
    final author = j['author'] is Map ? j['author'] as Map : const {};
    final stats = j['stats'] is Map ? j['stats'] as Map : const {};
    final music = j['music'] is Map ? j['music'] as Map : const {};
    final authorId = author['uniqueId'];
    if (authorId is! String || authorId.isEmpty) return null;
    int number(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final title = music['title'];
    final musicAuthor = music['authorName'];
    return TiktokItem(
      id: id,
      playUrl: play is String ? play : '',
      authorId: authorId,
      authorName: (author['nickname'] as String?) ?? authorId,
      avatarUrl: author['avatarThumb'] as String?,
      caption: (j['desc'] as String?) ?? '',
      coverUrl: (video['cover'] ?? video['originCover']) as String?,
      music: title is String && title.isNotEmpty
          ? (musicAuthor is String && musicAuthor.isNotEmpty
                ? '$title · $musicAuthor'
                : title)
          : null,
      width: number(video['width']),
      height: number(video['height']),
      duration: Duration(seconds: number(video['duration'])),
      likes: number(stats['diggCount']),
      comments: number(stats['commentCount']),
      shares: number(stats['shareCount']),
      plays: number(stats['playCount']),
    );
  }

  /// TikTok marks paid placements in a few ways; any of them → skipped.
  static bool isAd(Map<String, dynamic> j) =>
      j['isAd'] == true ||
      j['is_ad'] == true ||
      j['adAuthorization'] == true ||
      j['ad_info'] != null ||
      j['adLabelVersion'] != null && j['adLabelVersion'] != 0;
}
