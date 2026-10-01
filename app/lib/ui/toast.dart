import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'icons.dart';

/// Toast (`.toast`): ink pill with a haldi check, 13/600 white, 96px above
/// the bottom, slides up + fades in over 300 ms and stays 2.2 s.
class BToast extends StatelessWidget {
  const BToast({super.key, required this.message});

  final String message;

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Shows [message] over the current screen, replacing any visible toast.
  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    hide();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 96 + MediaQuery.paddingOf(context).bottom,
        child: Center(
          child: _ToastIn(child: BToast(message: message)),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(Motion.toastHold, hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: BColors.ink, borderRadius: BorderRadius.circular(BRadii.icon)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BIcon(BIcons.check, size: 16, color: BColors.haldi),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: BText.body(BType.chip, weight: FontWeight.w600, color: BColors.card),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToastIn extends StatelessWidget {
  const _ToastIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Motion.toastIn),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}
