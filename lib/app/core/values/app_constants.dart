abstract class AppConstants {
  static const appName = 'Toomu';

  // Notifications
  static const playbackChannelId = 'com.example.toomu.playback';
  static const playbackChannelName = 'Music playback';

  // Downloads
  static const defaultMaxConcurrentDownloads = 2;
  static const defaultConnectionsPerDownload = 8;
  static const downloadFolderName = 'Toomu';

  /// Static JSON file with remotely tunable settings (client order, sites,
  /// feed categories…), e.g. a raw GitHub URL. No server needed; null keeps
  /// the built-in defaults. See `remote_config.example.json`.
  static const String? remoteConfigUrl = null;

  // Storage keys
  static const kDownloadTasks = 'download_tasks';
  static const kThemeMode = 'theme_mode';
  static const kMaxConcurrent = 'max_concurrent_downloads';
  static const kConnections = 'connections_per_download';
  static const kFavorites = 'favorite_track_ids';
  static const kEqualizerEnabled = 'eq_enabled';
  static const kEqualizerGains = 'eq_gains';
  static const kSearchHistory = 'yt_search_history';
  static const kRemoteConfig = 'remote_config_cache';
  static const kYtdlpChannel = 'ytdlp_channel';
  static const kBubbleEnabled = 'floating_button_enabled';
  static const kVideoBackgroundPlay = 'video_background_play';
  static const kVideoAutoPip = 'video_auto_pip';
  static const kBubbleNowPlayingAsked = 'floating_button_now_playing_asked';
  static const kYtdlpUpdatedAt = 'ytdlp_updated_at';

  /// Quality last picked in the player for YouTube streams (720, 1080…).
  static const kStreamQuality = 'stream_quality';
}
