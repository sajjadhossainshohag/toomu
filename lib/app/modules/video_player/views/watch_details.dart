import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/app_group.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/track_artwork.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/watch_details_controller.dart';

/// Under the player while the phone is upright: the video's details, its channel, comments and Up next.
class WatchDetails extends StatefulWidget {
  const WatchDetails({required this.videoId, super.key});

  final String videoId;

  @override
  State<WatchDetails> createState() => _WatchDetailsState();
}

class _WatchDetailsState extends State<WatchDetails> {
  late final WatchDetailsController c = Get.put(
    WatchDetailsController(widget.videoId, Get.find<YoutubeController>().watchSource),
    tag: widget.videoId,
  );

  @override
  void dispose() {
    Get.delete<WatchDetailsController>(tag: widget.videoId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();

    return ColoredBox(
      color: ColorConstants.pageOn(dark),
      child: Obx(() {
        if (c.loading.value) return const Center(child: CircularProgressIndicator());
        final v = c.video.value;
        if (v == null) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24 * scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(c.error.value ?? "Couldn't load this video's details.", textAlign: TextAlign.center, style: TextStyle(color: ink)),
                  TextButton(onPressed: c.load, child: const Text('Try again')),
                ],
              ),
            ),
          );
        }
        final open = c.descriptionOpen.value;
        final when = v.uploadDateRaw ?? (v.uploadDate == null ? null : Formatters.ago(v.uploadDate!));
        final channel = c.channel.value;
        final likes = v.engagement.likeCount;
        return ListView(
          padding: EdgeInsets.only(bottom: 24 * scale),
          children: <Widget>[
            InkWell(
              onTap: () => c.descriptionOpen.toggle(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16 * scale, 14 * scale, 16 * scale, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      v.title,
                      maxLines: open ? null : 2,
                      overflow: open ? null : TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17 * scale, height: 1.3, fontWeight: FontWeight.w800, color: ink),
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      [
                        '${Formatters.compact(v.engagement.viewCount)} views',
                        ?when,
                        if (likes != null && likes > 0) '${Formatters.compact(likes)} likes',
                        open ? 'less' : '...more',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
            if (open && v.description.trim().isNotEmpty)
              Container(
                margin: EdgeInsets.fromLTRB(16 * scale, 10 * scale, 16 * scale, 0),
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(color: ColorConstants.groupOn(dark), borderRadius: BorderRadius.circular(14 * scale)),
                child: SelectableText(v.description.trim(), style: TextStyle(fontSize: 13.5 * scale, height: 1.45, color: ink)),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16 * scale, 14 * scale, 16 * scale, 0),
              child: Row(
                children: <Widget>[
                  ClipOval(
                    child: SizedBox.square(
                      dimension: 38 * scale,
                      child: channel == null || channel.logoUrl.isEmpty
                          ? _Letter(name: v.author, size: 38)
                          : CachedNetworkImage(
                              imageUrl: channel.logoUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: (38 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                              errorWidget: (_, _, _) => _Letter(name: v.author, size: 38),
                            ),
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(v.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5 * scale, fontWeight: FontWeight.w700, color: ink)),
                        if (channel?.subscribersCount != null)
                          Text(
                            '${Formatters.compact(channel!.subscribersCount!)} subscribers',
                            style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 56 * scale,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 0),
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _Pill(icon: Icons.download_rounded, label: 'Download', primary: true, onTap: () => yt.openVideo(v.id.value, known: v)),
                  _Pill(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: () => yt.shareVideo(v),
                  ),
                  _Pill(
                    icon: Icons.link_rounded,
                    label: 'Copy link',
                    onTap: () => yt.copyLink(v),
                  ),
                ],
              ),
            ),
            if (c.commentsOff.value)
              Padding(
                padding: EdgeInsets.fromLTRB(16 * scale, 14 * scale, 16 * scale, 0),
                child: Text('Comments are turned off.', style: TextStyle(fontSize: 13 * scale, color: ink.withValues(alpha: 0.6))),
              )
            else if (c.comments.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(16 * scale, 14 * scale, 16 * scale, 0),
                child: Material(
                  color: ColorConstants.groupOn(dark),
                  borderRadius: BorderRadius.circular(14 * scale),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14 * scale),
                    onTap: () => showCommentsSheet(c),
                    child: Padding(
                      padding: EdgeInsets.all(12 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                const TextSpan(text: 'Comments  '),
                                TextSpan(
                                  text: Formatters.compact(c.commentCount.value),
                                  style: TextStyle(fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700, color: ink),
                          ),
                          SizedBox(height: 8 * scale),
                          Row(
                            children: <Widget>[
                              _Letter(name: c.comments.first.author, size: 24),
                              SizedBox(width: 10 * scale),
                              Expanded(
                                child: Text(
                                  c.comments.first.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13 * scale, color: ink),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (c.related.isNotEmpty) ...<Widget>[
              const SectionTitle('Up next'),
              for (final r in c.related)
                _RelatedRow(video: r, loading: yt.watchingId.value == r.id.value, onTap: () => yt.watchInPlace(r)),
            ],
          ],
        );
      }),
    );
  }
}

void showCommentsSheet(WatchDetailsController c) => Get.bottomSheet<void>(
      Builder(
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: AppSheet(
            title: 'Comments',
            child: Obx(
              () => ListView.separated(
                itemCount: c.comments.length,
                separatorBuilder: (_, _) => SizedBox(height: 14 * context.scale),
                itemBuilder: (_, i) => _CommentTile(comment: c.comments[i]),
              ),
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final Color soft = ink.withValues(alpha: 0.6);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Letter(name: comment.author, size: 32),
        SizedBox(width: 12 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${comment.author} · ${comment.publishedTime}', style: TextStyle(fontSize: 12 * scale, color: soft)),
              SizedBox(height: 3 * scale),
              Text(comment.text, style: TextStyle(fontSize: 14 * scale, height: 1.4, color: ink)),
              SizedBox(height: 6 * scale),
              Row(
                children: <Widget>[
                  Icon(Icons.thumb_up_alt_outlined, size: 15 * scale, color: soft),
                  SizedBox(width: 5 * scale),
                  Text(comment.likeCount > 0 ? Formatters.compact(comment.likeCount) : '', style: TextStyle(fontSize: 12 * scale, color: soft)),
                  if (comment.replyCount > 0) ...<Widget>[
                    SizedBox(width: 16 * scale),
                    Text(
                      '${comment.replyCount} ${comment.replyCount == 1 ? 'reply' : 'replies'}',
                      style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w700, color: BrandColors.of(context).primary),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.video, required this.loading, required this.onTap});

  final Video video;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 6 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SizedBox(
                width: 160 * scale,
                height: 90 * scale,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CachedNetworkImage(
                      imageUrl: video.thumbnails.mediumResUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: (160 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                      placeholder: (_, _) => const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                      errorWidget: (_, _, _) => const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                    ),
                    if (video.duration != null)
                      Positioned(
                        right: 6 * scale,
                        bottom: 6 * scale,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                          decoration: BoxDecoration(color: ColorConstants.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6 * scale)),
                          child: Text(
                            Formatters.duration(video.duration),
                            style: TextStyle(fontSize: 10.5 * scale, fontWeight: FontWeight.w700, color: ColorConstants.white),
                          ),
                        ),
                      ),
                    if (loading)
                      ColoredBox(
                        color: ColorConstants.black.withValues(alpha: 0.45),
                        child: const Center(child: CircularProgressIndicator(color: ColorConstants.white)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5 * scale, height: 1.3, fontWeight: FontWeight.w700, color: ink),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    [
                      video.author,
                      if (video.engagement.viewCount > 0) '${Formatters.compact(video.engagement.viewCount)} views',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color fg = primary ? ColorConstants.white : ColorConstants.textOn(dark);
    final BorderRadius radius = BorderRadius.circular(20 * scale);
    return Padding(
      padding: EdgeInsets.only(right: 8 * scale),
      child: Material(
        color: primary ? ColorConstants.transparent : ColorConstants.groupOn(dark),
        borderRadius: radius,
        child: Ink(
          decoration: primary ? BoxDecoration(gradient: BrandColors.of(context).pillGradient, borderRadius: radius) : null,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 18 * scale, color: fg),
                  SizedBox(width: 6 * scale),
                  Text(label, style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double s = size * context.scale;
    final String letter = name.replaceFirst('@', '').trim();
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: BrandColors.of(context).primary.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(
        letter.isEmpty ? '?' : letter.characters.first.toUpperCase(),
        style: TextStyle(fontSize: s * 0.45, fontWeight: FontWeight.w800, color: BrandColors.of(context).primary),
      ),
    );
  }
}
