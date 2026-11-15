import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/round_icon_button.dart';
import '../controllers/browser_controller.dart';

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
                      onUpdateVisitedHistory: (_, url, _) => controller.onHistoryChanged(url),
                      onTitleChanged: (_, t) => controller.onTitle(t),
                      onProgressChanged: (_, p) => controller.onProgress(p),
                      shouldOverrideUrlLoading: (_, action) async => controller.onNavigate(action),
                      onDownloadStartRequest: (_, request) => controller.onDownloadStart(request),
                      onRenderProcessGone: (_, _) => controller.onRendererGone(),
                      onWebContentProcessDidTerminate: (_) => controller.onIosProcessGone(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Obx(() {
            final label = controller.fabLabel;
            final hidden = label == null;
            final icon = controller.extractor.value != null
                ? Icons.download_rounded
                : controller.capture.items.isNotEmpty
                ? Icons.video_library_rounded
                : Icons.travel_explore_rounded;
            return AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              offset: hidden ? const Offset(0, 2) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: hidden ? 0 : 1,
                child: IgnorePointer(
                  ignoring: hidden,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12 * scale),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: BrandColors.of(context).primary.withValues(alpha: 0.4),
                          blurRadius: 20 * scale,
                          offset: Offset(0, 8 * scale),
                        ),
                      ],
                    ),
                    child: GradientPill(
                      label: label ?? 'Download',
                      icon: icon,
                      compact: true,
                      height: 50,
                      onTap: controller.onFab,
                    ),
                  ),
                ),
              ),
            );
          }),
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
        ],
      ),
    );
  }
}
