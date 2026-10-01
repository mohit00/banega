import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/motion/motion.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../labels/labels.dart';
import '../../ui/ui.dart';
import '../account/application/account_providers.dart';
import '../account/presentation/paywall_screen.dart';
import '../account/presentation/weekly_card.dart';
import '../members/application/members_controller.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../menu/application/day_menu.dart';
import '../recipe/domain/recipe.dart';
import '../tickets/presentation/ticket_status_card.dart';
import 'home_providers.dart';

export 'home_providers.dart' show slotProvider, SlotController;

/// S4 — Home (prototype HOME): haldi header, ticker search bar, slot control,
/// "MAHARAJ KA PICK" hero, quick asks, the 2-column grid of 8 options, the
/// sticky "Aaj ka menu" bar and the bottom nav.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final slot = ref.watch(slotProvider);
    final recs = ref.watch(recommendationsProvider(slot));
    final menu = ref.watch(activeMenuProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final data = recs.value;

    void openRecipe(String id) => context.push(Routes.recipe(id));

    // A hired cook (cook mode only, no family mode) is locked to cook mode.
    ref.listen(meProvider, (_, next) {
      final me = next.value;
      if (me != null && me.canCook && !me.hasFamily) context.go(Routes.cook);
    });

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const _HomeHeader(),
                OfflineBanner(
                  onRetry: () {
                    ref.invalidate(recommendationsProvider(slot));
                    ref.read(kitchenRevisionProvider.notifier).bump();
                  },
                ),
                const SubscriptionBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: BSegmentControl<Slot>(
                    value: slot,
                    onChanged: ref.read(slotProvider.notifier).select,
                    segments: [for (final s in Slot.values) BSegment(s, l.slot(s))],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: data != null
                      ? Entrance.popIn(
                          key: ValueKey('hero-${slot.name}-${data.pick.id}'),
                          duration: Motion.heroPopIn,
                          child: HeroPickCard(card: data.pick, onOpen: () => openRecipe(data.pick.id)),
                        )
                      : recs.hasError
                      ? _LoadError(onRetry: () => ref.invalidate(recommendationsProvider(slot)))
                      : const _HeroSkeleton(),
                ),
                const HomeTicketCard(),
                const _QuickAsks(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text(l.slotOptions(l.slot(slot)), style: BText.display(BType.section))),
                      Text(
                        l.sabkeHisaab,
                        style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: _TileGrid(
                    slot: slot,
                    tiles: data?.tiles ?? const [],
                    menu: menu,
                    onOpen: openRecipe,
                    // Expired plan → read-only: "Plan band hai" (F-5.1-05).
                    onToggle: (c) =>
                        guardWrite(context, ref, () => ref.read(dayMenuProvider.notifier).toggle(c.id, c.name)),
                  ),
                ),
                const WeeklySummaryCard(),
                SizedBox(height: 120 + bottomInset),
              ],
            ),
          ),
          if (menu.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: BSizes.nav + 8 + bottomInset,
              child: Entrance.rise(
                child: PlanBar(entries: menu, onTap: () => context.push(Routes.plan)),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BBottomNav(
              current: BNavTab.ghar,
              showRasoi: ref.watch(meProvider).value?.canCook ?? false,
              onTap: (tab) => switch (tab) {
                BNavTab.ghar => null,
                BNavTab.maharaj => guardWrite(context, ref, () => context.push(Routes.chat)),
                BNavTab.parivaar => context.push(Routes.family),
                BNavTab.rasoi => context.push(Routes.cook),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Haldi header: slot eyebrow (+ "Demo data" pill), household name with
/// chevron → Family, family line, avatar stack, ticker search bar.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    final slot = ref.watch(slotProvider);
    final demo = ref.watch(dataSourceProvider) == DataSource.demo;
    final topInset = MediaQuery.paddingOf(context).top;
    final household = ref.watch(householdSettingsProvider).value?.name;
    // The demo family's name only in the sandbox; API mode waits for its own.
    final name = household == null || household.isEmpty ? (demo ? l.householdName : '') : household;
    return Container(
      color: BColors.haldi,
      padding: EdgeInsets.fromLTRB(16, 16 + topInset, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: () => context.push(Routes.family),
                  semanticLabel: '$name. ${l.familyLineFor(members)}',
                  builder: (context, _) => ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Wraps (pill under the eyebrow) at large text sizes.
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l.slotEyebrow(slot),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BText.eyebrow(tracking: BType.slotEyebrowTracking),
                            ),
                            if (demo) DemoDataPill(label: l.demoDataPill),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(name, style: BText.display(BType.display22))),
                            const SizedBox(width: 4),
                            const BIcon(BIcons.chevronDown, size: 18, color: BColors.ink),
                          ],
                        ),
                        Text(
                          l.familyLineFor(members),
                          style: BText.body(BType.captionL, weight: FontWeight.w600, color: BColors.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _InboxBell(),
              const SizedBox(width: 6),
              BIconButton(
                key: const ValueKey('home-settings'),
                icon: BIcons.settings,
                semanticLabel: l.settingsTitle,
                size: 40,
                background: BColors.card.withValues(alpha: .55),
                onPressed: () => context.push(Routes.settings),
              ),
              // The avatars repeat the "N log" line; drop them on narrow phones
              // so the household name keeps one line next to bell + settings.
              if (MediaQuery.sizeOf(context).width >= 400) ...[
                const SizedBox(width: 8),
                AvatarStack(avatars: [for (final m in members.take(3)) (m.initial, m.color)]),
              ],
            ],
          ),
          const SizedBox(height: 14),
          TickerSearchBar(
            onTap: () => guardWrite(context, ref, () => context.push(Routes.chat)),
            onMic: () => BToast.show(context, l.voiceToast),
          ),
        ],
      ),
    );
  }
}

/// Bell → Inbox, with a green dot while something is unread.
class _InboxBell extends ConsumerWidget {
  const _InboxBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final unread = ref.watch(unreadInboxProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BIconButton(
          key: const ValueKey('home-bell'),
          icon: BIcons.bell,
          semanticLabel: unread > 0 ? l.inboxBellUnread(unread) : l.inboxTitle,
          size: 40,
          background: BColors.card.withValues(alpha: .55),
          onPressed: () => context.push(Routes.inbox),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: BColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: BColors.card, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small pill shown in the header while the app runs on demo data.
class DemoDataPill extends StatelessWidget {
  const DemoDataPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BColors.card.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(BRadii.pill),
      ),
      child: Text(
        label,
        style: BText.body(10, weight: FontWeight.w800, color: BColors.ink2),
      ),
    );
  }
}

/// Dark-green "MAHARAJ KA PICK" card: 176 high, 20 radius, painted thali at
/// the right (scene 240×200 at right −60, top −8, scale .78).
class HeroPickCard extends StatelessWidget {
  const HeroPickCard({super.key, required this.card, this.onOpen});

  final RecipeCard card;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 176,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: BColors.greenHero, borderRadius: BorderRadius.circular(BRadii.hero)),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -8,
            width: ThaliHero.sceneSize.width,
            height: ThaliHero.sceneSize.height,
            child: Transform.scale(scale: .78, child: ThaliHero(steamCount: 2, semanticLabel: l.thaliAlt)),
          ),
          // `width: 64%` (border-box) with 18px padding.
          FractionallySizedBox(
            widthFactor: .64,
            heightFactor: 1,
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BBadge(label: l.maharajPick, background: BColors.haldi, foreground: BColors.ink),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(
                      card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BText.display(BType.display22, color: BColors.card, height: 1.08),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.heroMeta(l.summaryLabel(card.summary), card.mins),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BText.body(BType.captionL, weight: FontWeight.w600, color: BColors.greenHeroText),
                  ),
                  const Spacer(),
                  const SizedBox(height: 6),
                  Pressable(
                    onTap: onOpen,
                    semanticLabel: l.recipeDekho,
                    builder: (context, pressed) => PressScale(
                      pressed: pressed,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BColors.card,
                          borderRadius: BorderRadius.circular(BRadii.small),
                        ),
                        child: Text(
                          l.recipeDekho,
                          style: BText.body(BType.chip, weight: FontWeight.w800, color: BColors.greenHero),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 176,
      decoration: BoxDecoration(
        color: BColors.greenHero.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(BRadii.hero),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 176,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BColors.card,
        borderRadius: BorderRadius.circular(BRadii.hero),
        border: Border.all(color: BColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l.homeLoadError, style: BText.display(BType.section)),
          const SizedBox(height: 10),
          BChip(label: l.retry, onTap: onRetry),
        ],
      ),
    );
  }
}

/// Horizontal quick-ask chips (open Maharaj chat).
class _QuickAsks extends ConsumerWidget {
  const _QuickAsks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final asks = [
      l.quickAsk15Min,
      l.quickAskHalka,
      l.quickAskBaarish,
      l.quickAskTiffin,
      l.quickAskMehmaan,
      l.quickAskProtein,
    ];
    return SizedBox(
      height: 14 + BSizes.chip + 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        itemCount: asks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) =>
            BChip(label: asks[i], onTap: () => guardWrite(context, ref, () => context.push(Routes.chatAsk(asks[i])))),
      ),
    );
  }
}

/// Two-column grid (gap 10) of [RecipeTile]s with a 70 ms popIn stagger.
class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.slot,
    required this.tiles,
    required this.menu,
    required this.onOpen,
    required this.onToggle,
  });

  final Slot slot;
  final List<RecipeCard> tiles;
  final List<MenuEntry> menu;
  final ValueChanged<String> onOpen;
  final ValueChanged<RecipeCard> onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget tile(int i) {
      final c = tiles[i];
      return RecipeTile(
        key: ValueKey('tile-${slot.name}-${c.id}'),
        index: i,
        added: menu.any((e) => e.id == c.id),
        onOpen: () => onOpen(c.id),
        onToggle: () => onToggle(c),
        data: recipeCardData(l, c),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(i)),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tile(i + 1) : const SizedBox()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// [RecipeCard] → the tile / mini-card view data.
RecipeCardData recipeCardData(AppLocalizations l, RecipeCard c) => RecipeCardData(
  name: c.name,
  cuisine: l.cuisineLabel(c.cuisine),
  mins: c.mins,
  mark: DietMark.kindFor(c.diet),
  color: c.colour,
  fitKind: c.summary.badge,
  fitShort: l.summaryShort(c.summary),
  note: l.summaryNote(c.summary),
  image: c.imageUrl == null ? null : NetworkImage(c.imageUrl!),
);

/// Sticky green "{n} dish · Aaj ka menu / names · Cook ko bhejo ›" bar.
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.entries, this.onTap});

  final List<MenuEntry> entries;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = l.planBarTitle(entries.length);
    final names = entries.map((e) => e.name).join(', ');
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $names. ${l.cookKoBhejo}',
      builder: (context, pressed) => ExcludeSemantics(
        child: Container(
          // 58 tall; grows (instead of clipping) at large text sizes.
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: BColors.green,
            borderRadius: BorderRadius.circular(BRadii.cta),
            boxShadow: BShadows.planBar,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BColors.card.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(BRadii.small),
                ),
                child: const BIcon(BIcons.bowl, size: 20, color: BColors.card),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.card),
                    ),
                    Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.greenHeroText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  l.cookKoBhejo,
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.card),
                ),
              ),
              const BIcon(BIcons.chevronRight, size: 18, color: BColors.card),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlapping 32px avatars with a 2px haldi ring (-8px overlap).
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.avatars, this.size = 32, this.ring = BColors.haldi});

  final List<(String, Color)> avatars;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final step = size - 8; // CSS margin-left: -8px on each avatar
    return ExcludeSemantics(
      child: SizedBox(
        width: avatars.isEmpty ? 0 : size + step * (avatars.length - 1),
        height: size,
        child: Stack(
          children: [
            for (var i = 0; i < avatars.length; i++)
              Positioned(
                left: step * i,
                top: 0,
                child: BAvatar(
                  initial: avatars[i].$1,
                  color: avatars[i].$2,
                  size: size,
                  fontSize: 12,
                  borderColor: ring,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
