import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/frame_probe.dart';
import '../../../core/values/app_constants.dart';
import '../../../data/models/video_item.dart';
import '../../../data/repositories/video_resume_repository.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/video_session_service.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/app_snackbar.dart';

/// What to play: a list (e.g. a folder) and where to start.
class VideoPlaylist {
  const VideoPlaylist(this.items, [this.index = 0]);

  final List<VideoItem> items;
  final int index;
}

/// Aspect modes cycled by the aspect button (MX-style).
enum VideoFit {
  fit('Fit', BoxFit.contain, null, Icons.fit_screen_rounded),
  crop('Crop', BoxFit.cover, null, Icons.crop_rounded),
  stretch('Stretch', BoxFit.fill, null, Icons.open_in_full_rounded),
  wide('16:9', BoxFit.contain, 16 / 9, Icons.crop_16_9_rounded),
  classic('4:3', BoxFit.contain, 4 / 3, Icons.crop_7_5_rounded);

  const VideoFit(this.label, this.boxFit, this.aspect, this.icon);

  final String label;
  final BoxFit boxFit;
  final double? aspect;
  final IconData icon;
}

/// Centre overlay shown while a gesture runs.
class GestureFeedback {
  const GestureFeedback({required this.icon, required this.text, this.level});

  final IconData icon;
  final String text;

  /// 0..1 bar (brightness / volume); null for none.
  final double? level;
}

enum _Drag { seek, brightness, volume, zoom }

/// MX Player-style playback: libmpv (media_kit) plus gestures — swipe left
/// edge for brightness, right edge for volume, sideways to seek, double-tap
/// to skip ±10 s, pinch to zoom — and lock, aspect, rotate, speed, tracks,
/// playlist and resume.
class VideoPlaybackController extends GetxController with WidgetsBindingObserver {
  /// The player lives in [VideoSessionService] so audio can continue after
  /// this screen closes (background play) and the screen can re-join it.
  final _session = VideoSessionService.to;
  Player get player => _session.player;
  VideoController get video => _session.video;

  List<VideoItem> get items => _session.items;
  RxInt get index => _session.index;
  VideoItem get current => items[index.value];
  bool get hasNext => index.value < items.length - 1;
  bool get hasPrevious => index.value > 0;

  final playing = false.obs;
  final buffering = false.obs;
  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final rate = 1.0.obs;

  final controlsVisible = true.obs;
  final locked = false.obs;
  final fit = VideoFit.fit.obs;
  final zoom = 1.0.obs;

  final feedback = Rxn<GestureFeedback>();
  final seekPreview = Rxn<Duration>();

  /// Double-tap skip ripple: negative = back, positive = forward (seconds).
  final skipRipple = 0.obs;

  /// Shown for a few seconds after resuming ("Resumed from 12:30").
  final resumedFrom = Rxn<Duration>();

  /// Set by the view: the player's box (gestures are measured in it).
  Size viewSize = Size.zero;

  /// The whole screen; [viewSize] is only the player, a small box above the watch page while upright.
  Size screenSize = Size.zero;

  // ------------------------------------------- picture-in-picture / background

  static const _platform = MethodChannel('toomu/video');
  final _settings = SettingsService.to;

  final pipSupported = false.obs;
  final inPip = false.obs;
  RxBool get backgroundPlay => _settings.videoBackgroundPlay;

  final _resume = VideoResumeRepository.instance;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hideTimer, _feedbackTimer, _rippleTimer, _resumeTimer, _saveTimer;
  String? _savedKey;
  Duration? _savedAt;

  @override
  void onInit() {
    super.onInit();
    FrameProbe.watch('player open');
    final args = Get.arguments as VideoPlaylist;
    final rejoined = _session.attach(args, (call) => _onPlatformCall(call));
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(followPhone);
    VolumeController.instance.showSystemUI = false;

    // Music and video shouldn't play at once.
    final music = AudioPlayerService.to.player;
    if (music.playing) music.pause();

    _subs.addAll([
      player.stream.playing.listen((v) {
        playing.value = v;
        if (!inPip.value) v ? _scheduleHide() : showControls(autoHide: false);
        _syncPlatform();
      }),
      player.stream.buffering.listen((v) => buffering.value = v),
      // mpv reports the position every frame; the seek bar and time only
      // need a few updates a second (once a second while hidden).
      player.stream.position.listen((v) {
        if (seekPreview.value != null) return;
        final step = controlsVisible.value && !inPip.value
            ? const Duration(milliseconds: 250)
            : const Duration(seconds: 1);
        if ((v - position.value).abs() >= step) position.value = v;
      }),
      player.stream.duration.listen((v) => duration.value = v),
      player.stream.rate.listen((v) => rate.value = v),
      player.stream.completed.listen((done) {
        if (!done) return;
        // A stream that "ends" well before its length was cut off by the
        // server: reconnect at that point instead of moving on.
        final total = current.duration ?? duration.value;
        if (current.isStream &&
            total > Duration.zero &&
            player.state.position < total - const Duration(seconds: 10)) {
          _streamFailed(force: true);
          return;
        }
        _resume.save(current.resumeKey, duration.value, duration.value); // finished
        if (hasNext) next();
      }),
      player.stream.error.listen((e) {
        debugPrint('[Video] $e');
        _lastError = e;
        _streamFailed();
      }),
      player.stream.width.listen((_) => _syncPlatform()),
    ]);
    _platform.invokeMethod<bool>('pipSupported').then((v) => pipSupported.value = v ?? false);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition(onlyIfMoved: true));
    if (rejoined) {
      // Back from the mini bar: same file, keep playing where it is.
      playing.value = player.state.playing;
      position.value = player.state.position;
      duration.value = player.state.duration;
      rate.value = player.state.rate;
      _syncPlatform();
      player.play();
    } else {
      _open();
    }
  }

  @override
  void onClose() {
    _savePosition();
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in [_hideTimer, _feedbackTimer, _rippleTimer, _resumeTimer, _saveTimer]) {
      t?.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    _platform.invokeMethod<void>('updatePip', {'autoEnter': false, 'playing': false});
    // Background play on + playing → the audio continues after leaving the
    // player (notification + mini bar); otherwise the session ends.
    final keepPlaying = backgroundPlay.value && playing.value;
    _session.detach(keepPlaying: keepPlaying);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    VolumeController.instance.showSystemUI = true;
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _session.setVideoEnabled(true);
      return;
    }
    if (state != AppLifecycleState.paused) return;
    _savePosition();
    // In PiP the activity is visible, so this only fires when the app is
    // really gone (Home without PiP, screen off): keep playing only with
    // background play on, otherwise pause like MX.
    if (inPip.value) return;
    if (!backgroundPlay.value) {
      player.pause();
    } else {
      // Audio only while nobody can see it: decoding and drawing frames
      // for a hidden video is most of the battery (and heat) cost.
      _session.setVideoEnabled(false);
    }
  }

  // ---------------------------------------- picture-in-picture / background

  /// Tells Android the video's shape and play state: PiP window aspect +
  /// buttons, auto-enter on Home (only while playing), and the system media
  /// controls for background play.
  void _syncPlatform() {
    final w = player.state.width ?? current.width;
    final h = player.state.height ?? current.height;
    _platform.invokeMethod<void>('updatePip', {
      'width': w == 0 ? 16 : w,
      'height': h == 0 ? 9 : h,
      'playing': playing.value,
      'autoEnter': _settings.videoAutoPip.value && playing.value,
    });
    _session.syncMedia();
  }

  Future<void> enterPip() async {
    if (!pipSupported.value) return;
    controlsVisible.value = false;
    final w = player.state.width ?? current.width;
    final h = player.state.height ?? current.height;
    await _platform.invokeMethod<bool>('enterPip', {
      'width': w == 0 ? 16 : w,
      'height': h == 0 ? 9 : h,
      'playing': playing.value,
      'autoEnter': _settings.videoAutoPip.value && playing.value,
    });
  }

  void toggleBackgroundPlay() {
    final on = !backgroundPlay.value;
    _settings.setVideoBackgroundPlay(on);
    _flash(on ? Icons.headphones_rounded : Icons.headset_off_rounded,
        on ? 'Background play on' : 'Background play off');
    _syncPlatform();
    showControls();
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'pipChanged':
        final entered = call.arguments == true;
        inPip.value = entered;
        if (entered) {
          controlsVisible.value = false;
          feedback.value = null;
        } else {
          // Closing the PiP window (vs. expanding it) leaves the app stopped:
          // pause like MX.
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
            await player.pause();
          } else {
            showControls();
          }
        }
      case 'action':
        final action = call.arguments as String;
        if (action.startsWith('seek:')) {
          seekTo(Duration(milliseconds: int.tryParse(action.substring(5)) ?? 0));
          return;
        }
        switch (action) {
          case 'playPause':
            await player.playOrPause();
          case 'play':
            await player.play();
          case 'pause':
            await player.pause();
          case 'rewind':
            seekBy(-10);
          case 'forward':
            seekBy(10);
          case 'next':
            await next();
          case 'previous':
            await previous();
          case 'stop':
            _session.mediaStopped();
            await player.pause();
        }
    }
  }

  // --------------------------------------------------------------- loading

  Future<void> _open() async {
    resumedFrom.value = null;
    zoom.value = 1;
    final item = current;
    // Resume point decided up front so the player starts right there (no
    // load, then seek, then load again).
    final saved = _resume.positionOf(item.resumeKey);
    final total = item.duration ?? Duration.zero;
    final resumeAt = saved != null && (total == Duration.zero || saved < total - VideoResumeRepository.margin)
        ? saved
        : null;
    final sw = Stopwatch()..start();
    await _session.openItem(item, play: true, start: resumeAt);
    if (resumeAt != null) {
      resumedFrom.value = resumeAt;
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 6), () => resumedFrom.value = null);
    }
    if (item.isStream) {
      _logStart(sw);
    } else {
      _watchFileLoad(item);
    }
    _syncPlatform(); // new title for the notification / PiP aspect
  }

  /// mpv's last error message (shown if a file won't load).
  String? _lastError;

  /// Local files: if nothing has loaded a few seconds after opening, say so
  /// on screen with mpv's reason, instead of a silent black screen.
  void _watchFileLoad(VideoItem item) {
    _lastError = null;
    Timer(const Duration(seconds: 6), () {
      if (isClosed || !identical(current, item) || player.state.duration > Duration.zero) return;
      debugPrint('[Video] file not loaded after 6 s: ${item.path ?? item.uri} '
          '(playing=${player.state.playing}, buffering=${player.state.buffering}, error=$_lastError)');
      showSnack("Can't play this video", _lastError ?? 'The player could not open this file.',
          duration: const Duration(seconds: 6));
    });
  }

  /// Diagnostics: how long until the stream actually plays.
  void _logStart(Stopwatch sw) {
    final from = player.state.position;
    player.stream.position
        .firstWhere((p) => p > from)
        .timeout(const Duration(seconds: 30))
        .then((_) => debugPrint('[Video] stream playing after ${sw.elapsedMilliseconds} ms'
            '${current.provisional ? ' (fast links)' : ''}'))
        .catchError((Object _) => debugPrint('[Video] stream not playing after 30 s'));
  }

  /// A YouTube stream that won't play: switch once to its simpler
  /// combined stream, at the same position.
  bool _switching = false;

  ///  - fast links (no yt-dlp) → yt-dlp's links, same quality;
  ///  - yt-dlp's links → the combined 360p stream.
  /// [force]: it certainly failed (cut off), skip the "is it stuck" check.
  Future<void> _streamFailed({bool force = false}) async {
    if (!current.isStream || _switching) return;
    final failed = current;
    if (!failed.provisional && failed.fallback == null) return;
    _switching = true;
    try {
      if (!force) {
        // mpv also reports harmless errors: only switch if playback is
        // really stuck a few seconds later.
        final before = player.state.position;
        await Future<void>.delayed(const Duration(seconds: 3));
        final moved = player.state.position - before > const Duration(milliseconds: 500);
        // Paused on purpose isn't stuck; never loaded, or "playing"
        // without moving, is.
        final stuck = !moved && (player.state.playing || player.state.duration == Duration.zero);
        if (isClosed || !stuck || !identical(current, failed)) return;
      }
      final next = await _session.replacementFor(failed);
      if (isClosed || next == null || !identical(current, failed)) return;
      debugPrint('[Video] stream failed; switching to '
          '${failed.provisional ? 'yt-dlp links' : (next.quality ?? 'the combined stream')}');
      await _switchStream(next, play: true);
    } finally {
      _switching = false;
    }
  }



  void startOver() {
    resumedFrom.value = null;
    player.seek(Duration.zero);
  }

  // Each save rewrites the whole storage file, so a paused video isn't
  // saved again and again.
  void _savePosition({bool onlyIfMoved = false}) {
    if (items.isEmpty || duration.value == Duration.zero) return;
    final key = current.resumeKey;
    final at = position.value;
    if (onlyIfMoved && key == _savedKey && at == _savedAt) return;
    _savedKey = key;
    _savedAt = at;
    _resume.save(key, at, duration.value);
  }

  // -------------------------------------------------------------- controls

  void playPause() {
    player.playOrPause();
    showControls();
  }

  Future<void> next() async {
    if (!hasNext) return;
    _savePosition();
    index.value++;
    await _open();
  }

  Future<void> previous() async {
    // MX: "previous" restarts the video when more than 3 s in.
    if (position.value > const Duration(seconds: 3) || !hasPrevious) {
      await player.seek(Duration.zero);
      return;
    }
    _savePosition();
    index.value--;
    await _open();
  }

  DateTime? _lastSeekAt;

  void seekBy(int seconds) {
    // Repeated taps add up from the last target; otherwise start from the
    // live position (position.value is only refreshed a few times a second).
    final now = DateTime.now();
    final chained = _lastSeekAt != null && now.difference(_lastSeekAt!) < const Duration(seconds: 1);
    _lastSeekAt = now;
    final base = chained ? position.value : player.state.position;
    final target = _clampPosition(base + Duration(seconds: seconds));
    position.value = target;
    player.seek(target);
  }

  void seekTo(Duration d) {
    seekPreview.value = null;
    position.value = d;
    player.seek(d);
    _scheduleHide();
  }

  void previewSeek(Duration d) {
    seekPreview.value = d;
    position.value = d;
    _hideTimer?.cancel();
  }

  Duration _clampPosition(Duration d) {
    final max = duration.value;
    if (d < Duration.zero) return Duration.zero;
    return max > Duration.zero && d > max ? max : d;
  }

  void toggleControls() {
    if (controlsVisible.value) {
      controlsVisible.value = false;
      _hideTimer?.cancel();
    } else {
      showControls();
    }
  }

  void showControls({bool autoHide = true}) {
    controlsVisible.value = true;
    if (autoHide) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!playing.value) return;
    _hideTimer = Timer(const Duration(milliseconds: 3500), () => controlsVisible.value = false);
  }

  void toggleLock() {
    locked.value = !locked.value;
    _flash(locked.value ? Icons.lock_rounded : Icons.lock_open_rounded,
        locked.value ? 'Locked' : 'Unlocked');
    showControls();
  }

  void cycleFit() {
    fit.value = VideoFit.values[(fit.value.index + 1) % VideoFit.values.length];
    zoom.value = 1;
    _flash(fit.value.icon, fit.value.label);
    showControls();
  }

  static const followPhone = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  bool get _viewIsLandscape => screenSize.width > screenSize.height;

  void rotate() {
    SystemChrome.setPreferredOrientations(_viewIsLandscape
        ? [DeviceOrientation.portraitUp]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    showControls();
  }

  /// Leaving: turn upright *before* the screen closes. Turning during the
  /// close animation re-laid out the page behind it mid-flight — a flicker
  /// on some phones. The picture is hidden while the screen turns.
  final exiting = false.obs;

  Future<void> exit() async {
    if (exiting.value) return;
    exiting.value = true;
    FrameProbe.watch('player close', window: const Duration(milliseconds: 1800));
    if (_viewIsLandscape) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      // Until the window is upright (or ~0.5 s at most).
      for (var i = 0; i < 10; i++) {
        final size = screenSize;
        if (size != Size.zero && size.height >= size.width) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    Get.back();
  }

  Future<void> pickSpeed() async {
    _hideTimer?.cancel();
    final picked = await showOptionSheet<double>(
      title: 'Playback speed',
      selected: rate.value,
      options: [
        for (final r in const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0])
          SheetOption(value: r, label: r == 1.0 ? 'Normal' : '${r}x'),
      ],
    );
    if (picked != null) await player.setRate(picked);
    _scheduleHide();
  }

  // --------------------------------------------------------- stream quality

  /// Streams only: the quality menu (current one checked). The choice is
  /// also remembered for the next YouTube video.
  Future<void> pickQuality() async {
    final options = current.qualities;
    if (options.isEmpty) return;
    _hideTimer?.cancel();
    final now = current.currentQuality;
    final picked = await showOptionSheet<StreamQuality>(
      title: 'Quality',
      selected: now,
      options: [
        for (final q in options)
          SheetOption(
            value: q,
            label: q.label,
            subtitle: [
              if (q.codec != null) q.codec!,
              if (q.quality >= 1440 && q.codec != 'H.264') 'may heat the phone',
            ].join(' · '),
          ),
      ],
    );
    _scheduleHide();
    if (picked == null || identical(picked, now)) return;
    StorageService.to.write(AppConstants.kStreamQuality, picked.quality);
    await _switchStream(current.withQuality(picked));
  }

  /// Plays [item] in place of the current one, at the same position.
  Future<void> _switchStream(VideoItem item, {bool? play}) async {
    final at = player.state.position;
    final wasPlaying = play ?? (player.state.playing || buffering.value);
    _savePosition();
    items[index.value] = item;
    buffering.value = true;
    await _session.openItem(item, play: wasPlaying, start: at);
    _syncPlatform(); // new aspect for PiP
  }

  Future<void> pickAudioTrack() async {
    _hideTimer?.cancel();
    final tracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (tracks.isEmpty) {
      showSnack('Audio', 'This video has a single audio track.', duration: const Duration(seconds: 2));
      return;
    }
    final picked = await showOptionSheet<AudioTrack>(
      title: 'Audio track',
      selected: player.state.track.audio,
      options: [for (final t in tracks) SheetOption(value: t, label: _trackLabel(t.title, t.language, t.id))],
    );
    if (picked != null) await player.setAudioTrack(picked);
    _scheduleHide();
  }

  Future<void> pickSubtitle() async {
    _hideTimer?.cancel();
    final tracks = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final picked = await showOptionSheet<SubtitleTrack>(
      title: 'Subtitles',
      selected: player.state.track.subtitle,
      options: [
        SheetOption(value: SubtitleTrack.no(), label: 'Off'),
        for (final t in tracks) SheetOption(value: t, label: _trackLabel(t.title, t.language, t.id)),
      ],
    );
    if (picked != null) await player.setSubtitleTrack(picked);
    if (tracks.isEmpty && picked == null) {
      showSnack('Subtitles', 'This video has no subtitles.', duration: const Duration(seconds: 2));
    }
    _scheduleHide();
  }

  static String _trackLabel(String? title, String? language, String id) =>
      [title, language?.toUpperCase()].whereType<String>().where((s) => s.isNotEmpty).join(' • ').ifEmpty('Track $id');

  // -------------------------------------------------------------- gestures

  _Drag? _drag;
  Offset _dragStart = Offset.zero;
  double _startZoom = 1, _startBrightness = 0.5, _startVolume = 0.5;
  Duration _startPosition = Duration.zero;

  Future<void> onScaleStart(ScaleStartDetails d) async {
    if (locked.value) return;
    _drag = d.pointerCount >= 2 ? _Drag.zoom : null;
    _dragStart = d.localFocalPoint;
    _startZoom = zoom.value;
    _startPosition = position.value;
    _startBrightness = await ScreenBrightness.instance.application;
    _startVolume = await VolumeController.instance.getVolume();
  }

  void onScaleUpdate(ScaleUpdateDetails d) {
    if (locked.value || viewSize == Size.zero) return;
    if (d.pointerCount >= 2) _drag = _Drag.zoom;
    final delta = d.localFocalPoint - _dragStart;
    if (_drag == null) {
      if (delta.distance < 14) return; // ignore jitter
      _drag = delta.dx.abs() > delta.dy.abs()
          ? _Drag.seek
          : (_dragStart.dx < viewSize.width / 2 ? _Drag.brightness : _Drag.volume);
    }
    switch (_drag!) {
      case _Drag.zoom:
        zoom.value = (_startZoom * d.scale).clamp(1.0, 4.0);
        _show(Icons.zoom_in_rounded, '${(zoom.value * 100).round()}%');
      case _Drag.seek:
        // A full-width swipe = 90 s, like MX's fine seek.
        final offset = Duration(milliseconds: (delta.dx / viewSize.width * 90000).round());
        final target = _clampPosition(_startPosition + offset);
        previewSeek(target);
        final diff = target - _startPosition;
        final sign = diff.isNegative ? '−' : '+';
        _show(diff.isNegative ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
            '$sign${Formatters.duration(diff.abs())}\n'
            '${Formatters.duration(target)} / ${Formatters.duration(duration.value)}');
      case _Drag.brightness:
        final v = (_startBrightness - delta.dy / (viewSize.height * 0.8)).clamp(0.0, 1.0);
        ScreenBrightness.instance.setApplicationScreenBrightness(v);
        _show(Icons.brightness_6_rounded, '${(v * 100).round()}%', level: v);
      case _Drag.volume:
        final v = (_startVolume - delta.dy / (viewSize.height * 0.8)).clamp(0.0, 1.0);
        VolumeController.instance.setVolume(v);
        _show(v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '${(v * 100).round()}%', level: v);
    }
  }

  void onScaleEnd(ScaleEndDetails d) {
    if (_drag == _Drag.seek && seekPreview.value != null) seekTo(seekPreview.value!);
    _drag = null;
    _hideFeedbackSoon();
  }

  Offset _doubleTapAt = Offset.zero;
  void onDoubleTapDown(TapDownDetails d) => _doubleTapAt = d.localPosition;

  /// Left third: −10 s, right third: +10 s (repeated taps add up), middle:
  /// play/pause.
  void onDoubleTap() {
    if (locked.value || viewSize == Size.zero) return;
    final x = _doubleTapAt.dx / viewSize.width;
    if (x > 0.35 && x < 0.65) {
      playPause();
      return;
    }
    final step = x <= 0.35 ? -10 : 10;
    skipRipple.value = skipRipple.value.sign == step.sign ? skipRipple.value + step : step;
    seekBy(step);
    _rippleTimer?.cancel();
    _rippleTimer = Timer(const Duration(milliseconds: 800), () => skipRipple.value = 0);
  }

  void onTap() {
    if (locked.value) {
      // Only the unlock button appears while locked.
      showControls();
      return;
    }
    toggleControls();
  }

  void _show(IconData icon, String text, {double? level}) {
    _feedbackTimer?.cancel();
    feedback.value = GestureFeedback(icon: icon, text: text, level: level);
  }

  void _flash(IconData icon, String text) {
    _show(icon, text);
    _hideFeedbackSoon();
  }

  void _hideFeedbackSoon() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () => feedback.value = null);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
