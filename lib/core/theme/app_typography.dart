import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Product typography built on a readable, business-focused type scale.
abstract final class AppTypography {
  /// Shared Material text theme.
  static final TextTheme textTheme = GoogleFonts.manropeTextTheme().copyWith(
    displaySmall: GoogleFonts.manrope(
      color: AppColors.text,
      fontSize: 36,
      fontWeight: FontWeight.w800,
    ),
    headlineMedium: GoogleFonts.manrope(
      color: AppColors.text,
      fontSize: 28,
      fontWeight: FontWeight.w800,
    ),
    titleLarge: GoogleFonts.manrope(
      color: AppColors.text,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: GoogleFonts.manrope(
      color: AppColors.text,
      fontSize: 16,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.manrope(
      color: AppColors.mutedText,
      fontSize: 14,
      height: 1.5,
    ),
  );
}
