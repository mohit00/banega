import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../account/application/account_providers.dart';
import '../../account/presentation/rate_sheet.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';

/// Home's ticket card (S12): shown under the hero when the slot on screen
/// has a ticket today. Tap → ticket detail.
class HomeTicketCard extends ConsumerWidget {
  const HomeTicketCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(homeTicketProvider).value;
    if (ticket == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final ratingsOn = ref.watch(householdSettingsProvider).value?.ratingsEnabled ?? true;
    final canRate = ratingsOn && ticket.status == TicketStatus.completed && ticket.ratedAt == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TicketStatusCard(ticket: ticket, onTap: () => context.push(Routes.ticket(ticket.id))),
          if (canRate) ...[
            const SizedBox(height: 8),
            BGhostButton(
              key: const ValueKey('home-rate'),
              label: l.ticketRate,
              onPressed: () => showRateSheet(context, ref, ticket),
            ),
          ],
        ],
      ),
    );
  }
}

class TicketStatusCard extends StatelessWidget {
  const TicketStatusCard({super.key, required this.ticket, this.onTap});

  final Ticket ticket;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unassigned = ticket.status == TicketStatus.unassigned;
    final who = unassigned ? l.ticketUnassignedTitle : (ticket.assignee?.name ?? l.ticketNoAssignee);
    final title = l.ticketCardTitle(l.slotKey(ticket.slot));
    return Pressable(
      key: const ValueKey('home-ticket-card'),
      onTap: onTap,
      semanticLabel: [title, l.ticketStatus(ticket.status), who, if (unassigned) l.ticketUnassignedCard].join('. '),
      builder: (context, pressed) => PressScale(
        pressed: pressed,
        child: ExcludeSemantics(
          child: KitchenCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BIcon(BIcons.pot, size: 18, color: BColors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: BText.body(BType.body, weight: FontWeight.w800)),
                    ),
                    TicketStatusChip(status: ticket.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [who, if (ticket.dueAt != null) l.dueBy(hm(ticket.dueAt!))].join(' · '),
                  style: BText.body(
                    BType.caption,
                    weight: unassigned ? FontWeight.w800 : FontWeight.w700,
                    color: unassigned ? BColors.tweakFg : BColors.ink3,
                  ),
                ),
                if (unassigned) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('home-ticket-unassigned'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: BColors.tweakBg,
                      borderRadius: BorderRadius.circular(BRadii.small),
                    ),
                    child: Row(
                      children: [
                        const BIcon(BIcons.alert, size: 14, color: BColors.tweakFg),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l.ticketUnassignedCard,
                            style: BText.body(BType.caption, weight: FontWeight.w800, color: BColors.tweakFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  ticket.dishes.map((d) => d.name).join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BText.body(BType.chip, weight: FontWeight.w600),
                ),
                if (ticket.updated || ticket.stockIssueOpen) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (ticket.updated) KitchenTag(label: l.ticketUpdatedTag),
                      if (ticket.stockIssueOpen) KitchenTag(label: l.ticketStockIssueTag, icon: BIcons.alert),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
