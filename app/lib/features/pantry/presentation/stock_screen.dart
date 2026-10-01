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

/// S15 "Rasoi stock" (family, Hinglish) and K-stock (cook mode, Hindi, 200%
/// text): staples grouped by category with In / Low / Out pills (one tap →
/// PUT /v1/stock/{id}), search, a "Low + Out" filter and a bulk "Sab In".
class StockScreen extends StatelessWidget {
  const StockScreen({super.key, this.cook = false});

  final bool cook;

  @override
  Widget build(BuildContext context) => cook ? const CookScope(child: _Stock(cook: true)) : const _Stock(cook: false);
}

class _Stock extends ConsumerStatefulWidget {
  const _Stock({required this.cook});

  final bool cook;

  @override
  ConsumerState<_Stock> createState() => _StockState();
}

class _StockState extends ConsumerState<_Stock> {
  final _search = TextEditingController();
  bool _lowOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get cook => widget.cook;

  List<StockItem> _visible(List<StockItem> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final s in all)
        if ((!_lowOnly || s.level != ItemStatus.inStock) &&
            (q.isEmpty || s.name.toLowerCase().contains(q) || s.nameHi.contains(q) || s.ingredientId.contains(q)))
          s,
    ];
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    final l = AppLocalizations.of(context);
    try {
      await f();
      if (ok != null && mounted) BToast.show(context, ok);
    } catch (_) {
      if (mounted) BToast.show(context, cook ? l.cookError : l.toastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(stockProvider(cook));
    final all = async.value;
    final actions = ref.read(cook ? cookPantryActionsProvider : familyPantryActionsProvider);
    void back() => context.canPop() ? context.pop() : context.go(cook ? Routes.cook : Routes.home);
    final lowCount = all?.where((s) => s.level != ItemStatus.inStock).length ?? 0;
    final subtitle = all == null ? null : l.stockSubtitle(all.length, lowCount);

    final header = cook
        ? CookHeader(title: l.stockTitle, subtitle: subtitle, onBack: back)
        : KitchenHeader(
            title: l.stockTitle,
            subtitle: subtitle,
            onBack: back,
            trailing: BChip(
              key: const ValueKey('stock-ration'),
              label: l.rationTitle,
              leading: const BIcon(BIcons.bowl, size: 14, color: BColors.ink2),
              onTap: () => context.push(Routes.ration),
            ),
          );

    final visible = all == null ? const <StockItem>[] : _visible(all);
    final groups = <String, List<StockItem>>{};
    for (final s in visible) {
      (groups[s.category] ??= []).add(s);
    }
    final order = [
      ...StockCategory.order.where(groups.containsKey),
      ...groups.keys.where((k) => !StockCategory.order.contains(k)),
    ];
    final toIn = [
      for (final s in visible)
        if (s.level != ItemStatus.inStock) s.ingredientId,
    ];
    final labelSize = cook ? CookType.label : BType.chip;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const ValueKey('stock-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: BText.body(cook ? CookType.body : BType.body, weight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: l.stockSearchHint,
                isDense: true,
                filled: true,
                fillColor: BColors.card,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: BIcon(BIcons.search, size: 18, color: BColors.ink3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BRadii.cta),
                  borderSide: const BorderSide(color: BColors.border),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (low, label) in [(false, l.stockFilterAll), (true, l.stockFilterLowOut)])
                  BChip(
                    key: ValueKey('stock-filter-${low ? 'low' : 'all'}'),
                    label: label,
                    height: cook ? 48 : BSizes.chip,
                    selected: _lowOnly == low,
                    onTap: () => setState(() => _lowOnly = low),
                    child: Text(label, style: BText.body(labelSize, weight: FontWeight.w700)),
                  ),
                BChip(
                  key: const ValueKey('stock-all-in'),
                  label: l.stockAllIn,
                  height: cook ? 48 : BSizes.chip,
                  borderColor: BColors.green,
                  foreground: BColors.green,
                  leading: const BIcon(BIcons.check, size: 14, color: BColors.green),
                  onTap: toIn.isEmpty ? null : () => _run(() => actions.allIn(toIn), ok: l.stockAllInDone),
                  child: Text(
                    l.stockAllIn,
                    style: BText.body(labelSize, weight: FontWeight.w800, color: BColors.green),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: all == null
                ? Center(
                    child: async.hasError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(l.stockLoadError, style: BText.body(labelSize, weight: FontWeight.w700)),
                              const SizedBox(height: 10),
                              BChip(label: l.retry, onTap: () => ref.invalidate(stockProvider(cook))),
                            ],
                          )
                        : const CircularProgressIndicator(color: BColors.green),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      l.stockEmpty,
                      style: BText.body(labelSize, weight: FontWeight.w600, color: BColors.ink3),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      for (final cat in order) ...[
                        KitchenSectionTitle(l.stockCategory(cat)),
                        const SizedBox(height: 6),
                        KitchenCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(
                            children: [
                              for (final (i, s) in groups[cat]!.indexed)
                                _StockRow(
                                  item: s,
                                  cook: cook,
                                  last: i == groups[cat]!.length - 1,
                                  onLevel: (lv) => _run(() => actions.setLevel(s.ingredientId, lv)),
                                ),
                            ],
                          ),
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

class _StockRow extends StatelessWidget {
  const _StockRow({required this.item, required this.cook, required this.last, required this.onLevel});

  final StockItem item;
  final bool cook;
  final bool last;
  final ValueChanged<ItemStatus> onLevel;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      item.nameFor(hindi: cook),
      style: BText.body(cook ? CookType.body : BType.body, weight: FontWeight.w700),
    );
    final sub = !cook && item.nameHi.isNotEmpty
        ? Text(item.nameHi, style: BText.body(BType.caption, color: BColors.ink3))
        : null;
    final pills = LevelPills(
      key: ValueKey('stock-${item.ingredientId}'),
      id: item.ingredientId,
      level: item.level,
      large: cook,
      onChanged: onLevel,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: BColors.borderSoft)),
      ),
      // Cook mode stacks the pills under the name so 200% text never clips.
      child: cook
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, const SizedBox(height: 8), pills])
          : Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [name, ?sub]),
                ),
                const SizedBox(width: 8),
                pills,
              ],
            ),
    );
  }
}

/// In / Low / Out segmented pills; the current level is filled.
class LevelPills extends StatelessWidget {
  const LevelPills({super.key, required this.id, required this.level, required this.onChanged, this.large = false});

  final String id;
  final ItemStatus level;
  final ValueChanged<ItemStatus> onChanged;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget pill(ItemStatus s) {
      final on = level == s;
      final (bg, fg) = itemStatusColours(s);
      final label = l.stockLevel(s);
      return Pressable(
        key: ValueKey('level-$id-${s.wire}'),
        onTap: on ? null : () => onChanged(s),
        selected: on,
        semanticLabel: label,
        builder: (context, pressed) => Container(
          constraints: BoxConstraints(minHeight: large ? 48 : 34, minWidth: large ? 0 : 46),
          padding: EdgeInsets.symmetric(horizontal: large ? 8 : 10, vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? bg : BColors.card,
            borderRadius: BorderRadius.circular(BRadii.pill),
            border: Border.all(color: on ? fg : BColors.chipBorder, width: on ? 1.5 : 1),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: BText.body(
              large ? CookType.min : BType.caption,
              weight: FontWeight.w800,
              color: on ? fg : BColors.ink3,
            ),
          ),
        ),
      );
    }

    const levels = [ItemStatus.inStock, ItemStatus.low, ItemStatus.out];
    if (large) {
      return Row(
        children: [
          for (final (i, s) in levels.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: pill(s))],
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, s) in levels.indexed) ...[if (i > 0) const SizedBox(width: 6), pill(s)],
      ],
    );
  }
}
