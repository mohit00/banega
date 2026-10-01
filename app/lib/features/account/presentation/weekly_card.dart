import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/ui.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../application/account_providers.dart';

/// Home "Is hafte" card (Should): top dish, on-time %, coverage
/// (GET /v1/insights/weekly). Hidden until a meal was cooked this week.
class WeeklySummaryCard extends ConsumerWidget {
  const WeeklySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final w = ref.watch(weeklyInsightsProvider).value;
    if (w == null || w.isEmpty) return const SizedBox.shrink();
    String pct(double v) => v.round().toString();
    final stats = [
      l.weeklyMeals(w.mealsCooked),
      if (w.onTimePct != null) l.weeklyOnTime(pct(w.onTimePct!)),
      if (w.coveragePct != null) l.weeklyCoverage(pct(w.coveragePct!)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: KitchenCard(
        key: const ValueKey('weekly-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BIcon(BIcons.chef, size: 18, color: BColors.green),
                const SizedBox(width: 8),
                Text(l.weeklyTitle, style: BText.body(BType.body, weight: FontWeight.w800)),
              ],
            ),
            if (w.topDishes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l.weeklyTop(w.topDishes.first.$2), style: BText.body(BType.chip, weight: FontWeight.w700)),
            ],
            const SizedBox(height: 4),
            Text(
              stats.join(' · '),
              style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
