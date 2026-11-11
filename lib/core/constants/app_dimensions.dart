import 'package:flutter/material.dart';

/// Centralized dimensions, paddings, and radii according to DocuRay design rules.
abstract final class AppDimensions {
  // ─── Radii ───────────────────────────────────────────────────
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;
  static const double radiusInput = 12.0;
  static const double radiusSheet = 24.0;
  static const double radiusPill = 999.0;
  static const double radiusThumbnail = 8.0;
  static const double radiusSmall = 6.0;

  static const BorderRadius borderCard = BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius borderButton = BorderRadius.all(Radius.circular(radiusButton));
  static const BorderRadius borderInput = BorderRadius.all(Radius.circular(radiusInput));
  static const BorderRadius borderSheet = BorderRadius.only(
    topLeft: Radius.circular(radiusSheet),
    topRight: Radius.circular(radiusSheet),
  );
  static const BorderRadius borderPill = BorderRadius.all(Radius.circular(radiusPill));
  static const BorderRadius borderThumbnail = BorderRadius.all(Radius.circular(radiusThumbnail));

  // ─── Spacing (8pt-based) ─────────────────────────────────────
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // ─── Icon sizes ──────────────────────────────────────────────
  static const double iconSmall = 18.0;
  static const double iconMedium = 22.0;
  static const double iconLarge = 28.0;
  static const double iconXLarge = 36.0;

  // ─── Heights ─────────────────────────────────────────────────
  static const double buttonHeight = 48.0;
  static const double buttonHeightSmall = 36.0;
  static const double inputHeight = 48.0;
  static const double navBarHeight = 64.0;

  // ─── Animation Durations ────────────────────────────────────
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // ─── Page paddings ──────────────────────────────────────────
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0);
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(horizontal: 20.0);
}
