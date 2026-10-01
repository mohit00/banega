import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../application/pantry_providers.dart';
import '../domain/pantry_models.dart';

/// Approval sheet (family): what the cook asks, Haan / Nahi →
/// POST /v1/approvals/{id}/decide. First response wins; a 409 means someone
/// already answered.
Future<void> showApprovalSheet(BuildContext context, WidgetRef ref, Approval a) async {
  final l = AppLocalizations.of(context);
  final decision = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: BColors.paper,
    builder: (ctx) => _ApprovalSheet(approval: a),
  );
  if (decision == null || !context.mounted) return;
  try {
    await ref.read(familyPantryActionsProvider).decideApproval(a.id, decision);
    if (context.mounted) {
      BToast.show(context, decision == Decision.approved ? l.approvalApprovedToast : l.approvalRejectedToast);
    }
  } on KitchenError catch (e) {
    if (context.mounted) BToast.show(context, e.isConflict ? l.approvalGone : l.toastError);
  } catch (_) {
    if (context.mounted) BToast.show(context, l.toastError);
  }
}

/// Opens the pending approval for [ticketId] (or [approvalId]); false when
/// there is none.
Future<bool> openPendingApproval(BuildContext context, WidgetRef ref, {String? ticketId, String? approvalId}) async {
  List<Approval> pending;
  try {
    pending = await ref.read(approvalsRepositoryProvider).approvals(status: 'pending');
  } catch (_) {
    return false;
  }
  final a = pending
      .where((a) => a.pending && (approvalId != null ? a.id == approvalId : a.ticketId == ticketId))
      .firstOrNull;
  if (a == null || !context.mounted) return false;
  await showApprovalSheet(context, ref, a);
  return true;
}

class _ApprovalSheet extends StatelessWidget {
  const _ApprovalSheet({required this.approval});

  final Approval approval;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = approval;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 18 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.approvalTitle, style: BText.display(BType.section)),
          const SizedBox(height: 8),
          Text(
            l.approvalText(a),
            key: const ValueKey('approval-text'),
            style: BText.body(BType.cta, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (a.requestedBy.isNotEmpty) l.approvalAskedBy(a.requestedBy),
              if (a.expiresAt != null) l.approvalExpires(hmAmPm(a.expiresAt!)),
            ].join(' · '),
            style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BCta(
                  key: const ValueKey('approval-yes'),
                  label: l.approvalYes,
                  onPressed: () => Navigator.pop(context, Decision.approved),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BGhostButton(
                  key: const ValueKey('approval-no'),
                  label: l.approvalNo,
                  onPressed: () => Navigator.pop(context, Decision.rejected),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ticket detail banner for an open stock issue: what ran out and where
/// the ladder stands (choosing / waiting for you / timed out), with Haan /
/// Nahi when an approval is pending.
class StockIssueBanner extends ConsumerWidget {
  const StockIssueBanner({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final issue = ticket.issue;
    if (issue == null) return const SizedBox.shrink();
    final pending = ref.watch(pendingApprovalsProvider).value ?? const <Approval>[];
    final approval = pending.where((a) => a.ticketId == ticket.id && a.pending).firstOrNull;
    final timedOut = issue.state == StockIssueState.timedOut;
    final detail = approval?.detail.isNotEmpty ?? false ? approval!.detail : issue.detail;
    final line = switch (issue.state) {
      StockIssueState.pending => l.ticketIssuePending(detail),
      StockIssueState.timedOut => l.ladderTimeout,
      _ => l.ticketIssueChoosing,
    };
    return Container(
      key: const ValueKey('stock-issue-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: timedOut ? BColors.noBg : BColors.tweakBg,
        borderRadius: BorderRadius.circular(BRadii.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BIcon(BIcons.alert, size: 18, color: timedOut ? BColors.noFg : BColors.tweakFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.ladderTitle(issue.name.isEmpty ? (ticket.ladder?.ingredientName ?? '') : issue.name),
                  style: BText.body(BType.cta, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            line,
            style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink2),
          ),
          if (approval != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BCta(
                    key: const ValueKey('issue-yes'),
                    label: l.approvalYes,
                    onPressed: () => _decide(context, ref, approval, Decision.approved),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BGhostButton(
                    key: const ValueKey('issue-no'),
                    label: l.approvalNo,
                    onPressed: () => _decide(context, ref, approval, Decision.rejected),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Approval a, String decision) async {
    final l = AppLocalizations.of(context);
    try {
      await ref.read(familyPantryActionsProvider).decideApproval(a.id, decision);
      if (context.mounted) {
        BToast.show(context, decision == Decision.approved ? l.approvalApprovedToast : l.approvalRejectedToast);
      }
    } on KitchenError catch (e) {
      if (context.mounted) BToast.show(context, e.isConflict ? l.approvalGone : l.toastError);
    } catch (_) {
      if (context.mounted) BToast.show(context, l.toastError);
    }
  }
}
