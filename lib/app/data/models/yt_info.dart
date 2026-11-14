/// The parts of yt-dlp's `--dump-single-json` output the app uses.
class YtInfo {
  const YtInfo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.formats,
    this.thumbnail,
    this.duration,
  });

  final String id;
  final String title;
  final String uploader;
  final String? thumbnail;
  final Duration? duration;
  final List<YtFormat> formats;

  factory YtInfo.fromJson(Map<String, dynamic> j) => YtInfo(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Untitled',
        uploader: (j['uploader'] ?? j['channel'] ?? '') as String,
        thumbnail: j['thumbnail'] as String?,
        duration: (j['duration'] as num?) == null
            ? null
            : Duration(milliseconds: ((j['duration'] as num) * 1000).round()),
        formats: ((j['formats'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(YtFormat.fromJson)
            .toList(),
      );

  List<YtFormat> get videoFormats => formats.where((f) => f.hasVideo && (f.height ?? 0) > 0).toList();

  /// Audio-only formats, original language first, then best bitrate.
  /// (yt-dlp gives the original track the highest language_preference.)
  List<YtFormat> get audioFormats => formats.where((f) => f.hasAudio && !f.hasVideo).toList()
    ..sort((a, b) {
      final lang = (b.languagePreference ?? 0).compareTo(a.languagePreference ?? 0);
      return lang != 0 ? lang : (b.abr ?? 0).compareTo(a.abr ?? 0);
    });

  /// Highest-quality original-language audio, preferring AAC (m4a) because
  /// every Android player handles it.
  YtFormat? get bestAudio {
    final list = audioFormats;
    if (list.isEmpty) return null;
    final topLang = list.first.languagePreference;
    final original = list.where((f) => f.languagePreference == topLang).toList();
    return original.firstWhere((f) => f.ext == 'm4a', orElse: () => original.first);
  }
}

class YtFormat {
  const YtFormat({
    required this.formatId,
    required this.ext,
    this.vcodec,
    this.acodec,
    this.width,
    this.height,
    this.fps,
    this.filesize,
    this.abr,
    this.url,
    this.httpHeaders = const {},
    this.languagePreference,
    this.protocol,
  });

  final String formatId;
  final String ext;
  final String? vcodec;
  final String? acodec;
  final int? width;
  final int? height;
  final double? fps;
  final int? filesize;
  final double? abr;
  final String? url;
  final Map<String, String> httpHeaders;
  final int? languagePreference;

  /// "https" for plain files; "m3u8_native", "http_dash_segments"… otherwise.
  final String? protocol;

  /// A single URL a player can open directly (not a manifest/segments).
  bool get isDirect => url != null && (protocol == null || protocol == 'https' || protocol == 'http');

  bool get hasVideo => vcodec != null && vcodec != 'none';
  bool get hasAudio => acodec != null && acodec != 'none';

  factory YtFormat.fromJson(Map<String, dynamic> j) => YtFormat(
        formatId: '${j['format_id']}',
        ext: (j['ext'] as String?) ?? '',
        vcodec: j['vcodec'] as String?,
        acodec: j['acodec'] as String?,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        fps: (j['fps'] as num?)?.toDouble(),
        filesize: ((j['filesize'] ?? j['filesize_approx']) as num?)?.toInt(),
        abr: (j['abr'] as num?)?.toDouble(),
        url: j['url'] as String?,
        httpHeaders: ((j['http_headers'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        languagePreference: (j['language_preference'] as num?)?.toInt(),
        protocol: j['protocol'] as String?,
      );
}
