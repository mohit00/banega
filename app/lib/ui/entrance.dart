import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';

enum _Kind { rise, popIn, flipIn }

/// One-shot entrance animations from the prototype's keyframes:
/// - [Entrance.rise]: `rise` — fade + translateY(18px → 0)
/// - [Entrance.popIn]: `popIn` — fade + rotateX(38°) + translateY(24px) + scale(.94)
/// - [Entrance.flipIn]: `flipIn` — fade + rotateY(-65°) + translateX(40px)
///
/// [delay] implements CSS `animation-delay` with `fill-mode: both` (the child
/// stays hidden until its delay elapses). Under reduce-motion the child is
/// shown immediately.
class Entrance extends StatefulWidget {
  const Entrance.rise({super.key, required this.child, this.delay = Duration.zero, this.duration = Motion.rise})
    : _kind = _Kind.rise;

  const Entrance.popIn({super.key, required this.child, this.delay = Duration.zero, this.duration = Motion.popIn})
    : _kind = _Kind.popIn;

  const Entrance.flipIn({super.key, required this.child, this.delay = Duration.zero, this.duration = Motion.flipIn})
    : _kind = _Kind.flipIn;

  final Widget child;
  final Duration delay;
  final Duration duration;
  final _Kind _kind;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final reduce = Motion.reduce(context);
    final total = widget.delay + widget.duration;
    final c = AnimationController(vsync: this, duration: reduce || total == Duration.zero ? Duration.zero : total);
    final start = total == Duration.zero ? 0.0 : widget.delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(start, 1, curve: Motion.easeOut),
    );
    _c = c;
    if (reduce) {
      c.value = 1;
    } else {
      c.forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        final inv = 1 - v;
        final m = Matrix4.identity();
        switch (widget._kind) {
          case _Kind.rise:
            m.translateByDouble(0, Motion.riseOffset * inv, 0, 1);
          case _Kind.popIn:
            m
              ..setEntry(3, 2, 1 / 700)
              ..translateByDouble(0, 24 * inv, 0, 1)
              ..rotateX(38 * math.pi / 180 * inv)
              ..scaleByDouble(0.94 + 0.06 * v, 0.94 + 0.06 * v, 1, 1);
          case _Kind.flipIn:
            m
              ..setEntry(3, 2, 1 / 800)
              ..translateByDouble(40 * inv, 0, 0, 1)
              ..rotateY(-65 * math.pi / 180 * inv);
        }
        return Opacity(
          opacity: v.clamp(0, 1),
          child: Transform(alignment: Alignment.center, transform: m, child: child),
        );
      },
    );
  }
}
