import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/models/tiktok_item.dart';

/// Gets the next videos ready while one plays.
abstract class TiktokPrefetcher {
  /// These videos should be ready next (most wanted first).
  void want(List<TiktokItem> items);

  /// Deletes everything downloaded.
  Future<void> clear();
}

/// The first seconds of a TikTok video, on disk.
class TiktokHead {
  const TiktokHead({
    required this.path,
    required this.length,
    required this.total,
  });

  final String path;

  /// Bytes in the file (the video's first [length] bytes).
  final int length;

  /// The whole video's size.
  final int total;

  /// The file is the whole video (a short one).
  bool get complete => length >= total;
}

/// TikTok's app loads the start of the next videos while you watch, so a
/// swipe starts at once. This does the same: the first ~4 seconds of each
/// of the next videos are downloaded (a range request, one video at a
/// time), and TiktokHeadServer plays them from the file, then carries on
/// from TikTok. Only the start: whole videos cost data for videos often
/// swiped past.
class TiktokPrefetch implements TiktokPrefetcher {
  TiktokPrefetch({required this.folder, required this.headers});

  final Future<Directory> Function() folder;
  final Future<Map<String, String>> Function() headers;

  /// Heads kept (the newest); older ones are deleted.
  static const keep = 8;

  /// Seconds of video downloaded ahead.
  static const headSeconds = 4;

  static const defaultHeadMin = 256 << 10;
  static const defaultHeadMax = 2 << 20;

  /// Bounds of a head, whatever the video's bit rate (TikTok's 540p is
  /// ~0.7–1 Mbit/s: 4 s is ~400–600 KB).
  @visibleForTesting
  static int headMin = defaultHeadMin;
  @visibleForTesting
  static int headMax = defaultHeadMax;

  /// Bigger than this: not a reel, left to stream.
  @visibleForTesting
  static int maxBytes = 200 << 20;

  /// About [headSeconds] of a video of [total] bytes lasting [duration].
  static int headBytes(int total, Duration duration) {
    final guess = duration > Duration.zero
        ? total * headSeconds * 1000 ~/ duration.inMilliseconds
        : headMax ~/ 2;
    return math.min(total, guess.clamp(headMin, headMax).toInt());
  }

  final _ready = <String, TiktokHead>{}; // oldest first
  final _queue = <TiktokItem>[];
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  Future<void>? _running;
  Directory? _dir;
  int _generation = 0;

  /// The downloaded start of video [id], if there is one.
  TiktokHead? headFor(String id) => _ready[id];

  @override
  void want(List<TiktokItem> items) {
    _queue
      ..clear()
      ..addAll(
        items.where((i) => i.playUrl.isNotEmpty && !_ready.containsKey(i.id)),
      );
    _running ??= _pump().whenComplete(() => _running = null);
  }

  /// Done with everything asked for so far.
  @visibleForTesting
  Future<void> idle() async {
    while (_running != null) {
      await _running;
    }
  }

  Future<void> _pump() async {
    while (_queue.isNotEmpty) {
      await _fetch(_queue.removeAt(0));
    }
  }

  Future<Directory> _folder() async {
    final dir = _dir ??= await folder();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The whole size from TikTok's answer (`Content-Range: bytes 0-n/total`,
  /// or the length of a plain 200), null when it doesn't say.
  static int? totalOf(HttpClientResponse res) {
    if (res.statusCode == 206) {
      final m = RegExp(
        r'/(\d+)\s*$',
      ).firstMatch(res.headers.value('content-range') ?? '');
      return m == null ? null : int.parse(m[1]!);
    }
    return res.contentLength >= 0 ? res.contentLength : null;
  }

  Future<void> _fetch(TiktokItem item) async {
    final generation = _generation;
    final dir = await _folder();
    final part = File('${dir.path}/${item.id}.part');
    final sw = Stopwatch()..start();
    try {
      final req = await _client.getUrl(Uri.parse(item.playUrl));
      (await headers()).forEach(req.headers.set);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${headMax - 1}');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = totalOf(res);
      if (total == null || total <= 0) {
        throw const HttpException('size unknown');
      }
      if (total > maxBytes) {
        throw const HttpException('too big to load ahead');
      }
      final want = headBytes(total, item.duration);
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 20))) {
          final take = math.min(chunk.length, want - got);
          sink.add(take == chunk.length ? chunk : chunk.sublist(0, take));
          got += take;
          if (got >= want) break; // the rest plays from TikTok
        }
      } finally {
        await sink.close();
      }
      if (got < want) throw const HttpException('cut off');
      if (generation != _generation) {
        throw const HttpException('cleared meanwhile');
      }
      final done = part.renameSync('${dir.path}/${item.id}.mp4');
      _ready[item.id] = TiktokHead(path: done.path, length: got, total: total);
      debugPrint(
        '[TikTok] ready ahead: ${item.id} (first ${(got / 1024).round()} KB of '
        '${(total / 1048576).toStringAsFixed(1)} MB, ${sw.elapsedMilliseconds} ms)',
      );
      _trim();
    } catch (e) {
      debugPrint('[TikTok] loading ahead of ${item.id} failed: $e');
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
  }

  void _trim() {
    while (_ready.length > keep) {
      final oldest = _ready.keys.first;
      final head = _ready.remove(oldest)!;
      try {
        File(head.path).deleteSync();
      } catch (_) {}
    }
  }

  @override
  Future<void> clear() async {
    _generation++;
    _queue.clear();
    _ready.clear();
    try {
      final dir = _dir ?? await folder();
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          f.deleteSync(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[TikTok] clearing downloads ahead: $e');
    }
  }
}
