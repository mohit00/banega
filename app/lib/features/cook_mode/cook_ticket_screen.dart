import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../labels/kitchen_labels.dart';
import '../../ui/ui.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/domain/kitchen_models.dart';
import '../kitchen/presentation/kitchen_widgets.dart';
import '../pantry/presentation/ration_screen.dart';
import 'cook_ui.dart';
import 'ladder_sheet.dart';

/// K2 ticket detail: dishes (→ K5 recipe), who is eating + servings, notes,
/// required items with "Khatam hai", "Family se poochho" (→ K6) and the
/// next action.
class CookTicketScreen extends StatelessWidget {
  const CookTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) => CookScope(child: _K2(ticketId: ticketId));
}

class _K2 extends ConsumerWidget {
  const _K2({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(cookTicketProvider(ticketId));
    final pending = ref.watch(pendingTicketIdsProvider).value ?? const <String>{};
    final t = async.value;
    void back() => context.canPop() ? context.pop() : context.go(Routes.cook);

    if (t == null) {
      return Scaffold(
        backgroundColor: BColors.paper,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CookHeader(title: l.cookTitle, onBack: back),
            Expanded(
              child: Center(
                child: async.hasError
                    ? Text(l.cookLoadError, style: BText.body(CookType.body, weight: FontWeight.w700))
                    : const CircularProgressIndicator(color: BColors.green),
              ),
            ),
          ],
        ),
      );
    }

    final busy = ref.watch(ticketsInFlightProvider).contains(t.id);

    Future<void> markOut(RequiredItem item) async {
      try {
        final next = await ref.read(cookTicketActionsProvider).markItemOut(t, item);
        // Online: the response's ladder drives the K4 sheet.
        if (next.ladder != null && context.mounted) await showLadderSheet(context, t.id);
      } on AlreadyInFlight {
        // Double tap: ignored.
      } catch (_) {
        if (context.mounted) BToast.show(context, l.cookError);
      }
    }

    final label = BText.body(CookType.label, weight: FontWeight.w800, color: BColors.ink3);
    final body = BText.body(CookType.body, weight: FontWeight.w700);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CookHeader(title: l.slotKey(t.slot), subtitle: cookDue(l, t), onBack: back),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TicketStatusChip(status: t.status, large: true),
                    if (pending.contains(t.id)) KitchenTag(label: l.cookNotSent, icon: BIcons.alert, large: true),
                    if (t.updated) KitchenTag(label: l.ticketUpdatedTag, large: true),
                  ],
                ),
                const SizedBox(height: 14),
                Text(l.cookDishes, style: label),
                const SizedBox(height: 6),
                for (final d in t.dishes) ...[
                  KitchenCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text(d.name, style: body)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: CookActionButton(
                            key: ValueKey('cook-recipe-${d.recipeId}'),
                            label: l.cookOpenRecipe,
                            icon: BIcons.chevronRight,
                            secondary: true,
                            onPressed: () => context.push(Routes.cookRecipe(t.id, d.recipeId)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                Text(l.cookEaters, style: label),
                const SizedBox(height: 6),
                KitchenCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.cookServings(servingsText(t.servings)), style: body),
                      const SizedBox(height: 4),
                      Text(
                        [
                          t.eaters.map((e) => e.name).join(', '),
                          if (t.guests.count > 0) l.cookGuests(t.guests.count),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: BText.body(CookType.label, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (t.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(l.cookNotes, style: label),
                  const SizedBox(height: 6),
                  KitchenCard(
                    padding: const EdgeInsets.all(12),
                    child: Text(t.notes, style: BText.body(CookType.body)),
                  ),
                ],
                if (t.requiredItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(l.cookItems, style: label),
                  const SizedBox(height: 6),
                  KitchenCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      children: [
                        for (final item in t.requiredItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.displayText,
                                    style: BText.body(CookType.label, weight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (item.status == ItemStatus.out)
                                  ItemStatusPill(status: item.status, large: true)
                                else
                                  BChip(
                                    key: ValueKey('cook-out-${item.ingredientId}'),
                                    label: l.cookItemOut,
                                    height: 48,
                                    foreground: BColors.noFg,
                                    borderColor: BColors.noFg,
                                    onTap: t.status.isOpen && !busy ? () => markOut(item) : null,
                                    child: Text(
                                      l.cookItemOut,
                                      style: BText.body(CookType.min, weight: FontWeight.w800, color: BColors.noFg),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (t.stockIssueOpen && t.ladder != null) ...[
                  const SizedBox(height: 14),
                  CookActionButton(
                    key: const ValueKey('cook-ladder-open'),
                    label: '${l.ladderTitle(t.issue?.name ?? t.ladder!.ingredientName)} · ${l.ladderOpen}',
                    icon: BIcons.alert,
                    secondary: true,
                    onPressed: () => showLadderSheet(context, t.id),
                  ),
                ],
                const SizedBox(height: 14),
                CookActionButton(
                  key: const ValueKey('cook-ration-ask'),
                  label: l.cookRationAsk,
                  icon: BIcons.send,
                  secondary: true,
                  onPressed: () => showRaiseRationSheet(context, ref, ticket: t),
                ),
                const SizedBox(height: 14),
                CookActionButton(
                  key: const ValueKey('cook-ask-family'),
                  label: l.cookAskFamily,
                  icon: BIcons.chat,
                  secondary: true,
                  onPressed: () => context.push(Routes.cookThread(t.id)),
                ),
              ],
            ),
          ),
          if (cookNextSteps(t.status).$1 != null)
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
              decoration: const BoxDecoration(
                color: BColors.card,
                border: Border(top: BorderSide(color: BColors.border)),
              ),
              child: CookTicketActions(ticket: t),
            ),
        ],
      ),
    );
  }
}
