import 'media_format.dart';
import 'video_item.dart';
import 'yt_info.dart';

/// Picks what the video player streams for a YouTube video (no ads: these
/// are YouTube's media files themselves, played in our own player).
abstract class YoutubeStream {
  /// Quality picked when the user hasn't chosen one (shorter side, so
  /// vertical Shorts count by their width).
  static const defaultQuality = 1080;

  /// Codecs phones decode in hardware almost everywhere, best first. AV1
  /// often isn't, and decoding it in software heats the phone.
  static int _codecRank(String? vcodec) {
    final c = vcodec ?? '';
    if (c.startsWith('avc1')) return 0;
    if (c.startsWith('vp9') || c.startsWith('vp09')) return 1;
    return 2;
  }

  static String _codecName(String? vcodec) {
    final c = vcodec ?? '';
    if (c.startsWith('avc1')) return 'H.264';
    if (c.startsWith('vp9') || c.startsWith('vp09')) return 'VP9';
    if (c.startsWith('av01')) return 'AV1';
    return c.split('.').first.toUpperCase();
  }

  /// Every separate video stream, one per quality (best codec / frame
  /// rate within it), best quality first, each paired with the
  /// original-language audio.
  static List<StreamQuality> qualities(YtInfo info) {
    final audio = info.bestAudio;
    if (audio == null || !audio.isDirect) return const [];
    final byClass = <int, List<YtFormat>>{};
    for (final f in info.formats) {
      final h = f.height ?? 0;
      if (!f.hasVideo || f.hasAudio || !f.isDirect || h < 100) continue;
      byClass.putIfAbsent(MediaFormat.qualityClass(f.width, h), () => []).add(f);
    }
    final classes = byClass.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final q in classes)
        () {
          final group = byClass[q]!
            ..sort((a, b) {
              final c = _codecRank(a.vcodec).compareTo(_codecRank(b.vcodec));
              if (c != 0) return c;
              return (b.fps ?? 0).compareTo(a.fps ?? 0);
            });
          final f = group.first;
          final fps = f.fps ?? 0;
          final name = q >= 2160 ? '4K' : '${q}p';
          return StreamQuality(
            label: fps > 30 ? '$name${fps.round()}' : name,
            quality: q,
            videoUri: f.url!,
            audioUri: audio.url,
            httpHeaders: f.httpHeaders,
            width: f.width ?? 0,
            height: f.height ?? 0,
            codec: _codecName(f.vcodec),
            fps: f.fps,
          );
        }(),
    ];
  }

  /// The stream to start with: the highest quality ≤ [preferred] (the
  /// user's last choice, else [defaultQuality]); the combined 360p stream
  /// is its fallback, or the stream itself when nothing separate exists.
  /// Null when nothing is playable.
  static VideoItem? pick(
    YtInfo info, {
    required String videoId,
    String? title,
    int? preferred,
    bool provisional = false,
    bool partial = false,
  }) {
    final key = 'yt:$videoId';
    final name = title ?? info.title;
    final thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

    final list = qualities(info);
    final combined = info.formats.where((f) => f.hasVideo && f.hasAudio && f.isDirect).toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    VideoItem? simple;
    if (combined.isNotEmpty) {
      final f = combined.first;
      simple = VideoItem(
        uri: f.url!,
        title: name,
        duration: info.duration,
        width: f.width ?? 0,
        height: f.height ?? 0,
        httpHeaders: f.httpHeaders,
        remoteKey: key,
        thumbnailUrl: thumb,
        qualities: list, // so the menu still works after falling back
        provisional: provisional,
        partial: partial,
      );
    }

    if (list.isEmpty) return simple;
    final cap = preferred ?? defaultQuality;
    final start = list.firstWhere((q) => q.quality <= cap, orElse: () => list.last);
    return VideoItem(
      uri: '',
      title: name,
      duration: info.duration,
      remoteKey: key,
      thumbnailUrl: thumb,
      fallback: simple,
      qualities: list,
      provisional: provisional,
      partial: partial,
    ).withQuality(start);
  }
}
