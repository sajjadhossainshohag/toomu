import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_item.dart';
import '../../../routes/app_pages.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snackbar.dart';

class DownloadsController extends GetxController {
  final DownloadService _service = DownloadService.to;

  /// 0 = Active, 1 = Completed
  final tab = 0.obs;

  RxList<DownloadTask> get tasks => _service.tasks;

  List<DownloadTask> get active =>
      tasks.where((t) => t.status.value != DownloadStatus.completed).toList();

  List<DownloadTask> get completed =>
      tasks.where((t) => t.status.value == DownloadStatus.completed).toList();

  bool get anyRunning => tasks.any((t) => t.isActive);

  void pause(DownloadTask t) => _service.pause(t);
  void resume(DownloadTask t) => _service.resume(t);
  void pauseAll() => _service.pauseAll();
  void resumeAll() => _service.resumeAll();

  void refreshLink(DownloadTask t) => Get.toNamed(Routes.browser, arguments: t);

  void toggle(DownloadTask t) {
    switch (t.status.value) {
      case DownloadStatus.running:
      case DownloadStatus.queued:
        pause(t);
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        resume(t);
      case DownloadStatus.completed:
        open(t);
      case DownloadStatus.canceled:
        break;
    }
  }

  /// Audio plays in Toomu's player; video opens in the system player.
  Future<void> open(DownloadTask t) async {
    final exists = File(t.filePath).existsSync();
    debugPrint('[Downloads] open ${t.kind.name}: ${t.filePath.split('/').last} (${exists ? 'found' : 'MISSING'})');
    if (!exists) {
      showSnack('File missing', 'The file was moved or deleted.');
      return;
    }
    try {
      await _open(t);
    } catch (e) {
      debugPrint('[Downloads] open failed: $e');
      showSnack("Can't open this file", '$e');
    }
  }

  Future<void> _open(DownloadTask t) async {
    if (t.kind == DownloadKind.audio) {
      final audioTasks = completed
          .where((c) => c.kind == DownloadKind.audio)
          .toList();
      final tracks = audioTasks.map(_toTrack).toList();
      await AudioPlayerService.to.playTracks(
        tracks,
        index: audioTasks.indexOf(t).clamp(0, tracks.length - 1),
      );
    } else if (t.kind == DownloadKind.video) {
      // Play downloaded videos in Toomu's player, with the other downloaded
      // videos as the playlist.
      final videos = completed
          .where(
            (c) =>
                c.kind == DownloadKind.video && File(c.filePath).existsSync(),
          )
          .toList();
      await Get.toNamed(
        Routes.videoPlayer,
        arguments: VideoPlaylist(
          videos.map((c) => VideoItem.file(c.filePath, title: c.title)).toList(),
          videos.indexOf(t).clamp(0, videos.length - 1),
        ),
      );
    } else {
      await OpenFilex.open(t.filePath);
    }
  }

  Future<void> share(DownloadTask t) => SharePlus.instance.share(
    ShareParams(files: [XFile(t.filePath)], text: t.title),
  );

  /// Long-press menu "Delete" / "Cancel download": confirm, then remove.
  Future<void> delete(DownloadTask t) async {
    final choice = await _confirmDelete(t);
    if (choice == null) return;
    final freed = await _service.remove(t, deleteFile: choice);
    _reportFreed(freed, fallback: 'Removed from downloads');
  }

  /// Asks how to delete [t]. Returns whether to delete the file too, or
  /// null if the user cancelled.
  Future<bool?> _confirmDelete(DownloadTask t) async {
    final finished = t.status.value == DownloadStatus.completed;
    final exists = finished && File(t.filePath).existsSync();
    final size = exists
        ? ' (${Formatters.bytes(File(t.filePath).lengthSync())})'
        : '';
    final choice = await showDeleteDialog(
      title: finished ? 'Delete download?' : 'Cancel download?',
      message: finished
          ? '"${t.title}" will be removed from your downloads.'
          : 'The download stops and its partial files are removed.',
      confirmLabel: finished ? 'Delete' : 'Cancel download',
      // Partial files are always cleaned; only finished files are optional.
      fileToggleLabel: exists ? 'Also delete file from device$size' : null,
    );
    if (choice == null) return null;
    return finished ? choice.deleteFiles : true;
  }

  Future<void> clearCompleted() async {
    final count = completed.length;
    if (count == 0) return;
    final bytes = _service.completedBytesOnDisk();
    final choice = await showDeleteDialog(
      title: 'Clear completed?',
      message:
          'Removes $count finished download${count == 1 ? '' : 's'} from the list.',
      confirmLabel: 'Clear',
      fileToggleLabel: bytes > 0
          ? 'Also delete files from device (${Formatters.bytes(bytes)})'
          : null,
      deleteFilesByDefault: false,
    );
    if (choice == null) return;
    final freed = await _service.clearCompleted(
      deleteFiles: choice.deleteFiles,
    );
    _reportFreed(freed, fallback: 'History cleared');
  }

  /// Removes leftover temp files from interrupted downloads.
  Future<void> cleanTemporaryFiles() async {
    final freed = await _service.cleanTemporaryFiles();
    _reportFreed(freed, fallback: 'No temporary files to clean');
  }

  void _reportFreed(int bytes, {required String fallback}) {
    Get.closeAllSnackbars();
    showSnack(
      bytes > 0 ? 'Storage freed' : 'Done',
      bytes > 0 ? '${Formatters.bytes(bytes)} cleaned up' : fallback,
      duration: const Duration(seconds: 2),
    );
  }

  Track _toTrack(DownloadTask t) => Track(
    id: 'dl:${t.id}',
    title: t.title,
    album: 'Toomu downloads',
    uri: Uri.file(t.filePath).toString(),
    path: t.filePath,
    artworkUrl: t.thumbnailUrl.isEmpty ? null : t.thumbnailUrl,
  );
}
