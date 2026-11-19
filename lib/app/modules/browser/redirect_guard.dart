import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/values/app_constants.dart';

const tapRecorderJs = r'''
(function () {
  if (window.__toomuTap) return;
  window.__toomuTap = true;
  addEventListener('pointerdown', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    try { window.flutter_inappwebview.callHandler('toomuTap', a ? a.href : ''); } catch (err) {}
  }, true);
})();
''';

class RedirectGuard {
  RedirectGuard({this.isListed = Blocklist.contains});

  final bool Function(String host) isListed;

  String _tapSite = '';
  DateTime? _tapAt;

  static const _hijackWindow = Duration(seconds: 3);

  void onTap(String href) {
    _tapSite = siteOf(Uri.tryParse(href)?.host ?? '');
    _tapAt = DateTime.now();
  }

  /// Sites that move the page between their own domains (TikTok's feed and
  /// short links go through tiktokv.com, vm.tiktok.com…): never blocked, even
  /// when a blocklist has one of them.
  static const allowedSites = {
    'tiktok.com', 'tiktokv.com', 'tiktokcdn.com', 'tiktokcdn-us.com', 'tiktokw.us', 'ttwstatic.com', //
    'byteoversea.com', 'ibytedtos.com', 'musical.ly',
  };

  bool blocks({required String from, required Uri to, bool redirect = false, DateTime? now}) {
    final site = siteOf(to.host);
    if (site.isEmpty || site == siteOf(Uri.tryParse(from)?.host ?? '')) return false;
    if (allowedSites.contains(site)) return false;
    if (isListed(to.host)) return true;
    // Ad scripts send the page elsewhere when the user taps anything; jumps
    // without a tap (sign-in flows, server redirects) only stop for listed hosts.
    if (redirect) return false;
    final at = _tapAt;
    return at != null && (now ?? DateTime.now()).difference(at) < _hijackWindow && _tapSite != site;
  }

  static const _secondLevel = {'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'gob', 'mil', 'nic', 'ltd', 'plc', 'sch'};

  static String siteOf(String host) {
    // shortcut: guesses the registrable domain without the public-suffix list
    // (only "<common word>.<country>" counts as a suffix); add the list if
    // that blocks real sites.
    final labels = host.toLowerCase().split('.').where((l) => l.isNotEmpty).toList();
    if (labels.length < 3 || RegExp(r'^\d+$').hasMatch(labels.last)) return labels.join('.');
    final n = labels.length;
    final keep = labels[n - 1].length == 2 && _secondLevel.contains(labels[n - 2]) ? 3 : 2;
    return labels.sublist(n - keep).join('.');
  }
}

class Blocklist {
  Blocklist._();

  static String url = AppConstants.blocklistUrl;
  static Set<String> _hosts = const {};
  static Future<void>? _loading;

  static int _generation = 0;

  static Future<void> load() => _loading ??= _load();

  static void forget() {
    _generation++;
    _hosts = const {};
    _loading = null;
  }

  static bool contains(String host) {
    var h = host.toLowerCase();
    while (true) {
      if (_hosts.contains(h)) return true;
      final dot = h.indexOf('.');
      if (dot < 0) return false;
      h = h.substring(dot + 1);
    }
  }

  static Future<void> _load() async {
    final generation = _generation;
    try {
      final file = await cachedList(url, 'blocklist.txt');
      if (file == null) return;
      final path = file.path;
      final hosts = await Isolate.run(() => parse(File(path).readAsStringSync()));
      if (generation != _generation) return;
      _hosts = hosts;
      debugPrint('[Blocklist] ${_hosts.length} hosts');
    } catch (e) {
      debugPrint('[Blocklist] $e');
    }
  }

  @visibleForTesting
  static Set<String> parse(String text) {
    final hosts = <String>{};
    for (var line in text.split('\n')) {
      line = line.trim().toLowerCase();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
      final hash = line.indexOf('#');
      if (hash > 0) line = line.substring(0, hash).trim();
      final parts = line.split(RegExp(r'\s+'));
      var host = parts.length > 1 ? parts[1] : parts[0];
      if (host.startsWith('||')) {
        if (!host.endsWith('^')) continue;
        host = host.substring(2, host.length - 1);
      }
      if (!host.contains('.') || host.contains('/') || host.contains('*') || host == '0.0.0.0') continue;
      hosts.add(host);
    }
    return hosts;
  }

  @visibleForTesting
  static set hosts(Set<String> value) => _hosts = value;
}

/// [url] saved as [name] in the app's support folder, downloaded again once
/// it's a week old (the old copy is kept if that fails). Null if there's no
/// copy at all.
Future<File?> cachedList(String url, String name, {Duration maxAge = const Duration(days: 7)}) async {
  final file = File('${(await getApplicationSupportDirectory()).path}/$name');
  final fresh = file.existsSync() && DateTime.now().difference(file.lastModifiedSync()) < maxAge;
  if (!fresh) {
    try {
      await Dio().download(url, '${file.path}.part');
      await File('${file.path}.part').rename(file.path);
    } catch (e) {
      debugPrint('[Filters] $name update failed: $e');
    }
  }
  return file.existsSync() ? file : null;
}
