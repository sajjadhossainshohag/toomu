import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

abstract class Formatters {
  static String bytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : decimals)} ${units[unit]}';
  }

  /// 1234 → 1.2K, 3400000 → 3.4M
  static String compact(int n) {
    if (n >= 1000000000) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1e3).toStringAsFixed(1)}K';
    return '$n';
  }

  static String speed(int bytesPerSecond) => '${bytes(bytesPerSecond)}/s';

  static String ago(DateTime when, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(when);
    String n(int v, String unit) => '$v $unit${v == 1 ? '' : 's'} ago';
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return n(d.inMinutes, 'minute');
    if (d.inDays < 1) return n(d.inHours, 'hour');
    if (d.inDays < 7) return n(d.inDays, 'day');
    if (d.inDays < 30) return n(d.inDays ~/ 7, 'week');
    if (d.inDays < 365) return n(d.inDays ~/ 30, 'month');
    return n(d.inDays ~/ 365, 'year');
  }

  static String duration(Duration? d) {
    if (d == null) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Turns any title into a safe file name of at most [maxBytes] bytes.
  ///
  /// Android allows 255 *bytes* per name, and in UTF-8 Bengali/Hindi
  /// letters take 3 bytes, emoji 4; yt-dlp and aria2c then add up to ~30
  /// for their temporary files (".f299-drc.webm.part.aria2"). So names are
  /// cut by bytes, and only between whole letters.
  static String fileName(String input, {int maxBytes = 150}) {
    final cleaned = input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // No leading dots (hidden file) or trailing dots/spaces (SD cards and
    // Windows drop them, so the name changes under us).
    final safe = fitBytes(cleaned, maxBytes).replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (safe.isEmpty) return 'download';
    // Windows device names: no file may be called "CON" or "nul.mp4".
    return RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false).hasMatch(safe) ? '${safe}_' : safe;
  }

  /// [text] cut to at most [maxBytes] UTF-8 bytes, between whole letters
  /// (never inside a Bengali conjunct or an emoji).
  static String fitBytes(String text, int maxBytes) {
    if (utf8.encode(text).length <= maxBytes) return text;
    final out = StringBuffer();
    var used = 0;
    for (final letter in text.characters) {
      final size = utf8.encode(letter).length;
      if (used + size > maxBytes) break;
      out.write(letter);
      used += size;
    }
    return out.toString().trimRight();
  }
}
