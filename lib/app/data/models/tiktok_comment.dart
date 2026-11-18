import 'dart:convert';

/// One TikTok comment (or reply), from TikTok's comment answers
/// (`/api/comment/list/`, `/api/comment/list/reply/`).
class TiktokComment {
  const TiktokComment({
    required this.id,
    required this.text,
    required this.authorId,
    this.authorName = '',
    this.avatarUrl,
    this.likes = 0,
    this.liked = false,
    this.replyCount = 0,
    this.time,
    this.likedByAuthor = false,
  });

  final String id;
  final String text;

  /// "@name" without the @.
  final String authorId;
  final String authorName;
  final String? avatarUrl;
  final int likes;

  /// The signed-in account liked it.
  final bool liked;
  final int replyCount;
  final DateTime? time;

  /// TikTok's "Liked by creator".
  final bool likedByAuthor;

  String get shownName => authorName.isEmpty ? authorId : authorName;

  TiktokComment copyWith({int? likes, bool? liked}) => TiktokComment(
    id: id,
    text: text,
    authorId: authorId,
    authorName: authorName,
    avatarUrl: avatarUrl,
    likes: likes ?? this.likes,
    liked: liked ?? this.liked,
    replyCount: replyCount,
    time: time,
    likedByAuthor: likedByAuthor,
  );

  static TiktokComment? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['cid'] ?? ''}';
    final text = j['text'];
    if (id.isEmpty || text is! String) return null;
    final user = j['user'] is Map ? j['user'] as Map : const {};
    int number(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    bool flag(Object? v) => v == true || number(v) == 1;
    String? avatar() {
      for (final key in ['avatar_thumb', 'avatar_medium', 'avatar_168x168']) {
        final a = user[key];
        final list = a is Map ? a['url_list'] : null;
        if (list is List && list.isNotEmpty && list.first is String) {
          return list.first as String;
        }
        if (a is String && a.isNotEmpty) return a;
      }
      return null;
    }

    final seconds = number(j['create_time']);
    return TiktokComment(
      id: id,
      text: text,
      authorId: '${user['unique_id'] ?? user['uniqueId'] ?? ''}',
      authorName: '${user['nickname'] ?? ''}',
      avatarUrl: avatar(),
      likes: number(j['digg_count']),
      liked: flag(j['user_digged']),
      replyCount: number(j['reply_comment_total']),
      time: seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null,
      likedByAuthor: flag(j['is_author_digged']),
    );
  }
}

/// One answer of TikTok's comment list (or replies).
class TiktokCommentPage {
  const TiktokCommentPage({
    this.comments = const [],
    this.hasMore = false,
    this.total = 0,
  });

  final List<TiktokComment> comments;
  final bool hasMore;
  final int total;

  /// Null when [text] isn't a comment answer. TikTok answers visitors with
  /// an empty body (comments need an account), which gives null too.
  static TiktokCommentPage? parse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      final list = j['comments'];
      if (list is! List && j['status_code'] == null) return null;
      int number(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return TiktokCommentPage(
        comments: [
          for (final c in list is List ? list : const [])
            TiktokComment.fromJson(c),
        ].whereType<TiktokComment>().toList(),
        hasMore: j['has_more'] == true || number(j['has_more']) == 1,
        total: number(j['total']),
      );
    } catch (_) {
      return null;
    }
  }
}
