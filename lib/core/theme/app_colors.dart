import 'package:flutter/material.dart';

/// Semantic colors used by the SabiBom design system.
abstract final class AppColors {
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
}
