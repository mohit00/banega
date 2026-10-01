import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'icons.dart';
import 'pressable.dart';

enum BNavTab { ghar, maharaj, parivaar, rasoi }

/// Bottom navigation: a 68-high white bar with a top border and three items
/// (11/700, #6B6A63, active #1B1B18). The middle "Maharaj se pucho" item is a
/// raised 54px haldi chef button with a 4px white ring that bobs.
///
/// The widget is [height] tall (bar + the chef button's overhang); the
/// overhang is transparent to taps except for the button itself. Place it at
/// the bottom of a [Stack] over the scrolling content.
class BBottomNav extends StatelessWidget {
  const BBottomNav({super.key, required this.current, required this.onTap, this.showRasoi = false});

  final BNavTab current;
  final ValueChanged<BNavTab> onTap;

  /// Adds the fourth "Rasoi" tab (cook mode) for callers with a cook role.
  final bool showRasoi;

  /// How far the chef button rises above the bar.
  static const double overhang = 16;
  static const double height = BSizes.nav + overhang;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: height + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: BSizes.nav + bottomInset,
            child: Container(
              padding: EdgeInsets.only(left: 8, right: 8, bottom: bottomInset),
              decoration: const BoxDecoration(
                color: BColors.card,
                border: Border(top: BorderSide(color: BColors.border)),
              ),
              child: Row(
                children: [
                  _NavItem(
                    label: l.navGhar,
                    icon: BIcons.home,
                    on: current == BNavTab.ghar,
                    onTap: () => onTap(BNavTab.ghar),
                  ),
                  _NavItem(
                    label: l.navMaharaj,
                    icon: null,
                    on: current == BNavTab.maharaj,
                    onTap: () => onTap(BNavTab.maharaj),
                  ),
                  _NavItem(
                    label: l.navParivaar,
                    icon: BIcons.users,
                    on: current == BNavTab.parivaar,
                    onTap: () => onTap(BNavTab.parivaar),
                  ),
                  if (showRasoi)
                    _NavItem(
                      key: const ValueKey('nav-rasoi'),
                      label: l.navRasoi,
                      icon: BIcons.pot,
                      on: current == BNavTab.rasoi,
                      onTap: () => onTap(BNavTab.rasoi),
                    ),
                ],
              ),
            ),
          ),
          // Raised chef button, centred over the Maharaj item.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LayoutBuilder(
              builder: (context, c) {
                final n = showRasoi ? 4 : 3;
                final centre = 8 + 1.5 * (c.maxWidth - 16) / n;
                return Row(
                  children: [
                    SizedBox(width: math.max(0, centre - BSizes.chefButton / 2)),
                    ExcludeSemantics(
                      child: GestureDetector(onTap: () => onTap(BNavTab.maharaj), child: const ChefButton()),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.label, required this.icon, required this.on, required this.onTap});

  final String label;
  final BIconData? icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? BColors.ink : BColors.ink4;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        selected: on,
        builder: (context, _) => SizedBox(
          height: BSizes.navItem,
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) BIcon(icon!, size: 22, color: color) else const SizedBox(height: 22),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BText.body(BType.nav, weight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 54px haldi chef circle with a 4px white ring, drop shadow, inner
/// `inset 0 -4px 0 #E0A800` and the `bob` animation (2.4 s).
class ChefButton extends StatefulWidget {
  const ChefButton({super.key});

  @override
  State<ChefButton> createState() => _ChefButtonState();
}

class _ChefButtonState extends State<ChefButton> with SingleTickerProviderStateMixin {
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
        // bob: 0%,100% {0, 0deg} 50% {-3px, -4deg}, ease-in-out.
        final p = 0.5 - 0.5 * math.cos(2 * math.pi * _c.value);
        return Transform.translate(
          offset: Offset(0, -3 * p),
          child: Transform.rotate(angle: -4 * math.pi / 180 * p, child: child),
        );
      },
      child: Container(
        width: BSizes.chefButton,
        height: BSizes.chefButton,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: BColors.card, boxShadow: BShadows.chef),
        padding: const EdgeInsets.all(4),
        child: CustomPaint(
          painter: _ChefFacePainter(),
          child: const Center(child: BIcon(BIcons.chef, size: 26, color: BColors.ink)),
        ),
      ),
    );
  }
}

class _ChefFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final circle = Path()..addOval(Offset.zero & size);
    canvas.drawPath(circle, Paint()..color = BColors.haldi);
    canvas.save();
    canvas.clipPath(circle);
    canvas.drawPath(
      Path.combine(PathOperation.difference, circle, circle.shift(const Offset(0, -4))),
      Paint()..color = BColors.haldiDeep,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChefFacePainter oldDelegate) => false;
}
