import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pulsing brand loader displayed while SabiBom completes startup work.
class SabiLoadingIndicator extends StatefulWidget {
  const SabiLoadingIndicator({super.key});

  @override
  State<SabiLoadingIndicator> createState() => _SabiLoadingIndicatorState();
}

class _SabiLoadingIndicatorState extends State<SabiLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: 'Starting SabiBom',
      child: SizedBox(
        width: 48,
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (index) {
            final animation = DelayTween(
              delay: index * 0.2,
            ).animate(_controller);

            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final pulse = reduceMotion ? 0.0 : animation.value;
                return Transform.scale(
                  scale: 0.86 + (pulse * 0.14),
                  child: Opacity(opacity: 0.45 + (pulse * 0.55), child: child),
                );
              },
              child: const SizedBox(
                width: 10,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF5B3DF5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class DelayTween extends Tween<double> {
  DelayTween({required this.delay}) : super(begin: 0, end: 1);

  final double delay;

  @override
  double lerp(double t) {
    return super.lerp((math.sin((t - delay) * 2 * math.pi) + 1) / 2);
  }

  @override
  double evaluate(Animation<double> animation) => lerp(animation.value);
}
