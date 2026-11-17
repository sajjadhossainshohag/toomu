import 'dart:convert';

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

String downloadName({
  required String? suggested,
  required String url,
  required String pageTitle,
  required String pageUrl,
  String? contentDisposition,
  List<String> pageHints = const [],
}) {
  final names = [
    nameFromDisposition(contentDisposition),
    _nameInLink(url),
    _clean(suggested),
    _clean(_lastSegment(url)),
  ].whereType<String>().where((n) => n.isNotEmpty).toList();
  for (final n in names) {
    if (!looksGeneric(_withoutExt(n))) return n;
  }
  final ext = names.map(_extOf).firstWhere((e) => e.isNotEmpty, orElse: () => '');
  for (final t in [cleanPageTitle(pageTitle, pageUrl: pageUrl), ...pageHints.map((h) => cleanPageTitle(h, pageUrl: pageUrl))]) {
    if (looksGeneric(t)) continue;
    if (ext.isEmpty || t.toLowerCase().endsWith('.$ext')) return t;
    return '$t.$ext';
  }
  return names.firstOrNull ?? 'download';
}

String? nameFromDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  // RFC 6266: filename* (RFC 5987: charset'language'percent-encoded) wins over filename.
  final star = RegExp(r'''filename\*\s*=\s*"?([^;"]+)"?''', caseSensitive: false).firstMatch(header);
  if (star != null) {
    final parts = star[1]!.trim().split("'");
    if (parts.length >= 3) {
      final value = parts.sublist(2).join("'");
      try {
        final bytes = Uri.decodeQueryComponent(value.replaceAll('+', '%2B'), encoding: latin1).codeUnits;
        final name = parts[0].toLowerCase() == 'utf-8' ? utf8.decode(bytes) : latin1.decode(bytes);
        if (name.trim().isNotEmpty) return _clean(name);
      } catch (_) {}
    }
  }
  final plain = RegExp(r'''filename\s*=\s*(?:"([^"]*)"|([^;]+))''', caseSensitive: false).firstMatch(header);
  final value = (plain?[1] ?? plain?[2])?.trim();
  return value == null || value.isEmpty ? null : _clean(value);
}

String? _nameInLink(String url) {
  final q = Uri.tryParse(url)?.queryParameters ?? const <String, String>{};
  for (final key in const ['response-content-disposition', 'rscd']) {
    final name = nameFromDisposition(q[key]);
    if (name != null) return name;
  }
  for (final key in const ['filename', 'file_name', 'file', 'name', 'title']) {
    final v = q[key]?.trim() ?? '';
    // A bare number or id (file=12345) is a key, not a name.
    if (v.isNotEmpty && !RegExp(r'^\d+$').hasMatch(v)) return _clean(v);
  }
  return null;
}

String? _clean(String? name) {
  var n = name?.trim() ?? '';
  if (n.isEmpty) return null;
  if (RegExp(r'%[0-9a-fA-F]{2}').hasMatch(n)) {
    try {
      n = Uri.decodeComponent(n);
    } catch (_) {}
  }
  // UTF-8 bytes shown as Latin-1 ("à¦†…") come back as the real letters.
  if (n.codeUnits.every((c) => c < 256) && n.codeUnits.any((c) => c >= 0xC0)) {
    try {
      n = utf8.decode(latin1.encode(n));
    } catch (_) {}
  }
  n = n.split(RegExp(r'[/\\]')).last.replaceAll('"', '').trim();
  return n.isEmpty ? null : n;
}

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  // "bin" is Android's guess for "unknown": the server's type names it better later.
  return RegExp(r'^(?=.*[a-z])[a-z0-9]{1,5}$').hasMatch(ext) && ext != 'bin' ? ext : '';
}

String _withoutExt(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  return RegExp(r'^(?=.*[a-z])[a-z0-9]{1,5}$').hasMatch(ext) ? name.substring(0, dot) : name;
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
  // Codes with dots or other marks inside (KSUxH_Go3rh9CGC8.cVrpFcHH…): a long run of letters
  // mixed with digits; release names (The.Odyssey.2026.1080p) only have short parts.
  if (!t.contains(' ') &&
      _longRun.allMatches(t).any((m) => _digit.hasMatch(m[0]!) && _letter.hasMatch(m[0]!))) {
    return true;
  }
  // Codes: one long "word" of letters and digits (a8f7e6d2c1…, x7KpQ2_mZ9).
  if (!t.contains(' ') && t.length >= 10 && RegExp(r'^[a-z0-9_\-=]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t)) {
    return true;
  }
  return false;
}

final _longRun = RegExp(r'[a-z0-9]{16,}');
final _digit = RegExp(r'\d');
final _letter = RegExp('[a-z]');

const _genericWords = {
  'video', 'videos', 'player', 'video player', 'embed', 'watch', 'stream', 'streaming', 'untitled',
  'loading', 'loading...', 'home', 'index', 'master', 'playlist', 'manifest', 'chunklist', 'media', 'file',
  'download', 'downloadfile', 'movie', 'movies', 'jwplayer', 'jw player', 'plyr', 'videojs', 'video.js', 'blank', 'about:blank',
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
