import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Detects supported links inside arbitrary text (clipboard, shared text,
/// search box). New sources (Instagram, Facebook, direct files…) can be
/// added here later without touching the UI.
abstract class LinkParser {
  static final _urlRegex = RegExp(r'https?://\S+|(?:www\.|m\.)?youtu(?:\.be|be\.com)/\S+',
      caseSensitive: false);
  static final _idRegex = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _ytHosts = <String>{
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };
  static const _pathPrefixes = <String>{'shorts', 'live', 'embed', 'v', 'e'};

  /// Returns a YouTube video id if [text] contains a YouTube video link
  /// (or is a bare 11-char id).
  static String? youtubeVideoId(String text) {
    final trimmed = text.trim();
    if (_idRegex.hasMatch(trimmed)) return trimmed;
    for (final match in _urlRegex.allMatches(trimmed)) {
      final id = _fromUrl(match.group(0)!);
      if (id != null) return id;
    }
    return null;
  }

  static bool isYoutubeLink(String text) => youtubeVideoId(text) != null;

  static String? _fromUrl(String raw) {
    // Strip trailing punctuation that often sticks to shared links.
    var link = raw.replaceFirst(RegExp(r'[)\].,!?]+$'), '');
    if (!link.toLowerCase().startsWith('http')) link = 'https://$link';
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    String? candidate;
    if (host == 'youtu.be' || host == 'www.youtu.be') {
      candidate = segments.isEmpty ? null : segments.first;
    } else if (_ytHosts.contains(host)) {
      candidate = uri.queryParameters['v'];
      if (candidate == null &&
          segments.length >= 2 &&
          _pathPrefixes.contains(segments.first.toLowerCase())) {
        candidate = segments[1];
      }
    }
    if (candidate != null && _idRegex.hasMatch(candidate)) return candidate;

    // Last resort: the library's own parser.
    return VideoId.parseVideoId(link);
  }
}
