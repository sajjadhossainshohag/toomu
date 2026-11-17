import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/video_item.dart';
import '../../../data/providers/local_video_provider.dart';
import '../../../routes/app_pages.dart';
import '../../../services/permission_service.dart';
import '../../../widgets/option_sheet.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../home/controllers/home_controller.dart';
import '../../home/home_tabs.dart';
import '../../../widgets/app_snackbar.dart';

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

  static const tabs = <String>['Folders', 'All videos'];

  final tab = 0.obs;
  final loading = false.obs;
  final hasPermission = true.obs;
  final query = ''.obs;
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
  void onInit() {
    super.onInit();
    debounce(query, (String q) => _filter.value = q, time: const Duration(milliseconds: 200));
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

  void openFolder(VideoFolder folder) => Get.toNamed(Routes.videoFolder, arguments: folder);
}
