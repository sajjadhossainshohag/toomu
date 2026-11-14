import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// A playable audio item, independent of where it came from (device
/// library, finished download, or a YouTube stream).
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.uri,
    this.album,
    this.path,
    this.duration,
    this.localSongId,
    this.albumId,
    this.artworkUrl,
    this.dateAdded,
    this.sourceBuilder,
  });

  /// Custom audio source (e.g. YouTube streaming); default is a plain URI.
  final AudioSource Function(MediaItem item)? sourceBuilder;

  final String id;
  final String title;
  final String uri;
  final String? album;

  /// Absolute file path (for folder grouping). Null for remote streams.
  final String? path;
  final Duration? duration;

  /// MediaStore id, used to load embedded artwork.
  final int? localSongId;
  final int? albumId;
  final String? artworkUrl;
  final int? dateAdded;

  /// Album name when the file really has one (MediaStore reports
  /// `<unknown>` or nothing for untagged files); null otherwise.
  String? get subtitle {
    final a = album?.trim();
    return (a == null || a.isEmpty || a == '<unknown>') ? null : a;
  }

  String get displayAlbum =>
      (album == null || album!.isEmpty) ? 'Unknown album' : album!;

  String? get folder {
    if (path == null) return null;
    final i = path!.lastIndexOf('/');
    return i > 0 ? path!.substring(0, i) : null;
  }

  factory Track.fromMediaStore(Map<String, dynamic> m) {
    final id = (m['id'] as num).toInt();
    final path = m['path'] as String?;
    return Track(
      id: 'local:$id',
      title: m['title'] as String? ?? 'Unknown',
      uri: m['uri'] as String? ?? Uri.file(path ?? '').toString(),
      album: m['album'] as String?,
      path: path,
      duration: m['duration'] == null
          ? null
          : Duration(milliseconds: (m['duration'] as num).toInt()),
      localSongId: id,
      albumId: (m['albumId'] as num?)?.toInt(),
      dateAdded: (m['dateAdded'] as num?)?.toInt(),
    );
  }

  AudioSource toAudioSource() {
    final art = artworkUrl != null
        ? Uri.parse(artworkUrl!)
        : albumId != null
            ? Uri.parse('content://media/external/audio/albumart/$albumId')
            : null;
    final item = MediaItem(
      id: id,
      title: title,
      // Notification / lock-screen line under the title.
      artist: subtitle,
      album: subtitle,
      duration: duration,
      artUri: art,
      extras: {'localSongId': localSongId, 'path': path},
    );
    return sourceBuilder?.call(item) ?? AudioSource.uri(Uri.parse(uri), tag: item);
  }

}
