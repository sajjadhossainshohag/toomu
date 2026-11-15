import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/values/app_constants.dart';
import 'ytdlp_service.dart';
import '../extractors/extractors.dart';
import '../modules/browser/redirect_guard.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Snaptube-style remote tuning without a server: a static JSON file
/// (e.g. on GitHub) fetched at startup and cached. Lets you react to
/// YouTube changes without shipping an app update. Every field is optional.
///
/// ```json
/// {
///   "ytdlpArgs": ["--extractor-args", "youtube:player_client=default,tv"],
///   "ytdlpChannel": "stable",
///   "connectionsPerDownload": 4,
///   "blocklistUrl": "https://example.com/hosts",
///   "sites": [{"name": "YouTube", "url": "https://m.youtube.com/", "icon": "video", "color": "#FF0033"}],
///   "feedCategories": [{"label": "Music", "query": "new music video"}]
/// }
/// ```
class RemoteConfigService extends GetxService {
  static RemoteConfigService get to => Get.find();

  final _storage = StorageService.to;

  final sites = <SiteShortcut>[...Extractors.defaultSites].obs;

  /// (label, query) pairs; empty = built-in categories.
  final feedCategories = <({String label, String query})>[].obs;

  RemoteConfigService init() {
    final cached = _storage.read<String>(AppConstants.kRemoteConfig);
    if (cached != null) _apply(cached);
    unawaited(refresh());
    return this;
  }

  Future<void> refresh() async {
    const url = AppConstants.remoteConfigUrl;
    if (url == null) return;
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
      )).get<String>(url);
      final body = r.data;
      if (body == null || body.isEmpty) return;
      _apply(body); // throws on invalid JSON → keep the cached config
      await _storage.write(AppConstants.kRemoteConfig, body);
      debugPrint('[RemoteConfig] updated');
    } catch (e) {
      debugPrint('[RemoteConfig] refresh failed: $e');
    }
  }

  void _apply(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;

    // Extra yt-dlp options, e.g. YouTube client order via --extractor-args.
    final args = (json['ytdlpArgs'] as List?)?.whereType<String>().toList();
    if (args != null) YtDlpService.to.remoteArgs.assignAll(args);

    final channel = json['ytdlpChannel'];
    if (channel == 'stable' || channel == 'nightly') YtDlpService.to.channel.value = channel as String;

    // Only a default: never override a value the user picked.
    final connections = json['connectionsPerDownload'];
    if (connections is int &&
        connections > 0 &&
        _storage.read<int>(AppConstants.kConnections) == null) {
      SettingsService.to.connectionsPerDownload.value = connections.clamp(1, 8);
    }

    final siteList = json['sites'] as List?;
    if (siteList != null) {
      sites.assignAll(siteList.whereType<Map>().map((m) => SiteShortcut.fromJson(m.cast())));
    }

    final blocklist = json['blocklistUrl'];
    if (blocklist is String && blocklist.startsWith('https://')) Blocklist.url = blocklist;

    final cats = json['feedCategories'] as List?;
    if (cats != null) {
      feedCategories.assignAll(cats.whereType<Map>().map((m) =>
          (label: '${m['label']}', query: '${m['query']}')));
    }
  }
}
