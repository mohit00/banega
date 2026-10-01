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
import '../../account/presentation/rate_sheet.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../../pantry/application/pantry_providers.dart';
import '../../pantry/domain/pantry_models.dart';
import '../../pantry/presentation/approval_sheet.dart';
import '../../recipe/application/recipe_providers.dart' show urlLauncherProvider;

/// In-app inbox (GET /v1/inbox): the source of truth for notifications.
/// Tapping an item marks it read and opens its ticket.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(inboxProvider);
    final items = async.value ?? const <InboxItem>[];

    Future<void> open(InboxItem i) async {
      if (i.unread) {
        try {
          await ref.read(inboxRepositoryProvider).markRead(i.id);
        } catch (_) {}
        ref.read(kitchenRevisionProvider.notifier).bump();
      }
      if (!context.mounted) return;
      await openInboxItem(context, ref, i);
    }

    final approvals = ref.watch(pendingApprovalsProvider).value ?? const <Approval>[];

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: l.inboxTitle,
            titleSize: BType.display26,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
            trailing: BIconButton(
              icon: BIcons.settings,
              semanticLabel: l.settingsTitle,
              background: BColors.card.withValues(alpha: .55),
              onPressed: () => context.push(Routes.settings),
            ),
          ),
          Expanded(
            child: async.isLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: BColors.green))
                : items.isEmpty
                ? Center(
                    child: Text(
                      async.hasError ? l.toastError : l.inboxEmpty,
                      style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink3),
                    ),
                  )
                : RefreshIndicator(
                    color: BColors.green,
                    onRefresh: () => ref.refresh(inboxProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (approvals.isNotEmpty) ...[
                          Text(l.approvalTitle, style: BText.body(BType.sectionLabel, weight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          for (final a in approvals) ...[
                            _ApprovalRow(approval: a, onTap: () => showApprovalSheet(context, ref, a)),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                        ],
                        for (final (n, item) in items.indexed) ...[
                          if (n > 0) const SizedBox(height: 8),
                          _InboxRow(item: item, onTap: () => open(item)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: item.title,
      builder: (context, pressed) => KitchenCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(shape: BoxShape.circle, color: item.unread ? BColors.green : BColors.card),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: BText.body(BType.body, weight: item.unread ? FontWeight.w800 : FontWeight.w600),
                  ),
                  if (item.body.isNotEmpty) Text(item.body, style: BText.body(BType.caption, color: BColors.ink3)),
                ],
              ),
            ),
            if (item.createdAt != null)
              Text(hmAmPm(item.createdAt!), style: BText.body(BType.caption, color: BColors.ink4)),
          ],
        ),
      ),
    );
  }
}

/// Where an inbox item leads: approvals open the Approval sheet, rate
/// prompts the rate sheet, stock / ration events their screens, the plan
/// reminder the paywall, an export its link; otherwise the ticket.
Future<void> openInboxItem(BuildContext context, WidgetRef ref, InboxItem i) async {
  switch (i.event) {
    case 'approval_request' || 'stock_issue':
      final opened = await openPendingApproval(context, ref, ticketId: i.ticketId, approvalId: i.approvalId);
      if (!opened && i.ticketId != null && context.mounted) await context.push(Routes.ticket(i.ticketId!));
    case 'rate_prompt' when i.ticketId != null:
      try {
        final t = await ref.read(ticketsRepositoryProvider).ticket(i.ticketId!);
        if (!context.mounted) return;
        if (t.status == TicketStatus.completed && t.ratedAt == null) {
          await showRateSheet(context, ref, t);
        } else {
          await context.push(Routes.ticket(t.id));
        }
      } catch (_) {}
    case 'ration_request' || 'ration_decided':
      await context.push(Routes.ration);
    case 'stock_low':
      await context.push(Routes.stock);
    case 'expiry_reminder':
      await context.push(Routes.paywall);
    case 'export_ready' when i.link != null:
      await ref.read(urlLauncherProvider)(Uri.parse(i.link!));
    default:
      if (i.ticketId != null) await context.push(Routes.ticket(i.ticketId!));
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.approval, required this.onTap});

  final Approval approval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Pressable(
      key: ValueKey('approval-${approval.id}'),
      onTap: onTap,
      semanticLabel: l.approvalText(approval),
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: BColors.tweakBg, borderRadius: BorderRadius.circular(BRadii.tile)),
        child: Row(
          children: [
            const BIcon(BIcons.alert, size: 18, color: BColors.tweakFg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.approvalText(approval), style: BText.body(BType.body, weight: FontWeight.w800)),
                  if (approval.requestedBy.isNotEmpty)
                    Text(
                      l.approvalAskedBy(approval.requestedBy),
                      style: BText.body(BType.caption, color: BColors.ink3),
                    ),
                ],
              ),
            ),
            const BIcon(BIcons.chevronRight, size: 16, color: BColors.tweakFg),
          ],
        ),
      ),
    );
  }
}
