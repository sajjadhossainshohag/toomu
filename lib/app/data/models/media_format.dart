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
    String? name,
    this.mayNotPlay = false,
  }) : _name = name;

  final DownloadKind kind;

  /// Technical: "1080p", "MP3 192 kbps". Goes into file names and the Downloads list.
  final String label;

  final String? _name;

  String get name => _name ?? label;

  /// Only VP9/AV1 at this quality: older phones can't decode it.
  final bool mayNotPlay;

  final String extension;

  /// Estimate; the real size is known once yt-dlp starts.
  final int sizeBytes;

  /// A plain hint ("Smaller file") or the older-phones warning.
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
      byClass.putIfAbsent(qualityClass(f.width, f.height!), () => []).add(f);
    }
    final classes = byClass.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final q in classes)
        () {
          final group = byClass[q]!;
          final maxH = group.map((f) => f.height!).reduce(math.max);
          final old = !group.any((f) => f.vcodec?.startsWith('avc1') ?? false);
          return MediaFormat(
            kind: DownloadKind.video,
            label: '${q}p',
            name: qualityName(q),
            extension: 'mp4',
            height: q,
            sizeBytes: _videoSize(group) + (audio?.filesize ?? 0),
            detail: old ? 'May not play on older phones' : _hint(q),
            mayNotPlay: old,
            selector: _videoSelector(maxH),
          );
        }(),
    ];
  }

  static String qualityName(int q) => switch (q) {
        >= 4320 => '8K',
        >= 2160 => '4K Ultra HD',
        >= 1440 => '2K',
        >= 1080 => 'Full HD',
        >= 720 => 'HD',
        >= 480 => 'SD',
        >= 360 => 'Low',
        _ => 'Data saver',
      };

  static String _hint(int q) => switch (q) {
        >= 1440 => 'Very large file',
        >= 1080 => 'Sharp picture',
        >= 720 => 'Smaller file',
        >= 480 => 'Saves data',
        >= 360 => 'Saves more data',
        _ => 'Smallest, blurry',
      };

  static ({List<MediaFormat> first, List<MediaFormat> more}) firstFour(List<MediaFormat> video) {
    // 1080p to 360p first; missing ones are filled with the next sharper (2K, 4K), then 240p and 144p.
    int group(int q) => q > 1080 ? 1 : (q < 360 ? 2 : 0);
    int bestFirst(MediaFormat a, MediaFormat b) => b.height.compareTo(a.height);
    final byFit = [...video]
      ..sort((a, b) {
        final g = group(a.height).compareTo(group(b.height));
        if (g != 0) return g;
        return group(a.height) == 1 ? a.height.compareTo(b.height) : bestFirst(a, b);
      });
    return (
      first: byFit.take(4).toList()..sort(bestFirst),
      more: byFit.skip(4).toList()..sort(bestFirst),
    );
  }

  static MediaFormat? recommended(List<MediaFormat> options, int target) {
    if (options.isEmpty) return null;
    for (final f in options) {
      if (f.height <= target) return f;
    }
    return options.last;
  }

  static String _videoSelector(int maxH) =>
      'bv*[height<=$maxH][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=$maxH]+ba/b[height<=$maxH]/bv*+ba/b';

  static List<MediaFormat> listOptions() => [
    for (final h in const [1080, 720, 480, 360])
      MediaFormat(
        kind: DownloadKind.video,
        label: '${h}p',
        name: '${qualityName(h)} ${h}p',
        extension: 'mp4',
        height: h,
        sizeBytes: 0,
        detail: 'Or the best below it',
        selector: _videoSelector(h),
      ),
    const MediaFormat(
      kind: DownloadKind.audio,
      label: 'MP3 192 kbps',
      name: 'MP3',
      extension: 'mp3',
      sizeBytes: 0,
      detail: 'Plays everywhere',
      selector: 'ba/b',
      convert: 'mp3:192',
    ),
    const MediaFormat(
      kind: DownloadKind.audio,
      label: 'M4A',
      name: 'Original audio',
      extension: 'm4a',
      sizeBytes: 0,
      detail: 'Best sound, smallest file (M4A)',
      selector: 'ba[ext=m4a]/ba/b',
    ),
  ];

  // YouTube's audio is ~130–160 kbps, so 192 already keeps all of it: a 320 kbps MP3 is only bigger.
  static List<MediaFormat> audioOptions(YtInfo info) {
    final audio = info.bestAudio;
    final seconds = info.duration?.inSeconds ?? 0;
    return [
      MediaFormat(
        kind: DownloadKind.audio,
        label: 'MP3 192 kbps',
        name: 'MP3',
        extension: 'mp3',
        sizeBytes: seconds > 0 ? seconds * 192 * 1000 ~/ 8 : (audio?.filesize ?? 0),
        detail: 'Plays everywhere',
        selector: 'ba/b',
        convert: 'mp3:192',
      ),
      if (audio != null)
        MediaFormat(
          kind: DownloadKind.audio,
          label: 'M4A ${audio.abr?.round() ?? ''} kbps'.trim(),
          name: 'Original audio',
          extension: 'm4a',
          sizeBytes: audio.filesize ?? 0,
          detail: 'Best sound, smallest file (M4A)',
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
}
