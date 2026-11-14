import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../core/values/app_constants.dart';
import '../widgets/app_dialog.dart';
import 'storage_service.dart';
import '../widgets/app_snackbar.dart';

/// Controls the floating download bubble shown over the YouTube app
/// (native BubbleService). Turning it on walks the user through the two
/// system permissions it needs, resuming the flow each time they come back
/// from a settings screen.
class FloatingButtonService extends GetxService with WidgetsBindingObserver {
  static FloatingButtonService get to => Get.find();

  static const _channel = MethodChannel('toomu/bubble');
  final _storage = StorageService.to;

  final enabled = false.obs;

  /// User is in the middle of granting permissions.
  bool _pending = false;

  FloatingButtonService init() {
    enabled.value =
        Platform.isAndroid &&
        (_storage.read<bool>(AppConstants.kBubbleEnabled) ?? false);
    WidgetsBinding.instance.addObserver(this);
    if (enabled.value) unawaited(_restart());
    if (Platform.isAndroid) {
      unawaited(hasNowPlayingAccess().then((v) => nowPlayingAccess.value = v));
    }
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (Platform.isAndroid) {
      unawaited(hasNowPlayingAccess().then((v) => nowPlayingAccess.value = v));
    }
    if (_pending) {
      unawaited(enable());
    } else if (enabled.value) {
      unawaited(_restart());
    }
  }

  Future<({bool overlay, bool usage, bool running, bool notifications})>
  _status() async {
    final s =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
    return (
      overlay: s['overlay'] == true,
      usage: s['usage'] == true,
      running: s['running'] == true,
      notifications: s['notifications'] == true,
    );
  }

  /// "Notification access" lets a bubble tap read what YouTube is playing.
  Future<bool> hasNowPlayingAccess() async =>
      Platform.isAndroid && (await _status()).notifications;

  /// Shown in Settings; refreshed when the app resumes.
  final nowPlayingAccess = false.obs;

  /// Settings row: open the "Notification access" screen.
  Future<void> requestNowPlayingAccess() async {
    if (!Platform.isAndroid) return;
    if (await hasNowPlayingAccess()) {
      nowPlayingAccess.value = true;
      showSnack(
        'Already on',
        'Tapping the bubble opens the playing video\'s download options.',
      );
      return;
    }
    final ok = await showConfirmDialog(
      title: 'One-tap download',
      message:
          'Allow "Notification access" so the bubble knows which video YouTube is playing — '
          'and shows only on YouTube\'s video page, not on every screen. '
          'Toomu only asks YouTube what is playing; it never reads your notifications.\n\n'
          'If the switch is greyed out: open App info for Toomu → ⋮ → "Allow restricted settings", '
          'then try again.',
      confirmLabel: 'Open settings',
    );
    if (ok) await _channel.invokeMethod<void>('openNotificationSettings');
  }

  Future<void> toggle() => enabled.value ? disable() : enable();

  /// One step per call: asks for the next missing permission, or starts.
  Future<void> enable() async {
    if (!Platform.isAndroid) return;
    final s = await _status();
    if (!s.overlay) {
      _pending = await showConfirmDialog(
        title: 'Allow "Display over other apps"',
        message:
            'The download button floats over YouTube. On the next screen, turn on '
            '"Allow display over other apps" for Toomu, then come back.',
        confirmLabel: 'Open settings',
        cancelLabel: 'Not now',
      );
      if (_pending) await _channel.invokeMethod<void>('openOverlaySettings');
      return;
    }
    if (!s.usage) {
      _pending = await showConfirmDialog(
        title: 'Allow "Usage access"',
        message:
            'So the button appears only while YouTube is open, Toomu needs to know which '
            'app is on screen. Find Toomu in the list, turn on "Permit usage access", then come back.',
        confirmLabel: 'Open settings',
        cancelLabel: 'Not now',
      );
      if (_pending) await _channel.invokeMethod<void>('openUsageSettings');
      return;
    }
    // Optional: one-tap download (otherwise the bubble needs a copied link).
    if (!s.notifications &&
        !(_storage.read<bool>(AppConstants.kBubbleNowPlayingAsked) ?? false)) {
      await _storage.write(AppConstants.kBubbleNowPlayingAsked, true);
      _pending = await showConfirmDialog(
        title: 'One-tap download (recommended)',
        message:
            'Allow "Notification access" so tapping the bubble knows which video YouTube is '
            'playing and opens its download options right away, and the bubble shows only on '
            'YouTube\'s video page. Toomu only asks YouTube what is '
            'playing; it never reads your notifications.\n\n'
            'If the switch is greyed out: open App info for Toomu → ⋮ → "Allow restricted settings", '
            'then try again.',
        confirmLabel: 'Open settings',
        cancelLabel: 'Skip',
      );
      if (_pending) {
        await _channel.invokeMethod<void>('openNotificationSettings');
        return;
      }
    }
    _pending = false;
    await _channel.invokeMethod<void>('start');
    enabled.value = true;
    await _storage.write(AppConstants.kBubbleEnabled, true);
    showSnack(
      'Download button is on',
      'Open a video in YouTube to see it.',
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> disable() async {
    _pending = false;
    enabled.value = false;
    await _storage.write(AppConstants.kBubbleEnabled, false);
    await _channel.invokeMethod<void>('stop');
  }

  /// Keeps the service running after app restarts; turns the setting off if
  /// the user revoked a permission in system settings.
  Future<void> _restart() async {
    final s = await _status();
    if (!s.overlay || !s.usage) {
      enabled.value = false;
      await _storage.write(AppConstants.kBubbleEnabled, false);
      return;
    }
    if (!s.running) await _channel.invokeMethod<void>('start');
  }
}
