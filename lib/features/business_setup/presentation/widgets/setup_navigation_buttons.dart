import 'package:flutter/material.dart';

class SetupNavigationButtons extends StatelessWidget {
  const SetupNavigationButtons({
    super.key,
    required this.showBack,
    required this.isLastStep,
    required this.isLoading,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
  });

  final bool showBack;
  final bool isLastStep;
  final bool isLoading;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (showBack)
          Expanded(
            child: OutlinedButton(
              onPressed: isLoading ? null : onBack,
              child: const Text('Back'),
            ),
          ),
        if (showBack) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: isLoading ? null : (isLastStep ? onFinish : onNext),
            child: isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isLastStep ? 'Finish Setup' : 'Continue'),
          ),
        ),
      ],
    );
  }
}
