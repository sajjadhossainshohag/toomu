import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/video_item.dart';
import '../../../data/providers/local_video_provider.dart';
import '../../../routes/app_pages.dart';
import '../../../services/download_service.dart';
import '../../../services/permission_service.dart';
import '../../../services/video_session_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/option_sheet.dart';
import '../../private_folder/controllers/private_folder_controller.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../home/controllers/home_controller.dart';
import '../../home/home_tabs.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/selection_header.dart';

enum VideoSort { recent, name, size, duration }

class VideoFolder {
  const VideoFolder(this.name, this.videos);

  final String name;
  final List<VideoItem> videos;

  int get totalBytes => videos.fold(0, (s, v) => s + v.size);
}

/// MX-style video library: folders and all videos from the device.
class VideosController extends GetxController {
  final _provider = LocalVideoProvider();

  static const tabs = <String>['Videos', 'Folders'];

  final tab = 0.obs;
  final loading = false.obs;
  final hasPermission = true.obs;
  final query = ''.obs;
  final selection = Selection();
  List<Worker> _clearers = const [];
  final sort = VideoSort.recent.obs;
  final _all = <VideoItem>[].obs;
  final _filter = ''.obs;
  // Sorting thousands of videos on every rebuild stutters; kept until the
  // videos or the sort order change.
  List<VideoItem>? _sorted;
  VideoSort? _sortedBy;

  /// Bumped when coming back from the player so resume bars refresh.
  final watchedVersion = 0.obs;

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
    debounce(query, (String q) => _filter.value = q, time: const Duration(milliseconds: 200));
    _clearers = selection.clearOnChange([tab, if (Get.isRegistered<HomeController>()) Get.find<HomeController>().tabIndex]);
  }

  @override
  void onReady() {
    super.onReady();
    // Swiping builds neighbouring tabs early; only scan (and ask for the
    // permission) once this tab is actually shown.
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().whenTabShown(HomeTabs.videos, load);
    } else {
      load();
    }
  }

  Future<void> load() async {
    loading.value = true;
    hasPermission.value = await PermissionService.to.requestVideo();
    if (hasPermission.value) {
      try {
        final found = await _provider.videos();
        _sorted = null;
        _all.assignAll(found);
      } catch (e) {
        debugPrint('[Videos] library query failed: $e');
        showSnack('Videos', ErrorText.of(e));
      }
    }
    loading.value = false;
  }

  int get total => _all.length;

  List<VideoItem> get videos {
    final q = _filter.value.trim().toLowerCase();
    final sorted = _sortedVideos();
    return q.isEmpty
        ? [...sorted]
        : sorted
            .where((v) => v.title.toLowerCase().contains(q) || (v.folder?.toLowerCase().contains(q) ?? false))
            .toList();
  }

  List<VideoItem> _sortedVideos() {
    final by = sort.value;
    final all = _all.toList(); // read on every call so Obx keeps listening
    final cached = _sorted;
    if (cached != null && _sortedBy == by) return cached;
    switch (by) {
      case VideoSort.recent:
        all.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case VideoSort.name:
        final keys = {for (final v in all) v: v.title.toLowerCase()};
        all.sort((a, b) => keys[a]!.compareTo(keys[b]!));
      case VideoSort.size:
        all.sort((a, b) => b.size.compareTo(a.size));
      case VideoSort.duration:
        all.sort((a, b) => (b.duration ?? Duration.zero).compareTo(a.duration ?? Duration.zero));
    }
    _sortedBy = by;
    return _sorted = all;
  }

  List<VideoFolder> get folders {
    final map = <String, List<VideoItem>>{};
    for (final v in videos) {
      map.putIfAbsent(v.folder ?? 'Other', () => []).add(v);
    }
    return map.entries.map((e) => VideoFolder(e.key, e.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> pickSort() async {
    final picked = await showOptionSheet<VideoSort>(
      title: 'Sort videos by',
      selected: sort.value,
      options: const <SheetOption<VideoSort>>[
        SheetOption(value: VideoSort.recent, label: 'Recently added', icon: Icons.schedule_rounded),
        SheetOption(value: VideoSort.name, label: 'Name', icon: Icons.sort_by_alpha_rounded),
        SheetOption(value: VideoSort.size, label: 'Size', icon: Icons.sd_storage_rounded),
        SheetOption(value: VideoSort.duration, label: 'Length', icon: Icons.timer_outlined),
      ],
    );
    if (picked != null) sort.value = picked;
  }

  /// Plays [item] with the rest of [list] as its playlist (next/previous).
  Future<void> play(List<VideoItem> list, VideoItem item) async {
    await Get.toNamed(Routes.videoPlayer, arguments: VideoPlaylist(list, list.indexOf(item)));
    watchedVersion.value++;
  }

  void openFolder(VideoFolder folder) {
    selection.clear();
    Get.toNamed(Routes.videoFolder, arguments: folder);
  }

  Future<void> showMenu(VideoItem v) async {
    final action = await showOptionSheet<String>(
      title: v.title,
      options: const <SheetOption<String>>[
        SheetOption(value: 'private', label: 'Move to private folder', icon: Icons.lock_outline_rounded),
      ],
    );
    if (action == 'private' && v.id != null) await moveToPrivate([v]);
  }

  List<VideoItem> get _selected => selection.pick(_all, (v) => v.uri).where((v) => v.id != null).toList();

  void selectAll(Iterable<VideoItem> list) => selection.selectAll(list.map((v) => v.uri));

  Future<void> deleteSelected() async {
    final list = _selected;
    if (list.isEmpty) return;
    final one = list.length == 1;
    final ok = await showConfirmDialog(
      title: one ? 'Delete video?' : 'Delete ${list.length} videos?',
      message: '${one ? '"${list.first.title}"' : 'These videos'} will be permanently deleted from this device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    var accepted = false;
    try {
      accepted = await _provider.delete([for (final v in list) v.id!]);
    } catch (e) {
      showSnack('Could not delete', ErrorText.of(e));
    }
    // Judged on disk: Android deletes Toomu's own files even when its dialog for the others is declined.
    final gone = list.where((v) => v.path == null ? accepted : !File(v.path!).existsSync()).toList();
    if (gone.isEmpty) return;
    _forget(gone);
    await VideoSessionService.to.stopIfPlaying([for (final v in gone) ?v.path]);
    for (final v in gone) {
      if (v.path != null) await DownloadService.to.forgetFile(v.path!);
    }
    selection.clear();
    final failed = list.length - gone.length;
    showSnack(
      one ? 'Deleted' : 'Deleted ${gone.length}',
      failed > 0 ? "$failed couldn't be deleted" : (one ? list.first.title : 'Videos removed from this device'),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> moveSelectedToPrivate() async {
    if (await moveToPrivate(_selected)) selection.clear();
  }

  Future<bool> moveToPrivate(List<VideoItem> list) async {
    final moved = await moveToPrivateFolder(
      [for (final v in list) (path: v.path, title: v.title)],
      (paths) => _provider.delete([
        for (final v in list)
          if (paths.contains(v.path)) v.id!,
      ]),
    );
    _forget(list.where((v) => moved.contains(v.path)));
    return moved.isNotEmpty;
  }

  void _forget(Iterable<VideoItem> gone) {
    final uris = {for (final v in gone) v.uri};
    _sorted = null;
    _all.removeWhere((v) => uris.contains(v.uri));
  }
}
