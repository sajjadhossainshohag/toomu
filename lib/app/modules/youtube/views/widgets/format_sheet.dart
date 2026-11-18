import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/download_task.dart';
import '../../../../data/models/media_format.dart';
import '../../../../widgets/app_group.dart';
import '../../../../widgets/info_banner.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/gradient_pill.dart';
import '../../../../widgets/outline_pill.dart';
import '../../../../widgets/track_artwork.dart';
import '../../controllers/youtube_controller.dart';

/// Snaptube-style picker: video header, then Video / Audio format lists.
class FormatSheet extends GetView<YoutubeController> {
  const FormatSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: AppSheet(
        title: 'Download',
        child: Obx(() {
          final video = controller.selectedVideo.value;
          return ListView(
            shrinkWrap: true,
            children: <Widget>[
              _VideoHeader(
                title: video?.title,
                author: video?.author,
                thumb: (video?.thumbnailUrl.isEmpty ?? true) ? null : video!.thumbnailUrl,
                duration: video?.duration,
              ),
              SizedBox(height: 14 * scale),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GradientPill(
                      label: 'Watch',
                      icon: Icons.play_arrow_rounded,
                      height: 44,
                      gradient: ColorConstants.watchGradient,
                      onTap: video == null || video.id.isEmpty ? null : controller.watchVideo,
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: OutlinePill(
                      label: controller.streamingAudio.value ? 'Loading…' : 'Play audio',
                      icon: Icons.headphones_rounded,
                      height: 44,
                      onTap: video == null || video.id.isEmpty || controller.streamingAudio.value
                          ? null
                          : controller.playAudio,
                    ),
                  ),
                ],
              ),
              if (controller.candidates.isNotEmpty) ...<Widget>[
                const SectionTitle('Which one is it?', padded: false),
                for (final v in controller.candidates)
                  _CandidateTile(video: v, onTap: () => controller.pickCandidate(v)),
              ] else if (controller.formatsLoading.value)
                Padding(
                  padding: EdgeInsets.all(28 * scale),
                  child: Column(
                    children: <Widget>[
                      const Center(child: CircularProgressIndicator()),
                      if (controller.formatsStatus.value.isNotEmpty) ...<Widget>[
                        SizedBox(height: 12 * scale),
                        Text(
                          controller.formatsStatus.value,
                          style: TextStyle(
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w600,
                            color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (controller.formatsError.value != null) ...<Widget>[
                Padding(
                  padding: EdgeInsets.only(top: 16 * scale),
                  child: InfoBanner(controller.formatsError.value!,
                      icon: Icons.error_outline_rounded),
                ),
                if (controller.needsSignIn.value)
                  Padding(
                    padding: EdgeInsets.only(top: 12 * scale),
                    child: GradientPill(
                      label: 'Sign in to YouTube',
                      icon: Icons.account_circle_rounded,
                      onTap: controller.signInAndRetry,
                    ),
                  ),
              ]
              else ...() {
                final video = MediaFormat.firstFour(controller.videoFormats);
                final picked = MediaFormat.recommended(video.first, controller.lastVideoQuality);
                return <Widget>[
                  if (video.first.isNotEmpty) ...<Widget>[
                    const SectionTitle('Video', padded: false),
                    _CardGrid(
                      cards: [
                        for (final f in video.first)
                          _QualityCard(format: f, highlighted: f == picked, onTap: () => controller.download(f)),
                      ],
                    ),
                  ],
                  if (video.more.isNotEmpty) _MoreQualities(formats: video.more, onPick: controller.download),
                  if (controller.audioFormats.isNotEmpty) ...<Widget>[
                    const SectionTitle('Audio only', padded: false),
                    _CardGrid(
                      cards: [
                        for (final f in controller.audioFormats)
                          _QualityCard(format: f, onTap: () => controller.download(f)),
                      ],
                    ),
                  ],
                ];
              }(),
            ],
          );
        }),
      ),
    );
  }
}

class _VideoHeader extends StatelessWidget {
  const _VideoHeader({this.title, this.author, this.thumb, this.duration});

  final String? title;
  final String? author;
  final String? thumb;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12 * scale),
          child: SizedBox(
            width: 112 * scale,
            height: 63 * scale,
            child: thumb == null
                ? const ArtworkPlaceholder(size: 112, radius: 0, icon: Icons.smart_display_rounded)
                : CachedNetworkImage(imageUrl: thumb!, fit: BoxFit.cover, memCacheWidth: (112 * scale * MediaQuery.devicePixelRatioOf(context)).round()),
          ),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title ?? 'Loading…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14 * scale,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              SizedBox(height: 4 * scale),
              Text(
                [author, if (duration != null) Formatters.duration(duration)]
                    .whereType<String>()
                    .join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w500,
                  color: ink.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.onTap});

  final MediaFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final bool audio = format.kind == DownloadKind.audio;
    final BrandColors brand = BrandColors.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Material(
        color: ColorConstants.groupOn(dark),
        borderRadius: BorderRadius.circular(14 * scale),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14 * scale),
          child: Padding(
            padding: EdgeInsets.all(10 * scale),
            child: Row(
              children: <Widget>[
                GlyphTile(
                  icon: format.convert != null
                      ? Icons.library_music_rounded
                      : audio
                          ? Icons.music_note_rounded
                          : Icons.movie_rounded,
                  tint: format.convert != null
                      ? ColorConstants.tileRate
                      : audio
                          ? ColorConstants.tileAudio
                          : ColorConstants.tileVideo,
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        format.name,
                        style: TextStyle(
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      Text(
                        audio ? format.detail : '${format.label} · ${format.detail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w500,
                          color: format.mayNotPlay ? ColorConstants.error : ink.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (format.sizeBytes > 0)
                  Text(
                    '~${Formatters.bytes(format.sizeBytes)}',
                    style: TextStyle(
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                SizedBox(width: 10 * scale),
                Container(
                  width: 32 * scale,
                  height: 32 * scale,
                  decoration: BoxDecoration(gradient: brand.pillGradient, shape: BoxShape.circle),
                  child: Icon(Icons.download_rounded,
                      size: 18 * scale, color: ColorConstants.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final double gap = 10 * context.scale;
    return Column(
      children: <Widget>[
        for (var i = 0; i < cards.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: cards[i]),
                  SizedBox(width: gap),
                  Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.format, required this.onTap, this.highlighted = false});

  final MediaFormat format;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final bool video = format.kind == DownloadKind.video;
    final Color fg = highlighted ? ColorConstants.white : ColorConstants.textOn(dark);
    final BorderRadius radius = BorderRadius.circular(16 * scale);
    final String sub = [if (video) format.label, if (format.sizeBytes > 0) '~${Formatters.bytes(format.sizeBytes)}'].join(' · ');
    return Material(
      color: highlighted ? ColorConstants.transparent : ColorConstants.groupOn(dark),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: highlighted ? BorderSide.none : BorderSide(color: ColorConstants.textOn(dark).withValues(alpha: 0.12)),
      ),
      child: Ink(
        decoration: highlighted ? BoxDecoration(gradient: BrandColors.of(context).pillGradient, borderRadius: radius) : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 10 * scale, 12 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        format.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5 * scale, fontWeight: FontWeight.w800, color: fg),
                      ),
                    ),
                    Icon(Icons.download_rounded, size: 20 * scale, color: fg.withValues(alpha: highlighted ? 1 : 0.55)),
                  ],
                ),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75))),
                SizedBox(height: 4 * scale),
                Text(
                  format.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.w500,
                    color: format.mayNotPlay && !highlighted ? ColorConstants.error : fg.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreQualities extends StatefulWidget {
  const _MoreQualities({required this.formats, required this.onPick});

  final List<MediaFormat> formats;
  final void Function(MediaFormat) onPick;

  @override
  State<_MoreQualities> createState() => _MoreQualitiesState();
}

class _MoreQualitiesState extends State<_MoreQualities> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    if (_open) {
      return Column(
        children: <Widget>[
          for (final f in widget.formats) _FormatTile(format: f, onTap: () => widget.onPick(f)),
        ],
      );
    }
    final names = [for (final f in widget.formats) f.height > 1080 ? f.name : f.label].join(', ');
    return InkWell(
      onTap: () => setState(() => _open = true),
      borderRadius: BorderRadius.circular(12 * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 10 * scale),
        child: Row(
          children: <Widget>[
            Icon(Icons.expand_more_rounded, color: ink.withValues(alpha: 0.6)),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'More ($names)',
                style: TextStyle(fontSize: 13.5 * scale, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.75)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A search result the user can pick when the playing video is ambiguous.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.video, required this.onTap});

  final Video video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Material(
        color: ColorConstants.groupOn(context.isDark),
        borderRadius: BorderRadius.circular(14 * scale),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14 * scale),
          child: Padding(
            padding: EdgeInsets.all(8 * scale),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: SizedBox(
                    width: 96 * scale,
                    height: 54 * scale,
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnails.mediumResUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: (96 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
                  ),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13 * scale, height: 1.25, fontWeight: FontWeight.w700, color: ink),
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        [video.author, if (video.duration != null) Formatters.duration(video.duration)].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.55)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: ink.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
