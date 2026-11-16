import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/app_release.dart';
import '../core/utils/error_text.dart';
import '../core/utils/formatters.dart';
import '../core/values/app_constants.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/gradient_progress_bar.dart';
import 'storage_service.dart';

class UpdateService extends GetxService {
  static UpdateService get to => Get.find();

  static const currentTag = String.fromEnvironment('TOOMU_TAG');
  static const _channel = MethodChannel('toomu/update');

  final checking = false.obs;
  final progress = RxnDouble();

  final _storage = StorageService.to;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  UpdateService init() {
    if (Platform.isAndroid && currentTag.isNotEmpty) unawaited(_autoCheck());
    return this;
  }

  Future<void> _autoCheck() async {
    final last = _storage.read<int>(AppConstants.kUpdateCheckedAt) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 1).inMilliseconds) return;
    await Future<void>.delayed(const Duration(seconds: 5));
    try {
      final release = await _latest();
      await _storage.write(AppConstants.kUpdateCheckedAt, DateTime.now().millisecondsSinceEpoch);
      if (release.apkUrl != null && AppRelease.isNewer(release.tag, currentTag)) await _offer(release);
    } catch (e) {
      debugPrint('[Update] check failed: $e');
    }
  }

  Future<void> checkNow() async {
    if (checking.value || progress.value != null) return;
    checking.value = true;
    try {
      final release = await _latest();
      if (!AppRelease.isNewer(release.tag, currentTag)) {
        showSnack('Toomu is up to date', release.tag);
      } else if (release.apkUrl == null) {
        showSnack('No update for this phone', '${release.tag} has no APK for its CPU type.');
      } else {
        await _offer(release);
      }
    } catch (e) {
      showSnack("Couldn't check for updates", ErrorText.of(e));
    } finally {
      checking.value = false;
    }
  }

  Future<AppRelease> _latest() async {
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/${AppConstants.githubRepo}/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      return AppRelease.fromGitHub(r.data ?? const {}, abis);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 403 && code != 429) rethrow;
      // The API allows 60 requests an hour per IP (shared on mobile networks); the web pages aren't limited.
      return _latestFromWebPage(abis);
    }
  }

  Future<AppRelease> _latestFromWebPage(List<String> abis) async {
    const repo = 'https://github.com/${AppConstants.githubRepo}';
    final page = await _dio.get<void>(
      '$repo/releases/latest',
      options: Options(followRedirects: false, validateStatus: (s) => s != null && s < 400),
    );
    final tag = AppRelease.tagFromLocation(page.headers.value('location'));
    if (tag == null) throw StateError("Couldn't find the latest Toomu release.");
    for (final abi in abis) {
      final url = '$repo/releases/download/$tag/toomu-$abi.apk';
      final head = await _dio.head<void>(url, options: Options(validateStatus: (s) => s != null && s < 500));
      if (head.statusCode == 200) {
        final size = int.tryParse(head.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
        return AppRelease(tag: tag, notes: '', apkUrl: url, apkSize: size);
      }
    }
    return AppRelease(tag: tag, notes: '', apkUrl: null, apkSize: 0);
  }

  Future<void> _offer(AppRelease release) async {
    final notes = release.notes.length > 400 ? '${release.notes.substring(0, 400)}…' : release.notes;
    final ok = await showConfirmDialog(
      title: 'Update available',
      message: '${release.tag} · ${Formatters.bytes(release.apkSize)}${notes.isEmpty ? '' : '\n\n$notes'}',
      confirmLabel: 'Update',
      cancelLabel: 'Later',
    );
    if (ok) await _install(release);
  }

  Future<void> _install(AppRelease release) async {
    progress.value = 0;
    unawaited(showAppDialog<void>(
      title: 'Downloading update',
      child: Obx(() => GradientProgressBar(value: progress.value ?? 1)),
    ));
    try {
      final path = '${(await getTemporaryDirectory()).path}/toomu-update.apk';
      await _dio.download(
        release.apkUrl!,
        path,
        onReceiveProgress: (got, total) {
          if (total > 0) progress.value = got / total;
        },
      );
      if (Get.isDialogOpen ?? false) Get.back();
      showSnack('Installing update', 'Toomu closes when it is done. Open it again to use the new version.');
      await _channel.invokeMethod<void>('install', {'path': path});
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      showSnack("Couldn't update Toomu", ErrorText.of(e));
    } finally {
      progress.value = null;
    }
  }
}
