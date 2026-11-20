import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/round_icon_button.dart';
import '../../../services/settings_service.dart';
import '../../../core/utils/device_profile.dart';
import '../../downloads/controllers/downloads_controller.dart';
import '../address.dart';
import '../controllers/browser_controller.dart';
import '../controllers/browser_session.dart';
import '../media_button.dart';
import 'address_suggestions.dart';
import 'browser_menu.dart';
import 'downloads_sheet.dart';
import 'new_tab_page.dart';
import 'tab_switcher.dart';
import 'tab_web_view.dart';

class BrowserView extends GetView<BrowserSession> {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    final bool dark = context.isDark;
    final session = controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await session.handleBack()) Get.back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: ColorConstants.pageOn(dark),
          body: SafeArea(
            bottom: false,
            child: Obx(() {
              final tab = session.active.value;
              if (tab == null) return TabSwitcher(session: session);
              return Stack(
                children: <Widget>[
                  // Each part watches only what it shows: a progress tick or
                  // a scroll must not rebuild the whole screen.
                  _BarAndPage(
                    tab: tab,
                    bar: Obx(() => tab.finding.value ? _FindBar(tab: tab) : _TopBar(session: session, tab: tab)),
                    page: Column(
                      children: <Widget>[
                        _ProgressLine(tab: tab),
                        if (tab.refreshFor != null)
                          _Banner(text: 'Play the video to refresh the link of "${tab.refreshFor!.title}".'),
                        Obx(() {
                          final notice = tab.engineNotice.value;
                          return notice == null
                              ? const SizedBox.shrink()
                              : _Banner(text: notice, onClose: () => tab.engineNotice.value = null);
                        }),
                        Expanded(
                          child: _Pages(session: session, tab: tab),
                        ),
                      ],
                    ),
                  ),
                  if (session.showingSwitcher.value) Positioned.fill(child: TabSwitcher(session: session)),
                ],
              );
            }),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: Obx(() {
            final tab = session.active.value;
            if (tab == null || tab.showingNewTab.value || session.showingSwitcher.value || tab.addressFocused.value) {
              return const SizedBox.shrink();
            }
            return _MediaButton(controller: tab);
          }),
        ),
      ),
    );
  }
}

/// The tabs' pages (the last few kept loaded, only the shown one visible),
/// with the new-tab page and the address suggestions over them.
class _Pages extends StatelessWidget {
  const _Pages({required this.session, required this.tab});

  final BrowserSession session;
  final BrowserController tab;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loaded = [
        for (final t in session.tabs)
          if (session.live.contains(t.id) && t.restoreUrl.isNotEmpty) t,
      ];
      final shown = loaded.indexOf(tab);
      return Stack(
        children: <Widget>[
          if (loaded.isNotEmpty)
            Positioned.fill(
              // Under the new-tab page (or when the shown tab has no page
              // yet) no page is visible: don't keep drawing one there.
              child: Offstage(
                offstage: shown < 0 || tab.showingNewTab.value,
                child: IndexedStack(
                  index: shown < 0 ? 0 : shown,
                  sizing: StackFit.expand,
                  children: <Widget>[
                    // Keyed by tab: closing or inserting a tab must not hand
                    // another tab's page to it (that rebuilt and reloaded it).
                    for (final t in loaded)
                      KeyedSubtree(
                        key: ValueKey(t.id),
                        child: Obx(() => TabWebView(key: ValueKey(t.webKey.value), tab: t)),
                      ),
                  ],
                ),
              ),
            ),
          if (shown < 0 || tab.showingNewTab.value) Positioned.fill(child: NewTabPage(tab: tab)),
          if (tab.addressFocused.value) Positioned.fill(child: AddressSuggestions(tab: tab)),
        ],
      );
    });
  }
}

/// The top bar slides away while reading, like Chrome's (kept on weak
/// phones), and the page moves with it.
///
/// Only one page resize per show/hide: a WebView resize re-lays out the
/// whole page, so animating the bar's height (a resize every frame) was
/// janky. Hiding: the page takes the bar's space at once but is drawn
/// shifted down by the bar's height, so nothing moves; then bar and page
/// slide up together. Showing is the reverse: they slide down, then the
/// page gives the space back in the same frame its shift ends.
class _BarAndPage extends StatefulWidget {
  const _BarAndPage({required this.tab, required this.bar, required this.page});

  final BrowserController tab;
  final Widget bar;
  final Widget page;

  @override
  State<_BarAndPage> createState() => _BarAndPageState();
}

class _BarAndPageState extends State<_BarAndPage> with SingleTickerProviderStateMixin {
  /// 1 = bar shown, 0 = hidden.
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _shown, curve: Curves.easeOutCubic);

  bool _target = true;

  /// The page leaves room above it for the bar.
  bool _takesSpace = true;

  /// Measured after each layout; the first frame uses the usual height.
  double? _barHeight;

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  void _apply(bool shown) {
    if (!mounted || shown == _target) return;
    _target = shown;
    if (shown) {
      _shown.forward().whenCompleteOrCancel(() {
        if (mounted && _target && !_takesSpace) setState(() => _takesSpace = true);
      });
    } else {
      if (_takesSpace) setState(() => _takesSpace = false);
      _shown.reverse();
    }
  }

  void _measured(Size size) {
    if (mounted && size.height != _barHeight) setState(() => _barHeight = size.height);
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = _barHeight ?? 58 * context.scale;
    return Obx(() {
      final tab = widget.tab;
      // Every value read first: `lowEnd || …` stopped at lowEnd on low-end phones, so the Obx read nothing
      // and GetX replaced the whole browser with its "improper use" error page.
      final asked = [
        tab.barShown.value,
        tab.loading,
        tab.addressFocused.value,
        tab.finding.value,
        tab.showingNewTab.value,
      ];
      final shown = DeviceProfile.lowEnd || asked.contains(true);
      if (shown != _target) WidgetsBinding.instance.addPostFrameCallback((_) => _apply(shown));
      return Stack(
        children: <Widget>[
          Positioned.fill(
            top: _takesSpace ? barHeight : 0,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _curve,
                // The same page widget: moving it doesn't rebuild it.
                child: widget.page,
                builder: (_, page) =>
                    Transform.translate(offset: Offset(0, _takesSpace ? 0 : barHeight * _curve.value), child: page),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _curve,
              child: _SizeReporter(onSize: _measured, child: widget.bar),
              builder: (_, bar) => Transform.translate(offset: Offset(0, -barHeight * (1 - _curve.value)), child: bar),
            ),
          ),
        ],
      );
    });
  }
}

/// Reports its child's laid-out size after the frame (when it changes).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _reported) return;
    _reported = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.tab});

  final BrowserController tab;

  @override
  Widget build(BuildContext context) => Obx(() => _line(context));

  Widget _line(BuildContext context) {
    final double scale = context.scale;
    final p = tab.progress.value;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: tab.loading ? 1 : 0,
      child: SizedBox(
        height: 2.5 * scale,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: p.clamp(0.05, 1).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: BrandColors.of(context).progressGradient),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.onClose});

  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16 * scale, 10 * scale, onClose == null ? 16 * scale : 4 * scale, 10 * scale),
      color: BrandColors.of(context).primary.withValues(alpha: 0.12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w500, color: ink),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 18 * scale, color: ink.withValues(alpha: 0.6)),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session, required this.tab});

  final BrowserSession session;
  final BrowserController tab;

  @override
  Widget build(BuildContext context) => Obx(() => _bar(context));

  Widget _bar(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final bool editing = tab.addressFocused.value;
    final bool page = !tab.showingNewTab.value;

    return Padding(
      padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 4 * scale, 8 * scale),
      child: Row(
        children: <Widget>[
          if (!editing) ...<Widget>[
            RoundIconButton(icon: Icons.close_rounded, size: 40, onTap: Get.back, tooltip: 'Close browser'),
            SizedBox(width: 4 * scale),
          ],
          Expanded(
            child: Container(
              height: 42 * scale,
              padding: EdgeInsets.symmetric(horizontal: 12 * scale),
              decoration: BoxDecoration(
                color: ColorConstants.surfaceOn(dark),
                borderRadius: BorderRadius.circular(21 * scale),
                border: Border.all(color: ink.withValues(alpha: dark ? 0.12 : 0.06)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    editing || !page
                        ? Icons.search_rounded
                        : tab.url.value.startsWith('https')
                        ? Icons.lock_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 16 * scale,
                    color: ink.withValues(alpha: 0.55),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Focus(
                      onFocusChange: tab.onAddressFocus,
                      child: TextField(
                        controller: tab.address,
                        focusNode: tab.addressFocus,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: tab.onAddressChanged,
                        onSubmitted: tab.submit,
                        style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w500, color: ink),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Search Google or type web address',
                          hintStyle: TextStyle(fontSize: 14 * scale, color: ink.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                  ),
                  if (editing)
                    // The ✕ follows the text as you type (not a reactive value).
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: tab.address,
                      builder: (_, v, _) => v.text.isEmpty
                          ? const SizedBox.shrink()
                          : InkResponse(
                              onTap: () {
                                tab.address.clear();
                                tab.onAddressChanged('');
                              },
                              child: Icon(Icons.cancel_rounded, size: 18 * scale, color: ink.withValues(alpha: 0.4)),
                            ),
                    )
                  else if (page && tab.blockAds)
                    _AdShield(controller: tab, ink: ink, scale: scale),
                ],
              ),
            ),
          ),
          if (!editing) ...<Widget>[
            SizedBox(width: 2 * scale),
            const _DownloadsWhileActive(),
            TabCountButton(session: session),
            IconButton(
              tooltip: 'More',
              onPressed: () => showBrowserMenu(session),
              icon: Icon(Icons.more_vert_rounded, color: ink),
            ),
          ],
        ],
      ),
    );
  }
}

/// The downloads button only while something downloads (its ring shows
/// progress); otherwise Downloads is in the ⋮ menu.
class _DownloadsWhileActive extends StatelessWidget {
  const _DownloadsWhileActive();

  @override
  Widget build(BuildContext context) => Obx(
    () => Get.find<DownloadsController>().tasks.any((t) => t.isActive)
        ? const BrowserDownloadsButton()
        : const SizedBox.shrink(),
  );
}

/// Find in page: the words, "2/5", previous / next.
class _FindBar extends StatefulWidget {
  const _FindBar({required this.tab});

  final BrowserController tab;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final tab = widget.tab;
    return Padding(
      padding: EdgeInsets.fromLTRB(4 * scale, 8 * scale, 4 * scale, 8 * scale),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close',
            onPressed: tab.stopFind,
            icon: Icon(Icons.arrow_back_rounded, color: ink),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: tab.find,
              onSubmitted: (_) => tab.findNext(),
              style: TextStyle(fontSize: 15 * scale, color: ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Find in page',
                hintStyle: TextStyle(fontSize: 15 * scale, color: ink.withValues(alpha: 0.45)),
              ),
            ),
          ),
          Obx(() {
            final m = tab.findMatches.value;
            return Text(
              _text.text.isEmpty ? '' : findCount(m.active, m.total),
              style: TextStyle(fontSize: 13 * scale, color: ink.withValues(alpha: 0.6)),
            );
          }),
          IconButton(
            tooltip: 'Previous',
            onPressed: () => tab.findNext(forward: false),
            icon: Icon(Icons.keyboard_arrow_up_rounded, color: ink),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: tab.findNext,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: ink),
          ),
        ],
      ),
    );
  }
}

/// In the address bar: ads blocked on this page; tap to allow ads on the site.
class _AdShield extends StatelessWidget {
  const _AdShield({required this.controller, required this.ink, required this.scale});

  final BrowserController controller;
  final Color ink;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final blocked = controller.adsBlocked.value;
      controller.url.value; // rebuild when the site changes
      SettingsService.to.adsAllowedSites.length;
      final allowed = controller.adsAllowedHere;
      return Tooltip(
        message: allowed ? 'Ads allowed on this site' : 'Ads blocked',
        child: InkWell(
          onTap: controller.showAdMenu,
          borderRadius: BorderRadius.circular(8 * scale),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 6 * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  allowed ? Icons.shield_outlined : Icons.shield_rounded,
                  size: 16 * scale,
                  color: allowed ? ink.withValues(alpha: 0.4) : BrandColors.of(context).primary,
                ),
                if (!allowed && blocked > 0) ...[
                  SizedBox(width: 3 * scale),
                  Text(
                    blocked > 99 ? '99+' : '$blocked',
                    style: TextStyle(
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.w700,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Bottom-right media button: grey "find videos" until something is found,
/// then coloured with a count, or "Download" on supported pages. Slides
/// away while the page scrolls down.
class _MediaButton extends StatelessWidget {
  const _MediaButton({required this.controller});

  final BrowserController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    return Obx(() {
      final mode = controller.mediaButton;
      final count = controller.capture.items.length;
      final shown = mode != MediaButtonMode.hidden && controller.mediaButtonShown.value;

      final Widget button = switch (mode) {
        MediaButtonMode.download => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12 * scale),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: brand.primary.withValues(alpha: 0.35),
                blurRadius: 16 * scale,
                offset: Offset(0, 6 * scale),
              ),
            ],
          ),
          child: GradientPill(
            label: 'Download',
            icon: Icons.download_rounded,
            compact: true,
            height: 46,
            onTap: controller.onFab,
          ),
        ),
        MediaButtonMode.found => Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            RoundIconButton(
              icon: Icons.video_library_rounded,
              size: 54,
              filled: true,
              onTap: controller.onFab,
              tooltip: '$count found on this page',
            ),
            Positioned(
              right: -2 * scale,
              top: -2 * scale,
              child: IgnorePointer(
                child: Container(
                  constraints: BoxConstraints(minWidth: 20 * scale),
                  padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                  decoration: BoxDecoration(
                    color: ColorConstants.white,
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(color: brand.primary, width: 1.5 * scale),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w800, color: brand.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
        _ => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ColorConstants.surfaceOn(dark),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: ColorConstants.black.withValues(alpha: dark ? 0.4 : 0.14),
                blurRadius: 12 * scale,
                offset: Offset(0, 4 * scale),
              ),
            ],
          ),
          child: RoundIconButton(
            icon: Icons.travel_explore_rounded,
            size: 46,
            onTap: controller.onFab,
            tooltip: 'Find videos on this page',
          ),
        ),
      };

      return AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: shown ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: shown ? 1 : 0,
          child: IgnorePointer(ignoring: !shown, child: button),
        ),
      );
    });
  }
}
