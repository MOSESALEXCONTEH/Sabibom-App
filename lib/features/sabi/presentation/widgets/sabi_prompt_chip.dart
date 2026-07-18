import 'package:flutter/material.dart';

class SabiPromptChip extends StatelessWidget {
  const SabiPromptChip({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: const Color(0xFFF0ECFF),
      side: BorderSide.none,
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
