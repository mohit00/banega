import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/motion/motion.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../labels/labels.dart';
import '../../ui/ui.dart';
import '../members/application/members_controller.dart';

/// S5 — "Maharaj aapke ghar ko samajh raha hai…" (prototype "LOADING").
/// Moves on to Home after [Motion.loadingHold] (1.9 s; FRD max 3 s). In
/// Phase 3 this waits for the first GET /recommendations instead.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key, this.hold = Motion.loadingHold});

  final Duration hold;

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.hold, () {
      if (mounted) context.go(Routes.home);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    return Scaffold(
      backgroundColor: BColors.haldi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThaliHero(spin: Motion.thaliSpinFast, semanticLabel: l.thaliAlt),
                const SizedBox(height: 22),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    l.loadingTitle,
                    textAlign: TextAlign.center,
                    style: BText.display(BType.display26, height: 1.1),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  l.constraintLineFor(members),
                  textAlign: TextAlign.center,
                  style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink2),
                ),
                const SizedBox(height: 22),
                const LoadBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.loadbar`: 180×6 track (ink 12%) with a 40% green bar sweeping from
/// -100% to 250% every 1.1 s, ease-in-out.
class LoadBar extends StatefulWidget {
  const LoadBar({super.key});

  @override
  State<LoadBar> createState() => _LoadBarState();
}

class _LoadBarState extends State<LoadBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.loadBar);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _c.stop();
      _c.value = .5;
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
    const w = 180.0, bar = w * .4;
    return Container(
      width: w,
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: BColors.inkA(.12), borderRadius: BorderRadius.circular(6)),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final x = bar * (-1 + 3.5 * Curves.easeInOut.transform(_c.value));
          return Stack(
            children: [
              Positioned(
                left: x,
                top: 0,
                bottom: 0,
                width: bar,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: BColors.green, borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
