import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/values/app_constants.dart';
import 'storage_service.dart';

class SettingsService extends GetxService {
  static SettingsService get to => Get.find();

  final _storage = StorageService.to;

  final themeMode = ThemeMode.dark.obs;
  final maxConcurrentDownloads = AppConstants.defaultMaxConcurrentDownloads.obs;

  /// Video player: keep audio playing when the app is left / screen is off.
  final videoBackgroundPlay = false.obs;

  /// Video player: shrink into picture-in-picture when pressing Home.
  final videoAutoPip = true.obs;

  /// Test switch (Diagnostics): Android's decoder draws straight to the screen instead of copying every frame.

  final captureMedia = true.obs;
  final clipboardLinks = true.obs;

  /// Send crash reports: null until the user is first asked (after a crash).
  final crashReports = Rxn<bool>();

  /// One anonymous "used today" ping a day (no ID), so the developer knows how many use Toomu.
  final usageCount = true.obs;
  final blockRedirects = true.obs;

  /// Browser: block ads (ad hosts' requests, common ad boxes hidden).
  final blockAds = true.obs;

  /// Sites ("example.com") the user allowed ads on (a site that breaks).
  final adsAllowedSites = <String>{}.obs;

  /// Parallel connections per file (1DM-style segmented download).
  final connectionsPerDownload = AppConstants.defaultConnectionsPerDownload.obs;

  SettingsService init() {
    final savedTheme = _storage.read<String>(AppConstants.kThemeMode);
    if (savedTheme != null) themeMode.value = ThemeMode.values.byName(savedTheme);
    maxConcurrentDownloads.value =
        _storage.read<int>(AppConstants.kMaxConcurrent) ??
            AppConstants.defaultMaxConcurrentDownloads;
    connectionsPerDownload.value = _storage.read<int>(AppConstants.kConnections) ??
        AppConstants.defaultConnectionsPerDownload;
    videoBackgroundPlay.value = _storage.read<bool>(AppConstants.kVideoBackgroundPlay) ?? false;
    videoAutoPip.value = _storage.read<bool>(AppConstants.kVideoAutoPip) ?? true;
    captureMedia.value = _storage.read<bool>(AppConstants.kCaptureMedia) ?? true;
    clipboardLinks.value = _storage.read<bool>(AppConstants.kClipboardLinks) ?? true;
    crashReports.value = _storage.read<bool>(AppConstants.kCrashReports);
    usageCount.value = _storage.read<bool>(AppConstants.kUsageCount) ?? true;
    blockRedirects.value = _storage.read<bool>(AppConstants.kBlockRedirects) ?? true;
    blockAds.value = _storage.read<bool>(AppConstants.kBlockAds) ?? true;
    adsAllowedSites.assignAll(
      (_storage.read<List<dynamic>>(AppConstants.kAdsAllowedSites) ?? const []).whereType<String>(),
    );
    return this;
  }

  void setBlockRedirects(bool v) {
    blockRedirects.value = v;
    _storage.write(AppConstants.kBlockRedirects, v);
  }

  void setBlockAds(bool v) {
    blockAds.value = v;
    _storage.write(AppConstants.kBlockAds, v);
  }

  void setAdsAllowed(String site, bool allowed) {
    allowed ? adsAllowedSites.add(site) : adsAllowedSites.remove(site);
    _storage.write(AppConstants.kAdsAllowedSites, adsAllowedSites.toList());
  }

  void setCaptureMedia(bool v) {
    captureMedia.value = v;
    _storage.write(AppConstants.kCaptureMedia, v);
  }

  void setCrashReports(bool v) {
    crashReports.value = v;
    _storage.write(AppConstants.kCrashReports, v);
  }

  void setUsageCount(bool v) {
    usageCount.value = v;
    _storage.write(AppConstants.kUsageCount, v);
  }

  void setClipboardLinks(bool v) {
    clipboardLinks.value = v;
    _storage.write(AppConstants.kClipboardLinks, v);
  }

  void setVideoBackgroundPlay(bool v) {
    videoBackgroundPlay.value = v;
    _storage.write(AppConstants.kVideoBackgroundPlay, v);
  }

  void setVideoAutoPip(bool v) {
    videoAutoPip.value = v;
    _storage.write(AppConstants.kVideoAutoPip, v);
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    _storage.write(AppConstants.kThemeMode, mode.name);
  }

  void setConnectionsPerDownload(int value) {
    connectionsPerDownload.value = value;
    _storage.write(AppConstants.kConnections, value);
  }

  void setMaxConcurrentDownloads(int value) {
    maxConcurrentDownloads.value = value;
    _storage.write(AppConstants.kMaxConcurrent, value);
  }
}
