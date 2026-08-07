import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared elevation shadows for floating/elevated surfaces (bottom nav,
/// sheets, prominent cards). Keeps shadow styling consistent instead of each
/// screen inventing its own blur/offset/opacity.
extension AppShadows on BuildContext {
  /// Soft shadow for floating chrome (bottom nav pill, FAB clusters).
  List<BoxShadow> get floatingShadow => <BoxShadow>[
        BoxShadow(
          color: elevationShadowColor,
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// Lighter shadow for resting elevated cards (summary cards, sheets).
  List<BoxShadow> get cardShadow => <BoxShadow>[
        BoxShadow(
          color: elevationShadowColor,
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}
