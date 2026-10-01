import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';
import 'spices.dart';

/// A lightweight, painted version of the prototype's 3D CSS thali
/// (`.tscene` 240×200): a steel plate tilted 62° that spins, floats and
/// steams, with katoris of dal / sabzi / raita, rice, two rotis, achaar and
/// salad; optionally with the splash's orbiting spices.
///
/// No image assets. One ticker drives everything; under reduce-motion it
/// paints a single static frame.
class ThaliHero extends StatefulWidget {
  const ThaliHero({
    super.key,
    this.spin = Motion.thaliSpin,
    this.orbit = false,
    this.steamCount = 3,
    this.semanticLabel,
  });

  /// Time for one full turn (18 s by default, 4 s on the loading screen).
  final Duration spin;

  /// Draw the orbiting leaf / chilli / cumin / clove ring (splash only).
  final bool orbit;

  /// 3 on splash / loading, 2 on the Home hero card.
  final int steamCount;
  final String? semanticLabel;

  static const Size sceneSize = Size(240, 200);

  @override
  State<ThaliHero> createState() => _ThaliHeroState();
}

class _ThaliHeroState extends State<ThaliHero> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _seconds = ValueNotifier(0);

  /// The painter blurs and draws gradients every frame: 30 fps is plenty.
  static const _frame = Duration(microseconds: 33333);
  Duration _last = -_frame;

  void _onTick(Duration elapsed) {
    if (elapsed - _last < _frame) return;
    _last = elapsed;
    _seconds.value = elapsed.inMicroseconds / 1e6;
  }

  bool _still(BuildContext context) => Motion.reduce(context) || LowEndScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = _still(context);
    if (reduce && _ticker.isActive) {
      _ticker.stop();
    } else if (!reduce && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _still(context);
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: ThaliHero.sceneSize,
          painter: _ThaliPainter(
            seconds: _seconds,
            spinSeconds: widget.spin.inMicroseconds / 1e6,
            orbit: widget.orbit,
            steamCount: widget.steamCount,
            animate: !reduce,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- painting

/// CSS `radial-gradient(circle at fx fy, ...)` with the default
/// farthest-corner size, mapped onto [r].
ui.Gradient cssRadial(Rect r, double fx, double fy, List<Color> colors, List<double> stops) {
  final c = Offset(r.left + r.width * fx, r.top + r.height * fy);
  final dx = math.max(c.dx - r.left, r.right - c.dx), dy = math.max(c.dy - r.top, r.bottom - c.dy);
  return ui.Gradient.radial(c, math.sqrt(dx * dx + dy * dy), colors, stops);
}

/// A small dot, like the prototype's `radial-gradient(... 0 3px, transparent 4px)`.
void _dot(Canvas canvas, Rect r, double fx, double fy, double radius, Color color) {
  canvas.drawCircle(Offset(r.left + r.width * fx, r.top + r.height * fy), radius, Paint()..color = color);
}

enum _Food { dal, sabzi, raita }

void paintKatoriFill(Canvas canvas, Rect f, Color food, {bool herbs = true}) {
  canvas.drawOval(f, Paint()..shader = cssRadial(f, .38, .30, [food, food], const [0, 1]));
  // highlight: radial-gradient(circle at 38% 30%, rgba(255,255,255,.55), transparent 42%)
  final hl = Offset(f.left + f.width * .38, f.top + f.height * .30);
  canvas.drawOval(
    f,
    Paint()..shader = ui.Gradient.radial(hl, f.width * .42, const [Color(0x8CFFFFFF), Color(0x00FFFFFF)]),
  );
  if (herbs) {
    const g = Color(0xFF3F8F3A);
    final s = f.width / 68;
    _dot(canvas, f, .36, .42, 2 * s, g);
    _dot(canvas, f, .64, .58, 2 * s, g);
    _dot(canvas, f, .52, .30, 1.5 * s, g);
  }
  // inset 0 4px 8px rgba(0,0,0,.3)
  canvas.save();
  canvas.clipPath(Path()..addOval(f));
  final inner = Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(f.inflate(20))
    ..addOval(f.shift(const Offset(0, 4)));
  canvas.drawPath(
    inner,
    Paint()
      ..color = const Color(0x4D000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.restore();
}

class _ThaliPainter extends CustomPainter {
  _ThaliPainter({
    required this.seconds,
    required this.spinSeconds,
    required this.orbit,
    required this.steamCount,
    required this.animate,
  }) : super(repaint: seconds);

  final ValueNotifier<double> seconds;
  final double spinSeconds;
  final bool orbit;
  final int steamCount;
  final bool animate;

  static final double _tilt = math.cos(62 * math.pi / 180); // plate rotateX(62deg)
  static final double _lift = math.sin(62 * math.pi / 180);
  static final double _orbitTilt = math.cos(68 * math.pi / 180);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animate ? seconds.value : 0.0;
    final center = Offset(size.width / 2, size.height / 2);

    if (orbit) _paintOrbit(canvas, center, t);

    // .pshadow — 200×26 ellipse at the bottom.
    // radial-gradient(closest-side, rgba(40,40,20,.28), transparent) → an elliptical falloff.
    canvas.save();
    canvas.translate(center.dx, size.height + 4 - 13);
    canvas.scale(1, 13 / 100);
    canvas.drawCircle(
      Offset.zero,
      100,
      Paint()..shader = ui.Gradient.radial(Offset.zero, 100, const [Color(0x47282814), Color(0x00282814)]),
    );
    canvas.restore();

    // .tfloat — floaty 4.5 s ease-in-out, 0 → -10 → 0.
    final floatPhase = (t % 4.5) / 4.5;
    final floatY = -10 * (0.5 - 0.5 * math.cos(2 * math.pi * floatPhase));
    final spin = spinSeconds <= 0 ? 0.0 : 2 * math.pi * ((t % spinSeconds) / spinSeconds);

    canvas.save();
    canvas.translate(center.dx, center.dy + floatY);
    _paintThali(canvas, spin);
    canvas.restore();

    _paintSteam(canvas, size, t);
  }

  void _paintOrbit(Canvas canvas, Offset center, double t) {
    const kinds = [
      SpiceKind.leaf,
      SpiceKind.chilli,
      SpiceKind.cumin,
      SpiceKind.clove,
      SpiceKind.leaf,
      SpiceKind.chilli,
    ];
    final base = 2 * math.pi * ((t % 11) / 11);
    for (var i = 0; i < kinds.length; i++) {
      final a = base + i * math.pi / 3;
      final p = center + Offset(150 * math.cos(a), 150 * math.sin(a) * _orbitTilt);
      final s = SpiceShape.defaultSize(kinds[i]);
      SpicePainter.paintInto(canvas, Rect.fromLTWH(p.dx, p.dy, s.width, s.height), kinds[i]);
    }
  }

  /// Draws [draw] in the plate plane: origin at the plate centre, rotated by
  /// [spin], tilted by the 62° perspective, raised by [z] px.
  void _inPlane(Canvas canvas, double spin, Offset platePos, double z, void Function(Canvas) draw) {
    canvas.save();
    canvas.translate(0, -z * _lift);
    canvas.scale(1, _tilt);
    canvas.rotate(spin);
    canvas.translate(platePos.dx - 110, platePos.dy - 110);
    draw(canvas);
    canvas.restore();
  }

  void _paintThali(Canvas canvas, double spin) {
    // Plate body (bottom rim `0 18px 0 2px #7F868E` → a darker slab below).
    canvas.save();
    canvas.scale(1, _tilt);
    canvas.drawCircle(Offset(0, 18 / _tilt * .45), 112, Paint()..color = const Color(0xFF7F868E));
    canvas.drawCircle(Offset.zero, 117, Paint()..color = const Color(0xFF9CA2A9));
    canvas.drawCircle(Offset.zero, 115, Paint()..color = const Color(0xFFC3C8CE));
    final plate = Rect.fromCircle(center: Offset.zero, radius: 110);
    canvas.rotate(spin);
    canvas.drawOval(
      plate,
      Paint()
        ..shader = cssRadial(
          plate,
          .38,
          .32,
          const [Color(0xFFFDFDFE), Color(0xFFDADDE1), Color(0xFFB5BBC2), Color(0xFF8F969E)],
          const [0, .42, .78, 1],
        ),
    );
    final inner = plate.deflate(26);
    canvas.drawOval(
      inner,
      Paint()..shader = cssRadial(inner, .40, .35, const [Color(0xFFF2F3F5), Color(0xFFC9CED3)], const [0, .9]),
    );
    canvas.restore();

    // Items, back to front by their on-screen y.
    final items = <(Offset, void Function(Canvas))>[
      (const Offset(69, 177), (c) => _pickle(c, spin)),
      (const Offset(165, 181), (c) => _salad(c, spin)),
      (const Offset(113, 132), (c) => _rice(c, spin)),
      (const Offset(173, 129), (c) => _roti(c, spin, const Offset(173, 129), 6, 12)),
      (const Offset(161, 155), (c) => _roti(c, spin, const Offset(161, 155), 12, 0)),
      (const Offset(65, 45), (c) => _katori(c, spin, const Offset(65, 45), _Food.dal)),
      (const Offset(155, 45), (c) => _katori(c, spin, const Offset(155, 45), _Food.sabzi)),
      (const Offset(37, 111), (c) => _katori(c, spin, const Offset(37, 111), _Food.raita)),
    ];
    double screenY(Offset p) {
      final v = p - const Offset(110, 110);
      return v.dx * math.sin(spin) + v.dy * math.cos(spin);
    }

    items.sort((a, b) => screenY(a.$1).compareTo(screenY(b.$1)));
    for (final it in items) {
      it.$2(canvas);
    }
  }

  void _katori(Canvas canvas, double spin, Offset pos, _Food food) {
    // Wall: `0 7px 0 0 #7C838B` under the rim.
    _inPlane(canvas, spin, pos, 16 - 7, (c) {
      c.drawCircle(Offset.zero, 31, Paint()..color = const Color(0xFF7C838B));
    });
    _inPlane(canvas, spin, pos, 16, (c) {
      c.drawCircle(Offset.zero, 33, Paint()..color = const Color(0xFFAEB4BA));
      final r = Rect.fromCircle(center: Offset.zero, radius: 31);
      c.drawOval(
        r,
        Paint()
          ..shader = cssRadial(
            r,
            .34,
            .28,
            const [Color(0xFFFFFFFF), Color(0xFFCDD2D7), Color(0xFF8C939B)],
            const [0, .4, 1],
          ),
      );
      final f = r.deflate(7);
      switch (food) {
        case _Food.dal:
          c.drawOval(
            f,
            Paint()
              ..shader = cssRadial(
                f,
                .38,
                .30,
                const [Color(0xFFFBE38C), Color(0xFFE8B73A), Color(0xFFC98F17)],
                const [0, .6, 1],
              ),
          );
          _dot(c, f, .40, .45, 2, const Color(0xFF6B8F2D));
          _dot(c, f, .60, .35, 2, const Color(0xFF6B8F2D));
        case _Food.sabzi:
          c.drawOval(
            f,
            Paint()
              ..shader = cssRadial(
                f,
                .40,
                .30,
                const [Color(0xFF8DBF5A), Color(0xFF4E8A2E), Color(0xFF346B1D)],
                const [0, .7, 1],
              ),
          );
          _dot(c, f, .35, .40, 4, const Color(0xFFF2D06B));
          _dot(c, f, .62, .60, 3, const Color(0xFFF2D06B));
        case _Food.raita:
          c.drawOval(
            f,
            Paint()
              ..shader = cssRadial(
                f,
                .40,
                .30,
                const [Color(0xFFFFFFFF), Color(0xFFF1EDE3), Color(0xFFDAD3C3)],
                const [0, .7, 1],
              ),
          );
          _dot(c, f, .45, .40, 2, const Color(0xFF6FA34A));
          _dot(c, f, .60, .62, 2, const Color(0xFFC0542B));
      }
      // inset 0 4px 8px rgba(0,0,0,.3)
      c.save();
      c.clipPath(Path()..addOval(f));
      c.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(f.inflate(12))
          ..addOval(f.shift(const Offset(0, 4))),
        Paint()
          ..color = const Color(0x4D000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      c.restore();
    });
  }

  void _rice(Canvas canvas, double spin) {
    const pos = Offset(113, 132);
    _inPlane(canvas, spin, pos, 10 - 5, (c) {
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: 70, height: 56), Paint()..color = const Color(0xFFC9BFA8));
    });
    _inPlane(canvas, spin, pos, 10, (c) {
      final r = Rect.fromCenter(center: Offset.zero, width: 70, height: 56);
      c.drawOval(
        r,
        Paint()
          ..shader = cssRadial(
            r,
            .40,
            .30,
            const [Color(0xFFFFFFFF), Color(0xFFF1EBDD), Color(0xFFDCD2BD)],
            const [0, .6, 1],
          ),
      );
    });
  }

  void _roti(Canvas canvas, double spin, Offset pos, double z, double rotDeg) {
    _inPlane(canvas, spin, pos, z, (c) {
      c.rotate(rotDeg * math.pi / 180);
      final r = Rect.fromCircle(center: Offset.zero, radius: 37);
      c.drawOval(
        r,
        Paint()
          ..shader = cssRadial(
            r,
            .45,
            .45,
            const [Color(0xFFEBC585), Color(0xFFD8A55E), Color(0xFFC18A45)],
            const [0, .7, 1],
          ),
      );
      _dot(c, r, .30, .35, 3, const Color(0xFFA06A2C));
      _dot(c, r, .62, .58, 4, const Color(0xFFA06A2C));
      _dot(c, r, .55, .25, 2, const Color(0xFF8E5A22));
    });
  }

  void _pickle(Canvas canvas, double spin) {
    _inPlane(canvas, spin, const Offset(69, 177), 8, (c) {
      final r = Rect.fromCenter(center: Offset.zero, width: 26, height: 18);
      c.drawOval(
        r,
        Paint()..shader = cssRadial(r, .40, .35, const [Color(0xFFE0602F), Color(0xFFA8321A)], const [0, 1]),
      );
    });
  }

  void _salad(Canvas canvas, double spin) {
    _inPlane(canvas, spin, const Offset(165, 181), 8, (c) {
      final r = Rect.fromCenter(center: Offset.zero, width: 30, height: 22);
      c.drawOval(r, Paint()..color = const Color(0xFF4F8F3A));
      _dot(c, r, .30, .40, 5, const Color(0xFFF6F1E4));
      _dot(c, r, .65, .55, 6, const Color(0xFFD83A2E));
    });
  }

  void _paintSteam(Canvas canvas, Size size, double t) {
    if (!animate) return;
    const lefts = [92.0, 118.0, 142.0];
    for (var i = 0; i < steamCount && i < lefts.length; i++) {
      final local = t - i * .8;
      if (local < 0) continue;
      final p = (local % 2.6) / 2.6;
      final e = Curves.easeOut.transform(p);
      final opacity = p < .25 ? .75 * (p / .25) : .75 * (1 - (p - .25) / .75);
      final dy = -70 * e;
      final sx = 1 + .8 * e;
      final rect = Rect.fromLTWH(lefts[i], 18 + dy, 14, 44);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(sx, 1);
      final r = Rect.fromCenter(center: Offset.zero, width: 14, height: 44);
      canvas.drawOval(
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, r.height * .3),
            r.height * .5,
            [Color.fromRGBO(255, 255, 255, opacity), const Color(0x00FFFFFF)],
            const [0, .7],
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ThaliPainter old) =>
      old.spinSeconds != spinSeconds || old.orbit != orbit || old.steamCount != steamCount || old.animate != animate;
}

/// Recipe placeholder (`.kat`): a steel katori tilted 56° holding food of
/// [food] colour, on the cream image area. Used until recipe photos ship.
class KatoriThumb extends StatelessWidget {
  const KatoriThumb({super.key, required this.food, this.diameter = 84});

  final Color food;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(diameter + 10, diameter * math.cos(56 * math.pi / 180) + 30),
      painter: _KatoriPainter(food, diameter),
    );
  }
}

class _KatoriPainter extends CustomPainter {
  _KatoriPainter(this.food, this.d);
  final Color food;
  final double d;

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.cos(56 * math.pi / 180);
    final c = Offset(size.width / 2, d * k / 2 + 4);
    // `0 26px 18px -6px rgba(40,40,20,.28)` drop shadow
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(0, 20), width: d * .9, height: d * k * .8),
      Paint()
        ..color = const Color(0x47282814)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, k);
    final r = d / 2;
    // wall `0 12px 0 0 #7E858D`
    canvas.drawCircle(Offset(0, 12 / k * .6), r, Paint()..color = const Color(0xFF7E858D));
    canvas.drawCircle(Offset.zero, r + 2, Paint()..color = const Color(0xFFB3B9BF));
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = cssRadial(
          rect,
          .34,
          .28,
          const [Color(0xFFFFFFFF), Color(0xFFD4D8DC), Color(0xFF8C939B)],
          const [0, .4, 1],
        ),
    );
    paintKatoriFill(canvas, rect.deflate(d * 8 / 84), food);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KatoriPainter old) => old.food != food || old.d != d;
}
