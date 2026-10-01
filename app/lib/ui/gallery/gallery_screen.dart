import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/fit_engine.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/demo/demo_recipes.dart';
import '../../features/members/application/members_controller.dart';
import '../../features/recipe/domain/recipe.dart';
import '../../labels/labels.dart';
import '../ui.dart';

/// Internal design-system gallery (/gallery): every component from
/// build-plan §1.3 on one scrolling page, for side-by-side sign-off against
/// the prototype.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  bool _chip = true;
  bool _added = false;
  Slot _slot = Slot.lunch;
  BNavTab _tab = BNavTab.ghar;

  RecipeCardData _card(Recipe r) {
    final l = AppLocalizations.of(context);
    final members = ref.read(membersProvider);
    final s = summarize(members, r);
    return RecipeCardData(
      name: r.name,
      cuisine: l.cuisine(r.cuisine),
      mins: r.mins,
      mark: DietMark.forRecipe(r).kind,
      color: r.color,
      fitKind: s.kind,
      fitShort: l.fitShort(s),
      note: l.fitNote(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(t, style: BText.eyebrow(color: BColors.ink3)),
    );

    return Scaffold(
      backgroundColor: BColors.paper,
      appBar: AppBar(
        title: Text(l.galleryTitle, style: BText.body(BType.memberName, weight: FontWeight.w800)),
      ),
      bottomNavigationBar: BBottomNav(current: _tab, onTap: (t) => setState(() => _tab = t)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          label('CHIP'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BChip(label: l.needLowOil, selected: _chip, onTap: () => setState(() => _chip = !_chip)),
              BChip(label: l.needLowSugar, selected: !_chip, onTap: () => setState(() => _chip = !_chip)),
            ],
          ),
          label('SEGMENT'),
          BSegmentControl<Slot>(
            value: _slot,
            onChanged: (s) => setState(() => _slot = s),
            segments: [for (final s in Slot.values) BSegment(s, l.slot(s))],
          ),
          label('CTA / GHOST / ADD'),
          BCta(label: l.splashCta, trailing: BIcons.arrowRight, onPressed: () {}),
          const SizedBox(height: 10),
          BGhostButton(label: l.videoRecipe, onPressed: () {}),
          const SizedBox(height: 10),
          Row(
            children: [
              BAddButton(added: _added, onPressed: () => setState(() => _added = !_added)),
              const SizedBox(width: 10),
              BAddButton(added: !_added, onPressed: () => setState(() => _added = !_added)),
            ],
          ),
          label('DIET MARK / FIT BADGE / STEP'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const DietMark(DietMarkKind.veg),
              const DietMark(DietMarkKind.egg),
              const DietMark(DietMarkKind.nonveg),
              FitBadge(kind: FitKind.fit, label: l.fitAllPerfect),
              FitBadge(kind: FitKind.tweak, label: l.fitAllTweak(2)),
              FitBadge(kind: FitKind.no, label: l.fitPartial(3, 5)),
              const StepNumber(1),
              const StepNumber(2),
            ],
          ),
          label('AVATAR'),
          Row(
            children: [
              for (final m in ref.watch(membersProvider)) ...[
                BAvatar(initial: m.initial, color: m.color),
                const SizedBox(width: 8),
              ],
            ],
          ),
          label('RECIPE TILE'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RecipeTile(data: _card(demoRecipes[7]), added: _added, index: 0),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RecipeTile(data: _card(demoRecipes[19]), added: !_added, index: 1),
              ),
            ],
          ),
          label('RECIPE MINI CARD'),
          SizedBox(
            height: 250,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                RecipeMiniCard(data: _card(demoRecipes[9]), added: false),
                const SizedBox(width: 10),
                RecipeMiniCard(data: _card(demoRecipes[18]), added: true, index: 1),
              ],
            ),
          ),
          label('MEMBER TILE'),
          for (final m in ref.watch(membersProvider).take(2)) ...[
            MemberTile(
              name: m.name,
              initial: m.initial,
              color: m.color,
              dietLabel: l.diet(m.diet),
              summary: l.memberSummary(m),
            ),
            const SizedBox(height: 10),
          ],
          BDashedButton(label: l.addMember, onPressed: () {}),
          label('TICKER SEARCH BAR'),
          Container(color: BColors.haldi, padding: const EdgeInsets.all(12), child: const TickerSearchBar()),
          label('TYPING INDICATOR'),
          const TypingIndicator(),
          label('TOAST'),
          Align(
            alignment: Alignment.centerLeft,
            child: BChip(label: l.toastSentCook, onTap: () => BToast.show(context, l.toastSentCook)),
          ),
          label('THALI HERO'),
          Container(
            height: 260,
            color: BColors.haldi,
            alignment: Alignment.center,
            child: ThaliHero(semanticLabel: l.thaliAlt),
          ),
        ],
      ),
    );
  }
}
