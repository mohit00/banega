import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/data_source.dart';
import '../auth/application/auth_controller.dart';
import '../../labels/kitchen_labels.dart';
import '../../ui/ui.dart';
import '../home/home_providers.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/application/sync_service.dart';
import '../kitchen/domain/kitchen_models.dart';

/// Cook-mode type scale (F-4-04): body 20, labels 18, minimum 16; primary
/// actions 56 tall with icon + label.
abstract final class CookType {
  static const double title = 26;
  static const double body = 20;
  static const double label = 18;
  static const double min = 16;
  static const double action = 56;
}

/// Cook-mode subtree: Hindi strings (app_hi.arb, Hinglish fallback) and OS
/// font scaling honoured up to 200%.
class CookScope extends ConsumerWidget {
  const CookScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Localizations.override(
      context: context,
      locale: ref.watch(cookLocaleProvider),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 2,
        child: Consumer(
          builder: (context, ref, child) {
            // A queued write the server rejected for good: say so once.
            ref.listen(syncDropsProvider, (prev, next) {
              if (next.count > (prev?.count ?? 0)) BToast.show(context, AppLocalizations.of(context).cookSyncDropped);
            });
            return child!;
          },
          child: child,
        ),
      ),
    );
  }
}

/// 56-tall action with icon + label (green; [secondary] is outlined).
class CookActionButton extends StatelessWidget {
  const CookActionButton({super.key, required this.label, required this.icon, this.onPressed, this.secondary = false});

  final String label;
  final BIconData icon;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final fg = secondary ? BColors.green : BColors.card;
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Pressable(
        onTap: onPressed,
        semanticLabel: label,
        builder: (context, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: CookType.action),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          transform: Matrix4.translationValues(0, pressed && !secondary ? 3 : 0, 0),
          decoration: BoxDecoration(
            color: secondary ? BColors.card : BColors.green,
            borderRadius: BorderRadius.circular(BRadii.cta),
            border: secondary ? Border.all(color: BColors.green, width: 2) : null,
            boxShadow: secondary ? null : (pressed ? BShadows.ctaPressed : BShadows.ctaRest),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BIcon(icon, size: 24, color: fg),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: BText.body(CookType.label, weight: FontWeight.w800, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label + icon for a cook action that moves a ticket to [to].
(String, BIconData) cookActionFor(AppLocalizations l, TicketStatus to) => switch (to) {
  TicketStatus.accepted => (l.cookActionAccept, BIcons.check),
  TicketStatus.cooking => (l.cookActionStart, BIcons.pot),
  TicketStatus.ready => (l.cookActionReady, BIcons.bell),
  _ => (l.cookActionDone, BIcons.check),
};

/// POST a transition from cook mode; 409 → refresh + toast.
Future<void> cookTransition(BuildContext context, WidgetRef ref, Ticket t, TicketStatus to) async {
  final l = AppLocalizations.of(context);
  try {
    await ref.read(cookTicketActionsProvider).transition(t, to);
  } on AlreadyInFlight {
    // Double tap: ignored.
  } on KitchenError catch (e) {
    if (context.mounted) BToast.show(context, e.isConflict ? l.cookConflict : l.cookError);
  } catch (_) {
    if (context.mounted) BToast.show(context, l.cookError);
  }
}

/// The primary (and optional secondary) action buttons for a ticket.
class CookTicketActions extends ConsumerWidget {
  const CookTicketActions({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final (primary, secondary) = cookNextSteps(ticket.status);
    if (primary == null) return const SizedBox.shrink();
    final busy = ref.watch(ticketsInFlightProvider).contains(ticket.id);
    Widget button(TicketStatus to, {bool second = false}) {
      final (label, icon) = cookActionFor(l, to);
      return CookActionButton(
        key: ValueKey('cook-action-${ticket.id}-${to.wire}'),
        label: label,
        icon: icon,
        secondary: second,
        onPressed: busy ? null : () => cookTransition(context, ref, ticket, to),
      );
    }

    return Row(
      children: [
        if (secondary != null) ...[Expanded(child: button(secondary, second: true)), const SizedBox(width: 10)],
        Expanded(child: button(primary)),
      ],
    );
  }
}

/// Cook-mode header: title, back, the "Parivaar" mode switch and the duty
/// toggle (On duty / Chhutti with an off-duty-until date), plus the offline
/// banner.
class CookHeader extends ConsumerWidget {
  const CookHeader({super.key, required this.title, this.subtitle, this.onBack, this.showDuty = false});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool showDuty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final me = ref.watch(meProvider).value;
    final offline = ref.watch(cookOfflineProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: BColors.haldi,
          padding: EdgeInsets.fromLTRB(14, 12 + topInset, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null) ...[
                    BIconButton(
                      icon: BIcons.chevronLeft,
                      semanticLabel: l.back,
                      size: 48,
                      background: BColors.card.withValues(alpha: .55),
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(title, style: BText.display(CookType.title, height: 1.1))),
                ],
              ),
              const SizedBox(height: 10),
              // Language switch + back to family mode; wraps at large text.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _CookLanguageChip(),
                  if (me?.hasFamily ?? false)
                    BChip(
                      key: const ValueKey('cook-family-mode'),
                      label: l.cookFamilyMode,
                      height: 48,
                      leading: const BIcon(BIcons.home, size: 18, color: BColors.ink2),
                      onTap: () => context.go(Routes.home),
                    ),
                  // A hired cook has no Settings page, so log out lives here.
                  if (showDuty && ref.watch(dataSourceProvider) == DataSource.api)
                    BChip(
                      key: const ValueKey('cook-logout'),
                      label: l.settingsLogout,
                      height: 48,
                      onTap: () => _confirmLogout(context, ref),
                    ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: BText.body(CookType.label, weight: FontWeight.w700, color: BColors.ink2),
                ),
              ],
              if (showDuty && me?.cook != null) ...[const SizedBox(height: 12), _DutyToggle(cookId: me!.cook!.id)],
            ],
          ),
        ),
        KeyedSubtree(
          key: offline ? const ValueKey('cook-offline') : null,
          child: OfflineBanner(
            force: offline,
            message: offline ? l.cookOffline : null,
            textStyle: BText.body(CookType.min, weight: FontWeight.w700, color: BColors.card),
            onRetry: () => ref.read(kitchenRevisionProvider.notifier).bump(),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.settingsLogout, style: BText.display(CookType.title, height: 1.1)),
      actions: [
        TextButton(
          key: const ValueKey('cook-logout-cancel'),
          onPressed: () => Navigator.of(c).pop(false),
          child: Text(l.commonCancel, style: BText.body(CookType.label, weight: FontWeight.w700)),
        ),
        TextButton(
          key: const ValueKey('cook-logout-confirm'),
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(
            l.settingsLogout,
            style: BText.body(CookType.label, weight: FontWeight.w800, color: BColors.green),
          ),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(authControllerProvider.notifier).logout();
  if (context.mounted) context.go(Routes.phone);
}

class _DutyToggle extends ConsumerWidget {
  const _DutyToggle({required this.cookId});

  final String cookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // A hired cook cannot read /v1/cooks (403), so fall back to /v1/me.cook.
    final cooks = ref.watch(cooksProvider).value ?? const <Cook>[];
    final listed = cooks.where((c) => c.id == cookId).firstOrNull;
    final self = ref.watch(meProvider).value?.cook;
    final mine = self != null && self.id == cookId ? self : null;
    if (listed == null && mine == null) return const SizedBox.shrink();
    final on = listed?.onDuty ?? mine!.onDuty;
    final offDutyUntil = listed?.offDutyUntil ?? mine?.offDutyUntil;

    Future<void> patch(CookPatch p) async {
      try {
        await ref.read(cooksRepositoryProvider).patchCook(cookId, p);
        ref.read(kitchenRevisionProvider.notifier).bump();
        ref.invalidate(meProvider);
      } catch (_) {
        if (context.mounted) BToast.show(context, l.cookError);
      }
    }

    Future<void> toggle() async {
      if (!on) return patch(const CookPatch(onDuty: true, offDutyUntilSet: true));
      final today = ref.read(planDateProvider);
      final until = await showModalBottomSheet<DateTime>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.cookOffDutyAsk, style: BText.display(CookType.label)),
                const SizedBox(height: 12),
                CookActionButton(
                  key: const ValueKey('off-today'),
                  label: l.cookOffDutyToday,
                  icon: BIcons.clock,
                  secondary: true,
                  onPressed: () => Navigator.pop(ctx, today.add(const Duration(days: 1))),
                ),
                const SizedBox(height: 10),
                CookActionButton(
                  label: l.cookOffDutyTomorrow,
                  icon: BIcons.clock,
                  secondary: true,
                  onPressed: () => Navigator.pop(ctx, today.add(const Duration(days: 2))),
                ),
                const SizedBox(height: 10),
                CookActionButton(
                  label: l.cookOffDutyPick,
                  icon: BIcons.clock,
                  secondary: true,
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      firstDate: today,
                      lastDate: today.add(const Duration(days: 60)),
                      initialDate: today.add(const Duration(days: 1)),
                    );
                    if (d != null && ctx.mounted) Navigator.pop(ctx, d.add(const Duration(days: 1)));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      if (until != null) await patch(CookPatch(onDuty: false, offDutyUntil: until));
    }

    final untilDay = offDutyUntil?.subtract(const Duration(days: 1));
    final label = on
        ? l.cookOnDuty
        : untilDay == null
        ? l.cookOffDuty
        : l.cookOffDutyUntil('${untilDay.day}/${untilDay.month}');
    return Pressable(
      key: const ValueKey('cook-duty'),
      onTap: toggle,
      semanticLabel: label,
      selected: on,
      builder: (context, _) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: BColors.card,
          borderRadius: BorderRadius.circular(BRadii.cta),
          border: Border.all(color: on ? BColors.green : BColors.noFg, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? BColors.green : BColors.noFg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: BText.body(CookType.label, weight: FontWeight.w800)),
            ),
            IgnorePointer(
              child: Switch(value: on, onChanged: (_) {}, activeTrackColor: BColors.green),
            ),
          ],
        ),
      ),
    );
  }
}

/// "कब तक 1:30".
String cookDue(AppLocalizations l, Ticket t) => t.dueAt == null ? '' : l.cookDueBy(hm(t.dueAt!));

/// Cook-mode language switch (Hindi → Hinglish → English), shown in the cook
/// header. Labels are the language's own name.
class _CookLanguageChip extends ConsumerWidget {
  const _CookLanguageChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cur = ref.watch(cookLocaleProvider);
    final label = cur.languageCode == 'en'
        ? l.langEnglish
        : cur.scriptCode == 'Latn'
        ? l.langHinglish
        : l.langHindi;
    return BChip(
      key: const ValueKey('cook-language'),
      label: label,
      height: 48,
      semanticLabel: '${l.cookLanguage}: $label',
      onTap: () => ref.read(cookLocaleProvider.notifier).next(),
    );
  }
}
