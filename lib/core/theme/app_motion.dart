import 'package:flutter/material.dart';

/// Standard animation durations and curves for consistent, snappy motion
/// across the app. Prefer these over ad hoc `Duration`/`Curves` literals so
/// every transition feels like part of the same system.
abstract final class AppMotion {
  /// Micro-interactions: icon/state toggles, ripple-adjacent feedback.
  static const fast = Duration(milliseconds: 150);

  /// Default UI transitions: selection changes, expand/collapse, fades.
  static const standard = Duration(milliseconds: 240);

  /// Larger surface transitions: sheets, page-level reveals, skeleton fades.
  static const emphasized = Duration(milliseconds: 350);

  /// Default easing for most transitions (matches existing bottom nav feel).
  static const curve = Curves.easeOutCubic;

  /// Snappier easing for entrance animations (list items, cards).
  static const entranceCurve = Curves.easeOutQuart;

  /// Resolves a duration while respecting the platform reduced-motion flag.
  static Duration resolve(BuildContext context, Duration preferred) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : preferred;
}
