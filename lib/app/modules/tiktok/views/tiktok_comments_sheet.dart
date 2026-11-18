import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/tiktok_comment.dart';
import '../../../data/models/tiktok_item.dart';
import '../../../services/tiktok_account_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../controllers/tiktok_actions.dart';
import '../controllers/tiktok_comments_controller.dart';
import 'tiktok_sign_in_page.dart';

/// TikTok's red (likes).
const tiktokRed = Color(0xFFFE2C55);

/// Opens [item]'s comments in TikTok's sheet.
Future<void> showTiktokComments(BuildContext context, TiktokItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ColorConstants.transparent,
    builder: (_) => TiktokCommentsSheet(item: item),
  );
}

/// TikTok's comments sheet: "N comments" on top, each comment with its
/// author, time and heart, replies opening under it ("View N replies").
class TiktokCommentsSheet extends StatefulWidget {
  const TiktokCommentsSheet({super.key, required this.item, this.controller});

  final TiktokItem item;

  /// For tests; otherwise made from the TikTok tab's video page.
  final TiktokCommentsController? controller;

  @override
  State<TiktokCommentsSheet> createState() => _TiktokCommentsSheetState();
}

class _TiktokCommentsSheetState extends State<TiktokCommentsSheet> {
  late final TiktokCommentsController c =
      widget.controller ??
      TiktokCommentsController(
        item: widget.item,
        page: Get.find<TiktokActions>().page,
        signedIn: TiktokAccountService.to.signedIn,
        onProblem: (t, m) =>
            showSnack(t, m, duration: const Duration(seconds: 3)),
      );

  @override
  void initState() {
    super.initState();
    c.onStart();
  }

  @override
  void dispose() {
    c.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color sheet = dark ? const Color(0xFF1C1C1E) : ColorConstants.white;
    final Color ink = ColorConstants.textOn(dark);
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: BoxDecoration(
        color: sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14 * scale)),
      ),
      child: Column(
        children: <Widget>[
          // The full width: sized by the title alone, the close button
          // (pinned to the right) sat on top of the title.
          SizedBox(
            width: double.infinity,
            height: 48 * scale,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Obx(
                  () => Text(
                    '${Formatters.compact(c.total.value)} comments',
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                Positioned(
                  right: 4 * scale,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: ink,
                      size: 22 * scale,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Obx(() => _body(context, ink))),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Color ink) {
    final double scale = context.scale;
    final Color soft = ink.withValues(alpha: 0.55);
    if (!c.signedIn.value) {
      return _Message(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Sign in to see comments',
        text: 'TikTok shows comments only to signed-in accounts.',
        ink: ink,
        action: FilledButton(
          onPressed: TiktokSignInPage.open,
          child: const Text('Sign in'),
        ),
      );
    }
    if (c.loading.value && c.comments.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    final error = c.error.value;
    if (error != null && c.comments.isEmpty) {
      return _Message(
        icon: Icons.error_outline_rounded,
        title: error,
        ink: ink,
        action: TextButton(onPressed: c.load, child: const Text('Try again')),
      );
    }
    if (c.comments.isEmpty) {
      return _Message(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No comments yet',
        ink: ink,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) c.more();
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: 16 * scale),
        itemCount: c.comments.length + 1,
        itemBuilder: (_, i) {
          if (i == c.comments.length) {
            return c.loadingMore.value
                ? Padding(
                    padding: EdgeInsets.all(14 * scale),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : SizedBox(height: 8 * scale);
          }
          return Obx(() {
            if (i >= c.comments.length) return const SizedBox.shrink();
            final comment = c.comments[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CommentTile(
                  comment: comment,
                  creator: comment.authorId == widget.item.authorId,
                  onLike: () => c.toggleLike(comment),
                  ink: ink,
                ),
                if (comment.replyCount > 0)
                  _Replies(
                    c: c,
                    parent: comment,
                    creatorId: widget.item.authorId,
                    ink: ink,
                    soft: soft,
                  ),
              ],
            );
          });
        },
      ),
    );
  }
}

class _Replies extends StatelessWidget {
  const _Replies({
    required this.c,
    required this.parent,
    required this.creatorId,
    required this.ink,
    required this.soft,
  });

  final TiktokCommentsController c;
  final TiktokComment parent;
  final String creatorId;
  final Color ink, soft;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    // Built lazily by the list: it watches the replies itself.
    return Obx(() {
      final open = c.open.contains(parent.id);
      final list = c.replies[parent.id] ?? const <TiktokComment>[];
      final loading = c.loadingReplies.contains(parent.id);
      final more = c.moreReplies[parent.id] ?? false;
      final left = parent.replyCount - list.length;
      return Padding(
        padding: EdgeInsets.only(left: 52 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (open)
              for (final r in list)
                _CommentTile(
                  comment: r,
                  small: true,
                  creator: r.authorId == creatorId,
                  onLike: () => c.toggleLike(r, parent: parent.id),
                  ink: ink,
                ),
            Row(
              children: <Widget>[
                if (loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8 * scale),
                    child: SizedBox(
                      width: 16 * scale,
                      height: 16 * scale,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (!open)
                  _ReplyLink(
                    label:
                        'View ${Formatters.compact(parent.replyCount)} ${parent.replyCount == 1 ? 'reply' : 'replies'}',
                    down: true,
                    soft: soft,
                    onTap: () => c.toggleReplies(parent),
                  )
                else ...<Widget>[
                  if (more && left > 0)
                    _ReplyLink(
                      label: 'View ${Formatters.compact(left)} more',
                      down: true,
                      soft: soft,
                      onTap: () => c.loadReplies(parent),
                    ),
                  _ReplyLink(
                    label: 'Hide',
                    down: false,
                    soft: soft,
                    onTap: () => c.toggleReplies(parent),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _ReplyLink extends StatelessWidget {
  const _ReplyLink({
    required this.label,
    required this.down,
    required this.soft,
    required this.onTap,
  });

  final String label;
  final bool down;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 6 * scale, 16 * scale, 8 * scale),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (down) ...<Widget>[
              Container(
                width: 24 * scale,
                height: 1,
                color: soft.withValues(alpha: 0.4),
              ),
              SizedBox(width: 8 * scale),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13 * scale,
                fontWeight: FontWeight.w600,
                color: soft,
              ),
            ),
            Icon(
              down
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18 * scale,
              color: soft,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onLike,
    required this.ink,
    this.small = false,
    this.creator = false,
  });

  final TiktokComment comment;
  final VoidCallback onLike;
  final Color ink;
  final bool small;
  final bool creator;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color soft = ink.withValues(alpha: 0.55);
    final double avatar = (small ? 24 : 36) * scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        small ? 0 : 16 * scale,
        8 * scale,
        6 * scale,
        4 * scale,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipOval(
            child: SizedBox(
              width: avatar,
              height: avatar,
              child: comment.avatarUrl == null
                  ? ColoredBox(color: soft.withValues(alpha: 0.2))
                  : CachedNetworkImage(
                      imageUrl: comment.avatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: soft.withValues(alpha: 0.2)),
                    ),
            ),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        comment.shownName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          color: soft,
                        ),
                      ),
                    ),
                    if (creator) ...<Widget>[
                      SizedBox(width: 4 * scale),
                      Text(
                        '· Creator',
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          color: tiktokRed,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2 * scale),
                Text(
                  comment.text,
                  style: TextStyle(
                    fontSize: 15 * scale,
                    height: 1.3,
                    color: ink,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Row(
                  children: <Widget>[
                    if (comment.time != null)
                      Text(
                        tiktokAgo(comment.time!),
                        style: TextStyle(fontSize: 12.5 * scale, color: soft),
                      ),
                    if (comment.likedByAuthor) ...<Widget>[
                      SizedBox(width: 12 * scale),
                      Icon(
                        Icons.favorite_rounded,
                        size: 12 * scale,
                        color: tiktokRed,
                      ),
                      SizedBox(width: 3 * scale),
                      Flexible(
                        child: Text(
                          'Liked by creator',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5 * scale, color: soft),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          InkResponse(
            onTap: onLike,
            radius: 24 * scale,
            child: Semantics(
              button: true,
              selected: comment.liked,
              label: comment.liked ? 'Unlike comment' : 'Like comment',
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 4 * scale,
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      comment.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20 * scale,
                      color: comment.liked ? tiktokRed : soft,
                    ),
                    if (comment.likes > 0)
                      Text(
                        Formatters.compact(comment.likes),
                        style: TextStyle(fontSize: 12 * scale, color: soft),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TikTok's short times: "5m ago", "3h ago", "2d ago", then the date.
String tiktokAgo(DateTime when, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final d = at.difference(when);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (when.year == at.year) return '${when.month}-${when.day}';
  return '${when.year}-${when.month}-${when.day}';
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.ink,
    this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Color ink;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44 * scale, color: ink.withValues(alpha: 0.35)),
            SizedBox(height: 12 * scale),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (text != null) ...<Widget>[
              SizedBox(height: 6 * scale),
              Text(
                text!,
                textAlign: TextAlign.center,
                style: TextStyle(color: ink.withValues(alpha: 0.6)),
              ),
            ],
            if (action != null) ...<Widget>[
              SizedBox(height: 14 * scale),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
