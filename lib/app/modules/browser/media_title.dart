import 'redirect_guard.dart';

/// Names for media found in the browser.
///
/// Movie sites play the video in an embedded player frame from another site
/// (its title is empty, "Video Player" or a code), so naming the download
/// after the frame — or the stream's file, "master.m3u8" — gave random
/// names. The page the user is on carries the real name.

/// The name for media at [mediaUrl], reported by the frame at [frameUrl]
/// titled [frameTitle], on the page [pageUrl] titled [pageTitle].
String mediaTitle({
  required String frameTitle,
  required String frameUrl,
  required String pageTitle,
  required String pageUrl,
  required String mediaUrl,
}) {
  final page = cleanPageTitle(pageTitle, pageUrl: pageUrl);
  final frame = cleanPageTitle(frameTitle, pageUrl: frameUrl.isEmpty ? pageUrl : frameUrl);
  final inPlayerFrame = frameUrl.isNotEmpty && _host(frameUrl) != _host(pageUrl);
  final candidates = inPlayerFrame ? [page, frame] : [frame, page];
  for (final t in [...candidates, _fileTitle(mediaUrl)]) {
    if (!looksGeneric(t)) return t;
  }
  return 'Video';
}

/// A better name for a file download than the server's [suggested] one
/// (or the link's file name) when that one is a code; null to keep it.
String? downloadName({
  required String? suggested,
  required String url,
  required String pageTitle,
  required String pageUrl,
}) {
  final given = (suggested?.trim().isNotEmpty ?? false) ? suggested!.trim() : _lastSegment(url);
  final dot = given.lastIndexOf('.');
  final base = dot > 0 ? given.substring(0, dot) : given;
  final ext = dot > 0 ? given.substring(dot + 1) : '';
  if (!looksGeneric(base)) return null;
  final page = cleanPageTitle(pageTitle, pageUrl: pageUrl);
  if (looksGeneric(page)) return null;
  return ext.isEmpty || ext.length > 5 ? page : '$page.$ext';
}

/// [title] without the site's name and streaming-site filler:
/// "Watch Inception (2010) Full Movie Online Free | FMovies" → "Inception (2010)".
String cleanPageTitle(String title, {required String pageUrl}) {
  var t = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';
  final site = _siteLabel(pageUrl);
  final parts = t.split(_separators).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  bool noise(String p) => (site.length >= 3 && _squash(p).contains(site)) || looksGeneric(_stripFiller(p));
  // Site name / filler at either end ("FMovies - …", "… | Watch Online").
  while (parts.length > 1 && noise(parts.last)) {
    parts.removeLast();
  }
  while (parts.length > 1 && noise(parts.first)) {
    parts.removeAt(0);
  }
  t = _stripFiller(parts.join(' - '));
  return t;
}

/// A title that names nothing: empty, a code, a file or player name.
bool looksGeneric(String title) {
  final t = title.trim().toLowerCase();
  if (t.length < 2) return true;
  if (_genericWords.contains(t)) return true;
  if (t.startsWith('http')) return true;
  if (RegExp(r'\.(m3u8|mpd|mp4|webm|mkv|ts|m4s|php|html?|aspx?)$').hasMatch(t)) {
    return looksGeneric(t.substring(0, t.lastIndexOf('.')));
  }
  // Codes: one long "word" of letters and digits (a8f7e6d2c1…, x7KpQ2_mZ9).
  if (!t.contains(' ') && t.length >= 10 && RegExp(r'^[a-z0-9_\-=]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t)) {
    return true;
  }
  return false;
}

const _genericWords = {
  'video', 'videos', 'player', 'video player', 'embed', 'watch', 'stream', 'streaming', 'untitled',
  'loading', 'loading...', 'home', 'index', 'master', 'playlist', 'manifest', 'chunklist', 'media', 'file',
  'download', 'movie', 'movies', 'jwplayer', 'jw player', 'plyr', 'videojs', 'video.js', 'blank', 'about:blank',
  'online', 'free', 'hd', 'mp4', 'iframe', 'redirecting', 'redirecting...', 'just a moment...', 'please wait',
};

final _separators = RegExp(r'\s+[|\-–—:»·]+\s+|\s*\|\s*|\s*[»·]\s*');

/// Streaming-site filler around a name.
String _stripFiller(String s) {
  var t = s.trim();
  t = t.replaceFirst(RegExp(r'^(watch|stream|download)\s+', caseSensitive: false), '');
  final tail = RegExp(
    // Whole words after a space only: "Inception.2010.1080p" keeps its 1080p.
    r'(?:^|\s+)(full movie|full episode|online free|free online|watch online|for free|in hd|full hd|hd online|'
    r'eng(lish)? sub(bed)?|with subtitles|online|free|hd|1080p|720p)\s*$',
    caseSensitive: false,
  );
  String prev;
  do {
    prev = t;
    t = t.replaceFirst(tail, '').trim();
  } while (t != prev && t.isNotEmpty);
  return t;
}

String _fileTitle(String url) {
  final name = _lastSegment(url);
  final dot = name.lastIndexOf('.');
  return (dot > 0 ? name.substring(0, dot) : name).replaceAll(RegExp(r'[._]+'), ' ').trim();
}

String _lastSegment(String url) {
  final segments = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const <String>[];
  if (segments.isEmpty) return '';
  try {
    return Uri.decodeComponent(segments.last);
  } catch (_) {
    return segments.last;
  }
}

String _host(String url) => (Uri.tryParse(url)?.host ?? '').toLowerCase();

/// "www.fmovies.to" → "fmovies".
String _siteLabel(String url) {
  final site = RedirectGuard.siteOf(_host(url));
  final dot = site.indexOf('.');
  return _squash(dot > 0 ? site.substring(0, dot) : site);
}

String _squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
