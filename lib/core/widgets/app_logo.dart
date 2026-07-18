import 'package:flutter/material.dart';

/// The official SabiBom brand logo for all in-app company identity surfaces.
class AppLogo extends StatelessWidget {
  /// Creates the SabiBom brand mark.
  const AppLogo({super.key, this.size = 88});

  /// Square dimension of the mark.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .2),
        child: Image.asset('assets/images/SB icon.png', fit: BoxFit.contain),
      ),
    );
  }
}
