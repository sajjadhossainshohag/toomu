import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

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
  Future<AccountFeedPage?> nextPage() async =>
      _next == null ? null : _feed.continuation(_next);
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
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  static const _origin = 'https://www.youtube.com';
  static const webClientVersion = '2.20260708.00.00';
  static const webAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

  /// Home: recommendations plus the account's categories. Null when YouTube
  /// has none (e.g. watch history off: YouTube then shows an empty home).
  Future<AccountFeedPage?> home() async {
    final page = await _browse({
      'browseId': 'FEwhat_to_watch',
    }, withChips: true);
    return page.videos.isEmpty ? null : page;
  }

  Future<AccountFeedPage> subscriptions() =>
      _browse({'browseId': 'FEsubscriptions'});

  Future<AccountFeedPage> chip(AccountChip chip) => continuation(chip.token);

  Future<AccountFeedPage> continuation(String token) =>
      _browse({'continuation': token});

  Future<AccountFeedPage> history() => _browse({'browseId': 'FEhistory'});

  Future<AccountFeedPage> watchLater() => _browse({'browseId': 'VLWL'});

  Future<void> editWatchLater(String videoId, {required bool add}) =>
      _post('browse/edit_playlist', editWatchLaterBody(videoId, add: add));

  // YouTube's history only has what was reported as played: the same report youtube.com (and yt-dlp's
  // --mark-watched) sends, the player's "videostats playback" URL with a fresh client playback nonce.
  Future<void> markWatched(String videoId) async {
    final player = jsonDecode(
      await _post(
        'player',
        playerRequest(videoId, await _signatureTimestamp()),
      ),
    );
    final url = watchedUrl(player, _nonce());
    if (url == null) {
      final status = player is Map ? player['playabilityStatus'] : null;
      final why = status is Map
          ? ' (${status['status']}: ${status['reason']})'
          : '';
      throw StateError('YouTube gave no playback report link$why.');
    }
    final cookies = await _cookies();
    final req = await _client.getUrl(url);
    headersFor(cookies).forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    if (res.statusCode >= 300) {
      throw HttpException('YouTube answered ${res.statusCode}');
    }
  }

  /// The WEB player only answers with the video (and its report link) when asked with the signature
  /// timestamp of YouTube's current player script, as youtube.com does; otherwise "The page needs to be
  /// reloaded." (Nov 2026).
  @visibleForTesting
  static Map<String, Object> playerRequest(
    String videoId,
    int? signatureTimestamp,
  ) => {
    'videoId': videoId,
    if (signatureTimestamp != null)
      'playbackContext': {
        'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
      },
  };

  /// The player script named in YouTube's iframe API (its version changes every few days).
  @visibleForTesting
  static Uri? playerScriptOf(String iframeApi) {
    final id = RegExp(
      r'player\\?/([0-9a-f]{8})\\?/',
    ).firstMatch(iframeApi)?.group(1);
    return id == null
        ? null
        : Uri.parse('$_origin/s/player/$id/player_ias.vflset/en_US/base.js');
  }

  @visibleForTesting
  static int? signatureTimestampOf(String script) => int.tryParse(
    RegExp(
          r'(?:signatureTimestamp|sts):(\d{5})',
        ).firstMatch(script)?.group(1) ??
        '',
  );

  ({DateTime at, int value})? _sts;

  /// Looked up once a day (the script is ~2.5 MB); null when YouTube can't be read, and then the request
  /// goes without it, as before.
  Future<int?> _signatureTimestamp() async {
    final known = _sts;
    if (known != null &&
        DateTime.now().difference(known.at) < const Duration(hours: 12)) {
      return known.value;
    }
    try {
      final script = playerScriptOf(
        await _getText(Uri.parse('$_origin/iframe_api')),
      );
      final value = script == null
          ? null
          : signatureTimestampOf(await _getText(script));
      if (value != null) _sts = (at: DateTime.now(), value: value);
      return value ?? known?.value;
    } catch (e) {
      debugPrint('[YouTube] player script: ${e.toString().split('\n').first}');
      return known?.value;
    }
  }

  Future<String> _getText(Uri url) async {
    final req = await _client.getUrl(url);
    req.headers.set('User-Agent', webAgent);
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('YouTube answered ${res.statusCode}', uri: url);
    }
    return res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
  }

  static String _nonce() {
    const abc =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(16, (_) => abc.codeUnitAt(r.nextInt(abc.length))),
    );
  }

  static Map<String, Object> editWatchLaterBody(
    String videoId, {
    required bool add,
  }) => {
    'playlistId': 'WL',
    'actions': [
      add
          ? {'action': 'ACTION_ADD_VIDEO', 'addedVideoId': videoId}
          : {
              'action': 'ACTION_REMOVE_VIDEO_BY_VIDEO_ID',
              'removedVideoId': videoId,
            },
    ],
  };

  static Uri? watchedUrl(Object? player, String nonce) {
    final base =
        (((player is Map ? player['playbackTracking'] : null)
                as Map?)?['videostatsPlaybackUrl']
            as Map?)?['baseUrl'];
    if (base is! String) return null;
    final uri = Uri.parse(base);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'ver': '2', 'cpn': nonce},
    );
  }

  Future<AccountFeedPage> _browse(
    Map<String, Object> body, {
    bool withChips = false,
  }) async {
    final text = await _post('browse', body);
    // A page is up to ~1 MB of JSON: decoding it here would stall scrolling.
    return parse(
      this,
      await Isolate.run(() => jsonDecode(text)),
      withChips: withChips,
    );
  }

  Future<String> _post(String endpoint, Map<String, Object> body) async {
    final cookies = await _cookies();
    if (cookies.isEmpty) throw StateError('Not signed in to YouTube.');
    final req = await _client.postUrl(
      Uri.parse('$_origin/youtubei/v1/$endpoint?prettyPrint=false'),
    );
    headersFor(cookies).forEach(req.headers.set);
    req.add(
      utf8.encode(
        jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': webClientVersion,
              'hl': 'en',
            },
          },
          ...body,
        }),
      ),
    );
    final HttpClientResponse res;
    final String text;
    try {
      res = await req.close().timeout(const Duration(seconds: 15));
      text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      req.abort(); // the shared client would otherwise keep the stalled connection
      rethrow;
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SignInExpired();
    }
    if (res.statusCode != 200) {
      throw HttpException('YouTube answered ${res.statusCode}');
    }
    return text;
  }

  /// Headers of a signed-in request from youtube.com (as yt-dlp builds them).
  @visibleForTesting
  static Map<String, String> headersFor(
    Map<String, String> cookies, {
    DateTime? now,
  }) {
    final time = ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000)
        .round();
    String hash(String scheme, String sid) =>
        '$scheme ${time}_${sha1.convert(utf8.encode('$time $sid $_origin'))}';
    final sapisid = cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];
    final auth = [
      if (sapisid != null) hash('SAPISIDHASH', sapisid),
      if (cookies['__Secure-1PAPISID'] != null)
        hash('SAPISID1PHASH', cookies['__Secure-1PAPISID']!),
      if (cookies['__Secure-3PAPISID'] != null)
        hash('SAPISID3PHASH', cookies['__Secure-3PAPISID']!),
    ].join(' ');
    return {
      'Content-Type': 'application/json',
      'User-Agent': webAgent,
      'Origin': _origin,
      'X-Origin': _origin,
      'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      if (auth.isNotEmpty) 'Authorization': auth,
      'X-Goog-AuthUser': '0',
      'X-Youtube-Client-Name': '1',
      'X-Youtube-Client-Version': webClientVersion,
      'X-Youtube-Bootstrap-Logged-In': 'true',
    };
  }

  // ---------------------------------------------------------------- parsing

  /// Videos (both of YouTube's item formats), the next-page token and, on
  /// Home, the category chips. Shorts, playlists, mixes and ads are skipped.
  @visibleForTesting
  static AccountFeedPage parse(
    AccountFeed feed,
    Object? json, {
    bool withChips = false,
  }) {
    // Cookies YouTube doesn't accept still get a 200: a signed-out page with no videos.
    if (json case {
      'responseContext': {'mainAppWebResponseContext': {'loggedOut': true}},
    }) {
      throw SignInExpired();
    }
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
      final video = videoOf(j);
      if (video != null) {
        if (seen.add(video.id.value)) videos.add(video);
        return;
      }
      if (j['videoRenderer'] is Map ||
          j['playlistVideoRenderer'] is Map ||
          j['lockupViewModel'] is Map) {
        return; // skipped kind
      }
      final cont = j['continuationItemRenderer'];
      if (cont is Map) {
        next = _token(cont['continuationEndpoint']) ?? next;
        return;
      }
      final chip = j['chipCloudChipRenderer'];
      if (chip is Map) {
        final label = _text(chip['text']);
        final token = _token(chip['navigationEndpoint']);
        if (withChips && label != null && token != null && label != 'All') {
          chips.add(AccountChip(label, token));
        }
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

  static Video? videoOf(Map item) => switch (item) {
    {'videoRenderer': final Map v} => _fromVideoRenderer(v),
    // A playlist's items (Watch later).
    {'playlistVideoRenderer': final Map v} => _fromVideoRenderer(v),
    {'lockupViewModel': final Map l} => _fromLockup(l),
    _ => null,
  };

  static String? text(Object? t) => _text(t);

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
    final owner =
        (v['ownerText'] ?? v['longBylineText'] ?? v['shortBylineText']) as Map?;
    final channel =
        ((((owner?['runs'] as List?)?.firstOrNull
                    as Map?)?['navigationEndpoint']
                as Map?)?['browseEndpoint']
            as Map?)?['browseId'];
    final length = _text(v['lengthText']);
    // Playlist items: "1.2M views", " • ", "3 years ago" in one line.
    final info = [
      for (final r in ((v['videoInfo'] as Map?)?['runs'] as List?) ?? const [])
        if ((r as Map)['text'] case final String s
            when s.trim() != '•' && s.trim().isNotEmpty)
          s.trim(),
    ];
    return _video(
      id: id,
      title: _text(v['title']) ?? '',
      author: _text(owner) ?? '',
      channelId: channel is String ? channel : null,
      duration: length,
      views: _text(v['viewCountText']) ?? info.firstOrNull,
      age: _text(v['publishedTimeText']) ?? (info.length > 1 ? info[1] : null),
    );
  }

  static Video? _fromLockup(Map l) {
    if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') {
      return null; // playlists, mixes
    }
    final id = l['contentId'];
    if (id is! String) return null;
    final meta = (l['metadata'] as Map?)?['lockupMetadataViewModel'] as Map?;
    final rows =
        ((((meta?['metadata'] as Map?)?['contentMetadataViewModel']
                as Map?)?['metadataRows'])
            as List?) ??
        [];
    List<String> parts(int i) => i < rows.length
        ? [
            for (final p
                in ((rows[i] as Map)['metadataParts'] as List?) ?? const [])
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
  static int parseViews(String? text) {
    final m = RegExp(
      r'([\d.,]+)\s*([KMB])?',
      caseSensitive: false,
    ).firstMatch(text ?? '');
    if (m == null) return 0;
    final number = double.tryParse(m[1]!.replaceAll(',', '')) ?? 0;
    final scale = switch (m[2]?.toUpperCase()) {
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      _ => 1.0,
    };
    return (number * scale).round();
  }
}

/// YouTube refused the saved sign-in (401/403): it expired or was signed
/// out elsewhere.
class SignInExpired extends StateError {
  SignInExpired() : super(ErrorText.signInExpired);
}
