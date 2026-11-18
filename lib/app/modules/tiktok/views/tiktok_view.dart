import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/tiktok_item.dart';
import '../../../services/download_service.dart';
import '../../../services/video_session_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../services/tiktok_account_service.dart';
import '../controllers/tiktok_controller.dart';
import '../controllers/tiktok_feeds.dart';
import '../controllers/tiktok_actions.dart';
import 'tiktok_comments_sheet.dart';
import 'tiktok_seek_bar.dart';
import 'tiktok_sign_in_page.dart';

/// The TikTok tab: TikTok's "Following | For You" on top (with the
/// account button), each feed below it.
class TiktokView extends StatelessWidget {
  const TiktokView({super.key});

  @override
  Widget build(BuildContext context) {
    final feeds = Get.find<TiktokFeeds>();
    final account = TiktokAccountService.to;
    return ColoredBox(
      color: ColorConstants.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The video page for comments and likes, drawn under the feeds.
          if (Get.isRegistered<TiktokActions>())
            IgnorePointer(
              child: ValueListenableBuilder<Widget?>(
                valueListenable: Get.find<TiktokActions>().page.page,
                builder: (_, page, _) => page ?? const SizedBox.shrink(),
              ),
            ),
          Obx(
            () => IndexedStack(
              index: feeds.feed.value.index,
              sizing: StackFit.expand,
              children: <Widget>[
                account.signedIn.value
                    ? const TiktokFeedView(feedTag: TiktokFeeds.followingTag)
                    : const _SignInPrompt(),
                const TiktokFeedView(feedTag: TiktokFeeds.forYouTag),
              ],
            ),
          ),
          const _TopBar(),
        ],
      ),
    );
  }
}

/// "Following | For You", centred; the account at the right.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final feeds = Get.find<TiktokFeeds>();
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: 4 * scale),
          child: Row(
            children: <Widget>[
              SizedBox(width: 48 * scale),
              Expanded(
                child: Obx(
                  () => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _FeedTab(
                        label: 'Following',
                        on: feeds.feed.value == TiktokFeedKind.following,
                        onTap: () => feeds.tap(TiktokFeedKind.following),
                      ),
                      SizedBox(width: 18 * scale),
                      _FeedTab(
                        label: 'For You',
                        on: feeds.feed.value == TiktokFeedKind.forYou,
                        onTap: () => feeds.tap(TiktokFeedKind.forYou),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 48 * scale, child: const _AccountButton()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Semantics(
      selected: on,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 17 * scale,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: ColorConstants.white.withValues(alpha: on ? 1 : 0.65),
                  shadows: const <Shadow>[
                    Shadow(blurRadius: 6, color: Color(0x66000000)),
                  ],
                ),
              ),
              SizedBox(height: 5 * scale),
              Container(
                width: 28 * scale,
                height: 3 * scale,
                decoration: BoxDecoration(
                  color: on ? ColorConstants.white : ColorConstants.transparent,
                  borderRadius: BorderRadius.circular(2 * scale),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed out: sign in. Signed in: the account's picture; tap for Sign out.
class _AccountButton extends StatelessWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final account = TiktokAccountService.to;
    return Obx(() {
      final user = account.user.value;
      if (!account.signedIn.value) {
        return IconButton(
          tooltip: 'Sign in to TikTok',
          onPressed: TiktokSignInPage.open,
          icon: Icon(
            Icons.person_outline_rounded,
            color: ColorConstants.white,
            size: 26 * scale,
          ),
        );
      }
      return IconButton(
        tooltip: user == null ? 'TikTok account' : '@${user.id}',
        onPressed: () => _accountSheet(context),
        icon: user?.avatar == null
            ? Icon(
                Icons.account_circle_rounded,
                color: ColorConstants.white,
                size: 28 * scale,
              )
            : _Avatar(url: user!.avatar, size: 28 * scale),
      );
    });
  }

  void _accountSheet(BuildContext context) {
    final account = TiktokAccountService.to;
    final user = account.user.value;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.account_circle_rounded),
              title: Text(
                user == null
                    ? 'Signed in to TikTok'
                    : (user.name.isEmpty ? '@${user.id}' : user.name),
              ),
              subtitle: user == null ? null : Text('@${user.id}'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out of TikTok'),
              onTap: () async {
                Navigator.of(sheet).pop();
                await account.signOut();
                showSnack(
                  'Signed out of TikTok',
                  'For You is the visitor feed again.',
                  duration: const Duration(seconds: 3),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Following, signed out: what TikTok shows too.
class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.people_alt_rounded,
              color: ColorConstants.white,
              size: 56 * scale,
            ),
            SizedBox(height: 14 * scale),
            Text(
              'Videos from accounts you follow',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 * scale,
                fontWeight: FontWeight.w700,
                color: ColorConstants.white,
              ),
            ),
            SizedBox(height: 8 * scale),
            Text(
              'Sign in to TikTok to see them here, ad-free.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5 * scale,
                color: ColorConstants.white.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: 18 * scale),
            FilledButton(
              onPressed: TiktokSignInPage.open,
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One feed in TikTok's look: full-screen videos swiped up, the action
/// rail on the right, author / caption / sound at the bottom left, the seek
/// bar along the bottom. [feedTag] picks the feed's controller.
class TiktokFeedView extends GetView<TiktokController> {
  const TiktokFeedView({super.key, this.feedTag});

  final String? feedTag;

  @override
  String? get tag => feedTag;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ColorConstants.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // TikTok's page, drawn under the feed so it keeps loading videos
          // (the feed above is opaque; the page never takes a touch).
          IgnorePointer(
            child: ValueListenableBuilder<Widget?>(
              valueListenable: controller.source.page,
              builder: (_, page, _) => page ?? const SizedBox.shrink(),
            ),
          ),
          Obx(() {
            if (controller.items.isEmpty) {
              final error = controller.feedError.value;
              return ColoredBox(
                color: ColorConstants.black,
                child: error == null
                    ? const _Loading()
                    : _Problem(message: error, onRetry: controller.retry),
              );
            }
            return ColoredBox(
              color: ColorConstants.black,
              // The video changes once the swipe has settled: opening it
              // half way through made the page stutter while it moved.
              // Pull down on the first video: fresh videos (TikTok's refresh).
              child: RefreshIndicator(
                color: ColorConstants.black,
                backgroundColor: ColorConstants.white,
                onRefresh: controller.reset,
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (n) {
                    final at = controller.pages.hasClients
                        ? controller.pages.page
                        : null;
                    if (n.depth == 0 && at != null) {
                      controller.settled(at.round());
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: controller.pages,
                    scrollDirection: Axis.vertical,
                    physics: const TiktokSwipePhysics(),
                    // The next video's page (its cover) is built before it is reached.
                    allowImplicitScrolling: true,
                    // One more page after the last video: TikTok's spinner
                    // until the next ones come (then the first of them plays).
                    itemCount: controller.items.length + 1,
                    itemBuilder: (_, i) => i < controller.items.length
                        ? _TiktokPage(index: i, feedTag: feedTag)
                        : _EndPage(feedTag: feedTag),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Taps on the video: one = pause / play; two quick ones = like, with
/// TikTok's red heart bursting where the finger was (on every double tap,
/// also when already liked; a double tap never unlikes).
class TiktokTapLayer extends StatefulWidget {
  const TiktokTapLayer({super.key, required this.onTap, this.onDoubleTap});

  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<TiktokTapLayer> createState() => _TiktokTapLayerState();
}

class _TiktokTapLayerState extends State<TiktokTapLayer> {
  final _hearts = <({Key key, Offset at, double tilt})>[];
  Offset _down = Offset.zero;
  int _n = 0;

  void _heart() {
    final key = UniqueKey();
    // TikTok's hearts lean a little, left or right.
    final tilt = (_n++ % 3 - 1) * 0.25;
    setState(() => _hearts.add((key: key, at: _down, tilt: tilt)));
  }

  @override
  Widget build(BuildContext context) {
    final double size = 110 * context.scale;
    final like = widget.onDoubleTap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: like == null ? null : (d) => _down = d.localPosition,
      onDoubleTap: like == null
          ? null
          : () {
              _heart();
              like();
            },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final h in _hearts)
            Positioned(
              key: h.key,
              left: h.at.dx - size / 2,
              top: h.at.dy - size / 2,
              child: _Heart(
                size: size,
                tilt: h.tilt,
                onDone: () {
                  if (mounted) {
                    setState(() => _hearts.removeWhere((x) => x.key == h.key));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One heart: pops in, floats up a little and fades (~0.8 s).
class _Heart extends StatefulWidget {
  const _Heart({required this.size, required this.tilt, required this.onDone});

  final double size;
  final double tilt;
  final VoidCallback onDone;

  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, _) {
          final v = _t.value;
          final scale = v < 0.25
              ? Curves.easeOutBack.transform(v / 0.25) * 1.15
              : 1.15 - (v - 0.25) * 0.2;
          final fade = v < 0.6 ? 1.0 : 1 - (v - 0.6) / 0.4;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -v * widget.size * 0.35),
              child: Transform.rotate(
                angle: widget.tilt,
                child: Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.favorite_rounded,
                    size: widget.size,
                    color: tiktokRed,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 12, color: Color(0x66000000)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// TikTok's snap: a flick lands on the next video in under 0.2 s (Flutter's
/// page spring takes about three times as long and felt sluggish).
class TiktokSwipePhysics extends PageScrollPhysics {
  const TiktokSwipePhysics({super.parent});

  @override
  TiktokSwipePhysics applyTo(ScrollPhysics? ancestor) =>
      TiktokSwipePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 500, ratio: 1);
}

class _TiktokPage extends GetView<TiktokController> {
  const _TiktokPage({required this.index, this.feedTag});

  final int index;
  final String? feedTag;

  @override
  String? get tag => feedTag;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final item = controller.items[index];
    final session = VideoSessionService.to;
    // Portrait videos fill the screen (TikTok crops them a little); others fit.
    final fit =
        item.width > 0 && item.height > 0 && item.height < item.width * 1.4
        ? BoxFit.contain
        : BoxFit.cover;
    return Obx(() {
      final current = controller.page.value == index;
      final live = controller.playing.value == item.id;
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (item.coverUrl != null)
            CachedNetworkImage(
              imageUrl: item.coverUrl!,
              fit: fit,
              memCacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          if (live && session.hasPlayer)
            Video(
              controller: session.video,
              controls: NoVideoControls,
              fit: fit,
              fill: ColorConstants.transparent,
              pauseUponEnteringBackgroundMode: false,
              resumeUponEnteringForegroundMode: false,
            ),
          TiktokTapLayer(
            onTap: controller.togglePause,
            onDoubleTap: Get.isRegistered<TiktokActions>()
                ? () => Get.find<TiktokActions>().doubleTapLike(item)
                : null,
          ),
          if (current && live && controller.paused.value)
            IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 84 * scale,
                  color: ColorConstants.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          if (current && controller.opening.value)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(
                  color: ColorConstants.white,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          if (current && controller.videoError.value != null)
            _Problem(
              message: controller.videoError.value!,
              onRetry: () => controller.show(index),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                  stops: <double>[0, 0.15, 0.6, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14 * scale,
            right: 86 * scale,
            bottom: 30 * scale,
            child: _Details(
              item: item,
              spinning: live && !controller.paused.value,
            ),
          ),
          Positioned(
            right: 8 * scale,
            bottom: 26 * scale,
            child: _Rail(
              item: item,
              spinning: live && !controller.paused.value,
            ),
          ),
          if (live && session.hasPlayer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TiktokSeekBar(
                position: session.player.stream.position,
                initial: session.player.state.position,
                total: () => session.player.state.duration,
                onSeek: session.player.seek,
              ),
            ),
        ],
      );
    });
  }
}

/// Author, caption (tap for all of it) and the sound.
class _Details extends StatefulWidget {
  const _Details({required this.item, required this.spinning});

  final TiktokItem item;
  final bool spinning;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final item = widget.item;
    const shadow = <Shadow>[Shadow(blurRadius: 4, color: Color(0x80000000))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          item.authorName.isEmpty ? '@${item.authorId}' : item.authorName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5 * scale,
            fontWeight: FontWeight.w700,
            color: ColorConstants.white,
            shadows: shadow,
          ),
        ),
        if (item.caption.isNotEmpty) ...<Widget>[
          SizedBox(height: 6 * scale),
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Text(
              item.caption,
              maxLines: _open ? 12 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5 * scale,
                height: 1.35,
                color: ColorConstants.white,
                shadows: shadow,
              ),
            ),
          ),
        ],
        if (item.music != null) ...<Widget>[
          SizedBox(height: 8 * scale),
          Row(
            children: <Widget>[
              Icon(
                Icons.music_note_rounded,
                size: 15 * scale,
                color: ColorConstants.white,
              ),
              SizedBox(width: 4 * scale),
              Expanded(
                child: Text(
                  item.music!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: ColorConstants.white,
                    shadows: shadow,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Avatar, likes, comments, shares, save, and the spinning sound disc.
class _Rail extends StatelessWidget {
  const _Rail({required this.item, required this.spinning});

  final TiktokItem item;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Avatar(url: item.avatarUrl, size: 48 * scale),
        SizedBox(height: 18 * scale),
        if (Get.isRegistered<TiktokActions>())
          Obx(() {
            final actions = Get.find<TiktokActions>();
            final liked = actions.isLiked(item);
            return _RailCount(
              icon: Icons.favorite_rounded,
              color: liked ? tiktokRed : ColorConstants.white,
              label: Formatters.compact(actions.likesOf(item)),
              tooltip: liked ? 'Unlike' : 'Like',
              onTap: () => actions.toggleLike(item),
            );
          })
        else
          _RailCount(
            icon: Icons.favorite_rounded,
            label: Formatters.compact(item.likes),
          ),
        _RailCount(
          icon: Icons.textsms_rounded,
          label: Formatters.compact(item.comments),
          tooltip: 'Comments',
          onTap: () => showTiktokComments(context, item),
        ),
        _RailCount(
          icon: Icons.reply_rounded,
          flip: true,
          label: item.shares > 0 ? Formatters.compact(item.shares) : 'Share',
          tooltip: 'Share',
          onTap: () => SharePlus.instance.share(ShareParams(text: item.webUrl)),
        ),
        _RailCount(
          icon: Icons.download_rounded,
          label: 'Save',
          tooltip: 'Download (no watermark)',
          onTap: () async {
            await DownloadService.to.enqueueTiktok(item);
            showSnack(
              'Download started',
              item.caption.isEmpty ? '@${item.authorId}' : item.caption,
              duration: const Duration(seconds: 2),
            );
          },
        ),
        SizedBox(height: 6 * scale),
        _Disc(url: item.avatarUrl, spinning: spinning, size: 44 * scale),
      ],
    );
  }
}

class _RailCount extends StatelessWidget {
  const _RailCount({
    required this.icon,
    required this.label,
    this.onTap,
    this.tooltip,
    this.flip = false,
    this.color = ColorConstants.white,
  });

  final Color color;

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    const shadow = <Shadow>[Shadow(blurRadius: 6, color: Color(0x80000000))];
    Widget glyph = Icon(icon, size: 34 * scale, color: color, shadows: shadow);
    if (flip) glyph = Transform.flip(flipX: true, child: glyph);
    final body = Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * scale, horizontal: 4 * scale),
      child: Column(
        children: <Widget>[
          glyph,
          SizedBox(height: 2 * scale),
          Text(
            label,
            style: TextStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: ColorConstants.white,
              shadows: shadow,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return Semantics(label: label, child: body);
    return Tooltip(
      message: tooltip ?? label,
      child: InkResponse(onTap: onTap, radius: 30 * scale, child: body),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColorConstants.chevron,
        border: Border.all(color: ColorConstants.white, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Icon(
              Icons.person_rounded,
              color: ColorConstants.white,
              size: size * 0.6,
            )
          : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Icon(
                Icons.person_rounded,
                color: ColorConstants.white,
                size: size * 0.6,
              ),
            ),
    );
  }
}

/// TikTok's record turning while the sound plays.
class _Disc extends StatefulWidget {
  const _Disc({required this.url, required this.spinning, required this.size});

  final String? url;
  final bool spinning;
  final double size;

  @override
  State<_Disc> createState() => _DiscState();
}

class _DiscState extends State<_Disc> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _turn.repeat();
  }

  @override
  void didUpdateWidget(_Disc old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_turn.isAnimating) _turn.repeat();
    if (!widget.spinning && _turn.isAnimating) _turn.stop();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RotationTransition(
      turns: _turn,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[Color(0xFF3A3A3A), Color(0xFF111111)],
          ),
        ),
        child: ClipOval(
          child: widget.url == null
              ? const ColoredBox(color: ColorConstants.chevron)
              : CachedNetworkImage(imageUrl: widget.url!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// After the last video: loading more (or nothing came, Try again).
class _EndPage extends GetView<TiktokController> {
  const _EndPage({this.feedTag});

  final String? feedTag;

  @override
  String? get tag => feedTag;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ColorConstants.black,
      child: Obx(
        () => controller.endStuck.value
            ? _Problem(
                message: 'No new videos yet.',
                onRetry: controller.retryEnd,
              )
            : const _Loading(label: 'Loading more…'),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.label = 'Loading TikTok…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(
            color: ColorConstants.white,
            strokeWidth: 2.5,
          ),
          SizedBox(height: 16 * context.scale),
          Text(label, style: TextStyle(color: ColorConstants.white)),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ColorConstants.white),
            ),
            SizedBox(height: 8 * scale),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
