import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/round_icon_button.dart';
import '../../../services/settings_service.dart';
import '../controllers/browser_controller.dart';
import '../media_button.dart';
import 'downloads_sheet.dart';

class BrowserView extends GetView<BrowserController> {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await controller.handleBack()) Get.back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: ColorConstants.pageOn(dark),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _TopBar(controller: controller),
                Obx(() {
                  final p = controller.progress.value;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: p < 1 ? 1 : 0,
                    child: SizedBox(
                      height: 2.5 * scale,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: p.clamp(0.05, 1).toDouble(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: BrandColors.of(context).progressGradient),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (controller.refreshFor != null) _RefreshBanner(title: controller.refreshFor!.title),
                Expanded(
                  child: Obx(
                    () => InAppWebView(
                      key: ValueKey(controller.webKey.value),
                      initialUrlRequest: URLRequest(url: WebUri(controller.restoreUrl)),
                      initialSettings: controller.settings,
                      initialUserScripts: controller.userScripts,
                      onWebViewCreated: controller.onCreated,
                      onLoadStart: (_, url) => controller.onLoadStart(url),
                      onScrollChanged: (_, _, y) => controller.onScroll(y),
                      onUpdateVisitedHistory: (_, url, _) => controller.onHistoryChanged(url),
                      onTitleChanged: (_, t) => controller.onTitle(t),
                      onProgressChanged: (_, p) => controller.onProgress(p),
                      shouldOverrideUrlLoading: (_, action) async => controller.onNavigate(action),
                      onDownloadStartRequest: (_, request) => controller.onDownloadStart(request),
                      shouldInterceptRequest: controller.blockAds ? (_, request) => controller.onRequest(request) : null,
                      onRenderProcessGone: (_, _) => controller.onRendererGone(),
                      onWebContentProcessDidTerminate: (_) => controller.onIosProcessGone(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: _MediaButton(controller: controller),
        ),
      ),
    );
  }
}

class _RefreshBanner extends StatelessWidget {
  const _RefreshBanner({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
      color: BrandColors.of(context).primary.withValues(alpha: 0.12),
      child: Text(
        'Play the video to refresh the link of "$title".',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w500, color: ink),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final BrowserController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    return Padding(
      padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 8 * scale, 8 * scale),
      child: Row(
        children: <Widget>[
          RoundIconButton(icon: Icons.close_rounded, size: 40, onTap: Get.back, tooltip: 'Close'),
          SizedBox(width: 4 * scale),
          Expanded(
            child: Container(
              height: 42 * scale,
              padding: EdgeInsets.symmetric(horizontal: 12 * scale),
              decoration: BoxDecoration(
                color: ColorConstants.surfaceOn(dark),
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(color: ink.withValues(alpha: dark ? 0.12 : 0.06)),
              ),
              child: Row(
                children: <Widget>[
                  Obx(() => Icon(
                        controller.url.value.startsWith('https')
                            ? Icons.lock_rounded
                            : Icons.public_rounded,
                        size: 15 * scale,
                        color: ink.withValues(alpha: 0.5),
                      )),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Focus(
                      onFocusChange: controller.onAddressFocus,
                      child: TextField(
                        controller: controller.address,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        onSubmitted: controller.submit,
                        onTap: () => controller.address.selection = TextSelection(
                            baseOffset: 0, extentOffset: controller.address.text.length),
                        style: TextStyle(fontSize: 13.5 * scale, fontWeight: FontWeight.w500, color: ink),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Search or enter address',
                          hintStyle: TextStyle(
                            fontSize: 13.5 * scale,
                            color: ink.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (controller.blockAds) _AdShield(controller: controller, ink: ink, scale: scale),
                ],
              ),
            ),
          ),
          SizedBox(width: 4 * scale),
          RoundIconButton(icon: Icons.refresh_rounded, size: 40, onTap: controller.reload, tooltip: 'Reload'),
          Obx(() => controller.canGoForward.value
              ? RoundIconButton(
                  icon: Icons.arrow_forward_rounded,
                  size: 40,
                  onTap: controller.goForward,
                  tooltip: 'Forward',
                )
              : const SizedBox.shrink()),
          const BrowserDownloadsButton(),
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
                    style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.7)),
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
