import 'package:flutter/widgets.dart';

/// Motion tokens from the prototype's keyframes, plus a reduce-motion switch.
///
/// Every animation in the app should get its duration through [Motion.of] (or
/// check [Motion.reduce]) so that the OS "remove animations" setting turns
/// entrance animations into instant state changes and stops looping ones.
abstract final class Motion {
  /// `cubic-bezier(.2,.8,.2,1)` — used by rise, popIn, flipIn.
  static const Curve easeOut = Cubic(.2, .8, .2, 1);

  /// `cubic-bezier(.6,0,.3,1)` — ticker steps.
  static const Curve ticker = Cubic(.6, 0, .3, 1);

  // Entrances
  static const rise = Duration(milliseconds: 450); // .enter (screen enter)
  static const riseOffset = 18.0; // translateY(18px)
  static const popIn = Duration(milliseconds: 550); // tiles
  static const heroPopIn = Duration(milliseconds: 600);
  static const flipIn = Duration(milliseconds: 600); // chat mini-cards
  static const toastIn = Duration(milliseconds: 300);
  static const toastHold = Duration(milliseconds: 2200);

  // Staggers
  static const staggerTile = Duration(milliseconds: 70);
  static const staggerMember = Duration(milliseconds: 60);

  // Micro-interactions
  static const press = Duration(milliseconds: 120); // .cta transform/box-shadow
  static const chip = Duration(milliseconds: 200); // .chip / .add transition
  static const seg = Duration(milliseconds: 250); // .seg transition

  // Loops
  static const thaliSpin = Duration(seconds: 18);
  static const thaliSpinFast = Duration(seconds: 4); // loading screen
  static const floaty = Duration(milliseconds: 4500);
  static const steam = Duration(milliseconds: 2600);
  static const steamStagger = Duration(milliseconds: 800);
  static const orbit = Duration(seconds: 11);
  static const chefBob = Duration(milliseconds: 2400);
  static const rotiFlip = Duration(seconds: 1);
  static const rotiStagger = Duration(milliseconds: 150);
  static const tickerCycle = Duration(seconds: 10);
  static const loadBar = Duration(milliseconds: 1100);

  /// Functional delay (not an animation): loading screen → home.
  static const loadingHold = Duration(milliseconds: 1900);

  /// True when the OS asks for reduced motion.
  static bool reduce(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero under reduce-motion.
  static Duration of(BuildContext context, Duration d) => reduce(context) ? Duration.zero : d;

  /// Stagger delay for the [index]th item, or zero under reduce-motion.
  static Duration stagger(BuildContext context, int index, Duration step) =>
      reduce(context) ? Duration.zero : step * index;
}

/// Tells the painted hero art (thali) to stay still: low-end devices, or the
/// user's "Light animations" setting. Reduce-motion does the same.
class LowEndScope extends InheritedWidget {
  const LowEndScope({super.key, required this.lowEnd, required super.child});

  final bool lowEnd;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LowEndScope>()?.lowEnd ?? false;

  @override
  bool updateShouldNotify(LowEndScope old) => old.lowEnd != lowEnd;
}
