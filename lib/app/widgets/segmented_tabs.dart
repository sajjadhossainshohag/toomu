import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';

/// Horizontal pill tabs; the selected pill uses the brand pill gradient.
class SegmentedTabs extends StatefulWidget {
  const SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.scrollable = false,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool scrollable;

  @override
  State<SegmentedTabs> createState() => _SegmentedTabsState();
}

class _SegmentedTabsState extends State<SegmentedTabs> {
  final List<GlobalKey> _keys = <GlobalKey>[];
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> get labels => widget.labels;
  int get selected => widget.selected;
  ValueChanged<int> get onSelect => widget.onSelect;

  @override
  void didUpdateWidget(SegmentedTabs old) {
    super.didUpdateWidget(old);
    // Selected by a swipe: bring the pill into view.
    if (widget.scrollable && old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = widget.selected < _keys.length ? _keys[widget.selected].currentContext : null;
        final box = ctx?.findRenderObject();
        if (box == null || !box.attached || !_scroll.hasClients) return;
        // Only the pill row scrolls (not a page scroll it sits inside).
        final target = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.5).offset;
        final position = _scroll.position;
        _scroll.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final Color ink = ColorConstants.textOn(dark);

    Widget pill(int i) {
      final bool on = i == selected;
      return GestureDetector(
        key: _keys[i],
        onTap: () => onSelect(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 38 * scale,
          padding: EdgeInsets.symmetric(horizontal: 18 * scale),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? brand.pillGradient : null,
            color: on ? null : ColorConstants.groupOn(dark),
            borderRadius: BorderRadius.circular(12 * scale),
            border: on
                ? null
                : Border.all(color: ink.withValues(alpha: dark ? 0.08 : 0.06)),
          ),
          child: Text(
            labels[i],
            style: TextStyle(
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: on ? ColorConstants.white : ink.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    while (_keys.length < labels.length) {
      _keys.add(GlobalKey());
    }

    final EdgeInsets pad = EdgeInsets.symmetric(horizontal: DesignMetrics.gutter * scale);
    if (widget.scrollable) {
      // Few pills: a plain scroll row keeps every pill built, so the
      // selected one can always be scrolled into view.
      return SizedBox(
        height: 38 * scale,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: pad,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < labels.length; i++) ...<Widget>[
                if (i > 0) SizedBox(width: 8 * scale),
                pill(i),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: pad,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: 8 * scale),
            Expanded(child: pill(i)),
          ],
        ],
      ),
    );
  }
}
