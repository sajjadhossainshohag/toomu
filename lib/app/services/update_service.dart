import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme/design_metrics.dart';
import '../core/utils/app_release.dart';
import '../core/utils/error_text.dart';
import '../core/utils/formatters.dart';
import '../core/utils/parallel_download.dart';
import '../core/utils/speed_meter.dart';
import '../core/values/app_constants.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/gradient_pill.dart';
import '../widgets/outline_pill.dart';
import '../widgets/update_progress.dart';
import 'download_service.dart';
import 'storage_service.dart';

class UpdateService extends GetxService {
  static UpdateService get to => Get.find();

  static const currentTag = String.fromEnvironment('TOOMU_TAG');

  // Windows CI builds have no release tag, only a build label.
  static String get versionLabel => currentTag.isNotEmpty
      ? currentTag
      : const String.fromEnvironment('TOOMU_BUILD', defaultValue: 'Development build');
  static const _channel = MethodChannel('toomu/update');

  final checking = false.obs;
  final progress = RxnDouble();
  final _received = 0.obs;
  final _total = 0.obs;
  final _speed = 0.obs;

  late final _storage = StorageService.to;
  CancelToken? _cancel;
  bool _dialogOpen = false;

  bool get downloading => progress.value != null;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  bool _autoChecking = false;
  AppLifecycleListener? _lifecycle;

  UpdateService init() {
    if (Platform.isAndroid && currentTag.isNotEmpty) {
      unawaited(_autoCheck(launch: true));
      // Back in the app after a while: a release may have come out since.
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(_autoCheck(launch: false)));
    }
    return this;
  }

  @override
  void onClose() {
    _lifecycle?.dispose();
    super.onClose();
  }

  /// Every app open looks for a new version; coming back to the app does
  /// once an hour (GitHub's API allows 60 requests an hour per IP).
  @visibleForTesting
  static bool shouldAutoCheck({required bool launch, required int lastCheckMs, required int nowMs}) =>
      launch || nowMs - lastCheckMs >= const Duration(hours: 1).inMilliseconds;

  Future<void> _autoCheck({required bool launch}) async {
    final last = _storage.read<int>(AppConstants.kUpdateCheckedAt) ?? 0;
    if (!shouldAutoCheck(launch: launch, lastCheckMs: last, nowMs: DateTime.now().millisecondsSinceEpoch)) return;
    if (_autoChecking || checking.value || downloading) return;
    _autoChecking = true;
    try {
      // Let the first screen settle before a dialog.
      await Future<void>.delayed(Duration(seconds: launch ? 3 : 1));
      if (downloading || checking.value) return;
      final release = await _latest();
      await _storage.write(AppConstants.kUpdateCheckedAt, DateTime.now().millisecondsSinceEpoch);
      if (release.apkUrl != null && AppRelease.isNewer(release.tag, currentTag)) await _offer(release);
    } catch (e) {
      debugPrint('[Update] check failed: $e');
    } finally {
      _autoChecking = false;
    }
  }

  Future<void> checkNow() async {
    // Already downloading (the dialog was hidden): show its progress again
    // instead of offering the same update.
    if (downloading) return showProgress();
    if (checking.value) return;
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
    if (ok && !downloading) await _install(release);
  }

  /// The download's dialog. A tap outside or Back doesn't close it, only
  /// Hide (the download goes on, in the notification too) or Cancel.
  @visibleForTesting
  void showProgress() {
    if (_dialogOpen || !downloading) return;
    _dialogOpen = true;
    showAppDialog<void>(
      title: 'Downloading update',
      dismissible: false,
      child: Obx(() => UpdateProgress(received: _received.value, total: _total.value, speed: _speed.value)),
      actions: (context) => <Widget>[
        Expanded(child: OutlinePill(label: 'Cancel', height: 40, onTap: cancel)),
        SizedBox(width: 13 * context.scale),
        Expanded(child: GradientPill(label: 'Hide', height: 40, onTap: _closeProgress)),
      ],
    ).whenComplete(() => _dialogOpen = false);
  }

  void _closeProgress() {
    if (_dialogOpen) Get.back<void>();
  }

  void cancel() {
    _cancel?.cancel('canceled');
    _closeProgress();
  }

  Future<void> _install(AppRelease release) async {
    progress.value = 0;
    _received.value = 0;
    _speed.value = 0;
    _total.value = release.apkSize;
    final cancelToken = _cancel = CancelToken();
    showProgress();
    final notify = Platform.isAndroid && Get.isRegistered<DownloadService>() ? DownloadService.to : null;
    try {
      final path = '${(await getTemporaryDirectory()).path}/toomu-update.apk';
      final clock = Stopwatch()..start();
      final meter = SpeedMeter(0, Duration.zero);
      var got = 0;
      // Redraws 4× a second, not on every network chunk; the notification
      // (which keeps Toomu running with the screen off) once a second.
      final ticker = Timer.periodic(DownloadService.progressTick, (t) {
        _received.value = got;
        _speed.value = meter.add(got, clock.elapsed);
        if (_total.value > 0) progress.value = got / _total.value;
        if (t.tick % 4 == 1) {
          notify?.showAppUpdate(
            status: UpdateProgress.label(got, _total.value, _speed.value),
            progress: _total.value > 0 ? got * 1000 ~/ _total.value : -1,
            onCancel: cancel,
          );
        }
      });
      try {
        await parallelDownload(
          _dio,
          release.apkUrl!,
          path,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            got = received;
            if (total > 0) _total.value = total;
          },
        );
      } finally {
        ticker.cancel();
        notify?.showAppUpdate();
      }
      debugPrint('[Update] ${Formatters.bytes(_total.value)} in ${clock.elapsed.inSeconds} s');
      _closeProgress();
      showSnack('Installing update', 'Toomu closes when it is done. Open it again to use the new version.');
      await _channel.invokeMethod<void>('install', {'path': path});
    } catch (e) {
      _closeProgress();
      if (!cancelToken.isCancelled) showSnack("Couldn't update Toomu", ErrorText.of(e));
    } finally {
      _cancel = null;
      progress.value = null;
    }
  }
}
