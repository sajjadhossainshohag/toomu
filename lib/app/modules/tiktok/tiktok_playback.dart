import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../data/models/tiktok_item.dart';
import '../../data/models/video_item.dart';
import '../../services/audio_player_service.dart';
import '../../services/tiktok_service.dart';
import '../../services/video_session_service.dart';
import '../video_player/controllers/video_playback_controller.dart';
import 'controllers/tiktok_controller.dart';
import 'tiktok_head_server.dart';
import 'tiktok_prefetch.dart';

/// TikTok videos in the app's one video player (like Shorts), looped:
/// a video whose first seconds were loaded ahead plays through
/// [TiktokHeadServer] (instant start, then on from TikTok), others straight
/// from TikTok's servers.
class SessionTiktokPlayback implements TiktokPlayback {
  SessionTiktokPlayback({this.prefetch, TiktokHeadServer? heads})
    : heads = heads ?? TiktokHeadServer.shared;

  /// The next videos' first seconds.
  final TiktokPrefetch? prefetch;
  final TiktokHeadServer heads;

  VideoSessionService get _session => VideoSessionService.to;

  /// This tab's "screen" for the session: a newer screen (a YouTube video
  /// opened meanwhile) replaces it, and then [stop] leaves that one alone.
  late final void Function(MethodCall call) _screen = _ignore;

  void _ignore(MethodCall call) {}

  static String keyOf(TiktokItem item) => 'tt:${item.id}';

  @override
  bool holds(TiktokItem item) =>
      _session.hasPlayer && _session.current?.remoteKey == keyOf(item);

  @override
  Future<void> play(TiktokItem item) async {
    if (item.playUrl.isEmpty) throw StateError("This video can't play here.");
    // Music and video shouldn't play at once.
    await AudioPlayerService.to.pause();
    final head = prefetch?.headFor(item.id);
    final local = head == null ? null : await heads.urlFor(item, head);
    final video = videoFor(
      item,
      local: local,
      headers: local == null ? await TiktokService.playHeaders() : const {},
    );
    final session = _session;
    _mine = video.remoteKey;
    session.attach(VideoPlaylist([video], 0), _screen);
    await session.player.setPlaylistMode(PlaylistMode.single);
    await started(
      session.player.stream.buffering,
      () => session.openItem(video),
      position: session.player.stream.position,
    );
  }

  /// Opens the video with [open] and waits until it really plays: mpv
  /// reports loading when the new file starts and stops reporting it once
  /// playback runs. (Waiting for a position above zero didn't work: mpv
  /// keeps the previous video's position until the new one's first frame,
  /// so the seek bar showed and its time ran while the video still loaded.)
  /// The next videos download after this; never waits past [timeout].
  @visibleForTesting
  static Future<void> started(
    Stream<bool> buffering,
    Future<void> Function() open, {
    Stream<Duration> position = const Stream<Duration>.empty(),
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final ready = Completer<void>();
    var loading = false;
    final sub = buffering.listen((b) {
      if (b) {
        loading = true;
      } else if (loading && !ready.isCompleted) {
        ready.complete();
      }
    });
    // Or its first frame: after mpv says the new file started, positions
    // are the new video's. Needed because from a playing video to a fast
    // (preloaded) one mpv's idle flag flips on and off before media_kit
    // sees it, so "loading ended" never comes (the spinner then stayed up
    // for the whole timeout over a video that was ready).
    final frames = position.listen((p) {
      if (loading && p > Duration.zero && !ready.isCompleted) ready.complete();
    });
    try {
      await open();
      await ready.future.timeout(timeout);
    } on TimeoutException catch (_) {
      // Plays anyway; it just didn't say so.
    } finally {
      await sub.cancel();
      await frames.cancel();
    }
  }

  /// What the player opens for [item]: the head server's [local] address
  /// when its first seconds are loaded (the server adds TikTok's headers),
  /// else TikTok's file with [headers].
  static VideoItem videoFor(
    TiktokItem item, {
    String? local,
    Map<String, String> headers = const {},
  }) => VideoItem(
    uri: local ?? item.playUrl,
    title: item.caption.isEmpty ? '@${item.authorId}' : item.caption,
    remoteKey: keyOf(item),
    httpHeaders: local == null ? headers : const {},
    thumbnailUrl: item.coverUrl,
    width: item.width,
    height: item.height,
    duration: item.duration == Duration.zero ? null : item.duration,
  );

  /// The video this feed opened last (two feeds share the one player).
  String? _mine;

  bool get _ours =>
      _session.hasPlayer &&
      _mine != null &&
      _session.current?.remoteKey == _mine;

  @override
  Future<void> pause() async {
    if (_ours) await _session.player.pause();
  }

  @override
  Future<void> resume() async {
    if (_ours) await _session.player.play();
  }

  @override
  Future<void> stop() async {
    if (_ours) await _session.player.setPlaylistMode(PlaylistMode.none);
    await _session.detach(keepPlaying: false, screen: _screen);
  }
}
