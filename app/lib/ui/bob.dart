import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';

/// The prototype's `.chef` animation (`bob` 2.4 s): 0%,100% {0, 0deg},
/// 50% {-3px, -4deg}, ease-in-out. Still under reduce-motion.
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child});

  final Widget child;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.chefBob);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final p = 0.5 - 0.5 * math.cos(2 * math.pi * _c.value);
        return Transform.translate(
          offset: Offset(0, -3 * p),
          child: Transform.rotate(angle: -4 * math.pi / 180 * p, child: child),
        );
      },
      child: widget.child,
    );
  }
}
