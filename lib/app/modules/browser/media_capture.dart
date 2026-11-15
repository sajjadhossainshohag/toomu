import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/utils/media_manifest.dart';
import '../../data/models/captured_media.dart';
import '../../data/models/download_task.dart';
import '../../services/download_service.dart';

class MediaCapture {
  final items = <CapturedMedia>[].obs;
  void Function(CapturedMedia media)? onFound;

  String userAgent = '';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 400,
    ),
  );
  final Set<String> _seen = {};
  final Set<String> _partOfMaster = {};
  final Set<String> _segmentKeys = {};
  final Map<String, List<String>> _byKey = {};
  final Queue<Map<String, dynamic>> _queue = Queue();
  int _probing = 0;
  int _generation = 0;

  static const _maxProbes = 3;
  static const _maxItems = 60;
  static const _minFileBytes = 150 * 1024;
  static const _audioExt = {'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'wav'};
  static const _extOfType = {
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'video/x-matroska': 'mkv',
    'video/3gpp': '3gp',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/flac': 'flac',
    'audio/wav': 'wav',
  };

  void reset() {
    items.clear();
    _seen.clear();
    _partOfMaster.clear();
    _segmentKeys.clear();
    _byKey.clear();
    _queue.clear();
    _generation++;
  }

  void onReport(Map<String, dynamic> m) {
    final url = m['url'];
    if (url is! String || !url.startsWith('http')) return;
    final ua = m['ua'];
    if (ua is String && ua.isNotEmpty) userAgent = ua;
    if (_seen.contains(url)) {
      _updateFromElement(url, m);
      return;
    }
    if (_segmentKeys.contains(MediaManifest.segmentKey(url)) || _partOfMaster.contains(url)) return;
    _seen.add(url);
    _queue.add(m);
    _pump();
  }

  void _pump() {
    while (_probing < _maxProbes && _queue.isNotEmpty) {
      final m = _queue.removeFirst();
      _probing++;
      final generation = _generation;
      unawaited(
        _probe(m, generation)
            .catchError((Object e) => debugPrint('[Capture] ${m['url']}: $e'))
            .whenComplete(() {
              _probing--;
              _pump();
            }),
      );
    }
  }

  Future<void> _probe(Map<String, dynamic> m, int generation) async {
    final url = m['url'] as String;
    final page = (m['page'] as String?) ?? url;
    final headers = <String, String>{
      if ((m['ua'] as String? ?? '').isNotEmpty) 'User-Agent': m['ua'] as String,
      'Referer': page,
    };
    final cookies = await DownloadService.webCookies(url);
    final request = {...headers, if (cookies.isNotEmpty) 'Cookie': cookies};
    final type = '${m['type'] ?? ''}'.toLowerCase();
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';

    CapturedMedia? media;
    if (path.endsWith('.m3u8') || type.contains('mpegurl')) {
      media = await _hls(url, page, headers, request);
    } else if (path.endsWith('.mpd') || type.contains('dash+xml')) {
      media = await _dash(url, page, headers, request);
    } else {
      media = await _file(url, page, headers, request, path);
    }
    if (media == null || generation != _generation) return;
    media.title = _titleOf(m, url);
    _applyElement(media, m);
    _add(media, fromRequest: m['source'] == 'request');
  }

  Future<CapturedMedia?> _hls(
    String url,
    String page,
    Map<String, String> headers,
    Map<String, String> request,
  ) async {
    final text = await _text(url, request);
    if (!text.trimLeft().startsWith('#EXTM3U')) return null;
    final info = MediaManifest.parseHls(text, Uri.parse(url));
    var duration = info.duration;
    var protected = info.protected;
    if (info.variants.isNotEmpty) {
      final parts = {...info.variants.map((v) => v.url), ...info.renditions.map((r) => r.url)};
      _partOfMaster.addAll(parts);
      items.removeWhere((i) => parts.contains(i.url));
      // Master playlists carry no duration or keys: read the best quality's.
      try {
        final bestUrl = info.variants.first.url;
        // The variant may be on another host: send only that host's cookies.
        final cookies = await DownloadService.webCookies(bestUrl);
        final best = MediaManifest.parseHls(
          await _text(bestUrl, {...headers, if (cookies.isNotEmpty) 'Cookie': cookies}),
          Uri.parse(bestUrl),
        );
        duration = best.duration;
        protected = protected || best.protected;
      } catch (_) {}
    }
    if (duration != null && duration.inSeconds < 3) return null;
    final bandwidth = info.variants.isEmpty ? 0 : info.variants.first.bandwidth;
    return CapturedMedia(
      url: url,
      type: CapturedType.hls,
      kind: info.audioOnly ? DownloadKind.audio : DownloadKind.video,
      pageUrl: page,
      headers: headers,
      duration: duration,
      variants: info.variants,
      protected: protected,
      size: duration == null ? 0 : bandwidth ~/ 8 * duration.inSeconds,
    );
  }

  Future<CapturedMedia?> _dash(
    String url,
    String page,
    Map<String, String> headers,
    Map<String, String> request,
  ) async {
    final xml = await _text(url, request);
    if (!xml.contains('<MPD')) return null;
    final info = MediaManifest.parseDash(xml, url);
    final bandwidth = info.variants.isEmpty ? 0 : info.variants.first.bandwidth;
    final duration = info.duration;
    return CapturedMedia(
      url: url,
      type: CapturedType.dash,
      kind: info.audioOnly ? DownloadKind.audio : DownloadKind.video,
      pageUrl: page,
      headers: headers,
      duration: duration,
      variants: info.variants,
      protected: info.protected,
      size: duration == null ? 0 : bandwidth ~/ 8 * duration.inSeconds,
    );
  }

  Future<CapturedMedia?> _file(
    String url,
    String page,
    Map<String, String> headers,
    Map<String, String> request,
    String path,
  ) async {
    final r = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...request, 'Range': 'bytes=0-0'},
      ),
    );
    unawaited(r.data?.stream.listen(null).cancel());
    final type = (r.headers.value('content-type') ?? '').split(';').first.trim().toLowerCase();
    if (type.startsWith('text/') || type.contains('json') || type.contains('xml') || type.startsWith('image/')) {
      return null;
    }
    final range = r.headers.value('content-range') ?? '';
    final size = r.statusCode == 206
        ? int.tryParse(range.split('/').last) ?? 0
        : int.tryParse(r.headers.value('content-length') ?? '') ?? 0;
    if (size > 0 && size < _minFileBytes) return null;
    final dot = path.lastIndexOf('.');
    final urlExt = dot > 0 ? path.substring(dot + 1) : '';
    final ext = _extOfType[type] ?? (urlExt.isNotEmpty && urlExt.length <= 4 ? urlExt : 'mp4');
    return CapturedMedia(
      url: url,
      type: CapturedType.file,
      kind: type.startsWith('audio/') || _audioExt.contains(ext) ? DownloadKind.audio : DownloadKind.video,
      pageUrl: page,
      headers: headers,
      ext: ext,
      size: size,
    );
  }

  Future<String> _text(String url, Map<String, String> headers) async {
    final r = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain, headers: headers),
    );
    return r.data ?? '';
  }

  void _add(CapturedMedia media, {required bool fromRequest}) {
    if (_partOfMaster.contains(media.url)) return;
    if (fromRequest && media.type == CapturedType.file) {
      final key = MediaManifest.segmentKey(media.url);
      final group = _byKey.putIfAbsent(key, () => [])..add(media.url);
      if (MediaManifest.looksLikeSegments(group)) {
        _segmentKeys.add(key);
        items.removeWhere((i) => MediaManifest.segmentKey(i.url) == key);
        return;
      }
    }
    items.insert(0, media);
    if (items.length > _maxItems) items.removeLast();
    onFound?.call(media);
  }

  void _updateFromElement(String url, Map<String, dynamic> m) {
    for (final i in items) {
      if (i.url == url) {
        _applyElement(i, m);
        items.refresh();
        return;
      }
    }
  }

  static void _applyElement(CapturedMedia media, Map<String, dynamic> m) {
    final seconds = (m['duration'] as num?)?.toDouble() ?? 0;
    if (seconds > 0 && media.duration == null) {
      media.duration = Duration(milliseconds: (seconds * 1000).round());
    }
    final height = (m['height'] as num?)?.toInt() ?? 0;
    if (height > 0 && media.height == 0) {
      media.height = height;
      media.width = (m['width'] as num?)?.toInt() ?? 0;
    }
    final poster = m['poster'];
    if (poster is String && poster.startsWith('http') && media.poster.isEmpty) media.poster = poster;
  }

  static String _titleOf(Map<String, dynamic> m, String url) {
    final title = '${m['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final segments = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty) ?? const <String>[];
    if (segments.isEmpty) return 'Video';
    try {
      return Uri.decodeComponent(segments.last);
    } catch (_) {
      return segments.last;
    }
  }
}
