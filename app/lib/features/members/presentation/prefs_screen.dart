import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/labels.dart';
import '../../../ui/ui.dart';
import '../application/members_controller.dart';
import '../../../data/demo/demo_recipes.dart';
import '../domain/member.dart';

/// S3 — "{name} ki pasand" (prototype "PREFS", step 2 of 2). Every tap writes
/// straight to [membersProvider], like the prototype.
class PrefsScreen extends ConsumerStatefulWidget {
  const PrefsScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<PrefsScreen> createState() => _PrefsScreenState();
}

class _PrefsScreenState extends ConsumerState<PrefsScreen> {
  late String _selectedId = widget.memberId;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.family);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    final ctrl = ref.read(membersProvider.notifier);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (members.isEmpty) {
      // API mode before the list arrives (or after the last member left).
      final loading = ref.watch(membersStatusProvider).loading;
      return Scaffold(
        backgroundColor: BColors.card,
        body: Padding(
          padding: EdgeInsets.fromLTRB(16, 14 + topInset, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BIconButton(icon: BIcons.chevronLeft, semanticLabel: l.back, onPressed: _back),
              Expanded(
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator(color: BColors.green)
                      : Text(l.membersEmpty, style: BText.body(BType.body, color: BColors.ink3)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final edit = members.firstWhere((m) => m.id == _selectedId, orElse: () => members.first);

    // Optimistic writes: a failure rolls the member back and says so.
    void run(Future<void> Function() f) {
      f().catchError((Object _) {
        if (context.mounted) BToast.show(context, l.memberSaveError);
      });
    }

    Future<void> remove() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.removeMemberConfirm(edit.name)),
          content: Text(l.removeMemberBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
            TextButton(
              key: const ValueKey('member-remove-yes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.removeMemberYes, style: const TextStyle(color: BColors.noFg)),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      try {
        await ctrl.remove(edit.id);
        if (context.mounted) _back();
      } catch (_) {
        if (context.mounted) BToast.show(context, l.memberSaveError);
      }
    }

    return Scaffold(
      backgroundColor: BColors.card,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: back + eyebrow.
          Container(
            padding: EdgeInsets.fromLTRB(16, 14 + topInset, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BColors.border)),
            ),
            child: Row(
              children: [
                BIconButton(icon: BIcons.chevronLeft, semanticLabel: l.back, onPressed: _back),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.prefsStep,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BText.eyebrow(color: BColors.ink3),
                  ),
                ),
              ],
            ),
          ),
          // Member tab strip.
          SizedBox(
            height: 14 + 44 + 4,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = members[i];
                return BChip(
                  key: ValueKey('tab-${m.id}'),
                  selected: m.id == edit.id,
                  height: 44,
                  padding: const EdgeInsets.fromLTRB(5, 0, 14, 0),
                  semanticLabel: m.name,
                  leading: BAvatar(initial: m.initial, color: m.color, size: 32, fontSize: 12),
                  label: m.name,
                  onTap: () => setState(() => _selectedId = m.id),
                );
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Row(
                  children: [
                    BAvatar(initial: edit.initial, color: edit.color, size: 60, fontSize: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(l.prefsTitle(edit.name), style: BText.display(BType.display26)),
                          ),
                          Text(l.prefsSubtitle, style: BText.body(BType.chip, color: BColors.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsDietTitle,
                  child: _DietGrid(member: edit, onPick: (d) => run(() => ctrl.setDiet(edit.id, d))),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsSpiceTitle,
                  child: BSegmentControl<Spice>(
                    trackColor: BColors.paper,
                    value: edit.spice,
                    onChanged: (s) => run(() => ctrl.setSpice(edit.id, s)),
                    segments: [
                      for (final s in Spice.values) BSegment(s, l.spice(s), leading: ChilliPills(count: s.level)),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsNeedsTitle,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in Need.values)
                        BChip(
                          label: l.need(n),
                          selected: edit.needs.contains(n),
                          onTap: () => run(() => ctrl.toggleNeed(edit.id, n)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsCuisineTitle,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in Cuisine.values)
                        BChip(
                          label: l.cuisine(c),
                          selected: edit.cuisines.contains(c),
                          onTap: () => run(() => ctrl.toggleCuisine(edit.id, c)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _ToggleRow(
                  key: const ValueKey('prefs-kid'),
                  title: l.prefsKidTitle,
                  hint: l.prefsKidHint,
                  value: edit.isKid,
                  onChanged: (v) => run(() => ctrl.setKid(edit.id, v)),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsAllergensTitle,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in kAllergens)
                        BChip(
                          key: ValueKey('allergen-$a'),
                          label: l.allergen(a),
                          selected: edit.allergens.contains(a),
                          onTap: () => run(() => ctrl.toggleAllergen(edit.id, a)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsDislikesTitle,
                  child: _DislikesInput(
                    key: ValueKey('dislikes-${edit.id}'),
                    items: edit.dislikes,
                    onAdd: (v) => run(() => ctrl.addDislike(edit.id, v)),
                    onRemove: (v) => run(() => ctrl.removeDislike(edit.id, v)),
                  ),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: l.prefsVratTitle,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                        BChip(
                          key: ValueKey('vrat-$d'),
                          label: l.weekdayShort(d),
                          selected: edit.vratDays.contains(d),
                          onTap: () => run(() => ctrl.toggleVratDay(edit.id, d)),
                        ),
                    ],
                  ),
                ),
                if (edit.diet == Diet.nonveg) ...[
                  const SizedBox(height: 22),
                  _Section(
                    title: l.prefsNonvegTitle,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final x in kNonvegExclusions)
                          BChip(
                            key: ValueKey('nonveg-$x'),
                            label: l.nonvegExclusion(x),
                            selected: edit.nonvegExclusions.contains(x),
                            onTap: () => run(() => ctrl.toggleNonvegExclusion(edit.id, x)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _ToggleRow(
                  key: const ValueKey('prefs-no-dairy'),
                  title: l.prefsNoDairyTitle,
                  hint: l.prefsNoDairyHint,
                  value: edit.noDairy,
                  onChanged: (v) => run(() => ctrl.setNoDairy(edit.id, v)),
                ),
                const SizedBox(height: 14),
                _ToggleRow(
                  key: const ValueKey('prefs-show-on-home'),
                  title: l.prefsShowOnHomeTitle,
                  hint: l.prefsShowOnHomeHint,
                  value: edit.showOnHome,
                  onChanged: (v) => run(() => ctrl.setShowOnHome(edit.id, v)),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BTextButton(
                    key: const ValueKey('member-remove'),
                    label: l.removeMember,
                    color: BColors.noFg,
                    onPressed: remove,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: BCta(label: l.prefsSave(edit.name), onPressed: _back),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: BText.body(BType.sectionLabel, weight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// 3-column grid of diet chips (52 high) with a diet mark and a hint line.
class _DietGrid extends StatelessWidget {
  const _DietGrid({required this.member, required this.onPick});

  final Member member;
  final ValueChanged<Diet> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget cell(Diet d) => Expanded(
      child: BChip(
        selected: member.diet == d,
        height: 52,
        radius: BRadii.cta,
        alignment: MainAxisAlignment.start,
        fill: true,
        semanticLabel: '${l.diet(d)}, ${l.dietHint(d)}',
        leading: DietMark.forDiet(d),
        onTap: () => onPick(d),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.diet(d), overflow: TextOverflow.ellipsis),
            Text(
              l.dietHint(d),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BText.body(BType.badge, color: BColors.ink3),
            ),
          ],
        ),
      ),
    );

    // Three columns so all six diets (incl. No onion-garlic and
    // Pescatarian, F-5.2-01b) are reachable.
    return Column(
      children: [
        Row(
          children: [
            cell(Diet.veg),
            const SizedBox(width: 8),
            cell(Diet.jain),
            const SizedBox(width: 8),
            cell(Diet.noOnionGarlic),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            cell(Diet.egg),
            const SizedBox(width: 8),
            cell(Diet.pescatarian),
            const SizedBox(width: 8),
            cell(Diet.nonveg),
          ],
        ),
      ],
    );
  }
}

/// 1–3 little chilli pills (14×5) used in the spice segment.
class ChilliPills extends StatelessWidget {
  const ChilliPills({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          const SpiceShape(SpiceKind.chilli, size: Size(14, 5)),
        ],
        // label has margin-left:4px on top of the 4px flex gap
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Title + hint with a switch (Bachcha hai / No dairy / show on Home).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({super.key, required this.title, required this.hint, required this.value, required this.onChanged});

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BText.body(BType.sectionLabel, weight: FontWeight.w800)),
                Text(hint, style: BText.body(BType.caption, color: BColors.ink3)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: BColors.green),
        ],
      ),
    );
  }
}

/// Dislikes as removable chips + a field that suggests ingredient names.
class _DislikesInput extends StatefulWidget {
  const _DislikesInput({super.key, required this.items, required this.onAdd, required this.onRemove});

  final List<String> items;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_DislikesInput> createState() => _DislikesInputState();
}

class _DislikesInputState extends State<_DislikesInput> {
  TextEditingController? _field;

  void _add(String v) {
    if (v.trim().isEmpty) return;
    widget.onAdd(v);
    _field?.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in widget.items)
                BChip(
                  key: ValueKey('dislike-$d'),
                  selected: true,
                  semanticLabel: l.prefsDislikeRemove(d),
                  onTap: () => widget.onRemove(d),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d),
                      const SizedBox(width: 6),
                      const BIcon(BIcons.close, size: 12, color: BColors.fitFg),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Autocomplete<String>(
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<String>.empty();
            return ingredientNameSuggestions.where((n) => n.contains(q) && !widget.items.contains(n)).take(6);
          },
          onSelected: _add,
          fieldViewBuilder: (context, controller, focus, onSubmit) {
            _field = controller;
            return TextField(
              key: const ValueKey('dislike-input'),
              controller: controller,
              focusNode: focus,
              textInputAction: TextInputAction.done,
              onSubmitted: _add,
              style: BText.body(BType.body),
              decoration: InputDecoration(
                hintText: l.prefsDislikesHint,
                isDense: true,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(BRadii.cta))),
                suffixIcon: TextButton(
                  key: const ValueKey('dislike-add'),
                  onPressed: () => _add(controller.text),
                  child: Text(l.prefsDislikeAdd),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Ingredient names from the seed recipes (lower-case, without quantities),
/// offered while typing a dislike.
final List<String> ingredientNameSuggestions = () {
  final out = <String>{};
  final units = RegExp(r'\b(cup|cups|tsp|tbsp|kg|g|gm|ml|l|katori|mutthi|chammach)\b', caseSensitive: false);
  for (final r in demoRecipes) {
    for (final i in r.ingredients) {
      for (final part in i.replaceAll(RegExp(r'\(.*?\)'), '').split(RegExp(r'[,/]'))) {
        final name = part.replaceAll(RegExp(r'[0-9.]+'), '').replaceAll(units, '').trim().toLowerCase();
        if (name.length >= 3) out.add(name);
      }
    }
  }
  return out.toList()..sort();
}();
