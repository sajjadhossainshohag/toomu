import 'package:flutter/material.dart';

import 'color_constants.dart';

/// Brand palette exposed through the theme so widgets never hard-code the
/// brand color. A future "accent colour" setting only needs a new instance.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.primary,
    required this.accent,
    required this.gradientStart,
    required this.gradientEnd,
    required this.pillLight,
  });

  static const BrandColors ocean = BrandColors(
    primary: ColorConstants.primary,
    accent: ColorConstants.accent,
    gradientStart: ColorConstants.gradientStart,
    gradientEnd: ColorConstants.gradientEnd,
    pillLight: ColorConstants.pillLight,
  );

  final Color primary;
  final Color accent;
  final Color gradientStart;
  final Color gradientEnd;
  final Color pillLight;

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>() ?? ocean;

  LinearGradient get headerGradient => _recolor(ColorConstants.headerGradient);
  LinearGradient get badgeGradient => _recolor(ColorConstants.badgeGradient);
  LinearGradient get switchGradient => ColorConstants.switchGradient;
  LinearGradient get progressGradient => ColorConstants.progressGradient;

  /// Glassy pill used for primary buttons, selected chips and nav items.
  LinearGradient get pillGradient => LinearGradient(
        begin: const Alignment(0.79705, -0.83026),
        end: const Alignment(0.68015, 2.74982),
        stops: const <double>[0, 0.571067],
        colors: <Color>[pillLight, gradientStart],
      );

  LinearGradient _recolor(LinearGradient shape) => LinearGradient(
        begin: shape.begin,
        end: shape.end,
        stops: shape.stops,
        colors: <Color>[gradientEnd, gradientStart],
      );

  @override
  BrandColors copyWith({
    Color? primary,
    Color? accent,
    Color? gradientStart,
    Color? gradientEnd,
    Color? pillLight,
  }) =>
      BrandColors(
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        gradientStart: gradientStart ?? this.gradientStart,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        pillLight: pillLight ?? this.pillLight,
      );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
      pillLight: Color.lerp(pillLight, other.pillLight, t)!,
    );
  }
}
