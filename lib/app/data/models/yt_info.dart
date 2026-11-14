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

  /// This video as yt-dlp's info JSON (for `--load-info-json`), so yt-dlp
  /// can download from these links without looking the video up itself —
  /// a Python run plus YouTube requests saved. Mirrors the fields of
  /// yt-dlp's own YouTube results that format selection, sorting, merging
  /// and tagging use (yt-dlp 2026.10, `_video.py` `process_format_stream`).
  Map<String, Object?> toYtDlpInfo({String? title, String? uploader, String? thumbnail}) {
    final page = 'https://www.youtube.com/watch?v=$id';
    final name = title ?? this.title;
    final by = uploader ?? this.uploader;
    return {
      'id': id,
      'title': name,
      'fulltitle': name,
      if (by.isNotEmpty) 'uploader': by,
      if (by.isNotEmpty) 'channel': by,
      if (duration != null) 'duration': duration!.inMilliseconds / 1000,
      'thumbnail': thumbnail ?? this.thumbnail ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      'webpage_url': page,
      'original_url': page,
      'webpage_url_basename': 'watch',
      'webpage_url_domain': 'youtube.com',
      'extractor': 'youtube',
      'extractor_key': 'Youtube',
      'display_id': id,
      '_type': 'video',
      '_format_sort_fields': const [
        'quality', 'res', 'fps', 'hdr:12', 'source', 'vcodec', 'channels', 'acodec', 'lang', 'proto', //
      ],
      'formats': [
        for (final f in formats)
          if (f.isDirect)
            {
              'format_id': f.formatId,
              'url': f.url,
              'ext': f.ext,
              'protocol': 'https',
              'vcodec': f.vcodec ?? 'none',
              'acodec': f.acodec ?? 'none',
              if (f.width != null) 'width': f.width,
              if (f.height != null) 'height': f.height,
              if (f.fps != null && f.fps! > 1) 'fps': f.fps,
              if (f.tbr != null) 'tbr': f.tbr,
              if (f.abr != null) 'abr': f.abr,
              if (f.filesize != null) 'filesize': f.filesize,
              if (f.languagePreference != null) 'language_preference': f.languagePreference,
              // Dynamic-range-compressed audio copies rank below the originals.
              if (Uri.tryParse(f.url!)?.queryParameters['drc'] == '1') 'source_preference': -2,
              if (!f.hasVideo || !f.hasAudio) 'container': '${f.ext}_dash',
              'http_headers': f.httpHeaders,
              'downloader_options': const {'http_chunk_size': 10 << 20},
            },
      ],
    };
  }

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
    this.tbr,
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

  /// Total bitrate in kbit/s (yt-dlp sorts and sizes by it).
  final double? tbr;
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
        tbr: (j['tbr'] as num?)?.toDouble(),
        url: j['url'] as String?,
        httpHeaders: ((j['http_headers'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        languagePreference: (j['language_preference'] as num?)?.toInt(),
        protocol: j['protocol'] as String?,
      );
}
