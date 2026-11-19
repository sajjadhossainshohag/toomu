import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Simple flat app bar used at the top of every main tab: bold title (and an
/// optional small subtitle) on the left, icon buttons on the right, and an
/// optional [bottom] row (e.g. the search field) underneath. Page-colored,
/// no gradient — like most apps.
class AppHeader extends StatelessWidget {
  const AppHeader({
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.onBack,
    this.backIcon = Icons.arrow_back_rounded,
    this.bottom,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final IconData backIcon;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: ColorConstants.pageOn(dark),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 56 * scale,
                child: Padding(
                  padding: EdgeInsets.only(left: (onBack == null ? 16 : 4) * scale, right: 6 * scale),
                  child: Row(
                    children: <Widget>[
                      if (onBack != null)
                        IconButton(
                          onPressed: onBack,
                          icon: Icon(backIcon, color: ink),
                          tooltip: backIcon == Icons.close_rounded
                              ? MaterialLocalizations.of(context).closeButtonTooltip
                              : MaterialLocalizations.of(context).backButtonTooltip,
                        ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22 * scale,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: ink,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: ink.withValues(alpha: 0.55),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              if (bottom != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      DesignMetrics.gutter * scale, 2 * scale, DesignMetrics.gutter * scale, 6 * scale),
                  child: bottom,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain icon button for [AppHeader.actions].
class HeaderAction extends StatelessWidget {
  const HeaderAction({required this.icon, required this.onTap, this.tooltip, super.key});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 24 * context.scale),
        color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.85),
      );
}

class PageBackHeader extends StatelessWidget {
  const PageBackHeader({required this.title, this.actions = const <Widget>[], super.key});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          DesignMetrics.gutter * scale, 12 * scale, DesignMetrics.gutter * scale, 8 * scale),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: EdgeInsets.all(4 * scale),
              child: SvgPicture.asset(
                'assets/icons/back_arrow.svg',
                matchTextDirection: true,
                width: 24 * scale,
                height: 24 * scale,
                colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: ink,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
