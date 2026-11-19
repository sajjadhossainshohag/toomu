import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' show CookieManager, WebUri;
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';

import '../core/utils/error_text.dart';
import '../core/utils/formatters.dart';
import '../core/utils/host_os.dart';
import '../core/utils/media_manifest.dart';
import '../core/utils/speed_meter.dart';
import '../core/utils/subtitles.dart';
import '../core/values/app_constants.dart';
import '../data/models/download_task.dart';
import '../data/models/tiktok_item.dart';
import '../data/models/media_format.dart';
import '../data/models/video_meta.dart';
import '../data/providers/youtube_provider.dart';
import '../data/providers/ytdlp/ytdlp_bridge.dart';
import '../data/repositories/download_repository.dart';
import 'media_scanner_service.dart';
import 'permission_service.dart';
import 'settings_service.dart';
import 'stream_proxy.dart';
import 'tiktok_service.dart';
import 'storage_service.dart';
import 'ytdlp_service.dart';

/// Thrown when the user pauses/cancels a running task.
class _Stopped implements Exception {
  const _Stopped();
}

// A 200 to a range that doesn't start at 0 is the whole file (or an expired
// link's HTML page); writing it at the requested offset would corrupt the file.
class _RangeIgnored implements Exception {
  const _RangeIgnored(this.status);
  final int? status;

  @override
  String toString() => "The server didn't send the requested part (HTTP $status). The link may have expired.";
}

typedef RangeRequest =
    ({Uri url, Map<String, String> headers}) Function(int from, int to);

/// 1DM/Snaptube-style download engine.
///
/// * Queue with a configurable number of parallel downloads.
/// * YouTube: yt-dlp (bundled, auto-updated) does extraction, download,
///   HD merging and MP3 conversion. Pause = stop the process; resume = rerun,
///   yt-dlp continues its `.part` files in the task's work folder.
/// * Direct links (browser downloads): own engine, files split into chunks
///   fetched over several connections, resumable across restarts.
class DownloadService extends GetxService {
  static DownloadService get to => Get.find();

  /// Bytes per HTTP range request for direct downloads.
  static const _chunk = 10 * 1024 * 1024;
  static const _minSteal = 2 * 1024 * 1024;
  static const _minPiece = 1024 * 1024;

  @visibleForTesting
  static int pieceSizeFor(int total, int connections) {
    final even = (total + connections - 1) ~/ (connections < 1 ? 1 : connections);
    return even.clamp(_minPiece, _chunk);
  }

  @visibleForTesting
  static List<String> fragmentArgs(DownloadSource source, int connections) =>
      source == DownloadSource.stream && connections > 1 ? ['--concurrent-fragments', '$connections'] : const [];

  late final DownloadRepository _repo = DownloadRepository(StorageService.downloads);
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: stallLimit,
      headers: const {
        'user-agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      },
    ),
  );

  final tasks = <DownloadTask>[].obs;
  final Map<String, CancelToken> _running = {};

  /// Why a running task was stopped ('pause' | 'cancel'), read by [_start].
  final Map<String, String> _stopReasons = {};
  final Map<String, void Function()> _speedTicks = {};

  static const networkWaitText =
      "Connection lost. It resumes by itself when you're back online.";
  static const linkExpiredText =
      'The link expired. Open the menu and tap "Refresh link".';
  static const _maxNetworkRetries = 20;

  /// How often running downloads refresh their bytes and speed.
  static const progressTick = Duration(milliseconds: 250);

  @visibleForTesting
  static Duration stallLimit = const Duration(seconds: 30);

  /// Wait before retry n is n times this (tests make it short).
  @visibleForTesting
  static Duration retryBackoff = const Duration(seconds: 2);

  @visibleForTesting
  static int retriesAfterLoss({required int previous, required bool progressed}) => progressed ? 1 : previous + 1;
  final Map<String, int> _networkRetries = {};
  Timer? _networkTimer;
  bool _checkingNetwork = false;

  late Directory _videoDir;
  late Directory _audioDir;
  late Directory _filesDir;
  String _workRoot = '';

  /// Progress notification (native DownloadProgressService).
  static const _notify = MethodChannel('toomu/download_notify');
  Timer? _notifyTimer;

  Future<DownloadService> init() async {
    final root = await resolveRootDir();
    await _useRoot(root);
    if (Platform.isAndroid) {
      // Same storage as the finished files: yt-dlp's last step is then a rename, not a full copy.
      try {
        final work = await Directory('${root.path}/.work').create(recursive: true);
        await File('${work.path}/.nomedia').create();
        _workRoot = work.path;
      } catch (e) {
        debugPrint('[Download] work folder stays in the app cache: $e');
      }
    }

    final saved = _repo.load();
    tasks.assignAll(saved);
    if (saved.any((t) => t.error.value == networkWaitText)) _watchNetwork();
    for (final t in saved) {
      // Anything interrupted by an app kill becomes paused; user resumes.
      if (t.status.value == DownloadStatus.running ||
          t.status.value == DownloadStatus.queued) {
        t.status.value = DownloadStatus.paused;
      }
    }
    // Work folders live under yt-dlp's temp root, known once it's started.
    unawaited(
      YtDlpService.to.whenReady
          .then((_) async {
            for (final t in tasks) {
              if (t.status.value != DownloadStatus.completed) {
                t.receivedBytes.value = await _bytesOnDisk(t);
              }
            }
            return cleanTemporaryFiles(); // sweep leftovers from killed sessions
          })
          .catchError((Object _) => 0),
    );

    ever(SettingsService.to.maxConcurrentDownloads, (_) => _pump());
    _notify.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        _onNotificationAction(call.arguments as String);
      }
    });
    return this;
  }

  String get downloadRoot => _videoDir.parent.path;

  Future<void> _useRoot(Directory root) async {
    _videoDir = await Directory('${root.path}/Video').create(recursive: true);
    _audioDir = await Directory('${root.path}/Audio').create(recursive: true);
    _filesDir = await Directory('${root.path}/Files').create(recursive: true);
  }

  Future<void> _storageReady() async {
    final granted = await PermissionService.to.requestStorageWrite();
    // Android 7–9: without the permission at start-up the files went to the
    // app's private folder; once granted, new downloads use Download/Toomu.
    if (granted && Platform.isAndroid && downloadRoot != _publicRoot) {
      final root = await resolveRootDir();
      if (root.path == _publicRoot) await _useRoot(root);
    }
  }

  // ---------------------------------------------------------------- public API

  Future<DownloadTask> enqueue({
    required VideoMeta video,
    required MediaFormat format,
  }) async {
    await _storageReady();
    return _add(_youtubeTask(video, format, DateTime.now().microsecondsSinceEpoch.toString()));
  }

  static List<VideoMeta> notYetQueued(List<VideoMeta> videos, Iterable<DownloadTask> existing, DownloadKind kind) {
    final have = {
      for (final t in existing)
        if (t.kind == kind && t.status.value != DownloadStatus.canceled) t.videoId,
    };
    return [for (final v in videos) if (have.add(v.id)) v];
  }

  Future<int> enqueueAll(List<VideoMeta> videos, MediaFormat format) async {
    await _storageReady();
    final fresh = notYetQueued(videos, tasks, format.kind);
    final start = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < fresh.length; i++) {
      // One at a time: each file name is checked against the ones queued before it.
      tasks.insert(0, _youtubeTask(fresh[i], format, '${start + i}'));
    }
    if (fresh.isEmpty) return 0;
    await _persist();
    _pump();
    return fresh.length;
  }

  DownloadTask _youtubeTask(VideoMeta video, MediaFormat format, String id) {
    final dir = format.kind == DownloadKind.audio ? _audioDir : _videoDir;
    final base = Formatters.fileName(video.title);
    final suffix = format.kind == DownloadKind.video
        ? ' (${format.label})'
        : '';
    final path = _uniquePath(dir.path, '$base$suffix', format.extension);
    return DownloadTask(
        id: id,
        videoId: video.id,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnailUrl,
        format: format.selector,
        convert: format.convert,
        kind: format.kind,
        extension: format.extension,
        qualityLabel: format.label,
        filePath: path,
        createdAt: DateTime.now(),
        totalBytes: format.sizeBytes,
    );
  }

  /// A TikTok video (no watermark), saved with the videos.
  Future<DownloadTask> enqueueTiktok(TiktokItem item) async {
    await _storageReady();
    final caption = item.caption.trim().isEmpty
        ? 'TikTok ${item.id}'
        : item.caption.trim();
    final base = Formatters.fileName(
      '@${item.authorId} - $caption',
      maxBytes: 140,
    );
    return _add(
      DownloadTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        source: DownloadSource.tiktok,
        videoId: item.id,
        url: item.webUrl,
        title: caption,
        author: '@${item.authorId}',
        thumbnailUrl: item.coverUrl ?? '',
        // One file with sound; H.264 first (plays everywhere).
        format: 'b[vcodec^=h264]/b[vcodec^=avc]/b',
        kind: DownloadKind.video,
        extension: 'mp4',
        qualityLabel: 'TikTok',
        filePath: _uniquePath(_videoDir.path, base, 'mp4'),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Any downloadable URL (e.g. a link tapped in the in-app browser).
  Future<DownloadTask> enqueueDirect({
    required String url,
    String? fileName,
    int size = 0,
    String? pageUrl,
    Map<String, String> headers = const {},
    String thumbnailUrl = '',
    Map<String, String> subtitles = const {},
    String? mimeType,
  }) async {
    await _storageReady();
    final uri = Uri.parse(url);
    var name = fileName?.trim();
    if (name == null || name.isEmpty) {
      name =
          uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'download';
      name = Uri.decodeComponent(name);
    }
    final (:base, :ext, :kind) = directName(name, mimeType: mimeType);
    final dir = switch (kind) {
      DownloadKind.video => _videoDir,
      DownloadKind.audio => _audioDir,
      DownloadKind.file => _filesDir,
    };

    return _add(
      DownloadTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        source: DownloadSource.direct,
        url: url,
        pageUrl: pageUrl,
        headers: headers,
        subtitles: kind == DownloadKind.video ? subtitles : const {},
        title: base,
        author: uri.host,
        thumbnailUrl: thumbnailUrl,
        kind: kind,
        extension: ext,
        qualityLabel: ext.toUpperCase(),
        filePath: _uniquePath(dir.path, base, ext),
        createdAt: DateTime.now(),
        totalBytes: size,
      ),
    );
  }

  /// Saves [bytes] the page already has (an inline or script-made image)
  /// as a finished download: there is no link to download it from.
  Future<DownloadTask> saveBytes({
    required List<int> bytes,
    required String fileName,
    String? pageUrl,
    String? mimeType,
  }) async {
    await _storageReady();
    final task = await writeFinished(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      pageUrl: pageUrl,
      dirFor: (kind) => switch (kind) {
        DownloadKind.video => _videoDir,
        DownloadKind.audio => _audioDir,
        DownloadKind.file => _filesDir,
      },
      taken: (p) => tasks.any((t) => t.filePath == p),
    );
    await _add(task);
    MediaScannerService.to.scan(task.filePath);
    return task;
  }

  /// Writes [bytes] under a free name in its folder and returns the
  /// finished task for it.
  @visibleForTesting
  static Future<DownloadTask> writeFinished({
    required List<int> bytes,
    required String fileName,
    required Directory Function(DownloadKind kind) dirFor,
    String? mimeType,
    String? pageUrl,
    bool Function(String path)? taken,
  }) async {
    final (:base, :ext, :kind) = directName(fileName, mimeType: mimeType);
    final path = uniquePath(dirFor(kind).path, base, ext, taken: taken);
    await File(path).writeAsBytes(bytes, flush: true);
    return DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      source: DownloadSource.direct,
      pageUrl: pageUrl,
      title: base,
      author: Uri.tryParse(pageUrl ?? '')?.host ?? '',
      kind: kind,
      extension: ext,
      qualityLabel: ext.toUpperCase(),
      filePath: path,
      createdAt: DateTime.now(),
      totalBytes: bytes.length,
      receivedBytes: bytes.length,
      status: DownloadStatus.completed,
    );
  }

  Future<DownloadTask> enqueueStream({
    required String url,
    required String title,
    required String format,
    DownloadKind kind = DownloadKind.video,
    String extension = 'mp4',
    String? convert,
    String qualityLabel = '',
    String thumbnailUrl = '',
    int size = 0,
    String? pageUrl,
    Map<String, String> headers = const {},
    Map<String, String> subtitles = const {},
  }) async {
    await _storageReady();
    final dir = kind == DownloadKind.audio ? _audioDir : _videoDir;
    final base = Formatters.fileName(title);
    final suffix = kind == DownloadKind.video && qualityLabel.isNotEmpty ? ' ($qualityLabel)' : '';
    return _add(
      DownloadTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        source: DownloadSource.stream,
        url: url,
        pageUrl: pageUrl,
        headers: headers,
        subtitles: kind == DownloadKind.video ? subtitles : const {},
        title: title,
        author: Uri.tryParse(pageUrl ?? url)?.host ?? '',
        thumbnailUrl: thumbnailUrl,
        format: format,
        convert: convert,
        kind: kind,
        extension: extension,
        qualityLabel: qualityLabel,
        filePath: _uniquePath(dir.path, '$base$suffix', extension),
        createdAt: DateTime.now(),
        totalBytes: size,
      ),
    );
  }

  Future<void> replaceLink(
    DownloadTask task,
    String url,
    Map<String, String> headers, {
    int size = 0,
  }) async {
    if (task.isActive) return;
    // Partial data is only trusted when the new file is the same size.
    if (size <= 0 || size != task.totalBytes.value) {
      for (final p in _tempPathsOf(task)) {
        await _deleteQuietly(p);
      }
      task.receivedBytes.value = 0;
    }
    task.url = url;
    task.headers = headers;
    resume(task);
  }

  Future<DownloadTask> _add(DownloadTask task) async {
    tasks.insert(0, task);
    await _persist();
    _pump();
    return task;
  }

  static const _videoExt = {
    'mp4',
    'mkv',
    'webm',
    'mov',
    '3gp',
    'avi',
    'm4v',
    'ts',
  };
  static const _audioExt = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
    'wma',
  };

  static const _extOfMime = {
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/x-matroska': 'mkv',
    'video/quicktime': 'mov',
    'video/3gpp': '3gp',
    'video/x-msvideo': 'avi',
    'video/mp2t': 'ts',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/flac': 'flac',
    'audio/wav': 'wav',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/vnd.android.package-archive': 'apk',
  };
  static final _extLike = RegExp(r'^(?=.*[a-z])[a-z0-9]{1,8}$');

  @visibleForTesting
  static ({String base, String ext, DownloadKind kind}) directName(String name, {String? mimeType}) {
    final dot = name.lastIndexOf('.');
    final tail = dot > 0 && dot < name.length - 1 ? name.substring(dot + 1).toLowerCase() : '';
    final fromType = _extOfMime[(mimeType ?? '').split(';').first.trim().toLowerCase()];
    final known = _videoExt.contains(tail) || _audioExt.contains(tail) || _extOfMime.containsValue(tail);
    // After the last dot of a title or a server code there is often no extension
    // ("Ep. 3 The return", "KSUx.cVrp…"): then the server's type decides.
    if (known || (fromType == null && _extLike.hasMatch(tail))) {
      return (base: Formatters.fileName(name.substring(0, dot)), ext: tail, kind: _kindOf(tail));
    }
    final ext = fromType ?? 'bin';
    return (base: Formatters.fileName(name), ext: ext, kind: _kindOf(ext));
  }

  static DownloadKind _kindOf(String ext) => _videoExt.contains(ext)
      ? DownloadKind.video
      : _audioExt.contains(ext)
      ? DownloadKind.audio
      : DownloadKind.file;

  bool get hasActiveDownloads => _running.isNotEmpty;

  void pause(DownloadTask task) {
    if (task.status.value == DownloadStatus.queued) {
      task.status.value = DownloadStatus.paused;
      _persist();
      return;
    }
    _stop(task, 'pause');
  }

  void resume(DownloadTask task) {
    _networkRetries.remove(task.id);
    _resume(task);
  }

  void _resume(DownloadTask task) {
    if (task.status.value == DownloadStatus.paused ||
        task.status.value == DownloadStatus.failed) {
      task.error.value = null;
      task.status.value = DownloadStatus.queued;
      _persist();
      _pump();
    }
  }

  void pauseAll() => tasks.where((t) => t.isActive).forEach(pause);

  void resumeAll() => tasks
      .where(
        (t) =>
            t.status.value == DownloadStatus.paused ||
            t.status.value == DownloadStatus.failed,
      )
      .forEach(resume);

  /// Removes a task and its temp files. [deleteFile] also removes the
  /// downloaded file. Returns the number of bytes freed on disk.
  Future<int> remove(DownloadTask task, {bool deleteFile = false}) =>
      removeMany([task], deleteFiles: deleteFile);

  Future<int> removeMany(
    Iterable<DownloadTask> list, {
    required bool deleteFiles,
  }) async {
    var freed = 0;
    for (final task in list.toList()) {
      if (_running.containsKey(task.id)) {
        task.status.value = DownloadStatus.canceled;
        _stop(task, 'cancel');
      }
      tasks.remove(task);
      for (final p in _tempPathsOf(task)) {
        freed += await _deleteQuietly(p);
      }
      if (deleteFiles) {
        for (final s in Subtitles.sidecarsOf(task.filePath)) {
          freed += await _deleteQuietly(s);
        }
        freed += await _deleteQuietly(task.filePath);
        MediaScannerService.to.scan(task.filePath); // drop it from MediaStore
      }
    }
    await _persist();
    _pump();
    return freed;
  }

  /// A downloaded file was deleted elsewhere (e.g. from Music): drop its row.
  Future<void> forgetFile(String path) async {
    final gone = tasks.where((t) => t.filePath == path).toList();
    if (gone.isNotEmpty) await removeMany(gone, deleteFiles: false);
  }

  List<DownloadTask> get completed =>
      tasks.where((t) => t.status.value == DownloadStatus.completed).toList();

  /// Size of finished files that still exist on disk.
  Future<int> completedBytesOnDisk() async {
    final stats = await Future.wait(completed.map((t) => FileStat.stat(t.filePath)));
    return stats.fold<int>(0, (sum, s) => sum + (s.type == FileSystemEntityType.notFound ? 0 : s.size));
  }

  Future<int> clearCompleted({bool deleteFiles = false}) =>
      removeMany(completed, deleteFiles: deleteFiles);

  /// Deletes leftover temp files/folders that no download in the list owns
  /// any more. Partial data of paused/failed downloads is kept for resume.
  Future<int> cleanTemporaryFiles() {
    final owned = <String>{for (final t in tasks) ..._tempPathsOf(t)};
    final dirs = [_videoDir, _audioDir, _filesDir, _videoDir.parent].map((d) => d.path).toList();
    final works = [_workRoot, YtDlpService.to.workRoot].where((w) => w.isNotEmpty).toList();
    return Isolate.run(() {
      bool isTemp(String name) =>
          name.endsWith('.part') ||
          name.endsWith('.chunks') ||
          name.endsWith('.ytdl') ||
          name.startsWith('.merging_') ||
          name == '.probe';
      List<FileSystemEntity> list(String dir) =>
          Directory(dir).existsSync() ? Directory(dir).listSync(followLinks: false) : const [];
      final stale = [
        for (final dir in dirs)
          for (final e in list(dir))
            if (isTemp(e.uri.pathSegments.where((s) => s.isNotEmpty).last)) e.path,
        // yt-dlp work folders of tasks that no longer exist.
        for (final work in works)
          for (final e in list(work))
            if (!e.path.endsWith('/.nomedia')) e.path,
      ].where((p) => !owned.contains(p));
      return stale.fold<int>(0, (freed, p) => freed + _deleteSync(p));
    });
  }

  // ------------------------------------------------------------------ engine

  void _stop(DownloadTask task, String reason) {
    final token = _running[task.id];
    if (token == null) return;
    _stopReasons[task.id] = reason;
    token.cancel(reason);
    if (task.source != DownloadSource.direct) {
      unawaited(YtDlpBridge.cancel(task.id));
    }
  }

  void _pump() {
    final limit = SettingsService.to.maxConcurrentDownloads.value;
    final queued = tasks.reversed
        .where((t) => t.status.value == DownloadStatus.queued)
        .toList(); // oldest first
    for (final task in queued) {
      if (_running.length >= limit) break;
      _start(task);
    }
  }

  Future<void> _start(DownloadTask task) async {
    final token = CancelToken();
    _running[task.id] = token;
    task.status.value = DownloadStatus.running;
    task.error.value = null;
    // After the status change, so the first snapshot sees this task.
    // Progress moves 4× a second; the notification stays at once a second
    // (Android drops faster updates).
    _notifyTimer ??= Timer.periodic(progressTick, (t) {
      for (final tick in _speedTicks.values.toList()) {
        tick();
      }
      if (t.tick % 4 == 0) _updateNotification();
    });
    _updateNotification();

    var current = task.receivedBytes.value;
    final startBytes = current;
    final clock = Stopwatch()..start();
    final meter = SpeedMeter(current, Duration.zero);
    _speedTicks[task.id] = () {
      task.speed.value = meter.add(current, clock.elapsed);
      task.receivedBytes.value = current;
    };
    void onBytes(int b) => current = b;

    try {
      if (task.source == DownloadSource.direct) {
        task.phase.value = DownloadPhase.video;
        await _downloadDirect(task, token, onBytes);
        await File(task.partPath).rename(task.filePath);
      } else if (task.source == DownloadSource.youtube) {
        await _downloadYtDlp(task, token, onBytes);
      } else {
        await _downloadSite(task, token, onBytes);
      }
      if (task.source == DownloadSource.youtube && task.kind == DownloadKind.video) {
        await _saveSubtitles(task);
      }
      if (task.subtitles.isNotEmpty) await _savePageSubtitles(task);

      task.receivedBytes.value = task.totalBytes.value;
      task.status.value = DownloadStatus.completed;
      _networkRetries.remove(task.id);
      MediaScannerService.to.scan(task.filePath);
      _notifyFinished(task);
    } on Object catch (e) {
      final stopped =
          e is _Stopped ||
          (e is DioException && CancelToken.isCancel(e)) ||
          _stopReasons.containsKey(task.id);
      if (stopped) {
        task.status.value = _stopReasons[task.id] == 'cancel'
            ? DownloadStatus.canceled
            : DownloadStatus.paused;
      } else if (isNetworkError(e) &&
          (_networkRetries[task.id] = retriesAfterLoss(
                previous: _networkRetries[task.id] ?? 0,
                progressed: current > startBytes,
              )) <=
              _maxNetworkRetries) {
        debugPrint('[Download] ${task.title}: connection lost ($e)');
        task.status.value = DownloadStatus.failed;
        task.error.value = networkWaitText;
        _watchNetwork();
      } else {
        debugPrint('[Download] ${task.title} failed: $e');
        task.status.value = DownloadStatus.failed;
        task.error.value = _linkExpired(task, e) ? linkExpiredText : ErrorText.of(e);
        // No notification for failures: the Downloads tab shows the error.
      }
    } finally {
      _speedTicks.remove(task.id);
      _stopReasons.remove(task.id);
      task.speed.value = 0;
      task.phase.value = DownloadPhase.idle;
      if (task.status.value != DownloadStatus.completed) {
        final onDisk = await _bytesOnDisk(task);
        // A quick resume may have started a new run during the await.
        if (_running[task.id] == token) task.receivedBytes.value = onDisk;
      }
      if (_running[task.id] == token) _running.remove(task.id);
      if (task.status.value != DownloadStatus.canceled) await _persist();
      _pump();
      _updateNotification();
    }
  }

  // ------------------------------------------------------- network recovery

  static final _networkMarkers = RegExp(
    'unable to connect|timed out|network is unreachable|name resolution|'
    'name or service not known|failed to resolve|no address associated|'
    'connection (reset|refused|aborted)|getaddrinfo|remote end closed|'
    // Android when Wi-Fi or mobile data drops (ECONNABORTED, EHOSTUNREACH).
    'connection abort|no route to host|'
    'connection broken|incompleteread|eof occurred|eof from the server|'
    // aria2c: 2 = time out, 6 = network problem, 19 = name resolution failed.
    'network problem|failed to establish connection|aria2c exited with code (2|6|19)\\b',
  );

  static bool isNetworkError(Object e) => switch (e) {
    SocketException() || HttpException() || HandshakeException() || TimeoutException() => true,
    DioException(:final type, :final response) =>
      response == null && type != DioExceptionType.cancel && type != DioExceptionType.badCertificate,
    YtDlpException(:final message) => _networkMarkers.hasMatch(message.toLowerCase()),
    StateError(:final message) => message.contains('ended early'),
    _ => false,
  };

  static final _expiredStatus = RegExp(r'HTTP Error (401|403|404|410)');

  static bool _linkExpired(DownloadTask t, Object e) =>
      t.pageUrl != null &&
      t.url != t.pageUrl && // page downloads re-extract by themselves on retry
      switch (e) {
        DioException(:final response) => const {401, 403, 404, 410}.contains(response?.statusCode),
        YtDlpException(:final message) => _expiredStatus.hasMatch(message),
        _RangeIgnored() => true,
        _ => false,
      };

  void _watchNetwork() {
    _networkTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _retryWaiting());
  }

  Future<void> _retryWaiting() async {
    final waiting = tasks
        .where((t) => t.status.value == DownloadStatus.failed && t.error.value == networkWaitText)
        .toList();
    if (waiting.isEmpty) {
      _networkTimer?.cancel();
      _networkTimer = null;
      return;
    }
    if (_checkingNetwork) return;
    _checkingNetwork = true;
    try {
      final link = Uri.tryParse(waiting.first.url ?? '');
      if (!await online(link == null || link.host.isEmpty ? Uri.https('www.youtube.com') : link)) return;
    } finally {
      _checkingNetwork = false;
    }
    debugPrint('[Download] back online: resuming ${waiting.length}');
    for (final t in waiting) {
      _resume(t);
    }
  }

  @visibleForTesting
  static Future<bool> online(Uri uri) async {
    // A real connection, not a DNS lookup: phones answer those from cache.
    // On the file's own port: a server without HTTPS never answers on 443.
    try {
      final port = uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
      final socket = await Socket.connect(uri.host, port, timeout: const Duration(seconds: 5));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ notification

  /// Snapshot for the notification bar (about once a second): a summary
  /// plus one card per running download.
  void _updateNotification() {
    final active = tasks
        .where((t) => t.status.value == DownloadStatus.running)
        .toList();
    if (active.isEmpty) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _notify.invokeMethod<void>('stop');
      return;
    }
    final queued = tasks
        .where((t) => t.status.value == DownloadStatus.queued)
        .length;
    final done = active.fold(0, (s, t) => s + t.receivedBytes.value);
    final total = active.fold(0, (s, t) => s + t.totalBytes.value);
    final speed = active.fold(0, (s, t) => s + t.speed.value);
    final eta = _eta(total - done, speed);

    _notify.invokeMethod<void>('update', {
      'title': 'Downloading ${active.length} files',
      'text': <String>[
        if (total > 0) '${(done * 100 / total).floor()}%',
        if (speed > 0) Formatters.speed(speed),
        ?eta,
        if (queued > 0) '$queued waiting',
      ].join(' · '),
      'progress': total > 0 ? (done * 1000 / total).round() : -1,
      'items': [
        for (final t in active)
          {
            'id': t.id,
            'title': t.title,
            'thumb': t.thumbnailUrl.isEmpty ? null : t.thumbnailUrl,
            'progress': _busyPhase(t) != null || t.totalBytes.value <= 0
                ? -1
                : (t.progress * 1000).round().clamp(0, 1000),
            'status': _cardStatus(t, queued: active.length == 1 ? queued : 0),
            'kind': _kindLabel(t),
          },
      ],
    });
  }

  /// Merging / converting have no byte progress (spinner bar instead).
  String? _busyPhase(DownloadTask t) => switch (t.phase.value) {
    DownloadPhase.lookingUp => 'Getting video info…',
    DownloadPhase.starting => 'Starting download…',
    DownloadPhase.merging => 'Merging video & audio…',
    DownloadPhase.converting => 'Converting to MP3…',
    _ => null,
  };

  /// "45% · 3.2 MB/s · 12 s left" (+ "· 2 waiting" on a lone card).
  String _cardStatus(DownloadTask t, {required int queued}) {
    final waiting = queued > 0 ? ' · $queued waiting' : '';
    final busy = _busyPhase(t);
    if (busy != null) return '$busy$waiting';
    final total = t.totalBytes.value;
    if (total <= 0) return 'Starting…$waiting';
    final received = t.receivedBytes.value;
    return <String>[
          '${(t.progress * 100).floor()}%',
          if (t.speed.value > 0) Formatters.speed(t.speed.value),
          _eta(total - received, t.speed.value) ??
              '${Formatters.bytes(received)} of ${Formatters.bytes(total)}',
        ].join(' · ') +
        waiting;
  }

  static String? _eta(int remaining, int speed) {
    if (speed <= 0 || remaining <= 0) return null;
    final s = (remaining / speed).ceil();
    if (s < 60) return '$s s left';
    if (s < 3600) return '${(s / 60).ceil()} min left';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return m == 0 ? '$h h left' : '$h h $m min left';
  }

  /// Shown next to the app name, e.g. "Video · 1080p" or "MP3 · 320 kbps".
  static String _kindLabel(DownloadTask t) {
    final kind = switch (t.kind) {
      DownloadKind.video => 'Video',
      DownloadKind.audio => 'Audio',
      DownloadKind.file => 'File',
    };
    return t.qualityLabel.isEmpty ? kind : '$kind · ${t.qualityLabel}';
  }

  /// "Download complete" notification.
  void _notifyFinished(DownloadTask t) {
    _notify.invokeMethod<void>('finished', {
      'id': t.id,
      'title': t.title,
      'thumb': t.thumbnailUrl.isEmpty ? null : t.thumbnailUrl,
      'kind': _kindLabel(t),
    });
  }

  /// Buttons on the download notifications.
  void _onNotificationAction(String action) {
    if (action == 'pauseAll') return pauseAll();
    final sep = action.indexOf(':');
    if (sep < 0) return;
    final id = action.substring(sep + 1);
    final task = tasks.firstWhereOrNull((t) => t.id == id);
    if (task == null) return;
    switch (action.substring(0, sep)) {
      case 'pause':
        pause(task);
      case 'cancel':
        remove(task);
    }
  }

  // ---------------------------------------------------------------- yt-dlp

  Future<void> _downloadYtDlp(
    DownloadTask task,
    CancelToken token,
    void Function(int) onBytes,
  ) async {
    final yt = YtDlpService.to;
    final sw = Stopwatch()..start();
    task.phase.value = DownloadPhase.lookingUp;
    await yt.whenReady;
    _checkStopped(token);

    final work = _workDirOf(task);
    await Directory(work).create(recursive: true);
    // Tasks queued before names were limited by bytes can have names
    // Android can't create (255 bytes; a Bengali letter is 3).
    final fitted = _fittedPath(task.filePath);
    if (fitted != task.filePath) {
      debugPrint('[Download] file name shortened to fit the phone\'s limit');
      task.filePath = fitted;
      await _persist();
    }
    final target = File(task.filePath);
    final dir = target.parent.path;
    final name = target.uri.pathSegments.last;
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;

    final url = 'https://www.youtube.com/watch?v=${task.videoId}';
    final connections = SettingsService.to.connectionsPerDownload.value;
    final useAria2c = connections > 1;

    final common = <String>[
      '-f', task.ytdlpFormat,
      ..._postProcessArgs(task),
      '-P', 'home:$dir',
      '-P', 'temp:$work',
      '-o', '${base.replaceAll('%', '%%')}.%(ext)s',
      '--progress-template', _progressTemplate,
      // Built-in downloader: 10 MB requests avoid YouTube's per-connection
      // throttling; a link slowed below 100 KB/s is re-fetched.
      '--http-chunk-size', '10M',
      '--throttled-rate', '100K',
    ];
    // aria2c: several connections per file (Settings → Connections).
    List<String> argsWith({required bool aria2c}) =>
        aria2c ? ['--toomu-aria2c=$connections', ...common] : common;

    final progress = YtDlpProgress(
      task,
      onBytes,
      onFirstBytes: () {
        debugPrint('[Download] first bytes after ${sw.elapsedMilliseconds} ms');
      },
    );
    bool stopped(YtDlpResult r) => r.canceled || token.isCancelled;

    // yt-dlp's own lookup: the format sheet may have started one; else run
    // one now (pausing stops waiting for it).
    Future<String?> lookedUp() async {
      var json = await yt.infoJsonFor(url);
      if (json != null) return json;
      try {
        await Future.any<Object?>([yt.info(url), token.whenCancel]);
        json = await yt.infoJsonFor(url);
      } catch (e) {
        debugPrint(
          '[Download] lookup failed ($e); extracting during the download',
        );
      }
      _checkStopped(token);
      return json;
    }

    // 1. Links already in hand, fastest first — no second Python run and
    //    YouTube round before bytes flow:
    //    a. yt-dlp's lookup, if one finished (e.g. the sheet's);
    //    b. the fast lookup's whole-file links (~0.4 s, no Python; usually
    //       already done by the sheet), handed to yt-dlp as its info JSON;
    //    c. else wait for / run yt-dlp's lookup.
    var json = yt.savedInfoJson(url);
    var fromFast = false;
    if (json == null) {
      json = await _fastInfoJson(task);
      fromFast = json != null;
    }
    json ??= await lookedUp();
    debugPrint(
      '[Download] video details ${json != null ? 'ready (${fromFast ? 'fast lookup' : 'yt-dlp'})' : 'not ready (extracting)'} '
      'after ${sw.elapsedMilliseconds} ms',
    );
    // Each fallback starts clean: partial files of one downloader / link set
    // can't be resumed by another.
    Future<void> freshStart() async {
      await _deleteQuietly(work);
      await Directory(work).create(recursive: true);
      progress.reset();
    }

    final infoFile = File('$work/info.json');
    Future<YtDlpResult> fromSavedInfo(
      String info, {
      required bool aria2c,
    }) async {
      // Media links via the stream proxy: full-speed pieces for every
      // connection (YouTube throttles or refuses aria2c's large ranges).
      await infoFile.writeAsString(StreamProxy.to.routeInfoJson(info));
      return yt.runWithoutUrl(task.id, [
        ...argsWith(aria2c: aria2c),
        '--load-info-json', infoFile.path,
        // If these links fail, yt-dlp looks the video up again by
        // itself: make that the quick, JS-free client too.
        '--extractor-args',
        'youtube:player_client=visionos;skip=hls,translated_subs',
      ], onLine: progress.onLine);
    }

    Future<YtDlpResult> fromInfo(String info) async {
      task.phase.value = DownloadPhase.starting;
      var r = await fromSavedInfo(info, aria2c: useAria2c);
      // aria2c refused: the built-in downloader asks differently.
      if (useAria2c && !r.ok && !stopped(r)) {
        debugPrint(
          '[Download] aria2c failed on the saved links; trying the built-in downloader',
        );
        await freshStart();
        r = await fromSavedInfo(info, aria2c: false);
      }
      return r;
    }

    // The file can't be written (name, space, permission): no other links
    // or downloader can fix that, so stop with the reason.
    void stopIfLocal(YtDlpResult r) {
      final problem = r.ok ? null : localFileProblem(r.err);
      if (problem != null) throw YtDlpException(problem);
    }

    YtDlpResult? result;
    if (json != null) {
      _checkStopped(token);
      result = await fromInfo(json);
      stopIfLocal(result);
      if (fromFast && !result.ok && !stopped(result)) {
        debugPrint(
          '[Download] fast-lookup links failed; using yt-dlp\'s lookup',
        );
        await freshStart();
        final looked = await lookedUp();
        if (looked != null) result = await fromInfo(looked);
        stopIfLocal(result);
      }
      if (!result.ok && !stopped(result)) {
        debugPrint(
          '[Download] saved links failed; extracting again with other clients',
        );
        await freshStart();
      }
    }

    // 2. Full extraction (fresh links), with the YouTube client fallback.
    //    yt-dlp's built-in downloader here: these links aren't routed
    //    through the stream proxy, and aria2c's large ranges straight to
    //    YouTube get throttled or refused (aria2c exit code 22).
    if (result == null || (!result.ok && !stopped(result))) {
      result = await yt.runWithFallback(
        task.id,
        argsWith(aria2c: false),
        url,
        stopped: () => token.isCancelled,
        onLine: progress.onLine,
      );
      stopIfLocal(result);
    }

    if (result.canceled || token.isCancelled) throw const _Stopped();
    if (!result.ok) throw YtDlpException(result.err);

    _findOutput(task, target, dir, base);
    await _deleteQuietly(work);
  }

  static const _progressTemplate =
      'download:[toomu] %(info.format_id)s %(progress.downloaded_bytes)s '
      '%(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s';

  /// yt-dlp may pick another extension (e.g. a single WebM file).
  static void _findOutput(
    DownloadTask task,
    File target,
    String dir,
    String base,
  ) {
    if (target.existsSync()) return;
    final found =
        Directory(dir).listSync().whereType<File>().where((f) {
          final n = f.uri.pathSegments.last;
          return n.startsWith('$base.') &&
              !n.endsWith('.part') &&
              !n.endsWith('.ytdl');
        }).toList()..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
    if (found.isEmpty) {
      throw StateError('The download finished but the file is missing');
    }
    task.filePath = found.first.path;
  }

  Future<void> _downloadSite(
    DownloadTask task,
    CancelToken token,
    void Function(int) onBytes,
  ) async {
    final yt = YtDlpService.to;
    final sw = Stopwatch()..start();
    task.phase.value = DownloadPhase.starting;
    await yt.whenReady;
    _checkStopped(token);
    final work = _workDirOf(task);
    await Directory(work).create(recursive: true);
    final fitted = _fittedPath(task.filePath);
    if (fitted != task.filePath) {
      task.filePath = fitted;
      await _persist();
    }
    final target = File(task.filePath);
    final dir = target.parent.path;
    final name = target.uri.pathSegments.last;
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final progress = YtDlpProgress(
      task,
      onBytes,
      onFirstBytes: () {
        debugPrint('[Download] first bytes after ${sw.elapsedMilliseconds} ms');
      },
    );
    final connections = SettingsService.to.connectionsPerDownload.value;
    Future<YtDlpResult> run(int fragments) async => yt.runUrl(
          task.id,
          [
            '-f', task.ytdlpFormat,
            ..._postProcessArgs(task),
            '-P', 'home:$dir',
            '-P', 'temp:$work',
            '-o', '${base.replaceAll('%', '%%')}.%(ext)s',
            '--progress-template', _progressTemplate,
            ...fragmentArgs(task.source, fragments),
            // TikTok's firewall pass from the link check, same browser identity.
            ...task.source == DownloadSource.tiktok
                ? await TiktokService.ytDlpArgs()
                : headerArgs(await _requestHeaders(task)),
          ],
          task.url!,
          onLine: progress.onLine,
        );
    var r = await run(connections);
    if (r.canceled || token.isCancelled) throw const _Stopped();
    if (!r.ok && localFileProblem(r.err) == null && fragmentArgs(task.source, connections).isNotEmpty) {
      // Some sites refuse many requests at once: the same download one segment at a time.
      debugPrint('[Download] parallel segments failed; retrying one at a time');
      await _deleteQuietly(work);
      await Directory(work).create(recursive: true);
      progress.reset();
      r = await run(1);
      if (r.canceled || token.isCancelled) throw const _Stopped();
    }
    if (!r.ok) throw YtDlpException(localFileProblem(r.err) ?? r.err);
    _findOutput(task, target, dir, base);
    if (task.source == DownloadSource.stream && task.kind == DownloadKind.video) {
      await _saveStreamSubtitles(task, dir, work, base);
    }
    await _deleteQuietly(work);
  }

  /// [path] with its name cut to fit Android's 255-byte limit (with room
  /// for yt-dlp's and aria2c's temporary endings); unchanged if it fits.
  String _fittedPath(String path) {
    final slash = path.lastIndexOf('/');
    final dir = path.substring(0, slash);
    final name = path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    if (utf8.encode(base).length <= 170) return path;
    final ext = dot > 0 ? name.substring(dot + 1) : 'mp4';
    return _uniquePath(dir, Formatters.fileName(base), ext);
  }

  static final _youtube = YoutubeProvider();

  Future<void> _savePageSubtitles(DownloadTask task) async {
    for (final MapEntry(key: lang, value: url) in task.subtitles.entries) {
      try {
        final cookies = await webCookies(url);
        final r = await _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {...task.headers, if (cookies.isNotEmpty) 'Cookie': cookies},
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final text = r.data ?? '';
        if (!Subtitles.looksLikeSubtitles(text)) continue;
        await File(Subtitles.sidecarPath(task.filePath, lang, Subtitles.extOf(url))).writeAsString(text);
      } catch (e) {
        debugPrint('[Download] $lang subtitles failed: $e');
      }
    }
  }

  Future<void> _saveStreamSubtitles(DownloadTask task, String dir, String work, String base) async {
    final id = '${task.id}-subs';
    try {
      final headers = await _requestHeaders(task);
      final manifest = await _dio.get<String>(
        task.url!,
        options: Options(responseType: ResponseType.plain, headers: headers),
      );
      if (!MediaManifest.hasSubtitles(manifest.data ?? '')) return;
      final r = await YtDlpService.to
          .runUrl(id, [
            '--skip-download',
            '--write-subs',
            '--sub-langs', 'all',
            // Subtitle playlists are hundreds of tiny pieces: one at a time took 55 s for a 10-minute sample.
            '--concurrent-fragments', '8',
            '-P', 'home:$dir',
            '-P', 'temp:$work',
            '-o', '${base.replaceAll('%', '%%')}.%(ext)s',
            ...headerArgs(headers),
          ], task.url!)
          .timeout(const Duration(minutes: 5));
      debugPrint('[Download] stream subtitles ${r.ok ? 'saved' : 'failed'}');
    } catch (e) {
      unawaited(YtDlpBridge.cancel(id));
      debugPrint('[Download] no stream subtitles: $e');
    }
  }

  static Future<void> _saveSubtitles(DownloadTask task) async {
    try {
      final saved = await _youtube
          .saveSubtitles(task.videoId, task.filePath, Subtitles.wanted(PlatformDispatcher.instance.locale))
          .timeout(const Duration(seconds: 20));
      debugPrint('[Download] subtitles: ${saved.length}');
    } catch (e) {
      debugPrint('[Download] no subtitles: $e');
    }
  }

  /// [task]'s video as yt-dlp info JSON built from the fast lookup — only
  /// with whole-file links (visionOS client); null otherwise.
  static Future<String?> _fastInfoJson(DownloadTask task) async {
    try {
      final fast = await _youtube
          .fastLinks(task.videoId)
          .timeout(const Duration(seconds: 10));
      if (fast == null || !fast.full) return null;
      return jsonEncode(
        fast.info.toYtDlpInfo(
          title: task.title,
          uploader: task.author,
          thumbnail: task.thumbnailUrl.isEmpty ? null : task.thumbnailUrl,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Merge / convert options per task.
  static List<String> _postProcessArgs(DownloadTask t) {
    final kbps = t.mp3Kbps;
    if (kbps != null) {
      return [
        '-x',
        '--audio-format',
        'mp3',
        '--audio-quality',
        '${kbps}K',
        '--embed-metadata',
      ];
    }
    if (t.kind == DownloadKind.audio) {
      return [
        '-x',
        '--audio-format',
        t.extension == 'webm' ? 'opus' : t.extension,
        '--embed-metadata',
      ];
    }
    if (t.extension == 'mp4') {
      // No --embed-metadata: it rewrites the whole (large) file once more.
      return ['--merge-output-format', 'mp4', '--remux-video', 'mp4'];
    }
    return ['--merge-output-format', t.extension];
  }

  String _workDirOf(DownloadTask t) => workDirFor(t.id, root: _workRoot, legacyRoot: YtDlpService.to.workRoot);

  @visibleForTesting
  static String workDirFor(String id, {required String root, required String legacyRoot}) {
    final old = legacyRoot.isEmpty ? '' : '$legacyRoot/$id';
    if (root.isEmpty) return old;
    final dir = '$root/$id';
    // Paused downloads from before the move resume where their data is.
    return old.isNotEmpty && !Directory(dir).existsSync() && Directory(old).existsSync() ? old : dir;
  }

  List<String> _tempPathsOf(DownloadTask t) => [
    ...t.tempPaths,
    if (t.source != DownloadSource.direct && _workDirOf(t).isNotEmpty)
      _workDirOf(t),
  ];

  // ---------------------------------------------------------- direct links

  Future<void> _downloadDirect(
    DownloadTask task,
    CancelToken token,
    void Function(int) onBytes,
  ) async {
    await downloadUrl(
      Uri.parse(task.url!),
      await _requestHeaders(task),
      task.partPath,
      connections: SettingsService.to.connectionsPerDownload.value,
      token: token,
      onBytes: onBytes,
      knownTotal: task.totalBytes.value,
      onTotal: (total) async {
        // A different size means the file at this link changed: its old bytes
        // must not be joined with the new ones.
        if (total > 0 && task.totalBytes.value > 0 && total != task.totalBytes.value) {
          for (final p in _tempPathsOf(task)) {
            await _deleteQuietly(p);
          }
        }
        task.totalBytes.value = total;
      },
    );
  }

  @visibleForTesting
  Future<void> downloadUrl(
    Uri uri,
    Map<String, String> headers,
    String partPath, {
    required int connections,
    required CancelToken token,
    required void Function(int) onBytes,
    int knownTotal = 0,
    Future<void> Function(int total)? onTotal,
  }) async {
    // The first piece doubles as the size check: no extra round trip before the download starts.
    final first = await _dio.get<ResponseBody>(
      uri.toString(),
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...headers, 'Range': 'bytes=0-${_minPiece - 1}'},
      ),
    );
    Response<ResponseBody>? opened = first;
    try {
      var total = int.tryParse(first.headers.value('content-length') ?? '') ?? 0;
      var ranges = false;
      if (first.statusCode == 206) {
        final range = first.headers.value('content-range') ?? '';
        final whole = int.tryParse(range.split('/').last) ?? 0;
        if (whole > 0) (total, ranges) = (whole, true);
      }
      await onTotal?.call(total);
      opened = null;
      await _fetch(
        total: total,
        partPath: partPath,
        token: token,
        onBytes: onBytes,
        connections: connections,
        first: first,
        request: (from, to) => (url: uri, headers: {...headers, 'Range': 'bytes=$from-$to'}),
        rangeSupported: ranges,
      );
    } finally {
      if (opened != null) unawaited(opened.data?.stream.listen(null).cancel());
    }
  }

  Future<Map<String, String>> _requestHeaders(DownloadTask t) async {
    if (t.pageUrl == null && t.headers.isEmpty) return const {};
    final cookies = await webCookies(t.url!);
    return {...t.headers, if (cookies.isNotEmpty) 'Cookie': cookies};
  }

  static Future<String> webCookies(String url) async {
    try {
      final list = await CookieManager.instance().getCookies(url: WebUri(url));
      return list.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  static List<String> headerArgs(Map<String, String> headers) => [
    for (final e in headers.entries)
      ...switch (e.key.toLowerCase()) {
        'user-agent' => ['--user-agent', e.value],
        'referer' => ['--referer', e.value],
        _ => ['--add-header', '${e.key}:${e.value}'],
      },
  ];

  /// Downloads [total] bytes into [partPath], resuming what's on disk.
  /// Uses up to [connections] parallel connections, each writing its pieces
  /// straight into the part file. [first], if given, is an open response
  /// for the start of the file; it is used or closed.
  Future<void> _fetch({
    required int total,
    required String partPath,
    required CancelToken token,
    required void Function(int) onBytes,
    required RangeRequest request,
    required int connections,
    Response<ResponseBody>? first,
    bool rangeSupported = true,
  }) async {
    final part = File(partPath);
    final chunksDir = Directory(DownloadTask.chunksDirOf(partPath));
    if (partComplete(partPath, total)) {
      if (first != null) unawaited(first.data?.stream.listen(null).cancel());
      onBytes(total);
      return;
    }
    final startedSequential =
        part.existsSync() && part.lengthSync() > 0 && !chunksDir.existsSync();

    if (!rangeSupported || total <= 0) {
      return _fetchWhole(partPath, request, token, onBytes, total, first: first);
    }
    if (connections <= 1 || total <= _minPiece || startedSequential) {
      return _fetchSequential(total, partPath, request, token, onBytes, first: first);
    }
    return fetchParallel(
      total,
      partPath,
      chunksDir,
      connections,
      request,
      token,
      onBytes,
      first: first,
    );
  }

  /// Server without range support: one plain GET, restarting from zero.
  Future<void> _fetchWhole(
    String partPath,
    RangeRequest request,
    CancelToken token,
    void Function(int) onBytes,
    int total, {
    Response<ResponseBody>? first,
  }) async {
    final Response<ResponseBody> response;
    if (first != null && first.statusCode == 200) {
      response = first;
    } else {
      if (first != null) unawaited(first.data?.stream.listen(null).cancel());
      final req = request(0, 0);
      response = await _dio.get<ResponseBody>(
        req.url.toString(),
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...req.headers}..remove('Range'),
        ),
      );
    }
    final sink = File(partPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onBytes(received);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && received < total) {
      throw StateError('Download ended early ($received of $total bytes).');
    }
  }

  Future<void> _fetchSequential(
    int total,
    String partPath,
    RangeRequest request,
    CancelToken token,
    void Function(int) onBytes, {
    Response<ResponseBody>? first,
  }) async {
    var opening = first;
    final part = File(partPath);
    if (!part.existsSync()) await part.create(recursive: true);
    var received = part.lengthSync();
    if (received > total) {
      await part.writeAsBytes(const []);
      received = 0;
    }
    onBytes(received);

    final raf = await part.open(mode: FileMode.append);
    try {
      while (received < total) {
        _checkStopped(token);
        final end = (received + _chunk - 1).clamp(0, total - 1);
        await _withRetries(() async {
          final req = request(received, end);
          final usable = received == 0 && opening?.statusCode == 206 ? opening : null;
          opening = null;
          final response = usable ??
              await _dio.get<ResponseBody>(
                req.url.toString(),
                cancelToken: token,
                options: Options(
                  responseType: ResponseType.stream,
                  headers: req.headers,
                ),
              );
          if (response.statusCode != 206 && received > 0) throw _RangeIgnored(response.statusCode);
          await for (final chunk in response.data!.stream) {
            await raf.writeFrom(chunk);
            received += chunk.length;
            onBytes(received);
          }
        }, label: 'chunk at $received', link: request(0, 0).url);
      }
    } finally {
      final unused = opening;
      if (unused != null) unawaited(unused.data?.stream.listen(null).cancel());
      await raf.close();
    }
    if (received < total) {
      throw StateError('Download ended early ($received of $total bytes).');
    }
  }

  static const _journalName = 'written.json';

  @visibleForTesting
  static bool partComplete(String partPath, int total) {
    final part = File(partPath);
    // A part file with a journal has its full length as soon as the last piece lands, holes and all.
    return total > 0 &&
        part.existsSync() &&
        part.lengthSync() == total &&
        !Directory(DownloadTask.chunksDirOf(partPath)).existsSync();
  }

  static ({int chunk, List<int> written})? _readJournal(File journal, int total) {
    try {
      final j = jsonDecode(journal.readAsStringSync()) as Map<String, dynamic>;
      final written = (j['written'] as List).cast<int>();
      final chunk = j['chunk'] as int;
      if (j['total'] != total || chunk <= 0 || written.length != (total + chunk - 1) ~/ chunk) return null;
      return (chunk: chunk, written: written);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static int partBytesOnDisk(String partPath) {
    final chunks = DownloadTask.chunksDirOf(partPath);
    try {
      final j = jsonDecode(File('$chunks/$_journalName').readAsStringSync()) as Map<String, dynamic>;
      return (j['written'] as List).cast<int>().fold(0, (s, n) => s + n);
    } catch (_) {
      return _sizeOf(partPath) + _sizeOf(chunks);
    }
  }

  @visibleForTesting
  Future<void> fetchParallel(
    int total,
    String partPath,
    Directory chunksDir,
    int connections,
    RangeRequest request,
    CancelToken token,
    void Function(int) onBytes, {
    Response<ResponseBody>? first,
  }) async {
    var opening = first;
    try {
      await _fetchParallel(total, partPath, chunksDir, connections, request, token, onBytes, () {
        final r = opening;
        opening = null;
        return r?.statusCode == 206 ? r : null;
      });
    } finally {
      final unused = opening;
      if (unused != null) unawaited(unused.data?.stream.listen(null).cancel());
    }
  }

  Future<void> _fetchParallel(
    int total,
    String partPath,
    Directory chunksDir,
    int connections,
    RangeRequest request,
    CancelToken token,
    void Function(int) onBytes,
    Response<ResponseBody>? Function() takeFirst,
  ) async {
    await chunksDir.create(recursive: true);
    final part = File(partPath);
    final journal = File('${chunksDir.path}/$_journalName');
    final saved = _readJournal(journal, total);
    final legacy = chunksDir.listSync().whereType<File>().where((f) {
      final name = f.uri.pathSegments.last;
      return name != _journalName && !name.endsWith('.tmp');
    }).toList();
    // Pieces saved by an older version are 10 MB each; a resumed download keeps its piece size.
    final size = saved?.chunk ?? (legacy.isNotEmpty ? _chunk : pieceSizeFor(total, connections));
    final count = (total + size - 1) ~/ size;
    final written = saved?.written ?? List.filled(count, 0);

    final pieces = <_Piece>[];
    for (var i = 0; i < count; i++) {
      final start = i * size;
      final end = start + size > total ? total - 1 : start + size - 1;
      pieces.add(_Piece(start, end, written[i].clamp(0, end - start + 1), index: i));
    }

    Future<void> saveJournal() async {
      final tmp = File('${journal.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'total': total,
        'chunk': size,
        'written': [for (final p in pieces.where((p) => p.index != null)) p.saved],
      }));
      await tmp.rename(journal.path);
    }

    // Pieces saved by an older version, one file each: moved into the part file once.
    if (legacy.isNotEmpty) {
      final raf = await part.open(mode: FileMode.append);
      try {
        for (final f in legacy) {
          final i = int.tryParse(f.uri.pathSegments.last);
          if (i == null || i >= count) continue;
          final p = pieces[i];
          final have = f.lengthSync().clamp(0, p.end - p.start + 1);
          if (have <= p.saved) continue;
          await raf.setPosition(p.start);
          await for (final data in f.openRead(0, have)) {
            await raf.writeFrom(data);
          }
          p.written = p.saved = have;
        }
      } finally {
        await raf.close();
      }
      await saveJournal();
      for (final f in legacy) {
        await f.delete();
      }
    } else if (!journal.existsSync()) {
      await saveJournal();
    }

    var done = pieces.fold(0, (s, p) => s + p.saved);
    onBytes(done);

    final pending = Queue<_Piece>.of(pieces.where((p) => !p.complete));
    final active = <_Piece>{};
    // Idle connections wake when a piece ends instead of polling: the file is ready right after the last byte.
    var pieceEnded = Completer<void>();

    // Lets a failing worker stop its siblings without looking like a pause.
    final local = CancelToken();
    unawaited(token.whenCancel.then((e) => local.cancel(e.error)));

    var saving = Future<void>.value();
    void save() => saving = saving.then((_) => saveJournal()).catchError((Object e) {
          debugPrint('[Download] progress not saved: $e');
        });
    final saver = Timer.periodic(const Duration(seconds: 2), (_) => save());

    _Piece? steal() {
      // End game: an idle connection takes the second half of the piece with
      // the most left, so one throttled connection can't stall the last percent.
      _Piece? most;
      for (final p in active) {
        if (most == null || p.remaining > most.remaining) most = p;
      }
      if (most == null || most.remaining < _minSteal) return null;
      final mid = most.start + most.written + most.remaining ~/ 2;
      final tail = _Piece(mid, most.end, 0);
      most.end = mid - 1;
      pieces.add(tail);
      return tail;
    }

    Future<void> fetchPiece(_Piece p) async {
      active.add(p);
      final raf = await part.open(mode: FileMode.append);
      try {
        await _withRetries(() async {
          while (!p.complete) {
            // The opening answer only covers the start of the file: the rest of the piece is asked for after it.
            final opening = p.start + p.written == 0 ? takeFirst() : null;
            final req = request(p.start + p.written, p.end);
            final response = opening ??
                await _dio.get<ResponseBody>(
                  req.url.toString(),
                  cancelToken: local,
                  options: Options(
                    responseType: ResponseType.stream,
                    headers: req.headers,
                  ),
                );
            if (response.statusCode != 206 && p.start + p.written > 0) throw _RangeIgnored(response.statusCode);
            await raf.setPosition(p.start + p.written);
            await for (final chunk in response.data!.stream) {
              final room = p.remaining; // shrinks when a steal takes the tail
              if (room <= 0) break;
              final bytes = chunk.length > room ? chunk.sublist(0, room) : chunk;
              // Counted before the write: a steal during it splits after these.
              p.written += bytes.length;
              done += bytes.length;
              await raf.writeFrom(bytes);
              // Only bytes already written go into the journal: a kill then never skips missing ones.
              p.saved = p.written;
              onBytes(done);
              if (p.complete) break;
            }
            if (opening == null) break;
          }
        }, label: 'piece at ${p.start}', link: request(0, 0).url);
      } finally {
        active.remove(p);
        await raf.close();
        final ended = pieceEnded;
        pieceEnded = Completer<void>();
        ended.complete();
      }
      if (!p.complete) throw StateError('Piece at ${p.start} ended early.');
    }

    Future<void> worker() async {
      while (!local.isCancelled) {
        _checkStopped(token);
        final p = pending.isNotEmpty ? pending.removeFirst() : steal();
        if (p != null) {
          await fetchPiece(p);
        } else if (active.isEmpty) {
          return;
        } else {
          await Future.any([pieceEnded.future, Future<void>.delayed(const Duration(seconds: 1))]);
        }
      }
    }

    try {
      await Future.wait(
        List.generate(connections < 1 ? 1 : connections, (_) => worker()),
        eagerError: true,
      );
    } catch (_) {
      if (!local.isCancelled) local.cancel('sibling failed');
      rethrow;
    } finally {
      saver.cancel();
      save();
      await saving;
    }
    _checkStopped(token);

    final length = part.lengthSync();
    if (length < total) throw StateError('Download ended early ($length of $total bytes).');
    if (length > total) {
      final raf = await part.open(mode: FileMode.append);
      await raf.truncate(total);
      await raf.close();
    }
    await chunksDir.delete(recursive: true);
    onBytes(total);
  }

  /// Runs [attempt], backing off on network errors; gives up after 3 retries.
  Future<void> _withRetries(
    Future<void> Function() attempt, {
    required String label,
    Uri? link,
  }) async {
    var retries = 0;
    while (true) {
      try {
        return await attempt();
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        debugPrint(
          '[Download] $label failed: ${e.response?.statusCode ?? e.type}',
        );
        if (retries >= 3) rethrow;
        if (e.response == null && link != null && !await online(link)) rethrow;
        retries++;
        await Future<void>.delayed(retryBackoff * retries);
      }
    }
  }

  void _checkStopped(CancelToken token) {
    if (token.isCancelled) throw const _Stopped();
  }

  // ----------------------------------------------------------------- helpers

  static const _keepFinished = 200;

  // Files stay on disk; only the oldest finished entries leave the list.
  Future<void> _persist() {
    final old = tasks.where((t) => t.status.value == DownloadStatus.completed).skip(_keepFinished).toSet();
    if (old.isNotEmpty) tasks.removeWhere(old.contains);
    return _repo.save(tasks);
  }

  Future<int> _bytesOnDisk(DownloadTask t) {
    final work = _workDirOf(t);
    final paths = t.source != DownloadSource.direct
        ? [if (work.isNotEmpty) work]
        : const <String>[];
    if (t.source == DownloadSource.direct) {
      final part = t.partPath;
      return Isolate.run(() => partBytesOnDisk(part));
    }
    return Isolate.run(() => paths.fold<int>(0, (s, p) => s + _sizeOf(p)));
  }

  /// Size of a file, or of all files in a folder; 0 if missing.
  static int _sizeOf(String path) {
    try {
      switch (FileSystemEntity.typeSync(path, followLinks: false)) {
        case FileSystemEntityType.file:
          return File(path).lengthSync();
        case FileSystemEntityType.directory:
          return Directory(path)
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .fold(0, (s, f) => s + f.lengthSync());
        default:
          return 0;
      }
    } catch (_) {
      return 0;
    }
  }

  static const _publicRoot = '/storage/emulated/0/Download/${AppConstants.downloadFolderName}';

  @visibleForTesting
  static Future<Directory> resolveRootDir() async {
    if (Platform.isAndroid) {
      // Public Download/Toomu so files are visible to other apps.
      final public = Directory(_publicRoot);
      try {
        await public.create(recursive: true);
        final probe = File('${public.path}/.probe');
        await probe.writeAsString('ok');
        await probe.delete();
        return public;
      } catch (_) {
        final ext = await getExternalStorageDirectory();
        if (ext != null) return ext;
      }
    }
    if (HostOs.isWindows) {
      // %USERPROFILE%\Downloads\Toomu, where people look for downloads.
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return Directory('${downloads.path}/${AppConstants.downloadFolderName}');
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/${AppConstants.downloadFolderName}');
  }

  String _uniquePath(String dir, String base, String ext) =>
      uniquePath(dir, base, ext, taken: (p) => tasks.any((t) => t.filePath == p));

  /// `dir/base.ext`, or `dir/base (1).ext` etc. when that name is used on
  /// disk, by an unfinished download, or by [taken].
  @visibleForTesting
  static String uniquePath(String dir, String base, String ext, {bool Function(String path)? taken}) {
    var candidate = '$dir/$base.$ext';
    var i = 1;
    bool used(String p) => File(p).existsSync() || File('$p.part').existsSync() || (taken?.call(p) ?? false);
    while (used(candidate)) {
      candidate = '$dir/$base ($i).$ext';
      i++;
    }
    return candidate;
  }

  /// Deletes a file or folder; returns the bytes freed (0 if missing/failed).
  Future<int> _deleteQuietly(String path) => Isolate.run(() => _deleteSync(path));

  static int _deleteSync(String path) {
    final size = _sizeOf(path);
    try {
      switch (FileSystemEntity.typeSync(path, followLinks: false)) {
        case FileSystemEntityType.file:
          File(path).deleteSync();
        case FileSystemEntityType.directory:
          Directory(path).deleteSync(recursive: true);
        default:
          return 0;
      }
      return size;
    } catch (_) {
      return 0;
    }
  }

  @override
  void onClose() {
    for (final t in _running.values) {
      t.cancel('pause');
    }
    super.onClose();
  }
}

@visibleForTesting
/// Turns yt-dlp / aria2c output into download progress. HD downloads fetch
/// video then audio, so finished stages are added up.
class YtDlpProgress {
  YtDlpProgress(this.task, this.onBytes, {this.onFirstBytes});

  final DownloadTask task;
  final void Function(int) onBytes;

  /// Called once, when the first bytes arrive (timing log).
  final void Function()? onFirstBytes;
  bool _gotBytes = false;

  /// Native downloader: bytes per format id (from --progress-template).
  final _perFormat = <String, ({int done, int total})>{};

  /// aria2c: bytes of finished stages + the current one.
  int _stageBase = 0;
  int _stageDone = 0;
  int _stageTotal = 0;
  int _stages = 0;

  static final _template = RegExp(r'^\[toomu\] (\S+) (\S+) (\S+) (\S+) (\S+)');
  static final _aria2c = RegExp(
    r'\[#\w+\s+([\d.]+)([KMG]?i?B)/([\d.]+)([KMG]?i?B)\(\d+%\)',
  );

  void reset() {
    _perFormat.clear();
    _stageBase = _stageDone = _stageTotal = _stages = 0;
  }

  void onLine(String line) {
    // Extraction done ("[info] …: Downloading 1 format(s): 137+140"):
    // connecting now.
    if (task.phase.value == DownloadPhase.lookingUp &&
        (line.startsWith('[info]') && line.contains('Downloading') ||
            line.contains('[download] Destination:'))) {
      task.phase.value = DownloadPhase.starting;
    }
    final t = _template.firstMatch(line);
    if (t != null) {
      final done = _num(t[2]);
      final total = _num(t[3]) > 0 ? _num(t[3]) : _num(t[4]);
      _perFormat[t[1]!] = (done: done, total: total);
      _report(
        _perFormat.values.fold(0, (s, f) => s + f.done),
        _perFormat.values.fold(0, (s, f) => s + f.total),
        stage: _perFormat.length,
      );
      return;
    }
    if (line.contains('[download] Destination:')) {
      // A new file starts (video, then audio).
      _stageBase += _stageTotal;
      _stageDone = _stageTotal = 0;
      _stages++;
      return;
    }
    final a = _aria2c.firstMatch(line);
    if (a != null) {
      _stageDone = _bytes(a[1]!, a[2]!);
      _stageTotal = _bytes(a[3]!, a[4]!);
      _report(
        _stageBase + _stageDone,
        _stageBase + _stageTotal,
        stage: _stages,
      );
      return;
    }
    if (line.contains('[Merger]') || line.contains('[VideoRemuxer]')) {
      task.phase.value = DownloadPhase.merging;
    } else if (line.contains('[ExtractAudio]')) {
      task.phase.value = DownloadPhase.converting;
    }
  }

  void _report(int done, int total, {required int stage}) {
    if (total > task.totalBytes.value) task.totalBytes.value = total;
    onBytes(done);
    if (!_gotBytes && done > 0) {
      _gotBytes = true;
      onFirstBytes?.call();
    }
    // Still "starting" until bytes actually flow.
    if (done <= 0 &&
        (task.phase.value == DownloadPhase.lookingUp ||
            task.phase.value == DownloadPhase.starting)) {
      return;
    }
    task.phase.value = task.kind == DownloadKind.audio || stage > 1
        ? DownloadPhase.audio
        : DownloadPhase.video;
  }

  static int _num(String? s) =>
      s == null ? 0 : (double.tryParse(s)?.round() ?? 0);

  static int _bytes(String value, String unit) {
    final v = double.tryParse(value) ?? 0;
    final mult = switch (unit) {
      'KiB' || 'KB' => 1024,
      'MiB' || 'MB' => 1024 * 1024,
      'GiB' || 'GB' => 1024 * 1024 * 1024,
      _ => 1,
    };
    return (v * mult).round();
  }
}

class _Piece {
  _Piece(this.start, this.end, this.written, {this.index}) : saved = written;

  final int start;
  int end; // inclusive; lowered when another connection takes the tail

  final int? index;
  int written;
  int saved;

  int get remaining => end - start - written + 1;
  bool get complete => remaining <= 0;
}
