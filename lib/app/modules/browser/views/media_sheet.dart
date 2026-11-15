import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/captured_media.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/media_format.dart';
import '../../../data/models/yt_info.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/track_artwork.dart';
import '../controllers/browser_controller.dart';

Future<void> showMediaSheet(BrowserController c) =>
    Get.bottomSheet<void>(_MediaSheet(controller: c), isScrollControlled: true);

class _MediaSheet extends StatefulWidget {
  const _MediaSheet({required this.controller});

  final BrowserController controller;

  @override
  State<_MediaSheet> createState() => _MediaSheetState();
}

class _MediaSheetState extends State<_MediaSheet> {
  BrowserController get c => widget.controller;

  bool _audioTab = false;
  bool _selecting = false;
  final Set<CapturedMedia> _selected = {};

  @override
  void initState() {
    super.initState();
    // Nothing caught on this page: let yt-dlp read it (its site extractors
    // find videos the page script can't see).
    if (c.capture.items.isEmpty && c.pageResult.value == null) c.searchPage();
  }

  Future<void> _downloadSelected() async {
    final picked = _selected.toList();
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    for (final m in picked) {
      await c.downloadMedia(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return AppSheet(
      title: 'Media on this page',
      trailing: Obx(
        () => c.capture.items.where(_downloadable).length > 1
            ? TextButton(
                onPressed: () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
                child: Text(_selecting ? 'Cancel' : 'Select'),
              )
            : const SizedBox.shrink(),
      ),
      child: Obx(() {
        final all = c.capture.items.toList();
        final audio = all.where((m) => m.kind == DownloadKind.audio).toList();
        final video = all.where((m) => m.kind != DownloadKind.audio).toList();
        final tabs = audio.isNotEmpty && video.isNotEmpty;
        final list = !tabs ? all : (_audioTab ? audio : video);
        final page = c.pageResult.value;
        final searching = c.searching.value;
        final error = c.searchError.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (tabs)
              Padding(
                padding: EdgeInsets.only(bottom: 8 * scale),
                child: Wrap(
                  spacing: 8 * scale,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text('Video (${video.length})'),
                      selected: !_audioTab,
                      onSelected: (_) => setState(() => _audioTab = false),
                    ),
                    ChoiceChip(
                      label: Text('Audio (${audio.length})'),
                      selected: _audioTab,
                      onSelected: (_) => setState(() => _audioTab = true),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final m in list)
                    _MediaTile(
                      media: m,
                      controller: c,
                      selecting: _selecting,
                      selected: _selected.contains(m),
                      onSelect: (v) => setState(() => v ? _selected.add(m) : _selected.remove(m)),
                    ),
                  if (page != null) _PageResultTile(info: page, controller: c),
                  if (list.isEmpty && page == null && !searching)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 20 * scale),
                      child: Text(
                        'No video or audio found yet. Start playing the video on the page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14 * scale, color: ink.withValues(alpha: 0.6)),
                      ),
                    ),
                ],
              ),
            ),
            if (Platform.isAndroid && page == null)
              Padding(
                padding: EdgeInsets.only(top: 8 * scale),
                child: searching
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: 16 * scale,
                            height: 16 * scale,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10 * scale),
                          Text(
                            'Reading the page with yt-dlp…',
                            style: TextStyle(fontSize: 13 * scale, color: ink.withValues(alpha: 0.7)),
                          ),
                        ],
                      )
                    : Column(
                        children: <Widget>[
                          if (error != null)
                            Text(
                              error,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5 * scale, color: ColorConstants.error),
                            ),
                          TextButton.icon(
                            onPressed: c.searchPage,
                            icon: const Icon(Icons.travel_explore_rounded),
                            label: Text(error == null ? 'Search the page with yt-dlp' : 'Try again'),
                          ),
                        ],
                      ),
              ),
            if (_selecting)
              Padding(
                padding: EdgeInsets.only(top: 10 * scale),
                child: GradientPill(
                  label: _selected.isEmpty ? 'Select items' : 'Download ${_selected.length}',
                  icon: Icons.download_rounded,
                  compact: true,
                  height: 48,
                  onTap: _selected.isEmpty ? null : _downloadSelected,
                ),
              ),
          ],
        );
      }),
    );
  }

  static bool _downloadable(CapturedMedia m) => !m.protected;
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.media,
    required this.controller,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

  final CapturedMedia media;
  final BrowserController controller;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool> onSelect;

  Future<void> _menu() async {
    final action = await showOptionSheet<String>(
      title: media.title,
      options: <SheetOption<String>>[
        if (_MediaSheetState._downloadable(media))
          const SheetOption(value: 'download', label: 'Download', icon: Icons.download_rounded),
        const SheetOption(value: 'preview', label: 'Preview', icon: Icons.play_circle_outline_rounded),
        const SheetOption(value: 'copy', label: 'Copy link', icon: Icons.link_rounded),
      ],
    );
    switch (action) {
      case 'download':
        await controller.chooseQuality(media);
      case 'preview':
        await controller.preview(media);
      case 'copy':
        await controller.copyLink(media);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final m = media;
    final canDownload = _MediaSheetState._downloadable(m);
    final details = <String>[
      m.format,
      if (m.kind != DownloadKind.audio && m.bestHeight > 0) '${m.bestHeight}p',
      if (m.variants.length > 1) '${m.variants.length} qualities',
      if (m.duration != null) Formatters.duration(m.duration),
      if (m.size > 0) '${m.isStream ? '~' : ''}${Formatters.bytes(m.size)}',
    ].join(' • ');
    final note = m.protected ? 'Protected (DRM)' : null;
    final icon = m.kind == DownloadKind.audio ? Icons.music_note_rounded : Icons.movie_rounded;

    return InkWell(
      borderRadius: BorderRadius.circular(12 * scale),
      onTap: !canDownload
          ? null
          : selecting
          ? () => onSelect(!selected)
          : () => controller.chooseQuality(m),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SizedBox(
                width: 80 * scale,
                height: 48 * scale,
                child: m.poster.isEmpty
                    ? ArtworkPlaceholder(size: 80, radius: 0, icon: icon)
                    : CachedNetworkImage(
                        imageUrl: m.poster,
                        fit: BoxFit.cover,
                        memCacheWidth: (80 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                        errorWidget: (_, _, _) => ArtworkPlaceholder(size: 80, radius: 0, icon: icon),
                      ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    m.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: ink),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    note == null ? details : '$details • $note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      color: note == null ? ink.withValues(alpha: 0.6) : ColorConstants.error,
                    ),
                  ),
                  Text(
                    m.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5 * scale, color: ink.withValues(alpha: 0.45)),
                  ),
                ],
              ),
            ),
            if (selecting && canDownload)
              Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false))
            else
              IconButton(
                tooltip: 'More',
                icon: Icon(Icons.more_vert_rounded, color: ink.withValues(alpha: 0.7)),
                onPressed: _menu,
              ),
          ],
        ),
      ),
    );
  }
}

class _PageResultTile extends StatelessWidget {
  const _PageResultTile({required this.info, required this.controller});

  final YtInfo info;
  final BrowserController controller;

  Future<void> _choose() async {
    final formats = controller.pageFormats(info);
    final f = await showOptionSheet<MediaFormat>(
      title: info.title,
      options: <SheetOption<MediaFormat>>[
        for (final f in formats)
          SheetOption(
            value: f,
            label: f.label,
            subtitle: [f.detail, if (f.sizeBytes > 0) '~${Formatters.bytes(f.sizeBytes)}'].join(' • '),
            icon: f.kind == DownloadKind.audio ? Icons.music_note_rounded : Icons.movie_rounded,
          ),
      ],
    );
    if (f != null) await controller.downloadPageFormat(info, f);
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final thumb = info.thumbnail;
    return InkWell(
      borderRadius: BorderRadius.circular(12 * scale),
      onTap: _choose,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SizedBox(
                width: 80 * scale,
                height: 48 * scale,
                child: thumb == null || thumb.isEmpty
                    ? const ArtworkPlaceholder(size: 80, radius: 0, icon: Icons.smart_display_rounded)
                    : CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth: (80 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                        errorWidget: (_, _, _) =>
                            const ArtworkPlaceholder(size: 80, radius: 0, icon: Icons.smart_display_rounded),
                      ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: ink),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    [
                      'Found by yt-dlp',
                      if (info.duration != null) Formatters.duration(info.duration),
                    ].join(' • '),
                    style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Icon(Icons.download_rounded, color: ink.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
