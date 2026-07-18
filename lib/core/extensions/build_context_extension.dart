import 'package:flutter/material.dart';

/// Convenience accessors for values already provided by the widget tree.
extension BuildContextExtension on BuildContext {
  /// The active product color scheme.
  ColorScheme get colors => Theme.of(this).colorScheme;

  /// The active product type scale.
  TextTheme get textStyles => Theme.of(this).textTheme;
}
