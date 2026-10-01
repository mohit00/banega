import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../labels/labels.dart';
import '../../ui/ui.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/domain/kitchen_models.dart';
import '../kitchen/presentation/kitchen_widgets.dart';
import 'cook_ui.dart';

/// K4 out-of-stock ladder (FRD §5.9) as a bottom sheet driven by the
/// ticket's `ladder`: 1 "Bina {item} ke bana lo?" (when the item is
/// optional) → 2 substitutes (engine-checked, "Badal do") → 3 "Dish badlo"
/// (3 cards). A swap / dish change that needs the family shows "Family se
/// poochh rahe hain…" until they answer or the 30-min timeout fires.
Future<void> showLadderSheet(BuildContext context, String ticketId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: BColors.paper,
  builder: (ctx) => CookScope(child: LadderSheet(ticketId: ticketId)),
);

class LadderSheet extends ConsumerStatefulWidget {
  const LadderSheet({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<LadderSheet> createState() => _LadderSheetState();
}

class _LadderSheetState extends ConsumerState<LadderSheet> {
  LadderStep? _step;
  bool _busy = false;
  Timer? _expiry;

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  /// Re-reads the ticket when a pending approval's 30 min run out.
  void _watchExpiry(StockIssue? issue) {
    _expiry?.cancel();
    final at = issue?.expiresAt;
    if (issue?.state != StockIssueState.pending || at == null) return;
    final wait = at.difference(ref.read(clockProvider)());
    if (wait.isNegative) return;
    _expiry = Timer(wait + const Duration(seconds: 1), () {
      if (mounted) ref.invalidate(cookTicketProvider(widget.ticketId));
    });
  }

  Future<void> _resolve(Ticket t, LadderAction action, {String? sub, String? recipe}) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final next = await ref
          .read(cookTicketActionsProvider)
          .resolve(t, action, substituteIngredientId: sub, recipeId: recipe);
      if (!mounted) return;
      if (!next.stockIssueOpen) {
        BToast.show(context, l.ladderDone);
        Navigator.of(context).pop();
      }
    } on KitchenError catch (e) {
      if (mounted) BToast.show(context, e.isConflict ? l.cookConflict : l.cookError);
    } catch (_) {
      if (mounted) BToast.show(context, l.cookError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = ref.watch(cookTicketProvider(widget.ticketId)).value;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final ladder = t?.ladder;
    final issue = t?.issue;
    _watchExpiry(issue);

    final itemName = ladder?.ingredientName ?? issue?.name ?? '';
    final List<Widget> body;
    if (t == null) {
      body = [const Center(child: CircularProgressIndicator(color: BColors.green))];
    } else if (!t.stockIssueOpen || issue == null) {
      body = [_Message(key: const ValueKey('ladder-done'), text: l.ladderDone, icon: BIcons.check)];
    } else if (issue.state == StockIssueState.pending) {
      body = [
        _Message(
          key: const ValueKey('ladder-pending'),
          text: l.ladderPending,
          icon: BIcons.clock,
          detail: issue.detail,
          busy: true,
        ),
        const SizedBox(height: 8),
        Text(
          l.ladderPendingHint(30),
          style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink3),
        ),
      ];
    } else if (issue.state == StockIssueState.timedOut) {
      body = [
        _Message(
          key: const ValueKey('ladder-timeout'),
          text: l.ladderTimeout,
          icon: BIcons.alert,
          detail: issue.detail,
          warn: true,
        ),
      ];
    } else if (ladder == null) {
      body = [_Message(text: l.ticketIssueChoosing, icon: BIcons.alert)];
    } else {
      final step =
          _step ??
          (ladder.canSkip ? LadderStep.saveDish : (ladder.swaps.isNotEmpty ? LadderStep.swap : LadderStep.changeDish));
      final rejected = t.changeLog.isNotEmpty && t.changeLog.last.action == LadderLog.rejected;
      body = [
        if (rejected) ...[
          _Message(key: const ValueKey('ladder-rejected'), text: l.ladderRejected, icon: BIcons.alert, warn: true),
          const SizedBox(height: 12),
        ],
        ...switch (step) {
          LadderStep.saveDish => _skipStep(l, t, ladder),
          LadderStep.swap => _swapStep(l, t, ladder),
          LadderStep.changeDish => _dishStep(l, t, ladder),
        },
      ];
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.ladderTitle(itemName),
                      key: const ValueKey('ladder-title'),
                      style: BText.display(CookType.title, height: 1.1),
                    ),
                  ),
                  BIconButton(
                    icon: BIcons.close,
                    semanticLabel: l.ladderClose,
                    size: 48,
                    background: BColors.card,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...body,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _skipStep(AppLocalizations l, Ticket t, StockLadder ladder) => [
    Text(l.ladderSkipAsk(ladder.ingredientName), style: BText.body(CookType.body, weight: FontWeight.w800)),
    const SizedBox(height: 14),
    CookActionButton(
      key: const ValueKey('ladder-skip'),
      label: l.ladderSkipYes,
      icon: BIcons.check,
      onPressed: _busy ? null : () => _resolve(t, LadderAction.skip),
    ),
    const SizedBox(height: 10),
    CookActionButton(
      key: const ValueKey('ladder-more'),
      label: l.ladderMoreWays,
      icon: BIcons.chevronRight,
      secondary: true,
      onPressed: () => setState(() => _step = LadderStep.swap),
    ),
  ];

  List<Widget> _swapStep(AppLocalizations l, Ticket t, StockLadder ladder) => [
    Text(l.ladderSwapTitle, style: BText.body(CookType.body, weight: FontWeight.w800)),
    const SizedBox(height: 10),
    if (ladder.swaps.isEmpty)
      Text(
        l.ladderNoSwap,
        key: const ValueKey('ladder-no-swap'),
        style: BText.body(CookType.label, weight: FontWeight.w600, color: BColors.ink3),
      ),
    for (final s in ladder.swaps) ...[
      KitchenCard(
        key: ValueKey('ladder-swap-card-${s.substituteIngredientId}'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.name, style: BText.body(CookType.body, weight: FontWeight.w800)),
            if (s.ratio.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                s.ratio,
                style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink2),
              ),
            ],
            if (s.noteHi.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s.noteHi, style: BText.body(CookType.min, color: BColors.ink3)),
            ],
            if (s.fitAfter != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _Fit(summary: s.fitAfter!),
              ),
            ],
            const SizedBox(height: 10),
            CookActionButton(
              key: ValueKey('ladder-swap-${s.substituteIngredientId}'),
              label: l.ladderSwapDo,
              icon: BIcons.check,
              onPressed: _busy ? null : () => _resolve(t, LadderAction.swap, sub: s.substituteIngredientId),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 4),
    CookActionButton(
      key: const ValueKey('ladder-change'),
      label: l.ladderChangeDish,
      icon: BIcons.pot,
      secondary: true,
      onPressed: () => setState(() => _step = LadderStep.changeDish),
    ),
  ];

  List<Widget> _dishStep(AppLocalizations l, Ticket t, StockLadder ladder) => [
    Text(l.ladderDishTitle, style: BText.body(CookType.body, weight: FontWeight.w800)),
    const SizedBox(height: 10),
    if (ladder.dishes.isEmpty)
      Text(
        l.ladderNoDish,
        style: BText.body(CookType.label, weight: FontWeight.w600, color: BColors.ink3),
      ),
    for (final d in ladder.dishes) ...[
      KitchenCard(
        key: ValueKey('ladder-dish-card-${d.id}'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: d.colour.withValues(alpha: .55), shape: BoxShape.circle),
                  child: const Center(child: BIcon(BIcons.bowl, size: 22, color: BColors.ink2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: BText.body(CookType.body, weight: FontWeight.w800)),
                      Text(
                        '${d.mins} min',
                        style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _Fit(summary: d.summary),
            ),
            const SizedBox(height: 10),
            CookActionButton(
              key: ValueKey('ladder-dish-${d.id}'),
              label: l.ladderDishPick,
              icon: BIcons.check,
              onPressed: _busy ? null : () => _resolve(t, LadderAction.changeDish, recipe: d.id),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ],
  ];
}

class _Fit extends StatelessWidget {
  const _Fit({required this.summary});

  final CardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FitBadge(kind: summary.badge, label: l.summaryShort(summary));
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.text,
    required this.icon,
    this.detail = '',
    this.busy = false,
    this.warn = false,
  });

  final String text;
  final BIconData icon;
  final String detail;
  final bool busy;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? BColors.noBg : BColors.tweakBg,
        borderRadius: BorderRadius.circular(BRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3, color: BColors.green),
            )
          else
            BIcon(icon, size: 24, color: warn ? BColors.noFg : BColors.tweakFg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: BText.body(CookType.body, weight: FontWeight.w800)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
