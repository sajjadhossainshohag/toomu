import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// "Used today": one anonymous ping a day to the relay (`tool/crash-relay`, POST /ping), which
/// adds up daily, weekly and monthly users. No ID of any kind is sent: just the platform, the
/// version, the OS version, the phone model (shared by many people) and whether this is the first ping this week / month (that is what makes weekly and
/// monthly users countable without knowing who anyone is). Settings → Anonymous usage count.
class UsagePing {
  UsagePing({
    required this.endpoint,
    required this.appKey,
    required this.platform,
    required this.version,
    this.os = '',
    this.device = '',
    required this.lastDay,
    required this.saveDay,
  });

  final String endpoint;
  final String appKey;
  final String platform;
  final String version;

  /// "Android 14" / the Windows version, and "Samsung SM-S918B" (empty on Windows).
  final String os;
  final String device;

  /// The UTC day ("2026-11-22") of the last ping the relay accepted, or null.
  final String? Function() lastDay;
  final void Function(String day) saveDay;

  static String dayOf(DateTime t) => t.toUtc().toIso8601String().substring(0, 10);

  /// Monday of [day]'s week (ISO weeks, like the relay's /stats).
  static String weekOf(String day) {
    final d = DateTime.parse('${day}T00:00:00Z');
    return dayOf(d.subtract(Duration(days: d.weekday - 1)));
  }

  /// Whether to ping now, and what's new since the last one.
  @visibleForTesting
  static ({bool due, bool week, bool month}) plan(DateTime now, String? last) {
    final today = dayOf(now);
    if (last == today) return (due: false, week: false, month: false);
    return (
      due: true,
      week: last == null || weekOf(last) != weekOf(today),
      month: last == null || last.substring(0, 7) != today.substring(0, 7),
    );
  }

  /// Pings if today's isn't sent yet. True when the relay counted it.
  Future<bool> sendIfDue([DateTime? at]) async {
    final now = at ?? DateTime.now();
    final p = plan(now, lastDay());
    if (!p.due) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers
        ..contentType = ContentType.json
        ..set('x-toomu-key', appKey);
      req.add(utf8.encode(jsonEncode({
        'platform': platform,
        'version': version,
        'os': os,
        'device': device,
        'week': p.week,
        'month': p.month,
      })));
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode >= 300) return false;
      saveDay(dayOf(now));
      return true;
    } catch (_) {
      return false; // offline: tried again on the next start
    } finally {
      client.close(force: true);
    }
  }
}
