import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/browser_store.dart';
import '../../../services/remote_config_service.dart';
import '../controllers/browser_controller.dart';
import 'site_icon.dart';

/// Chrome's new-tab page: a search box, Toomu's site shortcuts and your
/// most visited sites.
class NewTabPage extends StatelessWidget {
  const NewTabPage({required this.tab, super.key});

  final BrowserController tab;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final BrandColors brand = BrandColors.of(context);

    Widget tile({required Widget icon, required String label, required VoidCallback onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14 * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 50 * scale,
              height: 50 * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ColorConstants.surfaceOn(dark), shape: BoxShape.circle),
              child: icon,
            ),
            SizedBox(height: 6 * scale),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );

    Widget grid(List<Widget> children) => GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.82,
      children: children,
    );

    Widget heading(String text) => Padding(
      padding: EdgeInsets.fromLTRB(4 * scale, 18 * scale, 0, 4 * scale),
      child: Text(
        text,
        style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.55)),
      ),
    );

    return ColoredBox(
      color: ColorConstants.pageOn(dark),
      child: ListView(
        padding: EdgeInsets.fromLTRB(20 * scale, 36 * scale, 20 * scale, 24 * scale),
        children: <Widget>[
          Center(
            child: ShaderMask(
              shaderCallback: (r) => brand.headerGradient.createShader(r),
              child: Text(
                'Toomu',
                style: TextStyle(
                  fontSize: 40 * scale,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          SizedBox(height: 22 * scale),
          // Tapping the box types in the address bar, like Chrome's.
          GestureDetector(
            onTap: tab.addressFocus.requestFocus,
            child: Container(
              height: 50 * scale,
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              decoration: BoxDecoration(
                color: ColorConstants.surfaceOn(dark),
                borderRadius: BorderRadius.circular(25 * scale),
                border: Border.all(color: ink.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search_rounded, size: 22 * scale, color: ink.withValues(alpha: 0.5)),
                  SizedBox(width: 10 * scale),
                  Text(
                    'Search or type web address',
                    style: TextStyle(fontSize: 14.5 * scale, color: ink.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
          heading('Shortcuts'),
          Obx(
            () => grid([
              for (final s in RemoteConfigService.to.sites)
                tile(
                  icon: Icon(s.icon, color: s.color, size: 24 * scale),
                  label: s.name,
                  onTap: () => tab.navigate(s.url),
                ),
            ]),
          ),
          Obx(() {
            BrowserStore.to.historyVersion.value;
            final top = BrowserStore.to.history.mostVisited(8);
            if (top.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                heading('Most visited'),
                grid([
                  for (final v in top)
                    tile(
                      icon: SiteIcon(url: v.url, size: 26),
                      label: Uri.parse(v.url).host.replaceFirst(RegExp(r'^(www|m)\.'), ''),
                      onTap: () => tab.navigate(v.url),
                    ),
                ]),
              ],
            );
          }),
        ],
      ),
    );
  }
}
