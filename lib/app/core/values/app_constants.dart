abstract class AppConstants {
  static const appName = 'Toomu';

  // Notifications
  static const playbackChannelId = 'io.github.toomu.playback';
  static const playbackChannelName = 'Music playback';

  // Downloads
  static const defaultMaxConcurrentDownloads = 2;
  static const defaultConnectionsPerDownload = 8;
  static const downloadFolderName = 'Toomu';

  /// Static JSON file with remotely tunable settings (client order, sites,
  /// feed categories…), e.g. a raw GitHub URL. No server needed; null keeps
  /// the built-in defaults. See `remote_config.example.json`.
  static const String? remoteConfigUrl = null;

  static const githubRepo = 'sajjadhossainshohag/toomu';

  /// Crash relay and user count (`tool/crash-relay`, a Cloudflare Worker: /report opens GitHub
  /// issues, /ping counts users). No trailing slash. Empty: nothing is sent.
  static const relayUrl = '';

  /// Sent as X-Toomu-Key. Not a secret (it ships in the app): it only keeps random traffic off the relay.
  static const crashReportKey = 'toomu-ec11073bba3ceb97e13b7ff5';

  // GitHub redirects /releases/latest/download/<file> to that file in the newest release.
  static String latestDownload({required bool windows}) =>
      'https://github.com/$githubRepo/releases/latest/download/${windows ? 'toomu-windows-setup.exe' : 'toomu-arm64-v8a.apk'}';

  /// Ad filters (Adblock Plus syntax), the main list AdBlock uses.
  /// Toomu's official YouTube channel (Settings → About).
  static const youtubeChannelUrl = 'https://www.youtube.com/@toomuapp';
  static const easylistUrl = 'https://easylist.to/easylist/easylist.txt';
  static const blocklistUrl = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts';

  // Storage keys
  static const kDownloadTasks = 'download_tasks';
  static const kThemeMode = 'theme_mode';
  static const kMaxConcurrent = 'max_concurrent_downloads';
  static const kConnections = 'connections_per_download';
  static const kFavorites = 'favorite_track_ids';
  static const kAudioQueue = 'audio_queue';
  static const kEqualizerEnabled = 'eq_enabled';
  static const kEqualizerGains = 'eq_gains';
  static const kSearchHistory = 'yt_search_history';
  static const kWatchHistory = 'yt_watch_history';
  static const kWatchLater = 'yt_watch_later';
  static const kRemoteConfig = 'remote_config_cache';
  static const kFeedCache = 'home_feed_cache';

  /// Searches the last "For you" feed mixed; the next one picks others.
  static const kFeedTopics = 'home_feed_topics';
  static const kBubbleEnabled = 'floating_button_enabled';
  static const kVideoBackgroundPlay = 'video_background_play';
  static const kVideoAutoPip = 'video_auto_pip';
  static const kCaptureMedia = 'browser_capture_media';
  static const kClipboardLinks = 'clipboard_links';
  static const kCrashReports = 'crash_reports';
  static const kUsageCount = 'usage_count';
  static const kUsagePingDay = 'usage_ping_day';
  static const kBlockRedirects = 'browser_block_redirects';
  static const kBlockAds = 'browser_block_ads';
  static const kAdsAllowedSites = 'browser_ads_allowed_sites';
  static const kUpdateCheckedAt = 'update_checked_at';
  static const kBubbleNowPlayingAsked = 'floating_button_now_playing_asked';
  static const kYtdlpUpdatedAt = 'ytdlp_updated_at';

  /// Quality last picked in the player for YouTube streams (720, 1080…).
  static const kStreamQuality = 'stream_quality';
  static const kDownloadQuality = 'download_quality';
}
