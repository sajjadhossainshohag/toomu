import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'account_feed.dart';

class WatchNextPage {
  const WatchNextPage(this.related, this.commentsToken);

  final List<Video> related;

  /// Null when the video has no comments section (comments turned off).
  final String? commentsToken;
}

class WatchNextComments {
  WatchNextComments(this.comments, this.total, this.nextToken, this._replies);

  final List<Comment> comments;

  /// From the first page's header; 0 on later pages and on replies.
  final int total;
  final String? nextToken;
  final Map<Comment, String> _replies;

  String? repliesToken(Comment comment) => _replies[comment];
}

/// YouTube's own "next" call, the one its website makes for a watch page: Up next and the comments. It replaced
/// youtube_explode's related videos (one "Streamed …" date in the list threw for all of it) and comments (broken
/// by YouTube's newer comment format, and deprecated).
class WatchNext {
  WatchNext([HttpClient? client]) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final HttpClient _client;

  Future<WatchNextPage> next(String videoId) async {
    final text = await _post({'videoId': videoId});
    return Isolate.run(() => parseNext(jsonDecode(text) as Map<String, dynamic>));
  }

  Future<WatchNextComments> comments(String token) async {
    final text = await _post({'continuation': token});
    return Isolate.run(() => parseComments(jsonDecode(text) as Map<String, dynamic>));
  }

  Future<String> _post(Map<String, Object> body) async {
    final req = await _client.postUrl(Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'));
    req.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.userAgentHeader, AccountFeed.webAgent);
    req.write(
      jsonEncode({
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': AccountFeed.webClientVersion, 'hl': 'en'},
        },
        ...body,
      }),
    );
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw HttpException('YouTube answered ${res.statusCode}');
    return text;
  }

  static WatchNextPage parseNext(Map json) {
    final two = (json['contents'] as Map?)?['twoColumnWatchNextResults'] as Map?;
    final related = <Video>[];
    for (final item
        in (((two?['secondaryResults'] as Map?)?['secondaryResults'] as Map?)?['results'] as List?) ?? const []) {
      if (item is! Map) continue;
      try {
        if (AccountFeed.videoOf(item) case final Video v) related.add(v);
      } catch (_) {
        // One item YouTube shaped differently doesn't take Up next down with it.
      }
    }
    String? comments;
    for (final c in (((two?['results'] as Map?)?['results'] as Map?)?['contents'] as List?) ?? const []) {
      final section = (c is Map ? c['itemSectionRenderer'] : null) as Map?;
      if (section?['sectionIdentifier'] == 'comment-item-section') comments ??= _token(section!['contents']);
    }
    return WatchNextPage(related, comments);
  }

  static WatchNextComments parseComments(Map json) {
    final items = <Object?>[
      for (final e in (json['onResponseReceivedEndpoints'] as List?) ?? const [])
        if (e is Map)
          for (final action in e.values)
            if (action is Map && action['continuationItems'] is List) ...action['continuationItems'] as List,
    ];
    // Since 2024 a thread only names its comment; the comment itself comes in a list of "entities" beside them.
    final entities = <Object?, Map>{
      for (final m
          in (((json['frameworkUpdates'] as Map?)?['entityBatchUpdate'] as Map?)?['mutations'] as List?) ?? const [])
        if (m is Map)
          if ((m['payload'] as Map?)?['commentEntityPayload'] case final Map p) m['entityKey']: p,
    };
    var total = 0;
    String? next;
    final comments = <Comment>[];
    final replies = Map<Comment, String>.identity();
    for (final item in items) {
      if (item is! Map) continue;
      if (item['commentsHeaderRenderer'] case final Map header) {
        total = AccountFeed.parseViews(AccountFeed.text(header['countText']));
        continue;
      }
      if (item['continuationItemRenderer'] case final Map more) {
        next = _token(more);
        continue;
      }
      final thread = item['commentThreadRenderer'] as Map?;
      final view =
          (thread == null ? item['commentViewModel'] : (thread['commentViewModel'] as Map?)?['commentViewModel'])
              as Map?;
      final entity = entities[view?['commentKey']];
      final comment = entity == null ? null : _comment(entity);
      if (comment == null) continue;
      comments.add(comment);
      if (_token(thread?['replies']) case final String token) replies[comment] = token;
    }
    return WatchNextComments(comments, total, next, replies);
  }

  static Comment? _comment(Map e) {
    final props = e['properties'] as Map?;
    final author = e['author'] as Map?;
    final toolbar = e['toolbar'] as Map?;
    final text = (props?['content'] as Map?)?['content'];
    if (text is! String) return null;
    ChannelId channel;
    try {
      channel = ChannelId((author?['channelId'] as String?) ?? '');
    } catch (_) {
      channel = ChannelId('UC${'A' * 22}');
    }
    return Comment(
      (author?['displayName'] as String?) ?? '',
      channel,
      text,
      AccountFeed.parseViews(toolbar?['likeCountNotliked'] as String?),
      (props?['publishedTime'] as String?) ?? '',
      AccountFeed.parseViews(toolbar?['replyCount'] as String?),
      false,
      null,
    );
  }

  static String? _token(Object? j) {
    if (j is Map) {
      final token = (j['continuationCommand'] as Map?)?['token'];
      if (token is String) return token;
      for (final v in j.values) {
        if (_token(v) case final String t) return t;
      }
    } else if (j is List) {
      for (final v in j) {
        if (_token(v) case final String t) return t;
      }
    }
    return null;
  }
}
