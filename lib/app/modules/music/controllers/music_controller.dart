import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/track.dart';
import '../../../data/providers/local_music_provider.dart';
import '../../../routes/app_pages.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../services/permission_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../home/controllers/home_controller.dart';
import '../../home/home_tabs.dart';
import '../../private_folder/controllers/private_folder_controller.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/selection_header.dart';

enum SongSort { title, recent, duration }

/// A named group of tracks (album, artist, folder) passed to CollectionView.
class MusicCollection {
  const MusicCollection({required this.title, required this.subtitle, required this.tracks});

  final String title;
  final String subtitle;
  final List<Track> tracks;
}

class MusicController extends GetxController {
  final LocalMusicProvider _provider = LocalMusicProvider();
  final AudioPlayerService audio = AudioPlayerService.to;

  static const tabs = <String>['Songs', 'Albums', 'Folders', 'Favorites'];

  final tab = 0.obs;
  final loading = false.obs;
  final hasPermission = true.obs;
  final query = ''.obs;
  final selection = Selection();
  List<Worker> _clearers = const [];
  final sort = SongSort.title.obs;
  final _all = <Track>[].obs;
  // Sorting thousands of titles on every search keystroke stutters; the
  // sorted library is kept until the songs or the sort order change.
  List<Track>? _sorted;
  SongSort? _sortedBy;
  // The four tabs all filter the same songs: one pass per search, not four.
  final _filter = ''.obs;
  List<Track>? _filtered, _filteredFrom;
  String? _filteredFor;

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
      Get.find<HomeController>().whenTabShown(HomeTabs.music, load);
    } else {
      load();
    }
  }

  Future<void> load() async {
    loading.value = true;
    hasPermission.value = await PermissionService.to.requestAudio();
    if (hasPermission.value) {
      try {
        final found = await _provider.songs();
        _sorted = null;
        _all.assignAll(found);
      } catch (e) {
        debugPrint('[Music] library query failed: $e');
        _sorted = null;
        _all.clear();
        showSnack('Music library', ErrorText.of(e));
      }
    }
    loading.value = false;
  }

  int get totalSongs => _all.length;

  List<Track> get songs => [..._filteredSongs()];

  List<Track> _filteredSongs() {
    final q = _filter.value.trim().toLowerCase();
    final sorted = _sortedSongs();
    if (q.isEmpty) return sorted;
    final cached = _filtered;
    if (cached != null && _filteredFor == q && identical(_filteredFrom, sorted)) return cached;
    _filteredFor = q;
    _filteredFrom = sorted;
    return _filtered = sorted
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.displayAlbum.toLowerCase().contains(q))
        .toList();
  }

  List<Track> _sortedSongs() {
    final by = sort.value;
    final all = _all.toList(); // read on every call so Obx keeps listening
    final cached = _sorted;
    if (cached != null && _sortedBy == by) return cached;
    switch (by) {
      case SongSort.title:
        final keys = {for (final t in all) t: t.title.toLowerCase()};
        all.sort((a, b) => keys[a]!.compareTo(keys[b]!));
      case SongSort.recent:
        all.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
      case SongSort.duration:
        all.sort((a, b) => (b.duration ?? Duration.zero).compareTo(a.duration ?? Duration.zero));
    }
    _sortedBy = by;
    return _sorted = all;
  }

  List<MusicCollection> get albums => _group((t) => t.displayAlbum, null);
  List<MusicCollection> get folders => _group(
        (t) => t.folder?.split('/').last ?? 'Unknown',
        (t) => t.folder ?? '',
      );

  List<Track> get favorites =>
      _filteredSongs().where((t) => audio.favorites.contains(t.id)).toList();

  List<MusicCollection> _group(
      String Function(Track) key, String Function(Track)? sub) {
    final map = <String, List<Track>>{};
    for (final t in _filteredSongs()) {
      map.putIfAbsent(key(t), () => []).add(t);
    }
    final groups = map.entries.map((e) {
      final n = e.value.length;
      final count = '$n song${n == 1 ? '' : 's'}';
      return MusicCollection(
        title: e.key,
        subtitle: sub == null ? count : '${sub(e.value.first)} • $count',
        tracks: e.value,
      );
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return groups;
  }

  // ---------------------------------------------------------------- actions

  void play(List<Track> list, Track t) => audio.playTracks(list, index: list.indexOf(t));
  void playAll(List<Track> list) => audio.playTracks(list);
  void shuffleAll(List<Track> list) => audio.shuffleAll(list);
  void playNext(Track t) => audio.playNext(t);
  void addToQueue(Track t) => audio.addToQueue(t);
  void toggleFavorite(Track t) => audio.toggleFavorite(t);

  Future<void> share(Track t) async {
    if (t.path == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(t.path!)], text: t.title));
  }

  List<Track> get _selected => selection.pick(_all, (t) => t.id).where((t) => t.localSongId != null).toList();

  void selectAll() => selection.selectAll((tab.value == 3 ? favorites : songs).map((t) => t.id));

  Future<void> deleteSelected() async {
    if (await delete(_selected)) selection.clear();
  }

  Future<void> moveSelectedToPrivate() async {
    if (await moveToPrivate(_selected)) selection.clear();
  }

  Future<bool> delete(List<Track> list) async {
    if (list.isEmpty) return false;
    final one = list.length == 1;
    final ok = await showConfirmDialog(
      title: one ? 'Delete song?' : 'Delete ${list.length} songs?',
      message: '${one ? '"${list.first.title}"' : 'These songs'} will be permanently deleted from this device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
    var accepted = false;
    try {
      accepted = await _provider.delete([for (final t in list) t.localSongId!]);
    } catch (e) {
      showSnack('Could not delete', ErrorText.of(e));
    }
    // Judged on disk: Android deletes Toomu's own files even when its dialog for the others is declined.
    final gone = list.where((t) => t.path == null ? accepted : !File(t.path!).existsSync()).toList();
    for (final t in gone) {
      await _forget(t);
    }
    if (gone.isEmpty) return false;
    final failed = list.length - gone.length;
    showSnack(
      one ? 'Deleted' : 'Deleted ${gone.length}',
      failed > 0 ? "$failed couldn't be deleted" : (one ? list.first.title : 'Songs removed from this device'),
      duration: const Duration(seconds: 2),
    );
    return true;
  }

  Future<bool> moveToPrivate(List<Track> list) async {
    final moved = await moveToPrivateFolder(
      [for (final t in list) (path: t.path, title: t.title)],
      (paths) => _provider.delete([
        for (final t in list)
          if (paths.contains(t.path)) t.localSongId!,
      ]),
    );
    for (final t in list) {
      if (moved.contains(t.path)) await _forget(t);
    }
    return moved.isNotEmpty;
  }

  Future<void> _forget(Track t) async {
    _sorted = null;
    _all.removeWhere((s) => s.id == t.id);
    await audio.removeTrack(t.id);
    if (audio.favorites.contains(t.id)) audio.toggleFavorite(t);
    if (t.path != null) await DownloadService.to.forgetFile(t.path!);
  }

  void openCollection(MusicCollection c) =>
      Get.toNamed(Routes.musicCollection, arguments: c);
}
