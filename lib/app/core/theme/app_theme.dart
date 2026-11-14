import 'package:flutter/material.dart';

import 'brand_colors.dart';
import 'color_constants.dart';

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Plus Jakarta Sans';
  static const double cardRadius = 16;
  static const double tileRadius = 20;

  static ThemeData get light => _build(_scheme(BrandColors.ocean, dark: false));
  static ThemeData get dark => _build(_scheme(BrandColors.ocean, dark: true));

  static ColorScheme _scheme(BrandColors brand, {required bool dark}) {
    final Color ink = ColorConstants.textOn(dark);
    final Color card = ColorConstants.cardOn(dark);
    return ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: brand.primary,
      onPrimary: ColorConstants.white,
      primaryContainer: brand.primary.withValues(alpha: 0.12),
      onPrimaryContainer: brand.primary,
      secondary: brand.accent,
      onSecondary: ColorConstants.white,
      secondaryContainer: brand.accent.withValues(alpha: 0.12),
      onSecondaryContainer: brand.accent,
      tertiary: ColorConstants.success,
      onTertiary: ColorConstants.white,
      error: ColorConstants.error,
      onError: ColorConstants.white,
      errorContainer: ColorConstants.error.withValues(alpha: 0.12),
      onErrorContainer: ColorConstants.error,
      surface: ColorConstants.pageOn(dark),
      onSurface: ink,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: ColorConstants.surfaceOn(dark),
      surfaceContainerHighest: ink.withValues(alpha: 0.06),
      onSurfaceVariant: ink.withValues(alpha: dark ? 0.6 : 0.62),
      outline: ink.withValues(alpha: 0.16),
      outlineVariant: ink.withValues(alpha: 0.08),
      inverseSurface: ColorConstants.textOn(dark),
      onInverseSurface: ColorConstants.textOn(!dark),
      inversePrimary: brand.accent,
      shadow: ColorConstants.black.withValues(alpha: dark ? 0.2 : 0.08),
      scrim: ColorConstants.black.withValues(alpha: dark ? 0.6 : 0.4),
    );
  }

  static ThemeData _build(ColorScheme scheme) {
    final TextTheme text = _textTheme(scheme);
    const BrandColors brand = BrandColors.ocean;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brand.primary,
        selectionColor: brand.primary.withValues(alpha: 0.25),
        selectionHandleColor: brand.primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: ColorConstants.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: ColorConstants.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(style: _pillButton(text)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _pillButton(text)),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.primary),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: _fieldBorder(scheme.outline),
        enabledBorder: _fieldBorder(scheme.outline),
        focusedBorder: _fieldBorder(scheme.primary, width: 1.5),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: ColorConstants.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: text.bodyLarge,
      ),
      // Sheets draw their own surface + handle (AppSheet); the theme only
      // limits the width so landscape sheets don't cover the whole screen.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ColorConstants.transparent,
        surfaceTintColor: ColorConstants.transparent,
        elevation: 0,
        showDragHandle: false,
        constraints: BoxConstraints(maxWidth: 480),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: ColorConstants.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
        titleTextStyle: text.titleMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        iconColor: scheme.onSurfaceVariant,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: brand.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.1),
        thumbColor: ColorConstants.white,
        overlayColor: brand.primary.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 2),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: brand.primary),
      splashFactory: InkSparkle.splashFactory,
      extensions: const <ThemeExtension<dynamic>>[brand],
    );
  }

  static ButtonStyle _pillButton(TextTheme text) => ButtonStyle(
        elevation: const WidgetStatePropertyAll<double>(0),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
      );

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: color, width: width),
      );

  static TextTheme _textTheme(ColorScheme scheme) {
    final Color on = scheme.onSurface;
    final Color muted = scheme.onSurfaceVariant;
    TextStyle s(double size, FontWeight w, Color c) =>
        TextStyle(fontSize: size, fontWeight: w, letterSpacing: 0, color: c);
    return TextTheme(
      headlineLarge: s(32, FontWeight.w700, on),
      headlineMedium: s(28, FontWeight.w700, on),
      headlineSmall: s(24, FontWeight.w700, on),
      titleLarge: s(20, FontWeight.w700, on),
      titleMedium: s(16, FontWeight.w600, on),
      titleSmall: s(14, FontWeight.w600, on),
      bodyLarge: s(16, FontWeight.w400, on),
      bodyMedium: s(14, FontWeight.w400, on),
      bodySmall: s(13, FontWeight.w400, muted),
      labelLarge: s(15, FontWeight.w700, on),
      labelMedium: s(13, FontWeight.w600, muted),
      labelSmall: s(12, FontWeight.w600, muted),
    );
  }
}
