import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../core/values/app_constants.dart';
import '../data/repositories/video_resume_repository.dart';
import 'audio_player_service.dart';
import 'browser_store.dart';
import 'diagnostics_service.dart';
import 'download_service.dart';
import 'floating_button_service.dart';
import 'media_scanner_service.dart';
import 'permission_service.dart';
import 'remote_config_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'stream_proxy.dart';
import 'update_service.dart';
import 'video_session_service.dart';
import 'youtube_account_service.dart';
import 'ytdlp_service.dart';

/// Registers app-lifetime services in dependency order.
/// Feature-scoped controllers live in each module's Binding instead.
abstract class AppServices {
  static Future<void> init() async {
    final storage = Get.put(StorageService(), permanent: true);
    for (final (box, key) in [
      (StorageService.logsBox, DiagnosticsService.key),
      (StorageService.downloadsBox, AppConstants.kDownloadTasks),
      (StorageService.positionsBox, VideoResumeRepository.storageKey),
    ]) {
      Get.put(storage.split(GetStorage(box), key), tag: box, permanent: true);
    }
    Get.put(StorageService(GetStorage(StorageService.queueBox)), tag: StorageService.queueBox, permanent: true);
    Get.put(StorageService(GetStorage(StorageService.browserBox)), tag: StorageService.browserBox, permanent: true);
    Get.put(DiagnosticsService().init(), permanent: true); // before anything logs
    Get.put(SettingsService().init(), permanent: true);
    Get.put(BrowserStore(), permanent: true); // reads lazily, on first use
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
    Get.put(UpdateService().init(), permanent: true);
  }
}
