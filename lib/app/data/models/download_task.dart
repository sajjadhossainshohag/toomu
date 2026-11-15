import 'package:get/get.dart';

enum DownloadStatus { queued, running, paused, completed, failed, canceled }

enum DownloadKind { video, audio, file }

/// Where the bytes come from.
/// * youtube: downloaded by yt-dlp using [DownloadTask.ytdlpFormat].
/// * direct: a plain URL (browser downloads, direct file links).
/// * tiktok / stream: yt-dlp on [DownloadTask.url] (a TikTok page, an
///   HLS/DASH manifest, or any page yt-dlp supports).
enum DownloadSource { youtube, direct, tiktok, stream }

/// What a running task is doing right now (not persisted).
/// [lookingUp]: yt-dlp is reading the video's details from YouTube;
/// [starting]: details known, the download is connecting (no bytes yet).
enum DownloadPhase {
  idle,
  lookingUp,
  starting,
  video,
  audio,
  merging,
  converting,
}

/// A single download job. Progress fields are reactive so each list row can
/// rebuild independently without refreshing the whole list.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.kind,
    required this.extension,
    required this.filePath,
    required this.createdAt,
    this.format,
    this.source = DownloadSource.youtube,
    this.videoId = '',
    this.url,
    this.author = '',
    this.thumbnailUrl = '',
    this.streamTag = 0,
    this.audioTag,
    this.qualityLabel = '',
    this.convert,
    this.pageUrl,
    this.headers = const {},
    int totalBytes = 0,
    int receivedBytes = 0,
    DownloadStatus status = DownloadStatus.queued,
    String? error,
  }) : totalBytes = totalBytes.obs,
       receivedBytes = receivedBytes.obs,
       status = status.obs,
       error = RxnString(error);

  final String id;
  final DownloadSource source;
  final String videoId;

  /// Direct downloads: the file URL.
  String? url;
  final String? pageUrl;

  // User-Agent and Referer only: cookies are read fresh from the WebView at
  // each start, so a renewed Cloudflare pass is used and none are stored.
  Map<String, String> headers;
  final String title;
  final String author;
  final String thumbnailUrl;

  /// yt-dlp `-f` selector. Null for tasks saved by older versions, which
  /// stored itags instead (yt-dlp's YouTube format ids are the itags).
  final String? format;

  /// Legacy (pre-yt-dlp) itags; only used to derive [ytdlpFormat].
  final int streamTag;
  final int? audioTag;

  String get ytdlpFormat =>
      format ??
      (audioTag != null ? '$streamTag+$audioTag/bv*+ba/b' : '$streamTag/b');

  /// Post-processing, e.g. `mp3:192` (convert to 192 kbps MP3).
  final String? convert;
  final DownloadKind kind;
  final String extension;
  final String qualityLabel;

  /// Final file; updated if yt-dlp ends up with a different extension.
  String filePath;
  final DateTime createdAt;

  final RxInt totalBytes;
  final RxInt receivedBytes;
  final Rx<DownloadStatus> status;
  final RxnString error;

  /// Transient, not persisted.
  final RxInt speed = 0.obs;
  final Rx<DownloadPhase> phase = DownloadPhase.idle.obs;

  bool get needsMerge => audioTag != null;

  /// e.g. 192 for `mp3:192`, null when no MP3 conversion is requested.
  int? get mp3Kbps => convert != null && convert!.startsWith('mp3:')
      ? int.tryParse(convert!.substring(4))
      : null;

  String get partPath => '$filePath.part';
  String get videoPartPath => '$filePath.video.part';
  String get audioPartPath => '$filePath.audio.part';

  /// Part files downloaded with several connections keep their pieces here.
  static String chunksDirOf(String partPath) => '$partPath.chunks';

  /// Every temp file/folder this task may leave behind.
  List<String> get tempPaths => needsMerge
      ? [
          videoPartPath,
          chunksDirOf(videoPartPath),
          audioPartPath,
          chunksDirOf(audioPartPath),
          mergeTempPath,
        ]
      : [partPath, chunksDirOf(partPath), if (convert != null) mergeTempPath];

  /// FFmpeg picks the container from the extension, so the temp output
  /// keeps the real one.
  String get mergeTempPath {
    final slash = filePath.lastIndexOf('/');
    return '${filePath.substring(0, slash + 1)}.merging_$id.$extension';
  }

  double get progress {
    final total = totalBytes.value;
    if (total <= 0) return 0;
    return (receivedBytes.value / total).clamp(0, 1).toDouble();
  }

  bool get isActive =>
      status.value == DownloadStatus.running ||
      status.value == DownloadStatus.queued;

  bool get isFinished =>
      status.value == DownloadStatus.completed ||
      status.value == DownloadStatus.canceled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'videoId': videoId,
    'format': format,
    'url': url,
    'title': title,
    'author': author,
    'thumbnailUrl': thumbnailUrl,
    'streamTag': streamTag,
    'audioTag': audioTag,
    'convert': convert,
    'pageUrl': pageUrl,
    'headers': headers,
    'kind': kind.name,
    'extension': extension,
    'qualityLabel': qualityLabel,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
    'totalBytes': totalBytes.value,
    'receivedBytes': receivedBytes.value,
    'status': status.value.name,
    'error': error.value,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    source:
        DownloadSource.values.asNameMap()[json['source']] ??
        DownloadSource.youtube,
    videoId: json['videoId'] as String? ?? '',
    format: json['format'] as String?,
    url: json['url'] as String?,
    title: json['title'] as String,
    author: json['author'] as String? ?? '',
    thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    streamTag: json['streamTag'] as int? ?? 0,
    audioTag: json['audioTag'] as int?,
    convert: json['convert'] as String?,
    pageUrl: json['pageUrl'] as String?,
    headers: ((json['headers'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
    kind: DownloadKind.values.asNameMap()[json['kind']] ?? DownloadKind.file,
    extension: json['extension'] as String,
    qualityLabel: json['qualityLabel'] as String? ?? '',
    filePath: json['filePath'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    totalBytes: json['totalBytes'] as int? ?? 0,
    receivedBytes: json['receivedBytes'] as int? ?? 0,
    status:
        DownloadStatus.values.asNameMap()[json['status']] ??
        DownloadStatus.paused,
    error: json['error'] as String?,
  );
}
