import 'dart:io';

import 'package:flutter/services.dart';

import '../models/video_item.dart';
import 'local_music_provider.dart';

/// Device videos via MediaStore (native, MainActivity.kt).
class LocalVideoProvider {
  static const _channel = MethodChannel('toomu/media_library');

  Future<List<VideoItem>> videos() async {
    final raw = Platform.isAndroid
        ? await _channel.invokeListMethod<Map<dynamic, dynamic>>('videos') ?? const []
        : await appFolderItems('Video');
    return raw.map((m) => VideoItem.fromMediaStore(Map<String, dynamic>.from(m))).toList();
  }
}

/// In-memory cache of video thumbnails so scrolling doesn't re-decode.
class VideoThumbCache {
  VideoThumbCache._();

  static const _channel = MethodChannel('toomu/media_library');
  static const _maxEntries = 300;
  static final _cache = <int, Future<Uint8List?>>{}; // insertion-ordered

  static Future<Uint8List?> load(int videoId) {
    final hit = _cache.remove(videoId);
    if (hit != null) return _cache[videoId] = hit; // refresh LRU position
    final future = _fetch(videoId);
    _cache[videoId] = future;
    if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
    return future;
  }

  static Future<Uint8List?> _fetch(int id) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('videoThumb', {'id': id, 'size': 320});
    } on PlatformException {
      return null;
    }
  }
}
