import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/core/theme/app_theme.dart';
import 'app/core/utils/device_profile.dart';
import 'app/core/values/app_constants.dart';
import 'app/routes/app_pages.dart';
import 'app/services/app_services.dart';
import 'app/services/settings_service.dart';
import 'app/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    // The app's screens are designed for portrait; the video player rotates
    // itself as needed and restores this when it closes.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    StorageService.init(),
    DeviceProfile.init(),
    JustAudioBackground.init(
      androidNotificationChannelId: AppConstants.playbackChannelId,
      androidNotificationChannelName: AppConstants.playbackChannelName,
      androidNotificationOngoing: true,
      // Toomu mark in the status bar (android/app/src/main/res/drawable).
      androidNotificationIcon: 'drawable/ic_stat_toomu',
      notificationColor: const Color(0xFF7C4DFF),
    ),
  ]);
  if (DeviceProfile.lowEnd) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 40 << 20
      ..maximumSize = 300;
  }

  // Global, app-lifetime services (storage, permissions, downloads, audio…).
  await AppServices.init();

  runApp(const ToomuApp());
}

class ToomuApp extends StatelessWidget {
  const ToomuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.to;
    return Obx(
      () => GetMaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode.value,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
        defaultTransition: AppPages.motion(Transition.cupertino),
      ),
    );
  }
}
