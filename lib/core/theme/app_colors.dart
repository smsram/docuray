import 'package:flutter/material.dart';

/// DocuRay design system – Paper & Ink color palette.
abstract final class AppColors {
  // ─── Light Theme ───────────────────────────────────────────────
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color success = Color(0xFF10B981);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // ─── Dark Theme ────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF111315);
  static const Color darkSurface = Color(0xFF191C1F);
  static const Color darkPrimary = Color(0xFF60A5FA);
  static const Color darkText = Color(0xFFF9FAFB);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkBorder = Color(0xFF2A2F34);

  // ─── Semantic helpers ──────────────────────────────────────────
  static const Color scannerOverlay = Color(0xCC000000);
  static const Color cornerHandle = Color(0xFF2563EB);
  static const Color aiAccent = Color(0xFF2563EB);
  static const Color aiBackground = Color(0xFFF0F6FF);
  static const Color syncedGreen = Color(0xFF10B981);
  static const Color favoriteYellow = Color(0xFFF59E0B);

  // ─── Card thumbnail placeholder shades ────────────────────────
  static const Color thumbBg1 = Color(0xFFEEF2FF);
  static const Color thumbBg2 = Color(0xFFE0F2FE);
  static const Color thumbBg3 = Color(0xFFF0FDF4);
  static const Color thumbBg4 = Color(0xFFFFF7ED);
  static const Color thumbBg5 = Color(0xFFFDF4FF);

  // ─── Transparent helpers ───────────────────────────────────────
  static const Color transparent = Colors.transparent;
}
