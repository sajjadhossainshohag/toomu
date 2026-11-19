import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/utils/error_text.dart';
import '../../../core/utils/host_os.dart';
import '../../../core/utils/shell_open.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/video_item.dart';
import '../../../routes/app_pages.dart';
import '../../../services/download_service.dart';
import '../../../services/media_scanner_service.dart';
import '../../../services/private_vault.dart';
import '../../../services/video_session_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/option_sheet.dart';
import '../../music/controllers/music_controller.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../videos/controllers/videos_controller.dart';

enum PrivateStage { loading, create, confirm, locked, open }

Future<void> openPrivateFolder() async => Get.toNamed<void>(Routes.privateFolder);

void reloadLibraries() {
  if (Get.isRegistered<VideosController>()) unawaited(Get.find<VideosController>().load());
  if (Get.isRegistered<MusicController>()) unawaited(Get.find<MusicController>().load());
}

Future<List<String>> moveToPrivateFolder(
  List<({String? path, String title})> items,
  Future<void> Function(List<String> paths) deleteOriginals,
) async {
  final one = items.length == 1;
  final found = items.where((i) => i.path != null && File(i.path!).existsSync()).toList();
  if (found.isEmpty) {
    showSnack(one ? "Can't move this file" : "Can't move these files", "Toomu can't reach ${one ? 'it' : 'them'} on this phone.");
    return const [];
  }
  final label = found.length == 1 ? found.first.title : '${found.length} files';
  final skipped = items.length - found.length;
  final ok = await showConfirmDialog(
    title: 'Move to private folder?',
    message: '${found.length == 1 ? '"$label" leaves' : '$label leave'} the gallery and other apps. '
        'Only Toomu opens ${found.length == 1 ? 'it' : 'them'}, with your PIN.\n\n'
        '${skipped > 0 ? "$skipped of the selected can't be moved (not finished or not on this phone) and stay where they are.\n\n" : ''}'
        '${HostOs.isWindows ? 'Uninstalling asks whether to keep private files.' : 'Uninstalling Toomu deletes private files unless you tick "Keep app data" when Android asks (Android 10 and newer).'}',
    confirmLabel: 'Move',
  );
  if (!ok) return const [];
  showSnack('Moving to private folder…', label, duration: const Duration(seconds: 30));
  try {
    final paths = [for (final i in found) i.path!];
    final moved = await (await PrivateVault.open()).moveManyIn(paths, () => deleteOriginals(paths));
    Get.closeAllSnackbars();
    final failed = items.length - moved.length;
    if (moved.isEmpty) {
      showSnack('Not moved', one ? 'The original stays where it was.' : 'The originals stay where they were.');
      return moved;
    }
    for (final p in moved) {
      await DownloadService.to.forgetFile(p);
    }
    await VideoSessionService.to.stopIfPlaying(moved);
    showSnack(
      one ? 'Moved to private folder' : 'Moved ${moved.length} to private folder',
      failed > 0 ? '$failed not moved; ${failed == 1 ? 'it stays' : 'they stay'} where ${failed == 1 ? 'it was' : 'they were'}.' : label,
      mainButton: TextButton(
        onPressed: () {
          Get.closeCurrentSnackbar();
          openPrivateFolder();
        },
        child: const Text('Open'),
      ),
    );
    return moved;
  } catch (e) {
    debugPrint('[Private] move failed: $e');
    Get.closeAllSnackbars();
    showSnack(one ? "Couldn't move it" : "Couldn't move them", ErrorText.of(e));
    return const [];
  }
}

class PrivateFolderController extends GetxController with WidgetsBindingObserver {
  static const pinLength = 4;

  final _auth = LocalAuthentication();
  late final PrivateVault _vault;
  final stage = PrivateStage.loading.obs;
  final pin = ''.obs;
  final error = RxnString();
  final files = <File>[].obs;
  final canUseBiometrics = false.obs;
  String? _first;
  var _changingPin = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _secure(true);
    _start();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _secure(false);
    super.onClose();
  }

  static void _secure(bool on) {
    if (Platform.isAndroid) unawaited(const MethodChannel('toomu/video').invokeMethod<void>('secure', {'on': on}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final unlocked = stage.value == PrivateStage.open || (_changingPin && stage.value != PrivateStage.locked);
    // Not on inactive: the fingerprint prompt makes the app inactive. Windows reports a minimized window as hidden.
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && unlocked) {
      files.clear();
      pin.value = '';
      _changingPin = false;
      stage.value = PrivateStage.locked;
      // Sheets, dialogs and the player opened from here go too: they would still act on private files.
      Get.until((r) => r.settings.name == Routes.privateFolder);
    }
  }

  Future<void> _start() async {
    _vault = await PrivateVault.open();
    canUseBiometrics.value = await _biometricsReady();
    stage.value = _vault.hasPin ? PrivateStage.locked : PrivateStage.create;
    unawaited(unlockWithBiometrics());
  }

  Future<bool> _biometricsReady() async {
    try {
      if (HostOs.isWindows) return await _auth.isDeviceSupported();
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (e) {
      debugPrint('[Private] biometrics: $e');
      return false;
    }
  }

  void press(String digit) {
    if (pin.value.length >= pinLength) return;
    error.value = null;
    pin.value += digit;
    if (pin.value.length == pinLength) _submit(pin.value);
  }

  void backspace() {
    if (pin.value.isNotEmpty) pin.value = pin.value.substring(0, pin.value.length - 1);
  }

  Future<void> _submit(String entered) async {
    pin.value = '';
    switch (stage.value) {
      case PrivateStage.create:
        _first = entered;
        stage.value = PrivateStage.confirm;
      case PrivateStage.confirm:
        if (entered != _first) {
          error.value = "The PINs didn't match. Try again.";
          stage.value = PrivateStage.create;
          return;
        }
        await _vault.setPin(entered);
        _open();
      case PrivateStage.locked:
        if (await _vault.tryPin(entered)) {
          _open();
        } else {
          final s = ((await _vault.lockLeft()).inMilliseconds / 1000).ceil();
          error.value = s == 0 ? 'Wrong PIN' : 'Too many tries. Wait ${s < 60 ? '$s s' : '${(s / 60).ceil()} min'}.';
        }
      case PrivateStage.loading || PrivateStage.open:
        break;
    }
  }

  void _open() {
    _changingPin = false;
    error.value = null;
    stage.value = PrivateStage.open;
    reload();
  }

  void reload() => files.assignAll(_vault.files());

  Future<void> unlockWithBiometrics() async {
    if (!canUseBiometrics.value || stage.value != PrivateStage.locked) return;
    // Fingerprint/face only on phones: people who share a phone often know its screen-lock PIN.
    if (await _authenticate(biometricOnly: !HostOs.isWindows)) {
      await _vault.resetTries();
      _open();
    }
  }

  Future<void> forgotPin() async {
    // Strict: the phone's screen-lock PIN never resets it, only an enrolled fingerprint or face.
    if (!canUseBiometrics.value) {
      error.value = "Without the PIN, the private folder can't be opened.";
    } else if (await _authenticate(biometricOnly: !HostOs.isWindows)) {
      changePin();
    } else {
      error.value = 'Not recognised. Try again.';
    }
  }

  void changePin() {
    _changingPin = true;
    files.clear();
    pin.value = '';
    error.value = null;
    stage.value = PrivateStage.create;
  }

  Future<bool> _authenticate({required bool biometricOnly}) async {
    try {
      return await _auth.authenticate(localizedReason: 'Open your private folder', biometricOnly: biometricOnly);
    } catch (e) {
      debugPrint('[Private] unlock: $e');
      return false;
    }
  }

  static String nameOf(File f) => f.uri.pathSegments.last;

  bool get _isOpen => stage.value == PrivateStage.open;

  Future<void> openItem(File f) async {
    if (!_isOpen) return;
    if (PrivateVault.kindOf(f.path) == DownloadKind.file) return _openElsewhere(f);
    final media = files.where((x) => PrivateVault.kindOf(x.path) != DownloadKind.file).toList();
    await Get.toNamed<void>(
      Routes.videoPlayer,
      arguments: VideoPlaylist.private([for (final m in media) VideoItem.file(m.path)], media.indexOf(f)),
    );
  }

  Future<void> showItemMenu(File f) async {
    final action = await showOptionSheet<String>(
      title: nameOf(f),
      options: const <SheetOption<String>>[
        SheetOption(
          value: 'out',
          label: 'Move out of private folder',
          subtitle: 'Back to the Toomu download folder',
          icon: Icons.lock_open_rounded,
        ),
        SheetOption(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded),
      ],
    );
    switch (action) {
      case 'out':
        await _moveOut(f);
      case 'delete':
        await _delete(f);
    }
  }

  Future<void> _openElsewhere(File f) async {
    final ok = await showConfirmDialog(
      title: 'Open in another app?',
      message: '"${nameOf(f)}" opens in another app, which may keep it in its recent files.',
      confirmLabel: 'Open',
    );
    if (!ok || !_isOpen) return;
    try {
      await openFile(f.path);
    } catch (e) {
      showSnack("Can't open this file", ErrorText.of(e));
    }
  }

  Future<void> _moveOut(File f) async {
    if (!_isOpen) return;
    final sub = switch (PrivateVault.kindOf(f.path)) {
      DownloadKind.video => 'Video',
      DownloadKind.audio => 'Audio',
      DownloadKind.file => 'Files',
    };
    try {
      final path = await _vault.moveOut(f, '${DownloadService.to.downloadRoot}/$sub');
      await MediaScannerService.to.scan(path);
      reload();
      showSnack('Moved out of private folder', path, duration: const Duration(seconds: 3));
      reloadLibraries();
    } catch (e) {
      debugPrint('[Private] move out failed: $e');
      showSnack("Couldn't move it", ErrorText.of(e));
    }
  }

  Future<void> _delete(File f) async {
    if (!_isOpen) return;
    final ok = await showConfirmDialog(
      title: 'Delete for good?',
      message: '"${nameOf(f)}" will be deleted. It can\'t be brought back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !_isOpen) return;
    await _vault.delete(f);
    reload();
  }
}
