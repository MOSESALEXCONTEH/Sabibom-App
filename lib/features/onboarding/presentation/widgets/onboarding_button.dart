import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Full-width primary onboarding action with repeated-tap protection.
class OnboardingButton extends StatelessWidget {
  /// Creates the primary onboarding action.
  const OnboardingButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    super.key,
  });

  /// Visible action label.
  final String label;

  /// Called when the user continues.
  final VoidCallback onPressed;

  /// Whether a page transition or route change is in progress.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: .65),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 5,
            shadowColor: Colors.black.withValues(alpha: .35),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(label),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded),
                  ],
                ),
        ),
      ),
    );
  }
}
