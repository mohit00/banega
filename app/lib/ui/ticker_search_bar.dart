import 'package:flutter/widgets.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'icons.dart';
import 'pressable.dart';

/// Home search bar: 48 high white pill (12 radius) with search icon, "Pucho",
/// a 20px-tall ticker cycling example asks every 2.5 s (10 s loop, steps
/// eased with cubic(.6,0,.3,1)) and a green mic.
class TickerSearchBar extends StatefulWidget {
  const TickerSearchBar({super.key, this.onTap, this.onMic, this.asks});

  final VoidCallback? onTap;
  final VoidCallback? onMic;

  /// Example asks; defaults to the four prototype strings.
  final List<String>? asks;

  @override
  State<TickerSearchBar> createState() => _TickerSearchBarState();
}

class _TickerSearchBarState extends State<TickerSearchBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.tickerCycle);

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

  /// Keyframes: 0–18% at 0, 25–43% at -1, 50–68% at -2, 75–93% at -3,
  /// 100% at -4 (the duplicated first line), in line units.
  static double _offsetLines(double t) {
    const holds = [0.0, .25, .5, .75];
    for (var i = 0; i < holds.length; i++) {
      final holdEnd = holds[i] + .18;
      final next = i + 1 < holds.length ? holds[i + 1] : 1.0;
      if (t <= holdEnd) return i.toDouble();
      if (t < next) return i + Motion.ticker.transform((t - holdEnd) / (next - holdEnd));
    }
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final asks = widget.asks ?? [l.tickerAsk1, l.tickerAsk2, l.tickerAsk3, l.tickerAsk4];
    final lines = [...asks, asks.first];
    final lineStyle = BText.body(BType.body, weight: FontWeight.w600, height: 20 / 14);
    return Pressable(
      onTap: widget.onTap,
      semanticLabel: '${l.searchPrefix} ${asks.first}',
      builder: (context, _) => Container(
        height: BSizes.input,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: BColors.card,
          borderRadius: BorderRadius.circular(BRadii.icon),
          boxShadow: BShadows.search,
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              const BIcon(BIcons.search, size: 20, color: BColors.ink),
              const SizedBox(width: 10),
              Text('${l.searchPrefix} ', style: BText.body(BType.body, color: BColors.ink3)),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Transform.translate(
                          offset: Offset(0, -20 * _offsetLines(_c.value)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final a in lines)
                                SizedBox(
                                  height: 20,
                                  child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: lineStyle),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: widget.onMic ?? widget.onTap,
                child: const BIcon(BIcons.mic, size: 20, color: BColors.green),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
