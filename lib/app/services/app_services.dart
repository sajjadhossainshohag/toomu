import 'package:get/get.dart';

import 'audio_player_service.dart';
import 'diagnostics_service.dart';
import 'download_service.dart';
import 'floating_button_service.dart';
import 'media_scanner_service.dart';
import 'permission_service.dart';
import 'remote_config_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'stream_proxy.dart';
import 'video_session_service.dart';
import 'youtube_account_service.dart';
import 'ytdlp_service.dart';

/// Registers app-lifetime services in dependency order.
/// Feature-scoped controllers live in each module's Binding instead.
abstract class AppServices {
  static Future<void> init() async {
    Get.put(StorageService(), permanent: true);
    Get.put(DiagnosticsService().init(), permanent: true); // before anything logs
    Get.put(SettingsService().init(), permanent: true);
    await Future.wait([
      Get.putAsync(() => YoutubeAccountService().init(), permanent: true),
      Get.putAsync(() => StreamProxy().init(), permanent: true), // 127.0.0.1, instant
      Get.putAsync(() => PermissionService().init(), permanent: true),
      Get.putAsync(() => AudioPlayerService().init(), permanent: true), // needs only storage
    ]);
    Get.put(YtDlpService().init(), permanent: true); // unpacks in background
    Get.put(RemoteConfigService().init(), permanent: true);
    Get.put(MediaScannerService(), permanent: true);
    await Get.putAsync(() => DownloadService().init(), permanent: true);
    Get.put(FloatingButtonService().init(), permanent: true);
    Get.put(VideoSessionService().init(), permanent: true);
  }
}
