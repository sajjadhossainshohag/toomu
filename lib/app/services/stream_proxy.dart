import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../data/models/yt_info.dart';
import 'ytdlp_service.dart';

/// A small HTTP server on 127.0.0.1 between the players (mpv for videos,
/// ExoPlayer for "Play audio") and YouTube's media servers.
///
/// Why (measured Nov 2026):
///  - YouTube's media servers answer what players ask for — "everything
///    from byte N on" — with 403, or throttle it to ~6 Mbit/s. Asked for at
///    most ~10 MB at a time with a `range=` URL parameter (the way YouTube's
///    own apps ask), the same file comes at full speed (130–200 Mbit/s on a
///    fast line). The proxy turns each player request into a series of such
///    pieces, and quietly re-asks for a piece when a connection drops.
///  - Links from the fast lookup (YouTube's Android client: ~0.3 s, no
///    yt-dlp) only serve about the first minute of a file without a PO
///    token. The proxy plays from them at once while yt-dlp looks the video
///    up, then carries on with yt-dlp's links: the same itag and size is the
///    very same file (byte for byte), so the player never notices.
class StreamProxy extends GetxService {
  StreamProxy({Future<YtInfo> Function(String videoId)? fullLookup, bool Function(Uri url)? isMediaFile})
      : _fullLookup = fullLookup ?? _ytDlpLookup,
        _isMediaFile = isMediaFile ?? _isYoutubeMedia;

  static StreamProxy get to => Get.find();

  /// Where full links come from (yt-dlp; replaceable in tests).
  final Future<YtInfo> Function(String videoId) _fullLookup;
  final bool Function(Uri url) _isMediaFile;

  static Future<YtInfo> _ytDlpLookup(String videoId) =>
      YtDlpService.to.info('https://www.youtube.com/watch?v=$videoId');

  static bool _isYoutubeMedia(Uri url) => url.host.endsWith('.googlevideo.com');

  HttpServer? _server;

  /// YouTube ties each link to the address it was looked up from (`ip=`):
  /// fetched over the other IP version (IPv4 vs IPv6) it answers 403. One
  /// client per IP version, so pooled connections never mix them.
  final Map<InternetAddressType?, HttpClient> _clients = {};

  HttpClient _clientFor(Uri url) {
    final ip = url.queryParameters['ip'];
    final type = ip == null
        ? null
        : ip.contains(':')
            ? InternetAddressType.IPv6
            : InternetAddressType.IPv4;
    return _clients.putIfAbsent(type, () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..idleTimeout = const Duration(seconds: 20);
      if (type != null) {
        client.connectionFactory = (uri, proxyHost, proxyPort) async {
          List<InternetAddress> addresses = const [];
          try {
            addresses = await InternetAddress.lookup(uri.host, type: type);
          } catch (_) {}
          // No address of that version: let the system choose.
          final Object host = addresses.isEmpty ? uri.host : addresses.first;
          return uri.scheme == 'https'
              ? SecureSocket.startConnect(host, uri.port)
              : Socket.startConnect(host, uri.port);
        };
      }
      return client;
    });
  }

  final Map<String, _File> _files = {};

  /// yt-dlp's (full) links per video, for files registered after they came.
  final Map<String, ({YtInfo info, DateTime at})> _full = {};
  final Map<String, Future<void>> _lookups = {};

  /// The first piece is small so the player starts quickly; later pieces
  /// double up to the largest size YouTube serves in one go (~10 MB).
  static const _firstPiece = 1 << 20;
  static const _maxPiece = 8 << 20;

  /// A piece that sends nothing for this long is asked for again.
  static const _stallLimit = Duration(seconds: 12);
  static const _maxFailures = 6;

  /// How long a request at the end of a fast link's free minute waits for
  /// yt-dlp's links (its lookup has its own, shorter limits).
  static const _upgradeWait = Duration(minutes: 4);

  Future<StreamProxy> init() async {
    await _bind();
    return this;
  }

  Future<void> _bind() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_handle, onError: (Object e) => debugPrint('[Proxy] $e'), onDone: () {
        if (identical(_server, server)) _server = null;
      });
      _server = server;
    } catch (e) {
      // Players then use YouTube's links directly (slower, may be refused).
      debugPrint('[Proxy] could not start: $e');
    }
  }

  /// The local address that plays [url] (a YouTube media file) through the
  /// proxy — or [url] itself when it isn't one the proxy can serve.
  ///
  /// [partial]: the link only serves the start of the file (fast lookup);
  /// the proxy gets yt-dlp's links for [videoId] to carry on. The same file
  /// always gets the same local address, so re-opening it keeps links
  /// already upgraded.
  String wrap(
    String url, {
    Map<String, String> headers = const {},
    String? videoId,
    bool partial = false,
  }) {
    final server = _server;
    if (server == null) {
      unawaited(_bind()); // for next time
      return url;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !_isMediaFile(uri)) return url;
    final q = uri.queryParameters;
    final length = int.tryParse(q['clen'] ?? '');
    final itag = q['itag'];
    if (length == null || length <= 0 || itag == null || q.containsKey('range')) return url;

    final owner = videoId ?? q['id'] ?? 'video';
    final key = '${owner.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}-$itag-$length';
    final file = _files.putIfAbsent(
      key,
      () => _File(url: url, headers: headers, length: length, itag: itag, mime: q['mime'], videoId: videoId, partial: partial),
    );
    // A newer link replaces the stored one (links expire after hours, or
    // when the phone's IP changes), but a fresh full link is kept over a
    // fast link that only serves the first minute.
    if (file.url != url && (!partial || file.partial || file.stale)) file.relink(url, headers, partial: partial);
    file.lastUsed = DateTime.now();
    if (file.partial && videoId != null) {
      final full = _full[videoId];
      // Look the video up right away: yt-dlp's links should be ready by
      // the time the free minute runs out.
      full != null && !_isStale(full.at) ? _offer(file, full.info) : _lookUp(videoId);
    }
    _prune();
    return 'http://127.0.0.1:${server.port}/yt/$key';
  }

  /// yt-dlp's info JSON with its YouTube media links pointed at the proxy,
  /// so downloads — yt-dlp's own and aria2c's parallel connections, which
  /// ask for huge ranges YouTube throttles or refuses — are fetched in
  /// pieces YouTube serves at full speed. Unchanged if nothing applies.
  String routeInfoJson(String json) {
    if (_server == null) return json;
    try {
      final info = jsonDecode(json) as Map<String, dynamic>;
      final id = info['id'] as String?;
      var routed = 0;
      void route(Map<String, dynamic> f) {
        final url = f['url'];
        final protocol = f['protocol'] as String?;
        if (url is! String || (protocol != null && protocol != 'https' && protocol != 'http')) return;
        final headers = <String, String>{
          for (final e in ((f['http_headers'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
        };
        final local = wrap(url, headers: headers, videoId: id);
        if (local != url) {
          f['url'] = local;
          routed++;
        }
      }

      for (final key in ['formats', 'requested_formats']) {
        for (final f in (info[key] as List?) ?? const []) {
          if (f is Map<String, dynamic>) route(f);
        }
      }
      route(info); // a single-format result keeps its link at the top
      return routed == 0 ? json : jsonEncode(info);
    } catch (e) {
      debugPrint('[Proxy] info JSON left as is: $e');
      return json;
    }
  }

  /// yt-dlp's links for [videoId]: files playing from fast links carry on
  /// with these (already-identical files only).
  void offerFullLinks(String videoId, YtInfo info) {
    _full[videoId] = (info: info, at: DateTime.now());
    if (_full.length > 20) _full.remove(_full.keys.first);
    for (final f in _files.values) {
      if (f.videoId == videoId && f.partial) _offer(f, info);
    }
  }

  void _offer(_File f, YtInfo info) {
    for (final format in info.formats) {
      final url = format.url;
      if (url == null) continue;
      final q = Uri.tryParse(url)?.queryParameters;
      if (q == null || q['itag'] != f.itag || q['clen'] != '${f.length}') continue;
      f.upgrade(url, format.httpHeaders);
      debugPrint('[Proxy] ${f.videoId} itag ${f.itag}: carrying on with yt-dlp\'s links');
      return;
    }
    f.noUpgrade('yt-dlp has no identical copy of itag ${f.itag}');
  }

  void _lookUp(String videoId) {
    _lookups[videoId] ??= () async {
      try {
        final info = await _fullLookup(videoId);
        offerFullLinks(videoId, info);
      } catch (e) {
        debugPrint('[Proxy] no full links for $videoId: $e');
        for (final f in _files.values) {
          if (f.videoId == videoId && f.partial) f.noUpgrade(e);
        }
      } finally {
        _lookups.remove(videoId);
      }
    }();
  }

  /// Forgets files nobody played for hours (their links have expired).
  void _prune() {
    if (_files.length < 48) return;
    final old = DateTime.now().subtract(const Duration(hours: 3));
    _files.removeWhere((_, f) => f.lastUsed.isBefore(old));
  }

  // ------------------------------------------------------------- serving

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    var gone = false;
    res.done.then<void>((_) {}, onError: (Object _) {
      gone = true;
    });
    try {
      final seg = req.uri.pathSegments;
      final f = seg.length == 2 && seg[0] == 'yt' ? _files[seg[1]] : null;
      if (f == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      f.lastUsed = DateTime.now();
      final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), f.length);
      if (range == null) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${f.length}');
        return;
      }
      final (start, end, partialContent) = range;
      if (partialContent) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${f.length}');
      }
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (f.mime != null) res.headers.set(HttpHeaders.contentTypeHeader, f.mime!);
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') return;
      await _pump(f, start, end, res, () => gone);
    } catch (e) {
      if (!gone) debugPrint('[Proxy] ${req.uri.path}: $e');
    } finally {
      // Fewer bytes than promised (gave up) makes this throw and drop the
      // connection; the player then reconnects or reports the error.
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// `Range` header → (start, end, is-partial); null when unsatisfiable.
  @visibleForTesting
  static (int, int, bool)? parseRange(String? header, int total) {
    final m = header == null ? null : RegExp(r'^\s*bytes=(\d*)-(\d*)').firstMatch(header);
    if (m == null || (m[1]!.isEmpty && m[2]!.isEmpty)) return (0, total - 1, false);
    int start, end = total - 1;
    if (m[1]!.isEmpty) {
      start = math.max(0, total - int.parse(m[2]!)); // last N bytes
    } else {
      start = int.parse(m[1]!);
      if (m[2]!.isNotEmpty) end = math.min(int.parse(m[2]!), total - 1);
    }
    if (start >= total || start > end) return null;
    return (start, end, true);
  }

  /// Bytes [start]..[end] of [f] into [out], piece by piece.
  Future<void> _pump(_File f, int start, int end, HttpResponse out, bool Function() gone) async {
    var pos = start;
    var size = _firstPiece;
    var failures = 0;
    while (pos <= end && !gone()) {
      final last = math.min(end, pos + size - 1);
      final piece = await _copyPiece(f, pos, last, out);
      if (piece.clientGone) return;
      pos += piece.got;
      if (piece.got > 0) failures = 0;
      if (pos > last) {
        size = math.min(size * 2, _maxPiece);
        continue;
      }
      final status = piece.status;
      if (f.partial && (status == 403 || status == 401 || status == 410)) {
        // A big piece may straddle the end of the free minute: take what's
        // left of it in small pieces first.
        if (size > _firstPiece) {
          size = _firstPiece;
          continue;
        }
        // The fast link's free minute is over: wait for yt-dlp's links.
        debugPrint('[Proxy] ${f.videoId} itag ${f.itag}: fast link ends at '
            '${(pos / 1048576).toStringAsFixed(1)} MB; waiting for full links');
        if (f.videoId != null) _lookUp(f.videoId!);
        await f.whenFull().timeout(_upgradeWait);
        continue;
      }
      if (++failures > _maxFailures) {
        throw HttpException('YouTube refused the stream (${status ?? piece.error})');
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * failures));
    }
  }

  /// One piece (bytes [from]..[to]) from YouTube, copied into [out] as it
  /// arrives.
  Future<_Piece> _copyPiece(_File f, int from, int to, HttpResponse out) async {
    final HttpClientResponse res;
    try {
      final url = Uri.parse('${f.url}&range=$from-$to');
      final req = await _clientFor(url).getUrl(url);
      f.headers.forEach((name, value) {
        final n = name.toLowerCase();
        if (n != 'range' && n != 'accept-encoding' && n != 'host') req.headers.set(name, value);
      });
      res = await req.close().timeout(_stallLimit);
    } catch (e) {
      return _Piece(0, error: e);
    }
    if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
      // Don't read the error page; drop the connection.
      unawaited(res.listen(null).cancel());
      return _Piece(0, status: res.statusCode);
    }
    // Exactly the bytes asked for, or nothing: a server that ignored the
    // range would otherwise put the wrong part of the file into a video
    // or download.
    final expected = to - from + 1;
    if (res.contentLength >= 0 && res.contentLength != expected) {
      unawaited(res.listen(null).cancel());
      return _Piece(0, error: 'got ${res.contentLength} bytes for a $expected-byte piece');
    }
    return _pipe(res, out, limit: expected);
  }

  /// Copies [from] into [to], reading from YouTube only as fast as the
  /// player takes the data (its buffer may be full for minutes): nothing
  /// piles up in memory.
  Future<_Piece> _pipe(HttpClientResponse from, HttpResponse to, {required int limit}) {
    final done = Completer<_Piece>();
    var got = 0;
    Timer? stall;
    late final StreamSubscription<List<int>> sub;
    void finish({Object? error, bool clientGone = false}) {
      stall?.cancel();
      if (!done.isCompleted) done.complete(_Piece(got, error: error, clientGone: clientGone));
    }

    void watch() {
      stall?.cancel();
      stall = Timer(_stallLimit, () {
        sub.cancel();
        finish(error: 'no data for ${_stallLimit.inSeconds} s');
      });
    }

    sub = from.listen(
      (data) {
        if (got + data.length > limit) {
          // More than asked for (no length given up front): never pass it on.
          sub.cancel();
          finish(error: 'server sent more than the requested piece');
          return;
        }
        got += data.length;
        try {
          to.add(data);
        } catch (_) {
          sub.cancel();
          finish(clientGone: true);
          return;
        }
        stall?.cancel();
        sub.pause();
        to.flush().then((_) {
          if (done.isCompleted) return;
          watch();
          sub.resume();
        }, onError: (Object _) {
          sub.cancel();
          finish(clientGone: true);
        });
      },
      onError: (Object e) {
        sub.cancel();
        finish(error: e);
      },
      onDone: finish,
      cancelOnError: true,
    );
    watch();
    return done.future;
  }

  @override
  void onClose() {
    _server?.close(force: true);
    for (final c in _clients.values) {
      c.close(force: true);
    }
    super.onClose();
  }
}

bool _isStale(DateTime linkedAt) => DateTime.now().difference(linkedAt) > const Duration(hours: 1);

/// One YouTube media file the players can ask the proxy for.
class _File {
  _File({
    required this.url,
    required this.headers,
    required this.length,
    required this.itag,
    required this.partial,
    this.mime,
    this.videoId,
  });

  String url;
  Map<String, String> headers;

  /// Only the start of the file is served (a fast-lookup link).
  bool partial;
  final int length;
  final String itag;
  final String? mime;
  final String? videoId;
  DateTime lastUsed = DateTime.now();
  Completer<void>? _waiting;

  DateTime linkedAt = DateTime.now();
  bool get stale => _isStale(linkedAt);

  void relink(String newUrl, Map<String, String> newHeaders, {required bool partial}) {
    if (!partial) return upgrade(newUrl, newHeaders);
    url = newUrl;
    headers = newHeaders;
    this.partial = true;
    linkedAt = DateTime.now();
  }

  void upgrade(String fullUrl, Map<String, String> fullHeaders) {
    url = fullUrl;
    headers = fullHeaders;
    partial = false;
    linkedAt = DateTime.now();
    _waiting?.complete();
    _waiting = null;
  }

  void noUpgrade(Object reason) {
    _waiting?.completeError(reason);
    _waiting = null;
  }

  /// Completes once full links are in.
  Future<void> whenFull() => partial ? (_waiting ??= Completer<void>()).future : Future.value();
}

class _Piece {
  const _Piece(this.got, {this.status, this.error, this.clientGone = false});

  /// Bytes copied to the player.
  final int got;

  /// YouTube's refusal (HTTP status), if any.
  final int? status;
  final Object? error;

  /// The player hung up (seeked, closed): stop.
  final bool clientGone;
}
