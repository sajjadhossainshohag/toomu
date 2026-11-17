import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../core/utils/host_os.dart';
import '../core/values/app_constants.dart';
import '../data/models/track.dart';
import 'storage_service.dart';
import 'video_session_service.dart';
import '../widgets/app_snackbar.dart';

enum SleepMode { off, timer, endOfTrack }

/// Single app-wide player (MX Player-style audio features):
/// background playback + notification, queue, shuffle/repeat, speed & pitch,
/// sleep timer, A-B repeat, equalizer and favorites.
class AudioPlayerService extends GetxService {
  static AudioPlayerService get to => Get.find();

  final _storage = StorageService.to;

  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioPipeline(
      androidAudioEffects: Platform.isAndroid
          ? <AndroidAudioEffect>[equalizer, loudness]
          : const <AndroidAudioEffect>[],
    ),
  );

  // ---------------------------------------------------------------- state
  final queue = <Track>[].obs;
  final currentIndex = RxnInt();
  final playing = false.obs;
  final processing = ProcessingState.idle.obs;
  final position = Duration.zero.obs;
  final buffered = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final shuffle = false.obs;
  final loopMode = LoopMode.off.obs;
  final speed = 1.0.obs;
  final pitch = 1.0.obs;

  final sleepMode = SleepMode.off.obs;
  final sleepRemaining = Duration.zero.obs;
  Timer? _sleepTimer;

  final abStart = Rxn<Duration>();
  final abEnd = Rxn<Duration>();

  final favorites = <String>{}.obs;
  final equalizerEnabled = false.obs;

  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<Duration>? _positionSub;
  AppLifecycleListener? _lifecycle;
  final _queueStore = StorageService.queue;

  Track? get current {
    final i = currentIndex.value;
    return (i == null || i < 0 || i >= queue.length) ? null : queue[i];
  }

  bool get hasMedia => current != null;

  Future<AudioPlayerService> init() async {
    if (HostOs.usesAudioSession) {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    }

    favorites.addAll(
        (_storage.read<List>(AppConstants.kFavorites) ?? const []).cast<String>());

    _subs.addAll([
      // Runtime errors (e.g. HTTP 403 halfway through a stream) arrive here.
      player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) {
        final id = current?.id;
        if (id != null) _trackErrors.add(id);
      }),
      player.playingStream.listen((v) {
        if (playing.value && !v) _saveQueue();
        playing.value = v;
      }),
      player.processingStateStream.listen((v) => processing.value = v),
      player.bufferedPositionStream.listen((v) => buffered.value = v),
      player.durationStream.listen((v) => duration.value = v ?? Duration.zero),
      player.shuffleModeEnabledStream.listen((v) => shuffle.value = v),
      player.loopModeStream.listen((v) => loopMode.value = v),
      player.speedStream.listen((v) => speed.value = v),
      player.pitchStream.listen((v) => pitch.value = v),
      player.currentIndexStream.listen(_onIndexChanged),
      player.positionDiscontinuityStream.listen(_onDiscontinuity),
    ]);

    _watchPosition(visible: true);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _watchPosition(visible: false);
        _saveQueue();
      },
      onShow: () => _watchPosition(visible: true),
    );

    if (Platform.isAndroid) await _restoreEqualizer();
    // After the first frame: loading a file must not slow down the start.
    SchedulerBinding.instance.addPostFrameCallback((_) => unawaited(_restoreQueue()));
    return this;
  }

  void _watchPosition({required bool visible}) {
    _positionSub?.cancel();
    // Hidden, nothing reads the position often (A-B repeat still does).
    final stream = visible || abEnd.value != null
        ? player.createPositionStream(
            steps: 800,
            minPeriod: const Duration(milliseconds: 16),
            maxPeriod: const Duration(milliseconds: 200),
          )
        : player.createPositionStream(
            minPeriod: const Duration(seconds: 1),
            maxPeriod: const Duration(seconds: 1),
          );
    _positionSub = stream.listen(_onPosition);
  }

  void _saveQueue() {
    final i = currentIndex.value;
    if (i == null || queue.isEmpty || !queue.every((t) => t.restorable)) {
      _queueStore.remove(AppConstants.kAudioQueue);
      return;
    }
    _queueStore.write(AppConstants.kAudioQueue, {
      'tracks': [for (final t in queue) t.toJson()],
      'index': i,
      'positionMs': player.position.inMilliseconds,
    });
  }

  Future<void> _restoreQueue() async {
    final saved = _queueStore.read<Map>(AppConstants.kAudioQueue);
    if (saved == null || hasMedia) return;
    try {
      final tracks = [
        for (final m in saved['tracks'] as List) Track.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      final present = await Future.wait(tracks.map((t) => File(t.path!).exists()));
      final restored = restoredQueue(
        tracks,
        present,
        (saved['index'] as num).toInt(),
        Duration(milliseconds: (saved['positionMs'] as num? ?? 0).toInt()),
      );
      if (restored == null || hasMedia) return;
      queue.assignAll(restored.tracks);
      await player.setAudioSources(
        restored.tracks.map((t) => t.toAudioSource()).toList(),
        initialIndex: restored.index,
        initialPosition: restored.position,
      );
    } catch (e) {
      debugPrint('[Audio] last queue not restored: $e');
      _queueStore.remove(AppConstants.kAudioQueue);
      if (!player.playing) queue.clear();
    }
  }

  static ({List<Track> tracks, int index, Duration position})? restoredQueue(
    List<Track> saved,
    List<bool> present,
    int index,
    Duration position,
  ) {
    final kept = [for (var i = 0; i < saved.length; i++) if (present[i]) saved[i]];
    if (kept.isEmpty) return null;
    final current = index >= 0 && index < saved.length && present[index] ? saved[index] : null;
    return current == null
        ? (tracks: kept, index: 0, position: Duration.zero)
        : (tracks: kept, index: kept.indexOf(current), position: position);
  }

  // ------------------------------------------------------------- playback

  /// Plays [tracks] from [index] (optionally from [position]). Returns
  /// false if loading failed. [quiet] skips the error snackbar (callers
  /// with their own fallback).
  Future<bool> playTracks(
    List<Track> tracks, {
    int index = 0,
    Duration? position,
    bool quiet = false,
  }) async {
    if (tracks.isEmpty) return false;
    // Music takes over from a video playing in the background.
    if (Get.isRegistered<VideoSessionService>() && VideoSessionService.to.inBackground.value) {
      await VideoSessionService.to.stop();
    }
    clearAbRepeat();
    queue.assignAll(tracks);
    try {
      await player.setAudioSources(
        tracks.map((t) => t.toAudioSource()).toList(),
        initialIndex: index,
        initialPosition: position,
      );
      player.play();
      return true;
    } on PlayerException catch (e) {
      if (!quiet) showSnack('Playback error', e.message ?? 'Could not play this file');
      return false;
    } on PlayerInterruptedException catch (_) {
      // A newer load request replaced this one.
      return false;
    }
  }

  /// Ids of tracks whose playback failed mid-stream (e.g. the server cut
  /// the stream off), so callers can switch to another source.
  final _trackErrors = StreamController<String>.broadcast();
  Stream<String> get trackErrors => _trackErrors.stream;

  Future<void> shuffleAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final shuffled = [...tracks]..shuffle();
    await playTracks(shuffled);
  }

  void togglePlay() => player.playing ? player.pause() : player.play();

  /// Mini bar ✕: stops playback, clears the queue and removes the
  /// notification, so the mini bar disappears.
  Future<void> close() async {
    _queueStore.remove(AppConstants.kAudioQueue);
    cancelSleepTimer();
    clearAbRepeat();
    queue.clear();
    currentIndex.value = null;
    await player.stop();
    await player.clearAudioSources();
    // stop() can re-emit the old index; the queue is empty so it's ignored.
    currentIndex.value = null;
  }
  Future<void> next() => player.seekToNext();

  /// MX behaviour: "previous" restarts the track if > 3s in.
  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration d) => player.seek(d);
  Future<void> seekRelative(int seconds) {
    final target = player.position + Duration(seconds: seconds);
    final max = duration.value;
    return player.seek(target < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && target > max ? max : target));
  }

  Future<void> skipTo(int index) => player.seek(Duration.zero, index: index);

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
  }

  /// off → all → one → off
  Future<void> cycleLoopMode() => player.setLoopMode(switch (player.loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      });

  Future<void> setSpeed(double v) => player.setSpeed(v);
  Future<void> setPitch(double v) => player.setPitch(v);

  // ---------------------------------------------------------------- queue

  Future<void> playNext(Track t) async {
    if (!hasMedia) {
      await playTracks([t]);
      return;
    }
    final at = (currentIndex.value ?? -1) + 1;
    queue.insert(at, t);
    await player.insertAudioSource(at, t.toAudioSource());
  }

  Future<void> addToQueue(Track t) async {
    if (!hasMedia) {
      await playTracks([t]);
      return;
    }
    queue.add(t);
    await player.addAudioSource(t.toAudioSource());
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= queue.length) return;
    queue.removeAt(index);
    await player.removeAudioSourceAt(index);
  }

  /// Drops a deleted track from the queue (stops if it was the only one).
  Future<void> removeTrack(String id) async {
    final i = queue.indexWhere((t) => t.id == id);
    if (i < 0) return;
    if (queue.length == 1) {
      await player.stop();
      queue.clear();
      currentIndex.value = null;
      return;
    }
    await removeAt(i);
  }

  Future<void> move(int from, int to) async {
    if (from == to) return;
    final t = queue.removeAt(from);
    queue.insert(to, t);
    await player.moveAudioSource(from, to);
  }

  // ---------------------------------------------------------- sleep timer

  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    sleepMode.value = SleepMode.timer;
    sleepRemaining.value = d;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = sleepRemaining.value - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        player.pause();
        cancelSleepTimer();
      } else {
        sleepRemaining.value = left;
      }
    });
  }

  void sleepAtEndOfTrack() {
    _sleepTimer?.cancel();
    sleepMode.value = SleepMode.endOfTrack;
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepMode.value = SleepMode.off;
    sleepRemaining.value = Duration.zero;
  }

  // ------------------------------------------------------------ A-B repeat

  /// Tap 1: set A, tap 2: set B (loop starts), tap 3: clear.
  void cycleAbRepeat() {
    if (abStart.value == null) {
      abStart.value = player.position;
    } else if (abEnd.value == null) {
      final b = player.position;
      if (b > abStart.value!) {
        abEnd.value = b;
        player.seek(abStart.value);
      } else {
        clearAbRepeat();
      }
    } else {
      clearAbRepeat();
    }
  }

  void clearAbRepeat() {
    abStart.value = null;
    abEnd.value = null;
  }

  // ------------------------------------------------------------- favorites

  bool isFavorite(Track t) => favorites.contains(t.id);

  void toggleFavorite(Track t) {
    favorites.contains(t.id) ? favorites.remove(t.id) : favorites.add(t.id);
    _storage.write(AppConstants.kFavorites, favorites.toList());
  }

  // ------------------------------------------------------------- equalizer

  Future<AndroidEqualizerParameters?> equalizerParameters() async =>
      Platform.isAndroid ? equalizer.parameters : null;

  Future<void> setEqualizerEnabled(bool v) async {
    equalizerEnabled.value = v;
    await equalizer.setEnabled(v);
    _storage.write(AppConstants.kEqualizerEnabled, v);
  }

  Future<void> setBandGain(AndroidEqualizerBand band, double gain) async {
    await band.setGain(gain);
    final params = await equalizer.parameters;
    _storage.write(
        AppConstants.kEqualizerGains, params.bands.map((b) => b.gain).toList());
  }

  Future<void> resetEqualizer() async {
    final params = await equalizer.parameters;
    for (final b in params.bands) {
      await b.setGain(0);
    }
    _storage.write(AppConstants.kEqualizerGains, params.bands.map((_) => 0.0).toList());
  }

  Future<void> _restoreEqualizer() async {
    final enabled = _storage.read<bool>(AppConstants.kEqualizerEnabled) ?? false;
    equalizerEnabled.value = enabled;
    await equalizer.setEnabled(enabled);
    final gains = _storage.read<List>(AppConstants.kEqualizerGains);
    if (gains == null) return;
    // Parameters resolve once a source is loaded; apply lazily.
    unawaited(equalizer.parameters.then((p) async {
      for (var i = 0; i < p.bands.length && i < gains.length; i++) {
        await p.bands[i].setGain((gains[i] as num).toDouble());
      }
    }));
  }

  // -------------------------------------------------------------- internal

  void _onPosition(Duration p) {
    position.value = p;
    final a = abStart.value, b = abEnd.value;
    if (a != null && b != null && p >= b) player.seek(a);
  }

  void _onIndexChanged(int? i) {
    final previous = currentIndex.value;
    currentIndex.value = i;
    if (previous != null && i != previous) clearAbRepeat();
  }

  // Only a track that played to its end counts (also when repeat-one starts
  // it again); Next, reordering or removing songs change the index too.
  void _onDiscontinuity(PositionDiscontinuity d) {
    if (d.reason == PositionDiscontinuityReason.autoAdvance && sleepMode.value == SleepMode.endOfTrack) {
      player.pause();
      cancelSleepTimer();
    }
  }

  @override
  void onClose() {
    for (final s in _subs) {
      s.cancel();
    }
    _positionSub?.cancel();
    _lifecycle?.dispose();
    _sleepTimer?.cancel();
    player.dispose();
    super.onClose();
  }
}
