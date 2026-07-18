import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Animated three-dot progress indicator rendered independently of artwork.
class OnboardingIndicator extends StatelessWidget {
  /// Creates the onboarding progress indicator.
  const OnboardingIndicator({
    required this.currentPage,
    required this.itemCount,
    super.key,
  });

  /// Index of the selected page.
  final int currentPage;

  /// Number of onboarding pages.
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Onboarding page ${currentPage + 1} of $itemCount',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(itemCount, (index) {
          final isActive = index == currentPage;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: isActive ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: .62),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          );
        }),
      ),
    );
  }
}
