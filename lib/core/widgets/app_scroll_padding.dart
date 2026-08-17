import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Page padding that keeps the final scroll item above system navigation.
EdgeInsets appSafeScrollPadding(
  BuildContext context, {
  double left = AppSpacing.md,
  double top = AppSpacing.md,
  double right = AppSpacing.md,
  double bottom = AppSpacing.xl,
}) => EdgeInsets.fromLTRB(
  left,
  top,
  right,
  bottom + MediaQuery.viewPaddingOf(context).bottom,
);
