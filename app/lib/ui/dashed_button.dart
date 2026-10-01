import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'icons.dart';
import 'pressable.dart';

/// "Member jodo" button: 56 high, 16 radius, 1.5px dashed #B9BAAF border,
/// plus icon + 14/800 label.
class BDashedButton extends StatelessWidget {
  const BDashedButton({super.key, required this.label, this.onPressed, this.icon = BIcons.plus});

  final String label;
  final VoidCallback? onPressed;
  final BIconData icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, _) => CustomPaint(
        painter: const _DashedRRectPainter(color: BColors.dashed, radius: BRadii.tile, width: 1.5),
        child: SizedBox(
          height: 56,
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BIcon(icon, size: 18, color: BColors.ink2),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.ink2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius, required this.width});

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    // Chrome draws dashes about 3× the border width with equal gaps.
    final dash = width * 3, gap = width * 3;
    for (final ui.PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius || old.width != width;
}
