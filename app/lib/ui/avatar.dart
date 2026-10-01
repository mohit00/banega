import 'package:flutter/widgets.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// Member avatar (`.av`): initial on the member colour, 800 weight white, with
/// the prototype's inset shadows `inset 0 -3px 0 rgba(0,0,0,.18)` and
/// `inset 0 2px 0 rgba(255,255,255,.25)`.
class BAvatar extends StatelessWidget {
  const BAvatar({
    super.key,
    required this.initial,
    required this.color,
    this.size = BSizes.avatar,
    this.fontSize = 14,
    this.borderColor,
    this.borderWidth = 2,
  });

  final String initial;
  final Color color;
  final double size;
  final double fontSize;

  /// Optional ring (the Home avatar stack uses a 2px haldi border).
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AvatarPainter(color, borderColor, borderWidth),
        child: Center(
          child: Text(
            initial,
            textAlign: TextAlign.center,
            style: BText.body(fontSize, weight: FontWeight.w800, color: BColors.card, height: 1),
          ),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.color, this.border, this.borderWidth);

  final Color color;
  final Color? border;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    // CSS box-sizing:border-box — the border eats into the circle.
    final inner = border == null ? outer : outer.deflate(borderWidth);
    if (border != null) canvas.drawOval(outer, Paint()..color = border!);
    final circle = Path()..addOval(inner);
    canvas.drawPath(circle, Paint()..color = color);
    canvas.save();
    canvas.clipPath(circle);
    // inset 0 -3px 0 rgba(0,0,0,.18): crescent along the bottom.
    canvas.drawPath(
      Path.combine(PathOperation.difference, circle, circle.shift(const Offset(0, -3))),
      Paint()..color = const Color(0x2E000000),
    );
    // inset 0 2px 0 rgba(255,255,255,.25): crescent along the top.
    canvas.drawPath(
      Path.combine(PathOperation.difference, circle, circle.shift(const Offset(0, 2))),
      Paint()..color = const Color(0x40FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.color != color || old.border != border || old.borderWidth != borderWidth;
}
