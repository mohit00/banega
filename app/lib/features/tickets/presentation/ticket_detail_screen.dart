import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../labels/labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../account/application/account_providers.dart';
import '../../account/presentation/rate_sheet.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../../pantry/presentation/approval_sheet.dart';
import '../../members/application/members_controller.dart';
import '../../members/domain/member.dart';

/// Family ticket detail: status, assignee, due, eaters/servings, dishes,
/// notes, change log; edit (PATCH), cancel (reason while cooking), mark
/// done, and the "Khaana bana?" prompt when the ticket is not confirmed.
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(ticketProvider(ticketId));
    final t = async.value;
    void back() => context.canPop() ? context.pop() : context.go(Routes.home);

    if (t == null) {
      return Scaffold(
        backgroundColor: BColors.paper,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitchenHeader(title: l.ticketTitle, onBack: back),
            Expanded(
              child: Center(
                child: async.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l.ticketLoadError, style: BText.body(BType.body, weight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          BChip(label: l.retry, onTap: () => ref.invalidate(ticketProvider(ticketId))),
                        ],
                      )
                    : const CircularProgressIndicator(color: BColors.green),
              ),
            ),
          ],
        ),
      );
    }

    final actions = ref.read(familyTicketActionsProvider);
    final busy = ref.watch(ticketsInFlightProvider).contains(t.id);
    Future<void> run(Future<void> Function() f, {String? ok}) async {
      try {
        await f();
        if (ok != null && context.mounted) BToast.show(context, ok);
      } on AlreadyInFlight {
        // Double tap: ignored.
      } on KitchenError catch (e) {
        if (context.mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    Future<void> cancel() async {
      String? reason;
      if (t.status == TicketStatus.cooking) {
        reason = await _askReason(context);
        if (reason == null) return;
      } else {
        final yes = await _confirmCancel(context);
        if (yes != true) return;
      }
      await run(() => actions.transition(t, TicketStatus.cancelled, reason: reason), ok: l.ticketCancelledToast);
    }

    final canCancel = legalTransitions[t.status]!.contains(TicketStatus.cancelled);
    final canComplete =
        (t.status == TicketStatus.cooking || t.status == TicketStatus.ready) &&
        legalTransitions[t.status]!.contains(TicketStatus.completed);
    // Before Cooking: full edit; Cooking / Ready: notes only (the sheet
    // switches to notes-only when the status is no longer editable).
    final canEdit = t.status.isOpen && t.status != TicketStatus.notConfirmed;
    final ratingsOn = ref.watch(householdSettingsProvider).value?.ratingsEnabled ?? true;
    final canRate = ratingsOn && t.status == TicketStatus.completed && t.ratedAt == null;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: l.ticketCardTitle(l.slotKey(t.slot)),
            subtitle: [t.date, if (t.dueAt != null) l.dueBy(hm(t.dueAt!))].join(' · '),
            onBack: back,
            trailing: TicketStatusChip(status: t.status, large: true),
          ),
          Expanded(
            child: RefreshIndicator(
              color: BColors.green,
              onRefresh: () => ref.refresh(ticketProvider(ticketId).future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  if (t.status == TicketStatus.notConfirmed) ...[
                    _KhanaBanaPrompt(
                      onYes: busy ? null : () => run(() => actions.transition(t, TicketStatus.completed)),
                      onNo: busy ? null : () => run(() => actions.transition(t, TicketStatus.cancelled)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (t.status == TicketStatus.unassigned) ...[
                    _UnassignedPanel(ticket: t, busy: busy),
                    const SizedBox(height: 12),
                  ],
                  KitchenCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Info(label: l.planAssigneeTitle, value: t.assignee?.name ?? l.ticketNoAssignee),
                        _Info(label: l.planDueTitle, value: t.dueAt == null ? '—' : hmAmPm(t.dueAt!)),
                        _Info(
                          label: l.planServingsTitle,
                          value: [
                            l.planServingsValue(servingsText(t.servings)),
                            if (t.guests.count > 0) l.ticketGuests(t.guests.count),
                          ].join(' · '),
                        ),
                        _Info(label: l.planEatersTitle, value: t.eaters.map((e) => e.name).join(', ')),
                      ],
                    ),
                  ),
                  if (t.updated || t.stockIssueOpen) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (t.updated) KitchenTag(label: l.ticketUpdatedTag),
                        if (t.stockIssueOpen) KitchenTag(label: l.ticketStockIssueTag, icon: BIcons.alert),
                      ],
                    ),
                  ],
                  if (t.issue != null) ...[const SizedBox(height: 10), StockIssueBanner(ticket: t)],
                  if (canRate) ...[
                    const SizedBox(height: 10),
                    BCta(
                      key: const ValueKey('ticket-rate'),
                      label: l.ticketRate,
                      onPressed: () => showRateSheet(context, ref, t),
                    ),
                  ] else if (t.ratedAt != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      key: const ValueKey('ticket-rated'),
                      children: [
                        const BIcon(BIcons.check, size: 16, color: BColors.green),
                        const SizedBox(width: 6),
                        Text(
                          l.ticketRated,
                          style: BText.body(BType.chip, weight: FontWeight.w700, color: BColors.green),
                        ),
                      ],
                    ),
                  ],
                  KitchenSectionTitle(l.ticketDishes),
                  const SizedBox(height: 6),
                  KitchenCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final d in t.dishes)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.name, style: BText.body(BType.body, weight: FontWeight.w800)),
                                if (d.summary != null)
                                  Text(
                                    l.summaryNote(d.summary!),
                                    style: BText.body(BType.caption, color: BColors.ink3),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (t.requiredItems.isNotEmpty) ...[
                    KitchenSectionTitle(l.planSaamanList),
                    const SizedBox(height: 6),
                    KitchenCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(
                        children: [
                          for (final i in t.requiredItems)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(i.displayText, style: BText.body(13.5, weight: FontWeight.w600)),
                                  ),
                                  ItemStatusPill(status: i.status),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (t.notes.isNotEmpty) ...[
                    KitchenSectionTitle(l.ticketNotes),
                    const SizedBox(height: 6),
                    KitchenCard(child: Text(t.notes, style: BText.body(BType.body))),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canEdit)
                        BChip(
                          key: const ValueKey('ticket-edit'),
                          label: l.ticketEdit,
                          leading: const BIcon(BIcons.edit, size: 14, color: BColors.ink2),
                          onTap: busy ? null : () => _edit(context, ref, t),
                        ),
                      if (canComplete)
                        BChip(
                          key: const ValueKey('ticket-complete'),
                          label: l.ticketMarkDone,
                          onTap: busy ? null : () => run(() => actions.transition(t, TicketStatus.completed)),
                        ),
                      if (canCancel)
                        BChip(
                          key: const ValueKey('ticket-cancel'),
                          label: l.ticketCancel,
                          foreground: BColors.noFg,
                          onTap: busy ? null : cancel,
                        ),
                      BChip(
                        label: l.ticketAskCook,
                        leading: const BIcon(BIcons.chat, size: 14, color: BColors.ink2),
                        onTap: () => context.push(Routes.ticketThread(t.id)),
                      ),
                    ],
                  ),
                  if (t.changeLog.isNotEmpty) ...[
                    KitchenSectionTitle(l.ticketChangeLog),
                    const SizedBox(height: 6),
                    KitchenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final c in t.changeLog.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      c.at == null ? '' : hmAmPm(c.at!),
                                      style: BText.body(BType.caption, color: BColors.ink4),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      [
                                        '${c.by}: ${l.changeAction(c.action)}',
                                        if (c.detail.isNotEmpty && c.detail != c.action) c.detail,
                                      ].join(' · '),
                                      style: BText.body(BType.chip, weight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _askReason(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ticketCancelReason),
        content: TextField(
          key: const ValueKey('cancel-reason'),
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: l.ticketCancelReasonHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.ticketKeep)),
          TextButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
            },
            child: Text(l.ticketCancelConfirm),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmCancel(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ticketCancel),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.ticketKeep)),
          TextButton(
            key: const ValueKey('cancel-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.ticketCancelConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Ticket t) async {
    final patch = await showModalBottomSheet<TicketPatch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BColors.paper,
      builder: (ctx) => _EditSheet(ticket: t, members: ref.read(membersProvider)),
    );
    if (patch == null || !context.mounted) return;
    final l = AppLocalizations.of(context);
    try {
      await ref.read(familyTicketActionsProvider).patch(t, patch);
      if (context.mounted) BToast.show(context, l.ticketSavedToast);
    } on KitchenError catch (e) {
      if (context.mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
    } catch (_) {
      if (context.mounted) BToast.show(context, l.toastError);
    }
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
            ),
          ),
          Expanded(
            child: Text(value, style: BText.body(BType.body, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _KhanaBanaPrompt extends StatelessWidget {
  const _KhanaBanaPrompt({required this.onYes, required this.onNo});

  final VoidCallback? onYes;
  final VoidCallback? onNo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('khana-bana'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: BColors.tweakBg, borderRadius: BorderRadius.circular(BRadii.tile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.khanaBanaPrompt, style: BText.display(BType.section)),
          const SizedBox(height: 4),
          Text(l.khanaBanaHint, style: BText.body(BType.caption, color: BColors.ink3)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: BCta(key: const ValueKey('khana-yes'), label: l.khanaBanaYes, onPressed: onYes),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BGhostButton(key: const ValueKey('khana-no'), label: l.khanaBanaNo, onPressed: onNo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit sheet: dishes (remove), eaters, servings, due time, notes. While
/// cooking only the note can change (FR-K7).
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.ticket, required this.members});

  final Ticket ticket;
  final List<Member> members;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late List<MenuDish> dishes = List.of(widget.ticket.dishes);
  late Set<String> eaters = {for (final e in widget.ticket.eaters) e.memberId};
  late double servings = widget.ticket.servings;
  late DateTime? due = widget.ticket.dueAt;
  late final notes = TextEditingController(text: widget.ticket.notes);

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  TicketPatch _patch() {
    final t = widget.ticket;
    final onlyNotes = !t.status.editable;
    List<String> ids(Iterable<String> v) => v.toList();
    return TicketPatch(
      dishes: onlyNotes || dishes.length == t.dishes.length ? null : ids(dishes.map((d) => d.recipeId)),
      eaters: onlyNotes || eaters.length == t.eaters.length && t.eaters.every((e) => eaters.contains(e.memberId))
          ? null
          : ids(eaters),
      servings: onlyNotes || servings == t.servings ? null : servings,
      dueAt: onlyNotes || due == t.dueAt ? null : due,
      notes: notes.text == t.notes ? null : notes.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editable = widget.ticket.status.editable;
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.ticketEdit, style: BText.display(BType.section)),
            if (editable) ...[
              KitchenSectionTitle(l.ticketDishes),
              for (final d in dishes)
                Row(
                  children: [
                    Expanded(
                      child: Text(d.name, style: BText.body(BType.body, weight: FontWeight.w700)),
                    ),
                    if (dishes.length > 1)
                      BIconButton(
                        icon: BIcons.close,
                        semanticLabel: l.removeDish,
                        iconSize: 16,
                        onPressed: () => setState(() => dishes.remove(d)),
                      ),
                  ],
                ),
              KitchenSectionTitle(l.planEatersTitle),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in widget.members)
                    BChip(
                      label: m.name,
                      selected: eaters.contains(m.id),
                      onTap: () => setState(() => eaters.contains(m.id) ? eaters.remove(m.id) : eaters.add(m.id)),
                    ),
                ],
              ),
              KitchenSectionTitle(
                l.planServingsTitle,
                trailing: CountStepper(
                  value: servingsText(servings),
                  lessLabel: l.servingsLess,
                  moreLabel: l.servingsMore,
                  onLess: servings > .5 ? () => setState(() => servings -= .5) : null,
                  onMore: () => setState(() => servings += .5),
                ),
              ),
              KitchenSectionTitle(
                l.planDueTitle,
                trailing: BChip(
                  label: due == null ? '—' : hmAmPm(due!),
                  onTap: () async {
                    final base = due ?? DateTime.now();
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
                    if (t != null) setState(() => due = DateTime(base.year, base.month, base.day, t.hour, t.minute));
                  },
                ),
              ),
            ],
            KitchenSectionTitle(l.ticketNotes),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('ticket-notes'),
              controller: notes,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: l.ticketNotesHint,
                filled: true,
                fillColor: BColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(BRadii.cta)),
              ),
            ),
            const SizedBox(height: 16),
            BCta(
              key: const ValueKey('ticket-save'),
              label: l.ticketSave,
              onPressed: () => Navigator.pop(context, _patch()),
            ),
          ],
        ),
      ),
    );
  }
}

/// An unassigned ticket: the admin picks a cook ("Kisko dein…"), and any
/// adult can take it as chef for the day ("Main banaunga").
class _UnassignedPanel extends ConsumerWidget {
  const _UnassignedPanel({required this.ticket, required this.busy});

  final Ticket ticket;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final me = ref.watch(meProvider).value;
    final isAdmin = me?.isAdmin ?? false;
    final canClaim = me?.hasFamily ?? false;
    final cooks = isAdmin ? (ref.watch(cooksProvider).value ?? const <Cook>[]) : const <Cook>[];
    final actions = ref.read(familyTicketActionsProvider);

    Future<void> assign(Cook c) async {
      try {
        await actions.assign(ticket, c.id, c.kind);
        if (context.mounted) BToast.show(context, l.ticketAssignedToast(c.name));
      } on AlreadyInFlight {
        // Double tap: ignored.
      } on KitchenError catch (e) {
        if (!context.mounted) return;
        BToast.show(context, switch (e.code) {
          'assignee_required' => l.ticketAssigneeRequired,
          _ when e.isConflict => l.toastConflict,
          _ => l.toastError,
        });
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    Future<void> claim() async {
      try {
        await actions.claim(ticket);
        if (context.mounted) BToast.show(context, l.ticketClaimed);
      } on AlreadyInFlight {
        // Double tap: ignored.
      } on KitchenError catch (e) {
        if (!context.mounted) return;
        BToast.show(context, e.code == 'already_claimed' || e.isConflict ? l.ticketAlreadyClaimed : l.toastError);
        ref.invalidate(ticketProvider(ticket.id));
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    return Container(
      key: const ValueKey('ticket-unassigned'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: BColors.tweakBg, borderRadius: BorderRadius.circular(BRadii.tile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BIcon(BIcons.alert, size: 18, color: BColors.tweakFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.ticketUnassignedTitle,
                  style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.tweakFg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.ticketUnassignedHint,
            style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink2),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            Text(l.ticketAssignTo, style: BText.body(BType.chip, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (cooks.isEmpty)
              Text(l.ticketNoCooks, style: BText.body(BType.caption, color: BColors.ink3))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in cooks)
                    BChip(
                      key: ValueKey('assign-${c.id}'),
                      label: l.cookChip(c),
                      onTap: busy || !c.onDuty ? null : () => assign(c),
                    ),
                ],
              ),
          ],
          if (canClaim) ...[
            const SizedBox(height: 12),
            BCta(
              key: const ValueKey('ticket-claim'),
              label: l.ticketClaim,
              trailing: BIcons.pot,
              onPressed: busy ? null : claim,
            ),
          ],
        ],
      ),
    );
  }
}
