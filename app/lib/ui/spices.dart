import 'package:flutter/widgets.dart';

import '../core/theme/tokens.dart';

/// The prototype's little CSS spice shapes (`.leaf`, `.chilli`, `.cumin`,
/// `.clove`), drawn with a painter so they can also be used on a canvas.
enum SpiceKind { leaf, chilli, cumin, clove }

class SpiceShape extends StatelessWidget {
  const SpiceShape(this.kind, {super.key, this.size});

  final SpiceKind kind;

  /// Overrides the default CSS size (e.g. chilli pills are 14×5).
  final Size? size;

  static Size defaultSize(SpiceKind k) => switch (k) {
    SpiceKind.leaf => const Size(16, 16),
    SpiceKind.chilli => const Size(30, 9),
    SpiceKind.cumin => const Size(10, 10),
    SpiceKind.clove => const Size(14, 6),
  };

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: size ?? defaultSize(kind), painter: SpicePainter(kind));
  }
}

class SpicePainter extends CustomPainter {
  const SpicePainter(this.kind);
  final SpiceKind kind;

  /// Paints [kind] into [rect] on [canvas].
  static void paintInto(Canvas canvas, Rect rect, SpiceKind kind) {
    switch (kind) {
      case SpiceKind.leaf:
        // border-radius: 0 100% 0 100%
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topRight: Radius.elliptical(rect.width, rect.height),
            bottomLeft: Radius.elliptical(rect.width, rect.height),
          ),
          Paint()..color = BColors.leaf,
        );
      case SpiceKind.chilli:
        // border-radius: 9px 2px 9px 2px, scaled down like CSS when the box is
        // shorter than the radii; inset -4px 0 0 green stalk on the right.
        final f = (rect.height / 11).clamp(0.0, 1.0);
        final big = Radius.circular(9 * f), small = Radius.circular(2 * f);
        final rr = RRect.fromRectAndCorners(rect, topLeft: big, topRight: small, bottomRight: big, bottomLeft: small);
        canvas.save();
        canvas.clipRRect(rr);
        canvas.drawRect(rect, Paint()..color = BColors.chilli);
        canvas.drawRect(
          Rect.fromLTRB(rect.right - 4, rect.top, rect.right, rect.bottom),
          Paint()..color = BColors.leaf,
        );
        canvas.restore();
      case SpiceKind.cumin:
        canvas.drawOval(rect, Paint()..color = BColors.cumin);
      case SpiceKind.clove:
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height)), Paint()..color = BColors.clove);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintInto(canvas, Offset.zero & size, kind);

  @override
  bool shouldRepaint(SpicePainter old) => old.kind != kind;
}
