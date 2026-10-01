import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// Maharaj typing row: ink avatar dot + white bubble with three roti discs
/// flipping (`rotiFlip` 1 s, 150 ms stagger) and "rotiyaan sek raha hoon…".
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.rotiFlip);

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
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: l.typing,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: BColors.ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: BColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        AnimatedBuilder(animation: _c, builder: (context, _) => _roti(i)),
                      ],
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          l.typing,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BText.body(BType.captionL, weight: FontWeight.w600, color: BColors.ink3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roti(int i) {
    final delay = Motion.rotiStagger.inMilliseconds / Motion.rotiFlip.inMilliseconds * i;
    final p = (_c.value - delay) % 1.0;
    // 0 → 180° → 0 with ease-in-out on each half.
    final half = p < .5 ? p * 2 : (1 - p) * 2;
    final angle = Curves.easeInOut.transform(half) * math.pi;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 1 / 300)
        ..rotateY(angle),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-.2, -.2),
            radius: .75,
            colors: [BColors.rotiLight, BColors.rotiDark],
          ),
        ),
      ),
    );
  }
}
