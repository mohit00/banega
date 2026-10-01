import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../cook_mode/cook_ui.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../application/pantry_providers.dart';
import '../domain/pantry_models.dart';

/// S13 Ration: pending / approved / bought tabs. The admin approves or
/// rejects with a note, and "Kharid liya" puts the items back In stock.
class RationScreen extends ConsumerStatefulWidget {
  const RationScreen({super.key});

  @override
  ConsumerState<RationScreen> createState() => _RationScreenState();
}

class _RationScreenState extends ConsumerState<RationScreen> {
  RationStatus _tab = RationStatus.pending;

  Future<void> _run(Future<void> Function() f, String ok) async {
    final l = AppLocalizations.of(context);
    try {
      await f();
      if (mounted) BToast.show(context, ok);
    } on KitchenError catch (e) {
      if (mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
    } catch (_) {
      if (mounted) BToast.show(context, l.toastError);
    }
  }

  Future<void> _decide(RationRequest r, String decision) async {
    final l = AppLocalizations.of(context);
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == Decision.approved ? l.rationApprove : l.rationReject),
        content: TextField(
          key: const ValueKey('ration-note'),
          controller: note,
          decoration: InputDecoration(hintText: l.rationNoteHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.settingsCancel)),
          TextButton(
            key: const ValueKey('ration-decide-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(decision == Decision.approved ? l.rationApprove : l.rationReject),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog's exit transition still reads it.
    final text = note.text.trim();
    if (ok != true) return;
    await _run(
      () => ref.read(familyPantryActionsProvider).decide(r.id, decision, note: text.isEmpty ? null : text),
      decision == Decision.approved ? l.rationApprovedToast : l.rationRejectedToast,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(rationRequestsProvider(false));
    final all = async.value;
    bool inTab(RationRequest r) => switch (_tab) {
      RationStatus.pending => r.status == RationStatus.pending,
      RationStatus.approved => r.status == RationStatus.approved,
      _ => r.status == RationStatus.bought || r.status == RationStatus.rejected,
    };
    final list = [...?all?.where(inTab)];
    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: l.rationTitle,
            titleSize: BType.display26,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
            trailing: BChip(
              key: const ValueKey('ration-stock'),
              label: l.stockTitle,
              onTap: () => context.push(Routes.stock),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: BSegmentControl<RationStatus>(
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
              segments: [
                BSegment(RationStatus.pending, l.rationTabPending),
                BSegment(RationStatus.approved, l.rationTabApproved),
                BSegment(RationStatus.bought, l.rationTabBought),
              ],
            ),
          ),
          Expanded(
            child: all == null
                ? Center(
                    child: async.hasError
                        ? BChip(label: l.retry, onTap: () => ref.invalidate(rationRequestsProvider(false)))
                        : const CircularProgressIndicator(color: BColors.green),
                  )
                : list.isEmpty
                ? Center(
                    child: Text(
                      l.rationEmpty,
                      style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink3),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      return RationCard(
                        request: r,
                        actions: [
                          if (r.status == RationStatus.pending) ...[
                            BChip(
                              key: ValueKey('ration-approve-${r.id}'),
                              label: l.rationApprove,
                              borderColor: BColors.green,
                              foreground: BColors.green,
                              onTap: () => _decide(r, Decision.approved),
                            ),
                            BChip(
                              key: ValueKey('ration-reject-${r.id}'),
                              label: l.rationReject,
                              foreground: BColors.noFg,
                              onTap: () => _decide(r, Decision.rejected),
                            ),
                          ],
                          if (r.status == RationStatus.approved)
                            BChip(
                              key: ValueKey('ration-bought-${r.id}'),
                              label: l.rationBought,
                              borderColor: BColors.green,
                              foreground: BColors.green,
                              leading: const BIcon(BIcons.check, size: 14, color: BColors.green),
                              onTap: () =>
                                  _run(() => ref.read(familyPantryActionsProvider).bought(r.id), l.rationBoughtToast),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One ration request: status, who raised it, the items, actions.
class RationCard extends StatelessWidget {
  const RationCard({super.key, required this.request, this.actions = const [], this.large = false});

  final RationRequest request;
  final List<Widget> actions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = request;
    final (bg, fg) = switch (r.status) {
      RationStatus.pending => (BColors.tweakBg, BColors.tweakFg),
      RationStatus.approved || RationStatus.bought => (BColors.fitBg, BColors.fitFg),
      RationStatus.rejected => (BColors.noBg, BColors.noFg),
    };
    final body = large ? CookType.label : BType.body;
    final small = large ? CookType.min : BType.caption;
    return KitchenCard(
      key: ValueKey('ration-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [l.rationRaisedBy(r.raisedBy), if (r.createdAt != null) hmAmPm(r.createdAt!)].join(' · '),
                  style: BText.body(small, weight: FontWeight.w700, color: BColors.ink3),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(BRadii.badge)),
                child: Text(
                  l.rationStatus(r.status),
                  style: BText.body(small, weight: FontWeight.w800, color: fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.items.map((i) => i.name).join(', '), style: BText.body(body, weight: FontWeight.w700)),
          if (r.note != null && r.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.note == 'self_approved' ? l.rationSelfApproved : r.note!,
              style: BText.body(small, color: BColors.ink3),
            ),
          ],
          if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: actions)],
        ],
      ),
    );
  }
}

/// Cook mode: the cook's own ration requests with status, and "Nayi maang".
class CookRationScreen extends StatelessWidget {
  const CookRationScreen({super.key});

  @override
  Widget build(BuildContext context) => const CookScope(child: _CookRation());
}

class _CookRation extends ConsumerWidget {
  const _CookRation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(rationRequestsProvider(true));
    final list = async.value;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CookHeader(
            title: l.cookRationTitle,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.cook),
          ),
          Expanded(
            child: list == null
                ? Center(
                    child: async.hasError
                        ? Text(l.cookLoadError, style: BText.body(CookType.body, weight: FontWeight.w700))
                        : const CircularProgressIndicator(color: BColors.green),
                  )
                : list.isEmpty
                ? Center(
                    child: Text(
                      l.rationEmpty,
                      style: BText.body(CookType.body, weight: FontWeight.w700, color: BColors.ink3),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => RationCard(request: list[i], large: true),
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: CookActionButton(
              key: const ValueKey('cook-ration-new'),
              label: l.cookRationNew,
              icon: BIcons.plus,
              onPressed: () => showRaiseRationSheet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// K2 "Ration maango": out / low items (pre-ticked) plus free-text items.
Future<void> showRaiseRationSheet(BuildContext context, WidgetRef ref, {Ticket? ticket}) async {
  final l = AppLocalizations.of(context);
  final stock = await ref.read(stockProvider(true).future).catchError((_) => const <StockItem>[]);
  if (!context.mounted) return;
  final fromTicket = ticket == null ? const <RationItem>[] : missingItems(ticket.requiredItems);
  final seen = {for (final i in fromTicket) i.ingredientId};
  final candidates = [
    ...fromTicket,
    for (final s in stock)
      if (s.level != ItemStatus.inStock && seen.add(s.ingredientId))
        RationItem(ingredientId: s.ingredientId, name: s.nameFor(hindi: true)),
  ];
  final items = await showModalBottomSheet<List<RationItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BColors.paper,
    builder: (ctx) => CookScope(child: _RaiseSheet(candidates: candidates)),
  );
  if (items == null || items.isEmpty || !context.mounted) return;
  try {
    await ref.read(cookPantryActionsProvider).raise(items, ticketId: ticket?.id);
    if (context.mounted) BToast.show(context, l.cookRationSent);
  } catch (_) {
    if (context.mounted) BToast.show(context, l.cookError);
  }
}

class _RaiseSheet extends StatefulWidget {
  const _RaiseSheet({required this.candidates});

  final List<RationItem> candidates;

  @override
  State<_RaiseSheet> createState() => _RaiseSheetState();
}

class _RaiseSheetState extends State<_RaiseSheet> {
  late final List<RationItem> _items = List.of(widget.candidates);
  late final Set<int> _on = {for (var i = 0; i < _items.length; i++) i};
  final _free = TextEditingController();

  @override
  void dispose() {
    _free.dispose();
    super.dispose();
  }

  void _add() {
    final t = _free.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _items.add(RationItem(name: t));
      _on.add(_items.length - 1);
      _free.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.cookRationSheetTitle, style: BText.display(CookType.title)),
            const SizedBox(height: 10),
            for (var i = 0; i < _items.length; i++)
              Pressable(
                key: ValueKey('raise-item-$i'),
                onTap: () => setState(() => _on.contains(i) ? _on.remove(i) : _on.add(i)),
                selected: _on.contains(i),
                semanticLabel: _items[i].name,
                builder: (context, _) => Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _on.contains(i) ? Icons.check_box : Icons.check_box_outline_blank,
                        color: _on.contains(i) ? BColors.green : BColors.ink3,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_items[i].name, style: BText.body(CookType.body, weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('raise-free'),
                    controller: _free,
                    onSubmitted: (_) => _add(),
                    style: BText.body(CookType.body, weight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: l.cookRationFreeHint,
                      filled: true,
                      fillColor: BColors.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(BRadii.cta)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BChip(
                  key: const ValueKey('raise-add'),
                  label: l.cookRationAdd,
                  height: 52,
                  onTap: _add,
                  child: Text(l.cookRationAdd, style: BText.body(CookType.label, weight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CookActionButton(
              key: const ValueKey('raise-send'),
              label: l.cookRationSend,
              icon: BIcons.send,
              onPressed: _on.isEmpty
                  ? null
                  : () => Navigator.pop(context, [
                      for (var i = 0; i < _items.length; i++)
                        if (_on.contains(i)) _items[i],
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}
