import 'package:flutter/widgets.dart';

import '../core/engine/fit_engine.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../features/members/domain/member.dart';
import '../features/recipe/domain/recipe.dart';
import 'icons.dart';

/// `.badge`: 22 high, 8px side padding, 6 radius, 11/800.
class BBadge extends StatelessWidget {
  const BBadge({
    super.key,
    required this.label,
    this.background = BColors.paper,
    this.foreground = BColors.ink3,
    this.leading,
  });

  final String label;
  final Color background;
  final Color foreground;
  final BIconData? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: BSizes.badge,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(BRadii.badge)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[BIcon(leading!, size: 11, color: foreground), const SizedBox(width: 4)],
          // Large text in a narrow spot (the hero at 200%) ellipsizes.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: BText.body(BType.badge, weight: FontWeight.w800, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fit badge (`.b-fit` / `.b-tw` / `.b-no`).
class FitBadge extends StatelessWidget {
  const FitBadge({super.key, required this.kind, required this.label});

  final FitKind kind;
  final String label;

  static (Color, Color) colors(FitKind k) => switch (k) {
    FitKind.fit => (BColors.fitBg, BColors.fitFg),
    FitKind.tweak => (BColors.tweakBg, BColors.tweakFg),
    FitKind.no => (BColors.noBg, BColors.noFg),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(kind);
    return BBadge(label: label, background: bg, foreground: fg);
  }
}

enum DietMarkKind { veg, egg, nonveg }

/// 14px square diet mark (`.vm`): veg green dot, egg orange dot, non-veg
/// maroon triangle.
class DietMark extends StatelessWidget {
  const DietMark(this.kind, {super.key});

  factory DietMark.forRecipe(Recipe r, {Key? key}) => DietMark(kindFor(r.diet), key: key);

  factory DietMark.forDiet(Diet d, {Key? key}) => DietMark(switch (d) {
    Diet.veg || Diet.jain || Diet.noOnionGarlic => DietMarkKind.veg,
    Diet.egg => DietMarkKind.egg,
    Diet.nonveg || Diet.pescatarian => DietMarkKind.nonveg,
  }, key: key);

  static DietMarkKind kindFor(RecipeDiet d) => switch (d) {
    RecipeDiet.veg => DietMarkKind.veg,
    RecipeDiet.egg => DietMarkKind.egg,
    RecipeDiet.nonveg => DietMarkKind.nonveg,
  };

  final DietMarkKind kind;

  Color get color => switch (kind) {
    DietMarkKind.veg => BColors.markVeg,
    DietMarkKind.egg => BColors.markEgg,
    DietMarkKind.nonveg => BColors.markNonveg,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: BSizes.dietMark,
      height: BSizes.dietMark,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BColors.card,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1.5),
      ),
      child: kind == DietMarkKind.nonveg
          ? CustomPaint(size: const Size(8, 7), painter: _TrianglePainter(color))
          : Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// Recipe step number (`.step`): 26px haldi square, 8 radius, 13/800.
class StepNumber extends StatelessWidget {
  const StepNumber(this.n, {super.key});

  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: BSizes.stepNumber,
      height: BSizes.stepNumber,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: BColors.haldi, borderRadius: BorderRadius.circular(BRadii.add)),
      child: Text('$n', style: BText.body(BType.chip, weight: FontWeight.w800)),
    );
  }
}
