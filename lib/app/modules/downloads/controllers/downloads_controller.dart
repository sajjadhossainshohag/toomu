import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/shell_open.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_item.dart';
import '../../../routes/app_pages.dart';
import '../../browser/controllers/browser_session.dart';
import '../../home/controllers/home_controller.dart';
import '../../private_folder/controllers/private_folder_controller.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../services/media_scanner_service.dart';
import '../../../services/video_session_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/selection_header.dart';

class DownloadsController extends GetxController {
  final DownloadService _service = DownloadService.to;

  /// 0 = Active, 1 = Completed
  final tab = 0.obs;
  final selection = Selection();
  List<Worker> _clearers = const [];

  @override
  void onClose() {
    for (final w in _clearers) {
      w.dispose();
    }
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    _clearers = selection.clearOnChange([tab, if (Get.isRegistered<HomeController>()) Get.find<HomeController>().tabIndex]);
  }

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

  /// Opens the page again to find the file's new link: in a tab of the
  /// browser if it's already open (its Downloads sheet), else the browser.
  void refreshLink(DownloadTask t) {
    if (Get.isRegistered<BrowserSession>()) {
      Get.until((route) => route.settings.name == Routes.browser);
      BrowserSession.to.newTab(refreshFor: t);
      return;
    }
    Get.toNamed(Routes.browser, arguments: t);
  }

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
    final exists = await File(t.filePath).exists();
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
      final candidates = completed.where((c) => c.kind == DownloadKind.video).toList();
      final present = await Future.wait(candidates.map((c) => File(c.filePath).exists()));
      final videos = [
        for (var i = 0; i < candidates.length; i++)
          if (present[i]) candidates[i],
      ];
      await Get.toNamed(
        Routes.videoPlayer,
        arguments: VideoPlaylist(
          videos.map((c) => VideoItem.file(c.filePath, title: c.title)).toList(),
          videos.indexOf(t).clamp(0, videos.length - 1),
        ),
      );
    } else {
      await openFile(t.filePath);
    }
  }

  Future<void> share(DownloadTask t) => SharePlus.instance.share(
    ShareParams(files: [XFile(t.filePath)], text: t.title),
  );

  List<DownloadTask> get _shown => tab.value == 0 ? active : completed;

  List<DownloadTask> get _selected {
    // A download that finished while selected moved to the other tab, out of sight: it's dropped, never acted on.
    final picked = selection.pick(_shown, (t) => t.id);
    selection.ids.retainAll(picked.map((t) => t.id));
    return picked;
  }

  void selectAll() => selection.selectAll(_shown.map((t) => t.id));

  Future<void> deleteSelected() async {
    if (await delete(_selected)) selection.clear();
  }

  Future<void> moveSelectedToPrivate() async {
    if (await moveToPrivate(_selected)) selection.clear();
  }

  Future<bool> moveToPrivate(List<DownloadTask> list) async {
    final done = list.where((t) => t.status.value == DownloadStatus.completed).toSet();
    if (done.isEmpty) {
      showSnack('Nothing to move', 'Only finished downloads can be moved to the private folder.');
      return false;
    }
    // Only the files are deleted here: a task leaves the list once its file is really gone.
    final moved = await moveToPrivateFolder(
      [for (final t in list) (path: done.contains(t) ? t.filePath : null, title: t.title)],
      (paths) async {
        for (final p in paths) {
          try {
            await File(p).delete();
          } on FileSystemException catch (e) {
            debugPrint('[Downloads] private move: $e');
          }
          await MediaScannerService.to.scan(p);
        }
      },
    );
    if (moved.isNotEmpty) reloadLibraries();
    return moved.isNotEmpty;
  }

  /// Long-press menu "Delete" / "Cancel download": confirm, then remove.
  Future<bool> delete(List<DownloadTask> list) async {
    if (list.isEmpty) return false;
    final choice = await _confirmDelete(list);
    if (choice == null) return false;
    final finished = list.where((t) => t.status.value == DownloadStatus.completed).toList();
    final unfinished = list.where((t) => !finished.contains(t)).toList();
    // Partial files are always cleaned; only finished files are optional.
    final freed = await _service.removeMany(unfinished, deleteFiles: true) +
        await _service.removeMany(finished, deleteFiles: choice);
    if (choice) await VideoSessionService.to.stopIfPlaying(finished.map((t) => t.filePath));
    if (list.length == 1) {
      _reportFreed(freed, fallback: 'Removed from downloads');
    } else {
      Get.closeAllSnackbars();
      showSnack(
        'Deleted ${list.length}',
        freed > 0 ? '${Formatters.bytes(freed)} cleaned up' : 'Removed from downloads',
        duration: const Duration(seconds: 2),
      );
    }
    return true;
  }

  Future<bool?> _confirmDelete(List<DownloadTask> list) async {
    final finished = list.where((t) => t.status.value == DownloadStatus.completed).toList();
    final stats = await Future.wait(finished.map((t) => FileStat.stat(t.filePath)));
    final onDisk = stats.where((s) => s.type != FileSystemEntityType.notFound).toList();
    final size = onDisk.fold<int>(0, (sum, s) => sum + s.size);
    final one = list.length == 1;
    final allDone = finished.length == list.length;
    final choice = await showDeleteDialog(
      title: !one ? 'Delete ${list.length} downloads?' : (allDone ? 'Delete download?' : 'Cancel download?'),
      message: !one
          ? 'They will be removed from your downloads.${allDone ? '' : ' Unfinished ones stop and their partial files are removed.'}'
          : allDone
              ? '"${list.first.title}" will be removed from your downloads.'
              : 'The download stops and its partial files are removed.',
      confirmLabel: one && !allDone ? 'Cancel download' : 'Delete',
      fileToggleLabel: onDisk.isEmpty
          ? null
          : 'Also delete ${onDisk.length == 1 ? 'file' : 'files'} from device (${Formatters.bytes(size)})',
    );
    return choice?.deleteFiles;
  }

  Future<void> clearCompleted() async {
    final count = completed.length;
    if (count == 0) return;
    final bytes = await _service.completedBytesOnDisk();
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
