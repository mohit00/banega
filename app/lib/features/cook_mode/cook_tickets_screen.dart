import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart' show wireDate;
import '../../labels/kitchen_labels.dart';
import '../../ui/ui.dart';
import '../home/home_providers.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/domain/kitchen_models.dart';
import '../kitchen/presentation/kitchen_widgets.dart';
import 'cook_ui.dart';

/// K1 "Aaj ke tickets": today / tomorrow tabs, the caller's tickets by due
/// time with the next action per state; duty toggle in the header.
class CookTicketsScreen extends StatelessWidget {
  const CookTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) => const CookScope(child: _K1());
}

class _K1 extends ConsumerStatefulWidget {
  const _K1();

  @override
  ConsumerState<_K1> createState() => _K1State();
}

class _K1State extends ConsumerState<_K1> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = ref.watch(planDateProvider);
    final date = wireDate(today.add(Duration(days: _tab)));
    final async = ref.watch(cookTicketsProvider(date));
    final pending = ref.watch(pendingTicketIdsProvider).value ?? const <String>{};
    final tickets = async.value;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CookHeader(title: l.cookTitle, showDuty: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: CookActionButton(
                    key: const ValueKey('cook-rasoi'),
                    label: l.cookRasoi,
                    icon: BIcons.bowl,
                    secondary: true,
                    onPressed: () => context.push(Routes.cookStock),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CookActionButton(
                    key: const ValueKey('cook-ration'),
                    label: l.cookRationTitle,
                    icon: BIcons.send,
                    secondary: true,
                    onPressed: () => context.push(Routes.cookRation),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                for (final (i, label) in [(0, l.cookTabToday), (1, l.cookTabTomorrow)]) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: BChip(
                      key: ValueKey('cook-tab-$i'),
                      label: label,
                      height: 52,
                      radius: BRadii.cta,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                      child: Text(label, style: BText.body(CookType.label, weight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: BColors.green,
              onRefresh: () => ref.refresh(cookTicketsProvider(date).future),
              child: tickets == null
                  ? ListView(
                      children: [
                        const SizedBox(height: 60),
                        if (async.hasError)
                          Column(
                            children: [
                              Text(
                                l.cookLoadError,
                                textAlign: TextAlign.center,
                                style: BText.body(CookType.body, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              BChip(label: l.retry, onTap: () => ref.invalidate(cookTicketsProvider(date))),
                            ],
                          )
                        else
                          const Center(child: CircularProgressIndicator(color: BColors.green)),
                      ],
                    )
                  : tickets.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 60),
                        Text(
                          l.cookEmpty,
                          textAlign: TextAlign.center,
                          style: BText.body(CookType.body, weight: FontWeight.w700, color: BColors.ink3),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => CookTicketCard(
                        ticket: tickets[i],
                        pending: pending.contains(tickets[i].id),
                        onOpen: () => context.push(Routes.cookTicket(tickets[i].id)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CookTicketCard extends StatelessWidget {
  const CookTicketCard({super.key, required this.ticket, this.pending = false, this.onOpen});

  final Ticket ticket;
  final bool pending;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KitchenCard(
      key: ValueKey('cook-ticket-${ticket.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onOpen,
            semanticLabel: '${l.slotKey(ticket.slot)}. ${cookDue(l, ticket)}',
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.slotKey(ticket.slot),
                        style: BText.body(CookType.label, weight: FontWeight.w800, color: BColors.ink3),
                      ),
                    ),
                    TicketStatusChip(status: ticket.status, large: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(cookDue(l, ticket), style: BText.display(CookType.title)),
                const SizedBox(height: 6),
                Text(
                  ticket.dishes.map((d) => d.name).join(', '),
                  style: BText.body(CookType.body, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  l.cookServings(servingsText(ticket.servings)),
                  style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink3),
                ),
                if (pending || ticket.updated || ticket.stockIssueOpen) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (pending)
                        KitchenTag(
                          key: const ValueKey('cook-not-sent'),
                          label: l.cookNotSent,
                          icon: BIcons.alert,
                          large: true,
                        ),
                      if (ticket.updated) KitchenTag(label: l.ticketUpdatedTag, large: true),
                      if (ticket.stockIssueOpen) KitchenTag(label: l.ticketStockIssueTag, large: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (cookNextSteps(ticket.status).$1 != null) ...[
            const SizedBox(height: 12),
            CookTicketActions(ticket: ticket),
          ],
        ],
      ),
    );
  }
}
