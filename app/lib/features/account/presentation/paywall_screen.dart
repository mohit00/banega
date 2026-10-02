import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../application/account_providers.dart';
import '../domain/account_models.dart';

/// S10 paywall: plan status, ₹50/hafta subscribe (demo flips to active; the
/// store adapter is a TODO), "Restore purchases".
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await f();
    } catch (_) {
      if (mounted) BToast.show(context, l.toastError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sub = ref.watch(subscriptionProvider).value;
    final now = ref.watch(clockProvider)();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final status = sub == null
        ? null
        : switch (sub.status) {
            SubscriptionStatus.trial => l.paywallTrial(sub.trialDaysLeft(now)),
            SubscriptionStatus.active => [
              l.paywallActive,
              if (sub.renewsAt != null) l.paywallRenews('${sub.renewsAt!.day}/${sub.renewsAt!.month}'),
            ].join(' · '),
            SubscriptionStatus.grace => l.paywallGrace,
            SubscriptionStatus.expired => l.planBandTitle,
            SubscriptionStatus.unknown => l.subStatusUnknown,
          };
    final active = sub?.status == SubscriptionStatus.active;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: l.paywallTitle,
            subtitle: status,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
            trailing: sub == null
                ? null
                : BBadge(
                    key: ValueKey('paywall-status-${sub.status.wire}'),
                    label: l.subscriptionStatus(sub.status),
                    background: BColors.card,
                    foreground: BColors.ink,
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                KitchenCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.paywallPrice, style: BText.display(BType.h1Alt, color: BColors.green)),
                      const SizedBox(height: 6),
                      Text(
                        l.paywallBody,
                        style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink2),
                      ),
                      const SizedBox(height: 14),
                      for (final f in [l.paywallFeature1, l.paywallFeature2, l.paywallFeature3])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const BIcon(BIcons.check, size: 16, color: BColors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(f, style: BText.body(BType.body, weight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.paywallCancelNote,
                  textAlign: TextAlign.center,
                  style: BText.body(BType.caption, color: BColors.ink3),
                ),
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
              children: [
                if (!active)
                  BCta(
                    key: const ValueKey('paywall-subscribe'),
                    label: l.paywallSubscribe,
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final outcome = await ref.read(accountActionsProvider).subscribe();
                            if (!context.mounted) return;
                            BToast.show(context, switch (outcome) {
                              PurchaseOutcome.subscribed => l.paywallSubscribed,
                              PurchaseOutcome.cancelled => l.paywallCancelled,
                              PurchaseOutcome.pending => l.paywallPending,
                              PurchaseOutcome.unavailable => l.paywallStoreSoon,
                            });
                          }),
                  ),
                if (!active) const SizedBox(height: 10),
                BGhostButton(
                  key: const ValueKey('paywall-restore'),
                  label: l.paywallRestore,
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final billing = ref.read(billingAdapterProvider);
                          final s = await ref.read(accountActionsProvider).restore();
                          if (!context.mounted) return;
                          BToast.show(
                            context,
                            s != null
                                ? l.paywallRestored
                                : billing.available
                                ? l.paywallNothingToRestore
                                : l.paywallStoreSoon,
                          );
                        }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Trial / grace / expired strip under the Home header (→ paywall).
class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sub = ref.watch(subscriptionProvider).value;
    if (sub == null || sub.status == SubscriptionStatus.active || sub.status == SubscriptionStatus.unknown) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(clockProvider)();
    final (text, bg, fg) = switch (sub.status) {
      SubscriptionStatus.trial => (l.trialBanner(sub.trialDaysLeft(now)), BColors.fitBg, BColors.fitFg),
      SubscriptionStatus.grace => (l.graceBanner, BColors.tweakBg, BColors.tweakFg),
      _ => (l.expiredBanner, BColors.noBg, BColors.noFg),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Pressable(
        key: ValueKey('sub-banner-${sub.status.wire}'),
        onTap: () => context.push(Routes.paywall),
        semanticLabel: text,
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(BRadii.cta)),
          child: Row(
            children: [
              BIcon(sub.status == SubscriptionStatus.trial ? BIcons.clock : BIcons.alert, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: BText.body(BType.chip, weight: FontWeight.w800, color: fg),
                ),
              ),
              BIcon(BIcons.chevronRight, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Plan band hai" sheet shown when a write is attempted on an expired plan.
Future<void> showPlanBandSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: BColors.paper,
  builder: (ctx) {
    final l = AppLocalizations.of(ctx);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 18 + MediaQuery.paddingOf(ctx).bottom),
      child: Column(
        key: const ValueKey('plan-band-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.planBandTitle, style: BText.display(BType.section)),
          const SizedBox(height: 8),
          Text(
            l.planBandBody,
            style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink2),
          ),
          const SizedBox(height: 16),
          BCta(
            key: const ValueKey('plan-band-cta'),
            label: l.planBandCta,
            onPressed: () {
              Navigator.pop(ctx);
              GoRouter.of(context).push(Routes.paywall);
            },
          ),
        ],
      ),
    );
  },
);

/// Runs [action] unless the plan is read-only, in which case the "Plan band
/// hai" sheet explains why (F-5.1-05).
void guardWrite(BuildContext context, WidgetRef ref, VoidCallback action) {
  if (ref.read(readOnlyProvider)) {
    showPlanBandSheet(context);
    return;
  }
  action();
}
