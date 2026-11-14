import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import 'gradient_rounded_border.dart';

/// Search / link input. Idle: surface card with soft brand shadow and a
/// tinted glyph badge. Focused: gradient rim + gradient badge.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.autofocus = false,
    super.key,
  });

  static const double radius = 16;
  static const Duration fade = Duration(milliseconds: 200);

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Extra action shown when the field is empty (e.g. "paste").
  final Widget? trailing;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _text =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.addListener(_refresh);
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _text.removeListener(_refresh);
    if (widget.controller == null) _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _clear() {
    _text.clear();
    widget.onChanged?.call('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final bool focused = _focus.hasFocus;
    final bool filled = _text.text.isNotEmpty;
    final BrandColors brand = BrandColors.of(context);
    final double corner = AppSearchField.radius * scale;
    final Color ink = ColorConstants.textOn(dark);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: AnimatedContainer(
        duration: AppSearchField.fade,
        curve: Curves.easeOut,
        height: 52 * scale,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceOn(dark),
          borderRadius: BorderRadius.circular(corner),
          border: Border.all(
            color: ink.withValues(alpha: focused ? 0 : (dark ? 0.16 : 0.06)),
            width: scale,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: brand.primary
                  .withValues(alpha: focused ? 0.2 : (dark ? 0 : 0.06)),
              blurRadius: (focused ? 18 : 10) * scale,
              offset: Offset(0, (focused ? 6 : 3) * scale),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: AppSearchField.fade,
                  opacity: focused ? 1 : 0,
                  child: GradientRoundedBorder(
                    radius: corner,
                    gradient: brand.pillGradient,
                    strokeWidth: 1.5 * scale,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(start: 8 * scale, end: 8 * scale),
              child: Row(
                children: <Widget>[
                  _badge(brand, scale, dark, focused),
                  SizedBox(width: 10 * scale),
                  Expanded(child: _field(scale, ink)),
                  AnimatedSwitcher(
                    duration: AppSearchField.fade,
                    child: filled
                        ? _clearButton(brand, scale)
                        : (widget.trailing ?? const SizedBox.shrink()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(double scale, Color ink) => TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: (v) {
          _focus.unfocus();
          widget.onSubmitted?.call(v);
        },
        onTapOutside: (_) => _focus.unfocus(),
        textInputAction: TextInputAction.search,
        autocorrect: false,
        cursorColor: BrandColors.of(context).primary,
        cursorWidth: 1.5,
        style: TextStyle(
          fontSize: 15 * scale,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ink,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: 15 * scale,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: ink.withValues(alpha: context.isDark ? 0.5 : 0.45),
          ),
        ),
      );

  Widget _badge(BrandColors brand, double scale, bool dark, bool focused) {
    final double size = 36 * scale;
    final BorderRadius corner = BorderRadius.circular(12 * scale);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: brand.primary.withValues(alpha: dark ? 0.24 : 0.1),
              borderRadius: corner,
            ),
          ),
          AnimatedOpacity(
            duration: AppSearchField.fade,
            opacity: focused ? 1 : 0,
            child: Container(
              decoration: BoxDecoration(gradient: brand.pillGradient, borderRadius: corner),
            ),
          ),
          SvgPicture.asset(
            'assets/icons/picker_search.svg',
            width: 18 * scale,
            height: 18 * scale,
            colorFilter: ColorFilter.mode(
              focused ? ColorConstants.white : brand.primary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _clearButton(BrandColors brand, double scale) => InkResponse(
        key: const ValueKey<String>('clear'),
        onTap: _clear,
        radius: 18 * scale,
        child: SizedBox.square(
          dimension: 36 * scale,
          child: Center(
            child: Container(
              width: 20 * scale,
              height: 20 * scale,
              decoration: BoxDecoration(gradient: brand.pillGradient, shape: BoxShape.circle),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/close.svg',
                  width: 9 * scale,
                  height: 9 * scale,
                  colorFilter: const ColorFilter.mode(ColorConstants.white, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      );
}
