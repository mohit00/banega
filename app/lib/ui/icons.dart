import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Stroke icons copied from the prototype's inline SVGs (24×24 viewBox).
///
/// Each icon is a list of SVG path strings; `<circle>` and `<rect>` elements
/// from the prototype have been rewritten as arc paths.
class BIconData {
  const BIconData(this.paths, {this.strokeWidth = 2.2});

  final List<String> paths;

  /// The stroke width the prototype used for this icon at 24px.
  final double strokeWidth;
}

abstract final class BIcons {
  static const arrowRight = BIconData(['M5 12h14M13 6l6 6-6 6'], strokeWidth: 2.5);
  static const chevronRight = BIconData(['M9 6l6 6-6 6'], strokeWidth: 2.2);
  static const chevronLeft = BIconData(['M15 6l-6 6 6 6'], strokeWidth: 2.4);
  static const chevronDown = BIconData(['M6 9l6 6 6-6'], strokeWidth: 2.6);
  static const plus = BIconData(['M12 5v14M5 12h14'], strokeWidth: 2.5);
  static const minus = BIconData(['M5 12h14'], strokeWidth: 2.5);

  /// Detail "Video recipe" external-link arrow.
  static const arrowUpRight = BIconData(['M7 17L17 7M9 7h8v8'], strokeWidth: 2.4);
  static const check = BIconData(['M5 12l5 5 9-10'], strokeWidth: 3);
  static const search = BIconData(['M4 11a7 7 0 1014 0a7 7 0 10-14 0', 'M20 20l-4-4']);
  static const mic = BIconData(['M9 6a3 3 0 016 0v5a3 3 0 01-6 0z', 'M5 11a7 7 0 0014 0M12 18v3']);
  static const clock = BIconData(['M3 12a9 9 0 1018 0a9 9 0 10-18 0', 'M12 7v5l3 2'], strokeWidth: 3);
  static const home = BIconData(['M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6h-6v6H4a1 1 0 01-1-1z']);
  static const chef = BIconData([
    'M6 14a4 4 0 01-.5-8 5 5 0 019-1.5A4 4 0 0118.5 14H6zM7 14v5h10v-5M7 17h10',
  ], strokeWidth: 2);
  static const users = BIconData([
    'M5.5 8a3.5 3.5 0 107 0a3.5 3.5 0 10-7 0',
    'M2.5 20a6.5 6.5 0 0113 0M16 4.5a3.5 3.5 0 010 7M18 14.5a6.5 6.5 0 013.5 5.5',
  ]);
  static const bowl = BIconData(['M4 11h16a8 8 0 01-16 0zM12 3v3M8 5v2M16 5v2']);

  // Phase 5 (Plan, tickets, cook mode).
  static const close = BIconData(['M6 6l12 12M18 6L6 18'], strokeWidth: 2.4);
  static const send = BIconData(['M21 3L10 14M21 3l-7 18-4-7-7-4z'], strokeWidth: 2.4);
  static const bell = BIconData(['M6 16v-5a6 6 0 0112 0v5l2 2H4z', 'M10 21h4']);
  static const play = BIconData(['M8 5v14l11-7z']);
  static const pause = BIconData(['M8 5v14M16 5v14'], strokeWidth: 3);
  static const share = BIconData(['M4 12v7a1 1 0 001 1h14a1 1 0 001-1v-7', 'M12 3v12M7 8l5-5 5 5']);
  static const settings = BIconData(['M4 7h10M18 7h2M4 17h2M10 17h10', 'M14 5v4M6 15v4']);
  static const pot = BIconData(['M4 10h16v6a4 4 0 01-4 4H8a4 4 0 01-4-4z', 'M2 10h20M9 6h6']);
  static const alert = BIconData(['M12 4l9 16H3z', 'M12 10v4M12 17v.5']);
  static const edit = BIconData(['M4 20h4L19 9l-4-4L4 16z']);
  static const chat = BIconData(['M4 5h16v11H9l-5 4z']);
}

/// Renders a [BIconData] as a stroked path, matching the prototype's
/// `fill="none" stroke-linecap="round" stroke-linejoin="round"` SVGs.
class BIcon extends StatelessWidget {
  const BIcon(this.icon, {super.key, this.size = 20, this.color, this.strokeWidth, this.semanticLabel});

  final BIconData icon;
  final double size;
  final Color? color;

  /// Stroke width in viewBox units (24-based); defaults to the prototype's.
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF1B1B18);
    final paint = CustomPaint(size: Size.square(size), painter: _IconPainter(icon, c, strokeWidth ?? icon.strokeWidth));
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, child: paint);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeWidth);

  final BIconData icon;
  final Color color;
  final double strokeWidth;

  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final d in icon.paths) {
      canvas.drawPath(_cache.putIfAbsent(d, () => parseSvgPath(d)), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

/// Minimal SVG path-data parser: M m L l H h V v A a Z z (enough for the
/// prototype's icons).
Path parseSvgPath(String d) {
  final path = Path();
  final t = _Tokens(d);
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
  String? cmd;
  while (!t.done) {
    if (t.peekIsCommand) cmd = t.command();
    switch (cmd) {
      case 'M' || 'm':
        final rel = cmd == 'm';
        var x = t.number(), y = t.number();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.moveTo(x, y);
        cx = sx = x;
        cy = sy = y;
        cmd = rel ? 'l' : 'L'; // implicit lineto for further pairs
      case 'L' || 'l':
        var x = t.number(), y = t.number();
        if (cmd == 'l') {
          x += cx;
          y += cy;
        }
        path.lineTo(x, y);
        cx = x;
        cy = y;
      case 'H' || 'h':
        final x = t.number();
        cx = cmd == 'h' ? cx + x : x;
        path.lineTo(cx, cy);
      case 'V' || 'v':
        final y = t.number();
        cy = cmd == 'v' ? cy + y : y;
        path.lineTo(cx, cy);
      case 'A' || 'a':
        final rx = t.number(), ry = t.number(), rot = t.number();
        final large = t.flag(), sweep = t.flag();
        var x = t.number(), y = t.number();
        if (cmd == 'a') {
          x += cx;
          y += cy;
        }
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot * math.pi / 180,
          largeArc: large,
          clockwise: sweep,
        );
        cx = x;
        cy = y;
      case 'Z' || 'z':
        path.close();
        cx = sx;
        cy = sy;
        cmd = null;
      default:
        throw FormatException('Unsupported SVG path command "$cmd" in "$d"');
    }
  }
  return path;
}

class _Tokens {
  _Tokens(this.s);

  final String s;
  int i = 0;

  static final _num = RegExp(r'[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?');

  void _skip() {
    while (i < s.length && (s[i] == ' ' || s[i] == ',' || s[i] == '\n' || s[i] == '\t')) {
      i++;
    }
  }

  bool get done {
    _skip();
    return i >= s.length;
  }

  bool get peekIsCommand {
    _skip();
    return i < s.length && RegExp('[MmLlHhVvAaZz]').hasMatch(s[i]);
  }

  String command() {
    _skip();
    return s[i++];
  }

  double number() {
    _skip();
    final m = _num.matchAsPrefix(s, i);
    if (m == null) throw FormatException('Expected number at $i in "$s"');
    i = m.end;
    return double.parse(m.group(0)!);
  }

  bool flag() {
    _skip();
    return s[i++] == '1';
  }
}
