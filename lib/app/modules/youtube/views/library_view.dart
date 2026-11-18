import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/segmented_tabs.dart';
import '../controllers/youtube_controller.dart';
import 'widgets/video_row.dart';

/// What you watched and what you saved for later: your YouTube account's lists when signed in, else the phone's.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  var _later = false;

  @override
  void initState() {
    super.initState();
    Get.find<YoutubeController>().loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();

    return Scaffold(
      backgroundColor: ColorConstants.pageOn(dark),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(4 * scale, 4 * scale, 8 * scale, 0),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: Get.back,
                    icon: Icon(Icons.arrow_back_rounded, color: ink),
                  ),
                  Expanded(
                    child: Text(
                      'Library',
                      style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w800, color: ink),
                    ),
                  ),
                  // Signed in, clearing would wipe the YouTube account's history: that stays on youtube.com.
                  if (!_later && !yt.onAccount)
                    Obx(
                      () => TextButton(
                        onPressed: yt.watched.isEmpty
                            ? null
                            : () async {
                                final ok = await showConfirmDialog(
                                  title: 'Clear watch history?',
                                  message: 'Every video you watched leaves the list. Downloads stay.',
                                  confirmLabel: 'Clear',
                                  destructive: true,
                                );
                                if (ok) yt.clearWatched();
                              },
                        child: const Text('Clear'),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 8 * scale),
              child: SegmentedTabs(
                labels: const <String>['History', 'Watch later'],
                selected: _later ? 1 : 0,
                onSelect: (i) => setState(() => _later = i == 1),
              ),
            ),
            Expanded(
              child: Obx(() {
                final List<Video> list = _later ? yt.watchLater : yt.watched;
                if (list.isEmpty) {
                  if (yt.libraryLoading.value) return const Center(child: CircularProgressIndicator());
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(32 * scale),
                      child: Text(
                        _later
                            ? 'Nothing saved yet. Save a video from its ⋮ menu or its watch page.'
                            : "Videos you watch show up here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ink.withValues(alpha: 0.6)),
                      ),
                    ),
                  );
                }
                final removable = _later || !yt.onAccount;
                return RefreshIndicator(
                  onRefresh: yt.loadLibrary,
                  child: ListView.builder(
                  padding: EdgeInsets.only(bottom: 16 * scale),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final v = list[i];
                    if (!removable) return VideoRow(video: v, onTap: () => yt.watchFromCard(v));
                    return Dismissible(
                      key: ValueKey('${_later ? 'later' : 'seen'}:${v.id.value}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _later ? yt.toggleWatchLater(v) : yt.removeWatched(v),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: EdgeInsets.only(right: 20 * scale),
                        color: ColorConstants.error.withValues(alpha: 0.15),
                        child: const Icon(Icons.delete_outline_rounded, color: ColorConstants.error),
                      ),
                      child: VideoRow(video: v, onTap: () => yt.watchFromCard(v)),
                    );
                  },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
