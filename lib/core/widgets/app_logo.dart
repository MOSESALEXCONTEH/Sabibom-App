import 'package:flutter/material.dart';

/// The official SabiBom brand logo for all in-app company identity surfaces.
class AppLogo extends StatelessWidget {
  /// Creates the SabiBom brand mark.
  const AppLogo({super.key, this.size = 88});

  /// Square dimension of the mark.
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF080A12) : Colors.transparent,
        borderRadius: BorderRadius.circular(size * .2),
        border: isDark
            ? Border.all(color: Theme.of(context).colorScheme.outlineVariant)
            : null,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .2),
          child: Image.asset('assets/images/SB icon.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
