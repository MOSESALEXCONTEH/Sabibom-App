import 'package:flutter/widgets.dart';

/// Immutable content for one SabiBom onboarding page.
class OnboardingItem {
  /// Creates onboarding content with a separate illustration and copy.
  const OnboardingItem({
    required this.imagePath,
    this.imageAlignment = Alignment.center,
    required this.title,
    required this.description,
  });

  /// Asset path for the product illustration.
  final String imagePath;

  /// Alignment used when the background image is cropped to fill the display.
  final Alignment imageAlignment;

  /// Main benefit statement.
  final String title;

  /// Supporting explanation.
  final String description;
}
