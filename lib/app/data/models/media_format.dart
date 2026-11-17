import 'dart:io';
import 'dart:math' as math;

import 'download_task.dart';
import 'yt_info.dart';

/// One option in the download sheet. For YouTube it is a yt-dlp format
/// [selector] with fallbacks rather than a fixed stream, so yt-dlp picks
/// whatever is actually downloadable when the download starts.
class MediaFormat {
  const MediaFormat({
    required this.kind,
    required this.label,
    required this.extension,
    required this.sizeBytes,
    required this.detail,
    required this.selector,
    this.height = 0,
    this.convert,
  });

  final DownloadKind kind;
  final String label;
  final String extension;

  /// Estimate; the real size is known once yt-dlp starts.
  final int sizeBytes;
  final String detail;

  /// yt-dlp `-f` value.
  final String selector;
  final int height;

  /// Post-processing, e.g. `mp3:192`.
  final String? convert;

  bool get isHd => height >= 720;

  /// YouTube's quality ladder ("1080p" etc.).
  static const _ladder = <int>[144, 240, 360, 480, 720, 1080, 1440, 2160, 4320];

  /// Quality class of a [width]×[height] frame the way YouTube names it:
  /// wide 3840×1920 is 2160p, vertical 1080×1920 is 1080p.
  static int qualityClass(int? width, int height) {
    final w = width ?? 0;
    final p = w <= 0
        ? height
        : w >= height
            ? math.max(height, (w * 9 / 16).round()) // landscape / wide
            : math.max(w, (height * 9 / 16).round()); // portrait
    return _ladder.reduce((a, b) => (a - p).abs() <= (b - p).abs() ? a : b);
  }

  /// Video options, one per quality class, best first. H.264 is preferred
  /// (plays everywhere); 1440p/4K fall back to VP9/AV1. Always saved as MP4.
  static List<MediaFormat> videoOptions(YtInfo info) {
    final audio = info.bestAudio;
    final byClass = <int, List<YtFormat>>{};
    for (final f in info.videoFormats) {
      if (f.height! < 100) continue;
      // iOS joins with AVFoundation: MP4-family (H.264) only.
      if (Platform.isIOS && !(f.vcodec?.startsWith('avc1') ?? false)) continue;
      byClass.putIfAbsent(qualityClass(f.width, f.height!), () => []).add(f);
    }
    final classes = byClass.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final q in classes)
        () {
          final group = byClass[q]!;
          final maxH = group.map((f) => f.height!).reduce(math.max);
          return MediaFormat(
            kind: DownloadKind.video,
            label: '${q}p',
            extension: 'mp4',
            height: q,
            sizeBytes: _videoSize(group) + (audio?.filesize ?? 0),
            detail: 'MP4 • ${_codecOf(group)}',
            selector: _videoSelector(maxH),
          );
        }(),
    ];
  }

  static String _videoSelector(int maxH) =>
      'bv*[height<=$maxH][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=$maxH]+ba/b[height<=$maxH]/bv*+ba/b';

  static List<MediaFormat> listOptions() => [
        for (final h in const [1080, 720, 480, 360])
          MediaFormat(
            kind: DownloadKind.video,
            label: '${h}p',
            extension: 'mp4',
            height: h,
            sizeBytes: 0,
            detail: 'MP4, or the best below it',
            selector: _videoSelector(h),
          ),
        // iOS has no MP3 encoder.
        if (!Platform.isIOS)
          const MediaFormat(
            kind: DownloadKind.audio,
            label: 'MP3 192 kbps',
            extension: 'mp3',
            sizeBytes: 0,
            detail: 'MP3 • converted',
            selector: 'ba/b',
            convert: 'mp3:192',
          ),
        const MediaFormat(
          kind: DownloadKind.audio,
          label: 'M4A',
          extension: 'm4a',
          sizeBytes: 0,
          detail: 'M4A • original quality',
          selector: 'ba[ext=m4a]/ba/b',
        ),
      ];

  /// MP3 (converted) + original-quality M4A.
  static List<MediaFormat> audioOptions(YtInfo info) {
    final audio = info.bestAudio;
    final seconds = info.duration?.inSeconds ?? 0;
    int mp3Size(int kbps) => seconds > 0 ? seconds * kbps * 1000 ~/ 8 : (audio?.filesize ?? 0);
    return [
      // iOS has no MP3 encoder.
      if (!Platform.isIOS)
        for (final kbps in const [320, 192, 128])
        MediaFormat(
          kind: DownloadKind.audio,
          label: 'MP3 $kbps kbps',
          extension: 'mp3',
          sizeBytes: mp3Size(kbps),
          detail: 'MP3 • converted',
          selector: 'ba/b',
          convert: 'mp3:$kbps',
        ),
      if (audio != null && (!Platform.isIOS || audio.ext == 'm4a'))
        MediaFormat(
          kind: DownloadKind.audio,
          label: 'M4A ${audio.abr?.round() ?? ''} kbps'.trim(),
          extension: 'm4a',
          sizeBytes: audio.filesize ?? 0,
          detail: 'M4A • original quality',
          selector: 'ba[ext=m4a]/ba/b',
        ),
    ];
  }

  static int _videoSize(List<YtFormat> group) {
    // Video-only streams (the audio size is added separately); combined
    // video+audio files would count the audio twice.
    final videoOnly = group.where((f) => !f.hasAudio).toList();
    if (videoOnly.isNotEmpty) group = videoOnly;
    final avc = group.where((f) => f.vcodec?.startsWith('avc1') ?? false).toList();
    final sizes = (avc.isNotEmpty ? avc : group).map((f) => f.filesize ?? 0);
    return sizes.isEmpty ? 0 : sizes.reduce(math.max);
  }

  static String _codecOf(List<YtFormat> group) {
    final codecs = group.map((f) => f.vcodec ?? '').toList();
    if (codecs.any((c) => c.startsWith('avc1'))) return 'H.264';
    if (codecs.any((c) => c.startsWith('vp9') || c.startsWith('vp09'))) return 'VP9';
    if (codecs.any((c) => c.startsWith('av01'))) return 'AV1';
    return 'Video';
  }
}
