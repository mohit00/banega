import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/data_source.dart';
import '../../../data/repositories.dart' show wireDate, SlotWire;
import '../../../labels/kitchen_labels.dart';
import '../../../labels/labels.dart';
import '../../../ui/ui.dart';
import '../../home/home_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../../account/presentation/paywall_screen.dart';
import '../../members/application/members_controller.dart';
import '../../pantry/application/pantry_providers.dart';
import '../../recipe/domain/recipe.dart';
import '../application/plan_controller.dart';

/// S8 Plan (prototype PLAN) plus the FRD additions: date selector, "Kaun kha
/// raha hai?" (eaters + guests), "Kitne log" servings, "Kab tak" due time,
/// "Kaun banayega" assignee, the Saaman list with stock pills, and "Maharaj
/// / cook ko bhejo" → a real ticket (+ WhatsApp share).
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final st = ref.watch(planControllerProvider);
    final ctrl = ref.read(planControllerProvider.notifier);
    final members = ref.watch(membersProvider);
    final today = ref.watch(planDateProvider);
    final menu = st.menu;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final slotName = l.slot(st.slot);
    final isToday = st.date == today;
    final title = isToday ? l.planTitle(slotName) : l.planTitleOn(l.dateChip(st.date, today), slotName);
    final String coverage;
    if (menu == null || menu.dishes.isEmpty) {
      coverage = l.planCoverageSome;
    } else if (menu.coverage.allCovered) {
      coverage = l.planCoverageAll;
    } else if (menu.coverage.uncovered.isNotEmpty) {
      coverage = l.planCoverageMissing(menu.coverage.uncovered.join(', '));
    } else {
      coverage = l.planCoverageSome;
    }
    final headcount = menu?.headcount ?? members.length;

    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } on AlreadyInFlight {
        // A double tap: the first write is still on its way.
      } on KitchenError catch (e) {
        if (context.mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    Future<void> confirm() => guard(() async {
      await ctrl.confirm();
      if (!context.mounted) return;
      final demo = ref.read(dataSourceProvider) == DataSource.demo;
      BToast.show(context, demo ? l.toastSentCook : l.toastTicketSent);
    });

    // F-5.6-04: "Missing saaman order karo" is a ration request of the
    // menu's low / out items (self-raised by the admin → auto-approved).
    Future<void> orderMissing() => guard(() async {
      final items = missingItems(menu?.requiredItems ?? const []);
      if (items.isEmpty) {
        BToast.show(context, l.rationNothingMissing);
        return;
      }
      await ref.read(familyPantryActionsProvider).raise(items, ticketId: st.ticket?.id);
      if (context.mounted) BToast.show(context, l.rationSentToast);
    });

    Future<void> openStock() async {
      await context.push(Routes.stock);
      await ctrl.sync();
    }

    Future<void> share() => guard(() async {
      final text = await ctrl.shareText();
      if (text == null || text.isEmpty) return;
      await ref.read(shareTextProvider)(text);
    });

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: title,
            subtitle: l.planSubtitle(headcount, coverage),
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          OfflineBanner(onRetry: () => guard(ctrl.sync)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _DateRow(today: today, selected: st.date, onSelect: (d) => guard(() => ctrl.setDate(d))),
                const SizedBox(height: 10),
                BSegmentControl<Slot>(
                  value: st.slot,
                  onChanged: (s) => guard(() => ctrl.setSlot(s)),
                  segments: [for (final s in Slot.values) BSegment(s, l.slot(s))],
                ),
                const SizedBox(height: 12),
                if (st.ticket != null) ...[_SentBanner(ticket: st.ticket!), const SizedBox(height: 10)],
                if (menu != null)
                  for (final d in menu.dishes) ...[
                    _DishRow(
                      dish: d,
                      onOpen: () async {
                        await context.push(Routes.recipeFor(d.recipeId, date: wireDate(st.date), slot: st.slot.wire));
                        await guard(ctrl.sync);
                      },
                      onRemove: st.sent ? null : () => guard(() => ctrl.removeDish(d.recipeId)),
                    ),
                    const SizedBox(height: 10),
                  ],
                if (!st.hasDishes)
                  if (st.loading)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator(color: BColors.green)),
                    )
                  else if (st.error != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(l.planLoadError, style: BText.body(BType.body, weight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          BChip(label: l.retry, onTap: () => guard(ctrl.sync)),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
                      child: Text(
                        l.planEmpty,
                        textAlign: TextAlign.center,
                        style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink3),
                      ),
                    ),
                if (menu != null && st.hasDishes) ...[
                  _EatersSection(menu: menu, enabled: !st.sent, guard: guard),
                  _ServingsSection(menu: menu, enabled: !st.sent, guard: guard),
                  _DueSection(dueAt: st.dueAt, enabled: !st.sent, guard: guard),
                  _AssigneeSection(menu: menu, enabled: !st.sent, guard: guard),
                  KitchenSectionTitle(
                    l.planSaamanList,
                    trailing: BChip(
                      key: const ValueKey('plan-stock'),
                      label: l.stockTitle,
                      leading: const BIcon(BIcons.bowl, size: 14, color: BColors.ink2),
                      onTap: openStock,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SaamanList(items: menu.requiredItems, checked: st.checked, onToggle: ctrl.toggleChecked),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: st.sent
                  ? [
                      BCta(
                        key: const ValueKey('plan-view-ticket'),
                        label: l.planViewTicket,
                        onPressed: () => context.push(Routes.ticket(st.ticket!.id)),
                      ),
                      const SizedBox(height: 10),
                      BGhostButton(
                        key: const ValueKey('plan-share'),
                        label: l.planShareWhatsApp,
                        leading: BIcons.share,
                        onPressed: st.sharing ? null : share,
                      ),
                    ]
                  : [
                      BCta(
                        key: const ValueKey('plan-send'),
                        label: l.planSendCook,
                        leading: BIcons.send,
                        onPressed: st.hasDishes && !st.sending && !st.loading
                            ? () => guardWrite(context, ref, confirm)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      BGhostButton(
                        key: const ValueKey('plan-order-missing'),
                        label: l.planOrderMissing,
                        onPressed: menu == null ? null : orderMissing,
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today + 6 days: "Aaj / Kal / Wed 30 …".
class _DateRow extends StatelessWidget {
  const _DateRow({required this.today, required this.selected, required this.onSelect});

  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final days = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)];
    return SizedBox(
      height: BSizes.chip,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => BChip(
          key: ValueKey('date-$i'),
          label: l.dateChip(days[i], today),
          selected: days[i] == selected,
          onTap: () => onSelect(days[i]),
        ),
      ),
    );
  }
}

class _SentBanner extends StatelessWidget {
  const _SentBanner({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KitchenCard(
      child: Row(
        children: [
          const BIcon(BIcons.check, size: 18, color: BColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                l.toastTicketSent,
                ticket.assignee?.name ?? l.ticketNoAssignee,
                if (ticket.dueAt != null) l.dueBy(hm(ticket.dueAt!)),
              ].join(' · '),
              style: BText.body(BType.chip, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          TicketStatusChip(status: ticket.status),
        ],
      ),
    );
  }
}

/// Dish row: 70px image, name + note, remove ×.
class _DishRow extends StatelessWidget {
  const _DishRow({required this.dish, this.onOpen, this.onRemove});

  final MenuDish dish;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final note = dish.summary != null ? l.summaryNote(dish.summary!) : (dish.note ?? '');
    return KitchenCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: BColors.cream, borderRadius: BorderRadius.circular(BRadii.icon)),
            child: dish.imageUrl != null
                ? Image.network(dish.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _swatch())
                : _swatch(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Pressable(
              onTap: onOpen,
              semanticLabel: dish.name,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dish.name, style: BText.body(15, weight: FontWeight.w800)),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(note, style: BText.body(BType.caption, color: BColors.ink3)),
                  ],
                ],
              ),
            ),
          ),
          if (onRemove != null)
            BIconButton(
              icon: BIcons.close,
              semanticLabel: l.removeDish,
              background: BColors.card,
              iconSize: 18,
              iconColor: BColors.ink4,
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }

  Widget _swatch() => ColoredBox(
    color: dish.colour.withValues(alpha: .55),
    child: const Center(child: BIcon(BIcons.bowl, size: 26, color: BColors.ink2)),
  );
}

typedef _Guard = Future<void> Function(Future<void> Function() f);

/// "Kaun kha raha hai?": member chips (default all) + guests + guest diet.
class _EatersSection extends ConsumerWidget {
  const _EatersSection({required this.menu, required this.enabled, required this.guard});

  final Menu menu;
  final bool enabled;
  final _Guard guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    final ctrl = ref.read(planControllerProvider.notifier);
    final eaterIds = {for (final e in menu.eaters) e.memberId};
    final g = menu.guests;
    VoidCallback? when(bool ok, Future<void> Function() f) => enabled && ok ? () => guard(f) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenSectionTitle(l.planEatersTitle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in members)
              BChip(
                key: ValueKey('eater-${m.id}'),
                label: m.name,
                selected: eaterIds.contains(m.id),
                padding: const EdgeInsets.only(left: 5, right: 14),
                leading: BAvatar(initial: m.initial, color: m.color, size: 26, fontSize: 11),
                onTap: when(true, () => ctrl.toggleEater(m.id)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        KitchenCard(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.planGuestAdults, style: BText.body(BType.body, weight: FontWeight.w700)),
                  ),
                  CountStepper(
                    key: const ValueKey('guest-adults'),
                    value: '${g.adults}',
                    lessLabel: l.servingsLess,
                    moreLabel: l.servingsMore,
                    onLess: when(g.adults > 0, () => ctrl.setGuests(g.copyWith(adults: g.adults - 1))),
                    onMore: when(true, () => ctrl.setGuests(g.copyWith(adults: g.adults + 1))),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(l.planGuestKids, style: BText.body(BType.body, weight: FontWeight.w700)),
                  ),
                  CountStepper(
                    key: const ValueKey('guest-kids'),
                    value: '${g.kids}',
                    lessLabel: l.servingsLess,
                    moreLabel: l.servingsMore,
                    onLess: when(g.kids > 0, () => ctrl.setGuests(g.copyWith(kids: g.kids - 1))),
                    onMore: when(true, () => ctrl.setGuests(g.copyWith(kids: g.kids + 1))),
                  ),
                ],
              ),
              if (g.count > 0) ...[
                const SizedBox(height: 4),
                Text(
                  l.planGuestDiet,
                  style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in GuestDiet.values)
                      BChip(
                        key: ValueKey('guest-diet-${d.wire}'),
                        label: l.guestDiet(d),
                        selected: g.diet == d,
                        onTap: when(
                          true,
                          () => ctrl.setGuests(g.diet == d ? g.copyWith(clearDiet: true) : g.copyWith(diet: d)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Kitne log": adult 1.0, kid 0.5, guests added; override stepper.
class _ServingsSection extends ConsumerWidget {
  const _ServingsSection({required this.menu, required this.enabled, required this.guard});

  final Menu menu;
  final bool enabled;
  final _Guard guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.read(planControllerProvider.notifier);
    final s = menu.servings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenSectionTitle(l.planServingsTitle),
        const SizedBox(height: 6),
        KitchenCard(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.planServingsValue(servingsText(s)),
                      key: const ValueKey('plan-servings'),
                      style: BText.body(BType.body, weight: FontWeight.w800),
                    ),
                    Text(l.planServingsHint, style: BText.body(BType.caption, color: BColors.ink3)),
                  ],
                ),
              ),
              CountStepper(
                value: servingsText(s),
                lessLabel: l.servingsLess,
                moreLabel: l.servingsMore,
                onLess: enabled && s > .5 ? () => guard(() => ctrl.setServings(s - .5)) : null,
                onMore: enabled ? () => guard(() => ctrl.setServings(s + .5)) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Kab tak": due time (default per slot), tap → time picker.
class _DueSection extends ConsumerWidget {
  const _DueSection({required this.dueAt, required this.enabled, required this.guard});

  final DateTime dueAt;
  final bool enabled;
  final _Guard guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.read(planControllerProvider.notifier);
    Future<void> pick() async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dueAt));
      if (t != null) await guard(() => ctrl.setDue(t.hour, t.minute));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenSectionTitle(l.planDueTitle),
        const SizedBox(height: 6),
        Row(
          children: [
            BChip(
              key: const ValueKey('plan-due'),
              label: hmAmPm(dueAt),
              leading: const BIcon(BIcons.clock, size: 14, color: BColors.ink2, strokeWidth: 2.4),
              onTap: enabled ? pick : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.planDueHint, style: BText.body(BType.caption, color: BColors.ink3)),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Kaun banayega": cook chips + "Koi nahi".
class _AssigneeSection extends ConsumerWidget {
  const _AssigneeSection({required this.menu, required this.enabled, required this.guard});

  final Menu menu;
  final bool enabled;
  final _Guard guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.read(planControllerProvider.notifier);
    final cooks = ref.watch(cooksProvider).value ?? const <Cook>[];
    final current = menu.assignee?.cookId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenSectionTitle(l.planAssigneeTitle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cooks)
              BChip(
                key: ValueKey('cook-${c.id}'),
                label: c.onDuty ? l.cookChip(c) : '${l.cookChip(c)} · ${l.cookOffDutyTag}',
                selected: current == c.id,
                onTap: enabled ? () => guard(() => ctrl.setAssignee(c.id)) : null,
              ),
            BChip(
              key: const ValueKey('cook-none'),
              label: l.planAssigneeNone,
              selected: current == null,
              onTap: enabled ? () => guard(() => ctrl.setAssignee(null)) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Saaman ki list": checkbox rows with an in / low / out / untracked pill.
class _SaamanList extends StatelessWidget {
  const _SaamanList({required this.items, required this.checked, required this.onToggle});

  final List<RequiredItem> items;
  final Set<String> checked;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return KitchenCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Pressable(
              onTap: () => onToggle(items[i].ingredientId),
              selected: checked.contains(items[i].ingredientId),
              semanticLabel: items[i].displayText,
              builder: (context, _) => Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: BColors.borderSoft)),
                ),
                child: Row(
                  children: [
                    _Checkbox(on: checked.contains(items[i].ingredientId)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        items[i].displayText,
                        style: BText.body(
                          13.5,
                          weight: FontWeight.w600,
                          color: checked.contains(items[i].ingredientId) ? BColors.ink4 : BColors.ink,
                        ),
                      ),
                    ),
                    ItemStatusPill(status: items[i].status),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? BColors.green : BColors.card,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: on ? BColors.green : BColors.dashed, width: 1.5),
      ),
      child: on ? const BIcon(BIcons.check, size: 12, color: BColors.card) : null,
    );
  }
}
