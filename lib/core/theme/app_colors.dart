import 'package:flutter/material.dart';

/// Semantic colors used by the SabiBom design system.
///
/// This is the single source of truth for both the light and dark palettes.
/// Screens should prefer the theme-aware [AppColorsX] helpers (or
/// `Theme.of(context).colorScheme`) over these raw constants so that both
/// themes stay in sync automatically.
abstract final class AppColors {
  // --- Light palette -------------------------------------------------
  /// Brand violet for primary actions and emphasis.
  static const primary = Color(0xFF5B3DF5);

  /// Success green for positive business signals.
  static const secondary = Color(0xFF10B981);

  /// Product canvas color.
  static const background = Color(0xFFF8FAFC);

  /// Elevated content surface color.
  static const surface = Colors.white;

  /// Default high-emphasis text color.
  static const text = Color(0xFF111827);

  /// Low-emphasis text color.
  static const mutedText = Color(0xFF6B7280);

  /// Neutral structural border color.
  static const border = Color(0xFFE5E7EB);

  /// Warning/attention amber.
  static const warning = Color(0xFFF59E0B);

  /// Destructive/danger red.
  static const danger = Color(0xFFEF4444);

  // --- Dark palette ----------------------------------------------------
  /// Brighter brand violet tuned for contrast on dark surfaces.
  static const primaryDark = Color(0xFF8B72FF);

  /// Dark canvas color.
  static const backgroundDark = Color(0xFF10141F);

  /// Dark elevated surface color.
  static const surfaceDark = Color(0xFF1B2130);

  /// Default high-emphasis text color in dark mode.
  static const textDark = Color(0xFFE7EAF2);

  /// Low-emphasis text color in dark mode.
  static const mutedTextDark = Color(0xFF9AA1B5);

  /// Neutral structural border color in dark mode.
  static const borderDark = Color(0xFF2C3444);
}

/// Theme-aware companions to [AppColors] for surfaces that need to flip
/// between light and dark variants. Use these instead of hardcoded light
/// tints so text stays readable when the dark theme is enabled.
extension AppColorsX on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  /// Soft violet tint used behind icons, chips and highlight boxes.
  Color get brandTint =>
      isDarkTheme ? const Color(0xFF2C2545) : const Color(0xFFF0ECFF);

  /// Slightly stronger violet tint (e.g. selected avatar backgrounds).
  Color get brandTintStrong =>
      isDarkTheme ? const Color(0xFF3A2F5C) : const Color(0xFFDCD2FF);

  /// Border color to pair with [brandTint].
  Color get brandTintBorder =>
      isDarkTheme ? const Color(0xFF4A3E73) : const Color(0xFFD7CDFB);

  /// Card/sheet surface color that follows the theme.
  Color get surfaceColor => Theme.of(this).colorScheme.surface;

  /// Default high-emphasis text color for the current theme.
  Color get textColor => Theme.of(this).colorScheme.onSurface;

  /// Low-emphasis text color for the current theme.
  Color get mutedTextColor =>
      isDarkTheme ? const Color(0xFF9AA1B5) : AppColors.mutedText;

  /// Neutral border color for the current theme.
  Color get borderColor => isDarkTheme ? AppColors.borderDark : AppColors.border;

  /// Warm warning tint (used for draft banners and alerts).
  Color get warningTint =>
      isDarkTheme ? const Color(0xFF3D2E15) : const Color(0xFFFFF7ED);

  /// Soft success tint (used behind positive badges/chips).
  Color get successTint =>
      isDarkTheme ? const Color(0xFF163527) : const Color(0xFFECFDF5);

  /// Soft danger tint (used behind negative badges/chips/alerts).
  Color get dangerTint =>
      isDarkTheme ? const Color(0xFF3B1B1B) : const Color(0xFFFEF2F2);

  /// Subtle, brand-tinted shadow color for floating surfaces (nav bar,
  /// sheets, elevated cards). Lighter/softer in dark mode to avoid muddy
  /// shadows on dark backgrounds.
  Color get elevationShadowColor =>
      isDarkTheme ? const Color(0x33000000) : const Color(0x14000000);
}
