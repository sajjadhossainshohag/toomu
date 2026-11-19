import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/download_service.dart';
import '../models/track.dart';

Future<List<Map<String, dynamic>>> appFolderItems(String sub) {
  final path = '${DownloadService.to.downloadRoot}/$sub';
  return Isolate.run(() => folderItems(path, sub));
}

@visibleForTesting
List<Map<String, dynamic>> folderItems(String path, String sub) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return [
    for (final f in dir.listSync().whereType<File>())
      if (!f.path.endsWith('.part'))
        () {
          final name = f.uri.pathSegments.last;
          final dot = name.lastIndexOf('.');
          return <String, dynamic>{
            // Relative key: the app container path changes between installs.
            'id': '$sub/$name'.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffffffff),
            'path': '$path/$name', // Not f.path: on Windows it joins with a backslash, which the subtitle lookup doesn't split on.
            'uri': Uri.file(f.path).toString(),
            'name': name,
            'title': dot > 0 ? name.substring(0, dot) : name,
            'size': f.lengthSync(),
            'dateAdded': f.lastModifiedSync().millisecondsSinceEpoch ~/ 1000,
            'folder': 'Toomu',
          };
        }(),
  ];
}

/// Reads the device music library (Android MediaStore) through our own
/// native channel in MainActivity.kt.
class LocalMusicProvider {
  static const _channel = MethodChannel('toomu/media_library');

  Future<List<Track>> songs() async {
    final raw = Platform.isAndroid
        ? await _channel.invokeListMethod<Map<dynamic, dynamic>>('songs') ?? const []
        : await appFolderItems('Audio');
    return raw.map((m) => Track.fromMediaStore(Map<String, dynamic>.from(m))).toList();
  }

  /// Deletes songs from the device; Android may show a confirmation.
  /// True if deleted, false if the user declined.
  Future<bool> delete(List<int> ids) async {
    if (!Platform.isAndroid) {
      for (final m in await appFolderItems('Audio')) {
        if (ids.contains(m['id'])) await File(m['path'] as String).delete();
      }
      return true;
    }
    return (await _channel.invokeMethod<bool>('delete', {'ids': ids})) ?? false;
  }
}

/// In-memory LRU cache of cover art so list scrolling doesn't re-query.
class ArtworkCache {
  ArtworkCache._();

  static const _channel = MethodChannel('toomu/media_library');
  static const _maxEntries = 300;
  static final _cache = <String, Future<Uint8List?>>{}; // insertion-ordered

  static void clear() => _cache.clear();

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
