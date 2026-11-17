import '../../core/utils/media_manifest.dart';
import 'download_task.dart';

enum CapturedType { file, hls, dash }

class CapturedMedia {
  CapturedMedia({
    required this.url,
    required this.type,
    required this.kind,
    required this.pageUrl,
    required this.headers,
    this.title = '',
    this.poster = '',
    this.ext = 'mp4',
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.duration,
    this.variants = const [],
    this.protected = false,
  });

  final String url;
  final CapturedType type;
  final DownloadKind kind;
  final String pageUrl;

  // User-Agent and Referer of the page; cookies are added per request.
  final Map<String, String> headers;
  String title;
  String poster;
  final String ext;

  // Exact for files, estimated (bitrate x duration) for streams; 0 = unknown.
  int size;
  int width;
  int height;
  Duration? duration;
  final List<StreamVariant> variants;
  final bool protected;
  final Map<String, String> subtitles = {};

  bool get isStream => type != CapturedType.file;

  String get format => switch (type) {
    CapturedType.hls => 'HLS',
    CapturedType.dash => 'DASH',
    CapturedType.file => ext.toUpperCase(),
  };

  int get bestHeight => variants.isNotEmpty ? variants.first.height : height;

  String get host => Uri.tryParse(url)?.host ?? '';
}
