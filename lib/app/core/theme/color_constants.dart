import 'package:flutter/material.dart';

/// Raw design tokens. Widgets should prefer [BrandColors.of] /
/// `Theme.of(context)` and only read these for neutral/fixed colors.
class ColorConstants {
  const ColorConstants._();

  // ─── Brand ──────────────────────────────────────────────────────────────

  // Violet. Change these to re-brand: every widget reads them through
  // BrandColors / the theme.
  static const Color primary       = Color(0xFF7C4DFF);
  static const Color accent        = Color(0xFF9E7BFF);
  static const Color gradientStart = Color(0xFF5B2BE0);
  static const Color gradientEnd   = Color(0xFFB69CFF);
  static const Color pillLight     = Color(0xFF9C7DFF);
  static const Color pillRimTop    = Color(0xFF44431A);
  static const Color pillRimBottom = Color(0xFF272918);
  static const Color unlockStart   = Color(0xFF6A3BF2);
  static const Color unlockEnd     = Color(0xFFC4A6FF);
  static const Color switchEnd     = Color(0xFFD6C2FF);

  // ─── Status ─────────────────────────────────────────────────────────────

  static const Color error   = Color(0xFFE63946);
  static const Color success = Color(0xFF12A150);
  static const Color warning = Color(0xFFDC6803);
  static const Color premium = Color(0xFFFF0152);

  // ─── Neutral ────────────────────────────────────────────────────────────

  static const Color white       = Color(0xFFFFFFFF);
  static const Color black       = Color(0xFF000000);
  static const Color chevron     = Color(0xFF66686A);
  static const Color transparent = Color(0x00000000);

  // ─── Light theme ────────────────────────────────────────────────────────

  static const Color lightText    = Color(0xFF1C1B1F);
  static const Color lightPage    = Color(0xFFF6F4FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFFFFFFF);

  // ─── Dark theme ─────────────────────────────────────────────────────────

  static const Color darkText    = Color(0xFFFFFFFF);
  static const Color darkPage    = Color(0xFF131218);
  static const Color darkSurface = Color(0xFF201E26);
  static const Color darkCard    = Color(0xFF1C1A22);

  // ─── Theme pickers ──────────────────────────────────────────────────────

  static Color textOn(bool dark) => dark ? darkText : lightText;
  static Color pageOn(bool dark) => dark ? darkPage : lightPage;
  static Color surfaceOn(bool dark) => dark ? darkSurface : lightSurface;
  static Color cardOn(bool dark) => dark ? darkCard : lightCard;

  /// Grouped-card background (settings groups, list cards).
  static Color groupOn(bool dark) =>
      dark ? white.withValues(alpha: 0.04) : lightCard;

  // ─── Feature tile tints (settings rows, quick actions) ──────────────────

  static const Color tileTheme     = Color(0xFFA11792);
  static const Color tileStorage   = Color(0xFFB14E24);
  static const Color tileDownloads = Color(0xFF3D63DD);
  static const Color tileAudio     = Color(0xFF8370C8);
  static const Color tileVideo     = Color(0xFFE5484D);
  static const Color tileFolder    = Color(0xFF27727E);
  static const Color tilePrivacy   = Color(0xFF24B1B1);
  static const Color tileShare     = Color(0xFF30AFFF);
  static const Color tileRate      = Color(0xFFFF9100);
  static const Color tileAbout     = Color(0xFF66BB6A);
  static const Color tileTimer     = Color(0xFF7C5CDB);
  static const Color tileEqualizer = Color(0xFFE5732E);
  static const Color tileFavorite  = Color(0xFFFF788D);

  // ─── Sites (browser start page) ────────────────────────────────────────

  static const Color siteYoutube      = Color(0xFFFF0033);
  static const Color siteYoutubeMusic = Color(0xFFE5484D);
  static const Color siteGoogle       = Color(0xFF3D63DD);

  // ─── Gradients ──────────────────────────────────────────────────────────

  static const List<double> _sweepStops = <double>[0.0936, 0.59593];

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[gradientStart, gradientEnd],
  );

  /// Curved page header band.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment(0.3407, -1.731),
    end: Alignment(-0.3407, 1.731),
    stops: _sweepStops,
    colors: <Color>[gradientEnd, gradientStart],
  );

  /// Hero / promo cards.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment(0.1996, -1.8874),
    end: Alignment(-0.1996, 1.8874),
    stops: _sweepStops,
    colors: <Color>[gradientEnd, gradientStart],
  );

  /// Small square/circle badges and artwork placeholders.
  static const LinearGradient badgeGradient = LinearGradient(
    begin: Alignment(1.04874, -0.94596),
    end: Alignment(-1.04874, 0.94596),
    stops: _sweepStops,
    colors: <Color>[gradientEnd, gradientStart],
  );

  static const LinearGradient switchGradient = LinearGradient(
    colors: <Color>[unlockStart, switchEnd],
  );

  /// Progress bars (downloads, seek bar).
  /// Watch / play buttons: warm coral next to the violet download button.
  static const LinearGradient watchGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFFF7A8A), Color(0xFFF0386B)],
  );

  static const LinearGradient progressGradient = LinearGradient(
    colors: <Color>[unlockStart, unlockEnd],
  );
}
