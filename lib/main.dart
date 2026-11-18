import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/core/theme/app_theme.dart';
import 'app/core/utils/device_profile.dart';
import 'app/core/utils/host_os.dart';
import 'app/core/values/app_constants.dart';
import 'app/routes/app_pages.dart';
import 'app/services/app_services.dart';
import 'app/services/settings_service.dart';
import 'app/services/storage_service.dart';
import 'app/widgets/floating_video.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (HostOs.usesMediaKitAudio) JustAudioMediaKit.ensureInitialized(windows: true);
  await Future.wait([
    // The app's screens are designed for portrait; the video player rotates
    // itself as needed and restores this when it closes.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    StorageService.init(),
    DeviceProfile.init(),
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
        builder: (_, child) => Stack(children: <Widget>[child!, const FloatingVideo()]),
      ),
    );
  }
}
