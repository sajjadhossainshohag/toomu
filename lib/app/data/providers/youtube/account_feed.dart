import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../youtube_provider.dart';

/// One of the signed-in account's home categories (YouTube's chip bar:
/// "Music", "Mixes", "Gaming"… personal to each account).
class AccountChip {
  const AccountChip(this.label, this.token);

  final String label;

  /// Continuation token that loads this category.
  final String token;
}

/// A page of the account's feed; more pages via continuation tokens.
class AccountFeedPage implements FeedPage {
  AccountFeedPage(this._feed, this.videos, this._next, {this.chips = const []});

  final AccountFeed _feed;
  @override
  final List<Video> videos;
  final String? _next;

  /// Only on the first Home page.
  final List<AccountChip> chips;

  @override
  Future<AccountFeedPage?> nextPage() async => _next == null ? null : _feed.continuation(_next);
}

/// The signed-in account's YouTube feeds — Home (recommendations),
/// Subscriptions and Home's categories — the way YouTube's website loads
/// them (InnerTube `browse`, authorised with the saved session).
class AccountFeed {
  AccountFeed(this._cookies);

  /// The saved session (name → value), read for every request.
  final Future<Map<String, String>> Function() _cookies;

  // One client keeps the connection to YouTube open between pages (no new
  // TLS handshake per page). It holds no login state: cookies go per request.
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static const _origin = 'https://www.youtube.com';
  static const _clientVersion = '2.20260708.00.00';
  static const _agent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

  /// Home: recommendations plus the account's categories. Null when YouTube
  /// has none (e.g. watch history off: YouTube then shows an empty home).
  Future<AccountFeedPage?> home() async {
    final page = await _browse({'browseId': 'FEwhat_to_watch'}, withChips: true);
    return page.videos.isEmpty ? null : page;
  }

  Future<AccountFeedPage> subscriptions() => _browse({'browseId': 'FEsubscriptions'});

  Future<AccountFeedPage> chip(AccountChip chip) => continuation(chip.token);

  Future<AccountFeedPage> continuation(String token) => _browse({'continuation': token});

  Future<AccountFeedPage> _browse(Map<String, Object> body, {bool withChips = false}) async {
    final cookies = await _cookies();
    if (cookies.isEmpty) throw StateError('Not signed in to YouTube.');
    final req = await _client.postUrl(Uri.parse('$_origin/youtubei/v1/browse?prettyPrint=false'));
    headersFor(cookies).forEach(req.headers.set);
    req.add(utf8.encode(jsonEncode({
      'context': {
        'client': {'clientName': 'WEB', 'clientVersion': _clientVersion, 'hl': 'en'},
      },
      ...body,
    })));
    final HttpClientResponse res;
    final String text;
    try {
      res = await req.close().timeout(const Duration(seconds: 15));
      text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    } catch (_) {
      req.abort(); // the shared client would otherwise keep the stalled connection
      rethrow;
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SignInExpired();
    }
    if (res.statusCode != 200) throw HttpException('YouTube answered ${res.statusCode}');
    // A page is up to ~1 MB of JSON: decoding it here would stall scrolling.
    return parse(this, await Isolate.run(() => jsonDecode(text)), withChips: withChips);
  }

  /// Headers of a signed-in request from youtube.com (as yt-dlp builds them).
  @visibleForTesting
  static Map<String, String> headersFor(Map<String, String> cookies, {DateTime? now}) {
    final time = ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000).round();
    String hash(String scheme, String sid) =>
        '$scheme ${time}_${sha1.convert(utf8.encode('$time $sid $_origin'))}';
    final sapisid = cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];
    final auth = [
      if (sapisid != null) hash('SAPISIDHASH', sapisid),
      if (cookies['__Secure-1PAPISID'] != null) hash('SAPISID1PHASH', cookies['__Secure-1PAPISID']!),
      if (cookies['__Secure-3PAPISID'] != null) hash('SAPISID3PHASH', cookies['__Secure-3PAPISID']!),
    ].join(' ');
    return {
      'Content-Type': 'application/json',
      'User-Agent': _agent,
      'Origin': _origin,
      'X-Origin': _origin,
      'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      if (auth.isNotEmpty) 'Authorization': auth,
      'X-Goog-AuthUser': '0',
      'X-Youtube-Client-Name': '1',
      'X-Youtube-Client-Version': _clientVersion,
      'X-Youtube-Bootstrap-Logged-In': 'true',
    };
  }

  // ---------------------------------------------------------------- parsing

  /// Videos (both of YouTube's item formats), the next-page token and, on
  /// Home, the category chips. Shorts, playlists, mixes and ads are skipped.
  @visibleForTesting
  static AccountFeedPage parse(AccountFeed feed, Object? json, {bool withChips = false}) {
    final videos = <Video>[];
    final seen = <String>{};
    String? next;
    final chips = <AccountChip>[];

    void walk(Object? j) {
      if (j is List) {
        for (final x in j) {
          walk(x);
        }
        return;
      }
      if (j is! Map) return;
      final video = j['videoRenderer'] is Map
          ? _fromVideoRenderer(j['videoRenderer'] as Map)
          : j['lockupViewModel'] is Map
              ? _fromLockup(j['lockupViewModel'] as Map)
              : null;
      if (video != null) {
        if (seen.add(video.id.value)) videos.add(video);
        return;
      }
      if (j['videoRenderer'] is Map || j['lockupViewModel'] is Map) return; // skipped kind
      final cont = j['continuationItemRenderer'];
      if (cont is Map) {
        next = _token(cont['continuationEndpoint']) ?? next;
        return;
      }
      final chip = j['chipCloudChipRenderer'];
      if (chip is Map) {
        final label = _text(chip['text']);
        final token = _token(chip['navigationEndpoint']);
        if (withChips && label != null && token != null && label != 'All') chips.add(AccountChip(label, token));
        return;
      }
      for (final v in j.values) {
        walk(v);
      }
    }

    walk(json);
    return AccountFeedPage(feed, videos, next, chips: chips);
  }

  static String? _token(Object? endpoint) {
    if (endpoint is! Map) return null;
    final direct = (endpoint['continuationCommand'] as Map?)?['token'];
    if (direct is String) return direct;
    // Newer: commandExecutorCommand { commands: [ { continuationCommand } ] }
    final commands = (endpoint['commandExecutorCommand'] as Map?)?['commands'];
    if (commands is List) {
      for (final c in commands) {
        final t = _token(c);
        if (t != null) return t;
      }
    }
    return null;
  }

  static String? _text(Object? t) {
    if (t is! Map) return null;
    if (t['simpleText'] is String) return t['simpleText'] as String;
    if (t['content'] is String) return t['content'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => (r as Map)['text'] ?? '').join();
    return null;
  }

  static Video? _fromVideoRenderer(Map v) {
    final id = v['videoId'];
    if (id is! String) return null;
    final owner = (v['ownerText'] ?? v['longBylineText'] ?? v['shortBylineText']) as Map?;
    final channel = ((((owner?['runs'] as List?)?.firstOrNull as Map?)?['navigationEndpoint'] as Map?)?['browseEndpoint']
        as Map?)?['browseId'];
    final length = _text(v['lengthText']);
    return _video(
      id: id,
      title: _text(v['title']) ?? '',
      author: _text(owner) ?? '',
      channelId: channel is String ? channel : null,
      duration: length,
      views: _text(v['viewCountText']),
      age: _text(v['publishedTimeText']),
    );
  }

  static Video? _fromLockup(Map l) {
    if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null; // playlists, mixes
    final id = l['contentId'];
    if (id is! String) return null;
    final meta = (l['metadata'] as Map?)?['lockupMetadataViewModel'] as Map?;
    final rows = ((((meta?['metadata'] as Map?)?['contentMetadataViewModel'] as Map?)?['metadataRows']) as List?) ?? [];
    List<String> parts(int i) => i < rows.length
        ? [
            for (final p in ((rows[i] as Map)['metadataParts'] as List?) ?? const [])
              if (_text((p as Map)['text']) case final String s) s,
          ]
        : const [];
    final second = parts(1);
    String? badge;
    void findBadge(Object? j) {
      if (badge != null) return;
      if (j is Map) {
        final b = j['thumbnailBadgeViewModel'];
        if (b is Map && b['text'] is String) {
          badge = b['text'] as String;
          return;
        }
        j.values.forEach(findBadge);
      } else if (j is List) {
        j.forEach(findBadge);
      }
    }

    findBadge(l['contentImage']);
    final avatar = meta?['image'];
    String? channel;
    void findChannel(Object? j) {
      if (channel != null) return;
      if (j is Map) {
        final b = j['browseEndpoint'];
        if (b is Map && b['browseId'] is String) {
          channel = b['browseId'] as String;
          return;
        }
        j.values.forEach(findChannel);
      } else if (j is List) {
        j.forEach(findChannel);
      }
    }

    findChannel(avatar);
    return _video(
      id: id,
      title: _text(meta?['title']) ?? '',
      author: parts(0).firstOrNull ?? '',
      channelId: channel,
      duration: badge,
      views: second.firstOrNull,
      age: second.length > 1 ? second[1] : null,
    );
  }

  static Video? _video({
    required String id,
    required String title,
    required String author,
    String? channelId,
    String? duration,
    String? views,
    String? age,
  }) {
    final length = parseDuration(duration);
    // Live streams and Shorts-style items without a length can't be
    // downloaded; the feed only shows what can.
    if (length == null || title.isEmpty) return null;
    ChannelId channel;
    try {
      channel = ChannelId(channelId ?? '');
    } catch (_) {
      channel = ChannelId('UC${'A' * 22}');
    }
    return Video(
      VideoId(id),
      title,
      author,
      channel,
      null,
      age,
      null,
      '',
      length,
      ThumbnailSet(id),
      null,
      Engagement(parseViews(views), null, null),
      false,
    );
  }

  /// "12:34" / "1:02:03" → Duration; null otherwise ("LIVE", "SHORTS").
  @visibleForTesting
  static Duration? parseDuration(String? text) {
    final parts = text?.trim().split(':');
    if (parts == null || parts.length < 2 || parts.length > 3) return null;
    var seconds = 0;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  /// "1.2M views", "2.5B", "12,345 views", "No views" → count.
  @visibleForTesting
  static int parseViews(String? text) {
    final m = RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false).firstMatch(text ?? '');
    if (m == null) return 0;
    final number = double.tryParse(m[1]!.replaceAll(',', '')) ?? 0;
    final scale = switch (m[2]?.toUpperCase()) { 'K' => 1e3, 'M' => 1e6, 'B' => 1e9, _ => 1.0 };
    return (number * scale).round();
  }
}

/// YouTube refused the saved sign-in (401/403): it expired or was signed
/// out elsewhere.
class SignInExpired extends StateError {
  SignInExpired() : super(ErrorText.signInExpired);
}
