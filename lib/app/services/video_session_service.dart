import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/utils/device_profile.dart';
import '../core/utils/subtitles.dart';
import '../data/models/video_item.dart';
import '../data/models/youtube_stream.dart';
import '../data/providers/local_video_provider.dart';
import '../data/repositories/video_resume_repository.dart';
import '../routes/app_pages.dart';
import '../modules/video_player/controllers/video_playback_controller.dart';
import '../modules/video_player/controllers/watch_details_controller.dart';
import 'diagnostics_service.dart';
import 'settings_service.dart';
import 'stream_proxy.dart';
import 'ytdlp_service.dart';

/// Owns the video player so playback can outlive the player screen:
/// with background play on, leaving the player keeps the audio going
/// (notification + mini bar), and reopening resumes the same session.
class VideoSessionService extends GetxService {
  static VideoSessionService get to => Get.find();

  static const _platform = MethodChannel('toomu/video');

  /// One player for the whole app, made on first use and then reused:
  /// a new mpv + video surface per video made opening the player stutter,
  /// and media_kit destroys a disposed mpv on the UI thread 5 s later (a
  /// stall right after closing).
  Player? _player;
  VideoController? _video;
  Player get player => _player!;
  bool get hasPlayer => _player != null;
  VideoController get video => _video!;

  /// A video is loaded (player screen open, or playing in the background).
  bool _active = false;
  bool private = false; // private folder: nothing of it may outlive the player or show outside the PIN

  final items = <VideoItem>[].obs;
  final index = 0.obs;

  /// Playing with no player screen open (shows the mini bar).
  final inBackground = false.obs;
  final playing = false.obs;

  /// Shrunk into the corner of the app (YouTube's minimize): still playing, picture on.
  final minimized = false.obs;
  Rect? minimizeFrom;

  VideoItem? get current => items.isEmpty ? null : items[index.value];

  /// Set while a player screen is attached; receives PiP / button events.
  void Function(MethodCall call)? _screen;

  final List<StreamSubscription<dynamic>> _subs = [];

  VideoSessionService init() {
    // Buttons from the PiP window / background notification land here even
    // when no player screen is open.
    _platform.setMethodCallHandler((call) async {
      // Native notes for the diagnostics log (MainActivity).
      if (call.method == 'log') {
        debugPrint('${call.arguments}');
        return;
      }
      final screen = _screen;
      if (screen != null) return screen(call);
      if (call.method == 'action' && _active) {
        final action = call.arguments as String;
        if (action.startsWith('seek:')) {
          await player.seek(Duration(milliseconds: int.tryParse(action.substring(5)) ?? 0));
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
            await player.seek(player.state.position - const Duration(seconds: 10));
          case 'forward':
            await player.seek(player.state.position + const Duration(seconds: 10));
          case 'next':
            await _skip(1);
          case 'previous':
            if (player.state.position > const Duration(seconds: 3) || index.value == 0) {
              await player.seek(Duration.zero);
            } else {
              await _skip(-1);
            }
          case 'stop':
            mediaStopped();
            await stop();
        }
      }
    });
    return this;
  }

  /// Called by the player screen. Returns true when it re-joins the running
  /// session (same playlist position), so it must not reopen the file.
  bool attach(VideoPlaylist args, void Function(MethodCall call) onPlatformCall) {
    _screen = onPlatformCall;
    final same = _active &&
        args.items.length == items.length &&
        args.index == index.value &&
        args.items.isNotEmpty &&
        args.items[args.index].resumeKey == current?.resumeKey;
    _outsideBuild(() {
      inBackground.value = false;
      minimized.value = false;
    });
    if (same) {
      setVideoEnabled(true);
      return true;
    }

    if (_active) _savePosition();
    private = args.private;
    _releaseDetails(args.items);
    items.assignAll(args.items);
    index.value = args.index.clamp(0, args.items.length - 1);
    _ensurePlayer();
    _active = true;
    // Choices from the last video don't carry over (mpv keeps them).
    setVideoEnabled(true);
    player.setRate(1.0);
    player.setAudioTrack(AudioTrack.auto());
    player.setSubtitleTrack(SubtitleTrack.auto());
    return false;
  }

  void _ensurePlayer() {
    // Never disposed: media_kit destroys mpv on the UI thread, which froze the app ("not responding")
    // when the player was released in the background.
    if (_player != null) return;
    // mpv's warnings and errors go to the diagnostics log (why a file or
    // stream won't open).
    MediaKit.ensureInitialized(); // loads libmpv: on first video, not at app start
    _player = Player(
      configuration: PlayerConfiguration(
        title: 'Toomu',
        // media_kit's libmpv (Android and Windows) is built without mpv's on-screen controller: its osc=no only
        // logs "property not found" on every video. osd-level is set in _configure instead.
        osc: true,
        logLevel: MPVLogLevel.warn,
        // Read-ahead; media_kit also uses it for the seek-back cache, which _configure makes smaller.
        bufferSize: DeviceProfile.lowEnd ? 16 << 20 : 32 << 20,
      ),
    );
    _video = VideoController(_player!);
    _configure(_player!);
    _subs.addAll([
      player.stream.log.listen((l) => mpvLog('[mpv] ${l.level} ${l.prefix}: ${l.text.trim()}')),
      player.stream.playing.listen((v) {
        playing.value = _active && v;
        syncMedia();
      }),
      player.stream.duration.listen((_) => syncMedia()),
      player.stream.rate.listen((_) => syncMedia()),
      // Seeks (from anywhere) move the media controls' seek bar.
      player.stream.position.listen(_checkDrift),
      player.stream.completed.listen((done) {
        if (!done || !_active || !inBackground.value) return;
        final item = current;
        final total = item?.duration ?? player.state.duration;
        if (item != null &&
            item.isStream &&
            total > Duration.zero &&
            player.state.position < total - const Duration(seconds: 10)) {
          _recoverInBackground(item); // cut off by the server, not the end
          return;
        }
        _savePosition(finished: true);
        if (index.value < items.length - 1) {
          _skip(1);
        } else {
          stop();
        }
      }),
    ]);
  }

  /// Player screen closing. With [keepPlaying] the audio continues in the
  /// background; otherwise the session ends.
  Future<void> detach({
    required bool keepPlaying,
    bool minimize = false,
    void Function(MethodCall call)? screen,
  }) async {
    // Up next: the new screen attaches before the replaced one closes; that one must not end the new video.
    if (screen != null && !identical(screen, _screen)) return;
    _screen = null;
    if (keepPlaying && _active && !private) {
      inBackground.value = true;
      minimized.value = minimize;
      if (!minimize) setVideoEnabled(false); // audio only until the player is reopened
      return;
    }
    await stop();
  }

  Future<void> stopIfPlaying(Iterable<String> paths) async {
    final path = current?.path;
    if (_active && path != null && paths.contains(path)) await stop();
  }

  /// Ends the session (mini bar ✕, notification Close, music starting…).
  Future<void> stop() async {
    _savePosition();
    _releaseDetails();
    inBackground.value = false;
    minimized.value = false;
    _endSession();
    await _stopMedia();
  }

  void _releaseDetails([Iterable<VideoItem> keep = const []]) {
    final kept = {for (final k in keep) k.youtubeId};
    for (final item in items) {
      final id = item.youtubeId;
      if (id != null && !kept.contains(id) && Get.isRegistered<WatchDetailsController>(tag: id)) {
        Get.delete<WatchDetailsController>(tag: id, force: true);
      }
    }
  }

  @visibleForTesting
  set debugActive(bool on) => _active = on;

  /// mpv's video is off (audio only). Kept after a video ends: mpv keeps it for the next file.
  bool _videoOff = false;

  /// Records what [setVideoEnabled] sends to mpv (tests have no player).
  @visibleForTesting
  void Function(bool on)? debugVideoTrack;

  /// Turns video decoding off while nobody can see it (background play)
  /// and back on when the player is visible again.
  void setVideoEnabled(bool on) {
    if (!_active || _videoOff == !on) return;
    _videoOff = !on;
    final debug = debugVideoTrack;
    if (debug != null) return debug(on);
    player.setVideoTrack(on ? VideoTrack.auto() : VideoTrack.no());
  }

  String? _lastMpvLog;
  int _badTimestamps = 0;
  static const _softwareAfter = 30;
  String? _hwdecBefore;

  @visibleForTesting
  void Function(String hwdec)? debugHwdec;

  @visibleForTesting
  void mpvLog(String line) {
    // Repeated frame timestamps: Android's hardware decoder breaks on some videos (picture lags or goes black,
    // audio plays on). Reopening only helps until it breaks again.
    if (line.contains('Invalid video timestamp')) {
      if (++_badTimestamps == _softwareAfter) unawaited(_softwareDecode());
      if (_badTimestamps > 3) return;
    }
    if (line != _lastMpvLog) debugPrint(line);
    _lastMpvLog = line;
  }

  Future<void> _softwareDecode() async {
    debugPrint('[Video] $_softwareAfter broken frame timestamps: software decoding for this video');
    final debug = debugHwdec;
    if (debug != null) return debug('no');
    final mpv = _player?.platform;
    if (mpv is! NativePlayer) return;
    try {
      _hwdecBefore = await mpv.getProperty('hwdec');
      await mpv.setProperty('hwdec', 'no');
    } catch (e) {
      debugPrint('[Video] software decoding: $e');
    }
  }

  /// Next / previous video with no player screen open.
  Future<void> _skip(int delta) async {
    final to = index.value + delta;
    if (to < 0 || to >= items.length) return;
    _savePosition();
    index.value = to;
    await openItem(current!);
    syncMedia();
  }

  /// What to play when [failed] (a stream) stops working:
  ///  - fast links (no yt-dlp) → yt-dlp's links at the same quality;
  ///  - yt-dlp's links → the combined 360p stream.
  Future<VideoItem?> replacementFor(VideoItem failed) async {
    final id = failed.youtubeId;
    if (!failed.provisional || id == null) return failed.fallback;
    try {
      final info = await YtDlpService.to
          .info('https://www.youtube.com/watch?v=$id')
          .timeout(const Duration(seconds: 90));
      return YoutubeStream.pick(info,
              videoId: id,
              title: failed.title,
              preferred: failed.currentQuality?.quality ?? YoutubeStream.defaultQuality) ??
          failed.fallback;
    } catch (e) {
      debugPrint('[Video] yt-dlp links unavailable: $e');
      return failed.fallback;
    }
  }

  Future<void> _recoverInBackground(VideoItem failed) async {
    final at = player.state.position;
    final next = await replacementFor(failed);
    if (next == null || !_active || !identical(current, failed)) return;
    debugPrint('[Video] stream cut off in background; reconnecting');
    items[index.value] = next;
    await openItem(next, start: at);
  }

  /// mpv options media_kit doesn't set the way streams need them. Called
  /// right after the player is created and never awaited: these calls are
  /// queued behind the player's start-up just like `open()`, and ahead of
  /// it, so nothing ever waits on them.
  static void _configure(Player p) {
    final mpv = p.platform;
    if (mpv is! NativePlayer) return;
    void set(String name, String value) {
      mpv.setProperty(name, value).catchError((Object e) => debugPrint('[Video] mpv option $name: $e'));
    }

    // YouTube streams come through the local stream proxy, which may hold a
    // read for a while (fast links running out, waiting for yt-dlp's):
    // media_kit's 5 s would make mpv give up and reconnect in a loop.
    set('network-timeout', '60');
    // Read ahead into the memory buffer only. On disk, read-ahead has
    // no size limit: more mobile data and more work for the phone.
    set('cache-on-disk', 'no');
    // Already-played video kept for seeking back: enough for a −10 s double-tap at 1080p, not a second full
    // buffer. Further back is fetched again.
    set('demuxer-max-back-bytes', '${DeviceProfile.lowEnd ? 6 << 20 : 12 << 20}');
    // Sidecar subtitles are added explicitly in openItem; mpv's own search would add them twice.
    set('sub-auto', 'no');
    set('osd-level', '0');
  }

  Future<void> logDecoder() async {
    final mpv = _player?.platform;
    if (mpv is! NativePlayer) return;
    try {
      final codec = await mpv.getProperty('video-codec');
      final hw = await mpv.getProperty('hwdec-current');
      debugPrint('[Video] decoding ${codec.split(' ').first} ${player.state.width}x${player.state.height} with '
          '${hw.isEmpty || hw == 'no' ? 'software (CPU)' : 'hardware ($hw)'}');
    } catch (e) {
      debugPrint('[Video] decoder unknown: $e');
    }
  }

  Future<void> logHealth(String after) async {
    final mpv = _player?.platform;
    if (mpv is! NativePlayer) return;
    try {
      final shown = await mpv.getProperty('frame-drop-count');
      final decoded = await mpv.getProperty('decoder-frame-drop-count');
      debugPrint('[Video] after $after: frames dropped $shown (late to the screen), $decoded (decoder too slow); '
          'phone ${await DiagnosticsService.heatNow()}');
    } catch (e) {
      debugPrint('[Video] health unknown: $e');
    }
  }

  /// Opens [item] in the player (at [start] if given): a file, or a stream
  /// with its separate audio track. YouTube media goes through the stream
  /// proxy (fast, piece by piece; see StreamProxy).
  Future<void> openItem(VideoItem item, {bool play = true, Duration? start}) async {
    final p = player;
    String route(String url) => item.isStream
        ? StreamProxy.to.wrap(url, headers: item.httpHeaders, videoId: item.youtubeId, partial: item.partial)
        : url;
    final video = route(item.playable);
    final audioUri = item.audioUri;
    final path = item.path;
    if (path != null) {
      final file = File(path);
      final exists = file.existsSync();
      debugPrint('[Video] opening file ${path.split('/').last} '
          '(${exists ? '${(file.lengthSync() / 1048576).toStringAsFixed(1)} MB' : 'MISSING'})');
    }
    final mpv = p.platform;
    _badTimestamps = 0;
    final hwdec = _hwdecBefore;
    _hwdecBefore = null;
    if (mpv is NativePlayer) {
      if (hwdec != null) await mpv.setProperty('hwdec', hwdec).catchError((Object e) => debugPrint('[Video] hwdec: $e'));
      try {
        // mpv keeps sub-files for every later file, so it is reset per open.
        await mpv.command(['change-list', 'sub-files', 'clr', '']);
        for (final s in path == null ? const <String>[] : Subtitles.sidecarsOf(path)) {
          await mpv.command(['change-list', 'sub-files', 'append', s]);
        }
      } catch (e) {
        debugPrint('[Video] subtitle files: $e');
      }
    }
    await p.open(
      Media(
        audioUri == null ? video : edl(video, route(audioUri)),
        httpHeaders: item.httpHeaders.isEmpty ? null : item.httpHeaders,
        start: start != null && start > Duration.zero ? start : null,
      ),
      play: play,
    );
  }

  /// One mpv "file" made of a video stream and a separate audio stream
  /// (mpv's EDL format, with the same headers mpv's own YouTube support
  /// uses): one buffer for both, both opened while loading.
  /// `%N%` = the next N bytes are taken literally (URLs contain ';' etc.).
  @visibleForTesting
  static String edl(String video, String audio) {
    String part(String s) => '!new_stream;!no_clip;!no_chapters;%${utf8.encode(s).length}%$s';
    return 'edl://${part(video)};${part(audio)}';
  }

  /// Artwork bytes for the media controls.
  Future<Uint8List?> _art(VideoItem item) async {
    if (item.id != null) return VideoThumbCache.load(item.id!);
    final url = item.thumbnailUrl;
    if (url == null) return null;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(res);
      client.close();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------- system media controls

  /// The Android media session (notification, lock screen, headset
  /// buttons) is up.
  bool _mediaOn = false;
  String? _artFor;
  Duration _sentPosition = Duration.zero;
  DateTime _sentAt = DateTime.now();
  bool _syncing = false, _syncAgain = false;

  /// Shows / updates the system media controls while background play is on
  /// (removes them when it's turned off). Safe to call often.
  Future<void> syncMedia() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncMediaOnce();
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncMediaOnce() async {
    final item = current;
    if (!_active || item == null) return;
    final enabled = SettingsService.to.videoBackgroundPlay.value && !private;
    if (!enabled) {
      if (_mediaOn) await _stopMedia();
      return;
    }
    final state = player.state;
    if (!state.playing && !_mediaOn) return; // nothing to show yet

    final args = <String, Object?>{
      'title': item.title,
      'subtitle': item.folder ?? 'Toomu',
      'playing': state.playing,
      'position': state.position.inMilliseconds,
      'duration': (state.duration > Duration.zero ? state.duration : item.duration ?? Duration.zero)
          .inMilliseconds,
      'speed': state.rate,
      'hasNext': index.value < items.length - 1,
    };
    final newItem = _artFor != item.resumeKey;
    if (newItem) {
      args['art'] = await _art(item);
    }
    if (!_active) return;
    try {
      final ok = await _platform.invokeMethod<bool>(_mediaOn ? 'updateBackground' : 'startBackground', args);
      if (ok == true) {
        _mediaOn = true;
        _artFor = item.resumeKey;
        _sentPosition = state.position;
        _sentAt = DateTime.now();
      }
    } on PlatformException catch (e) {
      debugPrint('[Video] media controls: $e');
    }
  }

  /// Resyncs when the real position strays from what the controls show
  /// (a seek, a stall).
  void _checkDrift(Duration position) {
    if (!_mediaOn || !_active) return;
    final elapsed = DateTime.now().difference(_sentAt);
    final expected = player.state.playing
        ? _sentPosition + elapsed * player.state.rate
        : _sentPosition;
    if ((position - expected).abs() > const Duration(milliseconds: 1500)) syncMedia();
  }

  /// The user closed the media controls (they're already gone).
  void mediaStopped() {
    _mediaOn = false;
    _artFor = null;
  }

  Future<void> _stopMedia() async {
    final wasOn = _mediaOn;
    mediaStopped();
    if (wasOn) await _platform.invokeMethod<void>('stopBackground');
  }

  /// Mini bar tap: back to the full player, same session.
  void reopen() {
    if (!_active) return;
    Get.toNamed(Routes.videoPlayer, arguments: VideoPlaylist(items.toList(), index.value));
  }

  void _savePosition({bool finished = false}) {
    final item = current;
    // Private files leave no trace in the resume positions, which Android backs up.
    if (!_active || item == null || private) return;
    final total = player.state.duration;
    VideoResumeRepository.instance.save(item.resumeKey, finished ? total : player.state.position, total);
  }

  /// Unloads the video; the player itself stays for the next one.
  void _endSession() {
    if (!_active) return;
    _active = false;
    // _videoOff stays: mpv keeps video off for later files too, so the next video must turn it back on.
    _player?.stop();
    _outsideBuild(() => playing.value = false);
  }

  /// The player screen attaches while it is being built (its controller is
  /// created then). Changing state other widgets watch (the mini bar) in
  /// the middle of a build is an error, so such changes wait until the
  /// frame is done.
  void _outsideBuild(void Function() change) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => change());
    } else {
      change();
    }
  }
}
