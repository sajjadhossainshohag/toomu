import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/models/tiktok_item.dart';
import '../../services/tiktok_service.dart';
import 'tiktok_prefetch.dart';

/// Plays a TikTok video whose first seconds were loaded ahead: a small
/// server on 127.0.0.1 answers the player's (range) requests, the bytes the
/// head has from its file at once, the rest from TikTok (the same range,
/// TikTok's headers added), so playback carries on past the head without a
/// pause. A seek past the head goes straight to TikTok. TikTok's files have
/// their index (`moov`) at the start, so the head alone starts the video.
class TiktokHeadServer {
  TiktokHeadServer({required this.headers});

  /// The app's one server (made and bound on first use).
  static final shared = TiktokHeadServer(headers: TiktokService.playHeaders);

  final Future<Map<String, String>> Function() headers;

  /// Videos remembered (the newest).
  static const keep = 16;

  final _videos = <String, ({TiktokHead head, String url})>{};
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  Future<HttpServer?>? _binding;
  HttpServer? _server;

  /// The local address for [item] with [head]; null if the server can't
  /// run (then the video plays from TikTok as before).
  Future<String?> urlFor(TiktokItem item, TiktokHead head) async {
    final server = await (_binding ??= _bind());
    if (server == null) return null;
    _videos.remove(item.id);
    _videos[item.id] = (head: head, url: item.playUrl);
    while (_videos.length > keep) {
      _videos.remove(_videos.keys.first);
    }
    return 'http://127.0.0.1:${server.port}/tt/${item.id}.mp4';
  }

  Future<HttpServer?> _bind() async {
    try {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) => unawaited(_serve(req)));
      return _server = s;
    } catch (e) {
      debugPrint('[TikTok] head server failed to start: $e');
      _binding = null;
      return null;
    }
  }

  Future<void> close() async {
    final s = _server;
    _server = null;
    _binding = null;
    await s?.close(force: true);
  }

  /// `bytes=a-b` / `bytes=a-` of a [total]-byte file → (from, to), both
  /// inclusive; null when there's no (usable) range.
  @visibleForTesting
  static (int, int)? rangeOf(String? header, int total) {
    final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header ?? '');
    if (m == null) return null;
    if (m[1]!.isEmpty) {
      if (m[2]!.isEmpty) return null;
      final last = int.parse(m[2]!); // the last N bytes
      return (math.max(0, total - last), total - 1);
    }
    final from = int.parse(m[1]!);
    final to = m[2]!.isEmpty
        ? total - 1
        : math.min(int.parse(m[2]!), total - 1);
    return (from, to);
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final segments = req.uri.pathSegments;
      final name = segments.length == 2 && segments.first == 'tt'
          ? segments.last
          : '';
      final video =
          _videos[name.endsWith('.mp4')
              ? name.substring(0, name.length - 4)
              : ''];
      if (video == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final total = video.head.total;
      final header = req.headers.value(HttpHeaders.rangeHeader);
      final range = rangeOf(header, total);
      if (header != null &&
          (range == null || range.$1 > range.$2 || range.$1 >= total)) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      final (from, to) = range ?? (0, total - 1);
      res.headers.contentType = ContentType('video', 'mp4');
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (range != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $from-$to/$total',
        );
      }
      res.contentLength = to - from + 1;
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      var at = from;
      final file = File(video.head.path);
      final have = file.existsSync()
          ? math.min(video.head.length, file.lengthSync())
          : 0;
      if (at < have) {
        final end = math.min(to + 1, have);
        await res.addStream(file.openRead(at, end));
        at = end;
      }
      if (at <= to) await _fromTiktok(video.url, at, to, res);
      await res.close();
    } catch (e) {
      debugPrint('[TikTok] head server: $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// Bytes [from]..[to] of TikTok's file, written to [out].
  Future<void> _fromTiktok(
    String url,
    int from,
    int to,
    HttpResponse out,
  ) async {
    final req = await _client.getUrl(Uri.parse(url));
    (await headers()).forEach(req.headers.set);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 206 && res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('TikTok answered ${res.statusCode}');
    }
    // A 200 is the whole file: skip to [from].
    var skip = res.statusCode == 200 ? from : 0;
    var left = to - from + 1;
    await for (final chunk in res) {
      var part = chunk;
      if (skip > 0) {
        if (part.length <= skip) {
          skip -= part.length;
          continue;
        }
        part = part.sublist(skip);
        skip = 0;
      }
      if (part.length > left) part = part.sublist(0, left);
      out.add(part);
      left -= part.length;
      if (left <= 0) break;
    }
  }
}
