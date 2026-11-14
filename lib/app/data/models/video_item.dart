/// A playable video: from the device library, a Toomu download, a file
/// opened from another app ("Open with Toomu"), or a YouTube stream.
class VideoItem {
  const VideoItem({
    required this.uri,
    required this.title,
    this.id,
    this.path,
    this.duration,
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.dateAdded = 0,
    this.folder,
    this.audioUri,
    this.httpHeaders = const {},
    this.remoteKey,
    this.thumbnailUrl,
    this.fallback,
    this.qualities = const [],
    this.provisional = false,
    this.partial = false,
  });

  /// Streams: links from the fast lookup (no yt-dlp). They start in well
  /// under a second; if they fail anyway, the player switches to yt-dlp's
  /// links at the same position.
  final bool provisional;

  /// Streams: the links only serve about the first minute (fast lookup
  /// without a whole-file client); the stream proxy carries on with
  /// yt-dlp's links for the same files.
  final bool partial;

  /// Streams: the YouTube video id (from the "yt:…" key).
  String? get youtubeId => remoteKey != null && remoteKey!.startsWith('yt:') ? remoteKey!.substring(3) : null;

  /// Streams: every quality the player can switch to (best first).
  final List<StreamQuality> qualities;

  /// Streams: the quality now playing (matched by video URL).
  StreamQuality? get currentQuality {
    for (final q in qualities) {
      if (q.videoUri == uri) return q;
    }
    return null;
  }

  /// The same stream at another quality (keeps the list and fallback).
  VideoItem withQuality(StreamQuality q) => VideoItem(
        uri: q.videoUri,
        audioUri: q.audioUri,
        httpHeaders: q.httpHeaders,
        title: title,
        duration: duration,
        width: q.width,
        height: q.height,
        remoteKey: remoteKey,
        thumbnailUrl: thumbnailUrl,
        fallback: fallback,
        qualities: qualities,
        provisional: provisional,
        partial: partial,
      );

  /// Streams: separate audio played alongside [uri] (YouTube serves HD as
  /// video-only + audio-only streams).
  final String? audioUri;

  /// Streams: headers the server expects (e.g. the client's User-Agent).
  final Map<String, String> httpHeaders;

  /// Streams: stable identity (stream URLs expire), e.g. "yt:dQw4w9WgXcQ".
  final String? remoteKey;

  /// Streams: artwork for the mini bar and media controls.
  final String? thumbnailUrl;

  /// Streams: what to switch to if this one fails to play (a simpler
  /// combined stream).
  final VideoItem? fallback;

  bool get isStream => remoteKey != null;

  /// MediaStore id (thumbnails); null for files opened from other apps.
  final int? id;
  final String uri;
  final String title;
  final String? path;
  final Duration? duration;
  final int size;
  final int width;
  final int height;
  final int dateAdded;
  final String? folder;

  /// Key for remembering the playback position.
  String get resumeKey => remoteKey ?? path ?? uri;

  bool get isLandscape => width == 0 || height == 0 ? true : width >= height;

  /// Width and height are known (files opened from other apps and fresh
  /// downloads learn theirs only once they play).
  bool get hasSize => width > 0 && height > 0;

  /// "1080p", "720p"… from the shorter side.
  String? get quality {
    if (width == 0 || height == 0) return null;
    final p = width < height ? width : height;
    if (p >= 2160) return '4K';
    if (p >= 1440) return '1440p';
    return '${p}p';
  }

  /// What media_kit opens: the file path when known (fastest), else the URI.
  String get playable => path ?? uri;

  factory VideoItem.fromMediaStore(Map<String, dynamic> m) {
    final name = (m['name'] as String?) ?? '';
    final title = (m['title'] as String?)?.trim();
    final ms = (m['duration'] as num?)?.toInt() ?? 0;
    return VideoItem(
      id: (m['id'] as num).toInt(),
      uri: m['uri'] as String,
      title: (title == null || title.isEmpty) ? _stripExtension(name) : title,
      path: m['path'] as String?,
      duration: ms > 0 ? Duration(milliseconds: ms) : null,
      size: (m['size'] as num?)?.toInt() ?? 0,
      width: (m['width'] as num?)?.toInt() ?? 0,
      height: (m['height'] as num?)?.toInt() ?? 0,
      dateAdded: (m['dateAdded'] as num?)?.toInt() ?? 0,
      folder: m['folder'] as String?,
    );
  }

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// A file outside the library (download, shared from another app).
  /// [title] is shown as is; a file [name] (or the path's last part)
  /// loses its extension.
  factory VideoItem.file(String pathOrUri, {String? name, String? title}) {
    final isUri = pathOrUri.contains('://');
    String fromPath() {
      final last = pathOrUri.split('/').last;
      // Only URIs are %-encoded. Decoding a plain path throws on Bengali
      // or emoji names and on a literal "%" ("100% Love.mp4").
      if (!isUri) return last;
      try {
        return Uri.decodeComponent(last);
      } catch (_) {
        return last;
      }
    }

    return VideoItem(
      uri: isUri ? pathOrUri : Uri.file(pathOrUri).toString(),
      path: isUri ? null : pathOrUri,
      title: title ?? _stripExtension(name ?? fromPath()),
    );
  }
}

/// One quality of a stream (e.g. 1080p60 H.264 + the audio track).
class StreamQuality {
  const StreamQuality({
    required this.label,
    required this.quality,
    required this.videoUri,
    required this.width,
    required this.height,
    this.audioUri,
    this.httpHeaders = const {},
    this.codec,
    this.fps,
  });

  /// "1080p60", "720p", "4K"…
  final String label;

  /// Quality class (2160, 1080, 720…), for remembering the choice.
  final int quality;
  final String videoUri;
  final String? audioUri;
  final Map<String, String> httpHeaders;
  final int width;
  final int height;

  /// "H.264", "VP9", "AV1".
  final String? codec;
  final double? fps;
}
