import 'dart:io';

import 'package:flutter/services.dart';

import '../models/track.dart';

/// Reads the device music library (Android MediaStore) through our own
/// native channel in MainActivity.kt.
class LocalMusicProvider {
  static const _channel = MethodChannel('toomu/media_library');

  Future<List<Track>> songs() async {
    if (!Platform.isAndroid) return const [];
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('songs') ?? const [];
    return raw.map((m) => Track.fromMediaStore(Map<String, dynamic>.from(m))).toList();
  }

  /// Deletes songs from the device; Android may show a confirmation.
  /// True if deleted, false if the user declined.
  Future<bool> delete(List<int> ids) async =>
      (await _channel.invokeMethod<bool>('delete', {'ids': ids})) ?? false;
}

/// In-memory LRU cache of cover art so list scrolling doesn't re-query.
class ArtworkCache {
  ArtworkCache._();

  static const _channel = MethodChannel('toomu/media_library');
  static const _maxEntries = 300;
  static final _cache = <String, Future<Uint8List?>>{}; // insertion-ordered

  static Future<Uint8List?> load(int songId, {int size = 200}) {
    final key = '$songId@$size';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // refresh LRU position
    final future = _fetch(songId, size);
    _cache[key] = future;
    if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
    return future;
  }

  static Future<Uint8List?> _fetch(int songId, int size) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('artwork', {'id': songId, 'size': size});
    } on PlatformException {
      return null;
    }
  }
}
