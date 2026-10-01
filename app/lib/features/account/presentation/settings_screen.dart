import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/perf.dart';
import '../../../data/data_source.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../../recipe/application/recipe_providers.dart' show urlLauncherProvider;
import '../application/account_providers.dart';
import '../application/locale_controller.dart';
import '../domain/account_models.dart';
import 'consent_screen.dart' show kPrivacyPolicyUrl;

/// S9 Settings: household name, cooks (add hired / primary / backup /
/// remove), members, language, notifications, ratings / stock / cook
/// toggles, plan, privacy (consent, export, deletion) and the demo
/// cook-role switch.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final h = ref.watch(householdSettingsProvider).value;
    final sub = ref.watch(subscriptionProvider).value;
    final actions = ref.read(accountActionsProvider);
    final lang = AppLanguage.of(ref.watch(localeProvider));

    Future<void> run(Future<void> Function() f, {String? ok}) async {
      try {
        await f();
        if (ok != null && context.mounted) BToast.show(context, ok);
      } on KitchenError catch (e) {
        if (context.mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    Future<void> patch(HouseholdPatch p) => run(() => actions.patch(p));

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitchenHeader(
            title: l.settingsTitle,
            titleSize: BType.display26,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (h != null && h.pendingDeletion) ...[
                  const SizedBox(height: 12),
                  _DeletionBanner(
                    until: h.undoUntil,
                    onRestore: () => run(actions.restoreHousehold, ok: l.settingsRestored),
                  ),
                ],
                // ---------------------------------------------------- household
                KitchenSectionTitle(l.settingsHousehold),
                const SizedBox(height: 6),
                KitchenCard(
                  child: Column(
                    children: [
                      _Row(
                        key: const ValueKey('settings-name'),
                        title: l.settingsHouseholdName,
                        value: h?.name ?? l.householdName,
                        action: l.settingsEdit,
                        onTap: h == null
                            ? null
                            : () async {
                                final name = await _askText(context, l.settingsHouseholdName, h.name);
                                if (name != null && name.trim().isNotEmpty) {
                                  await run(
                                    () => actions.patch(HouseholdPatch(name: name.trim())),
                                    ok: l.settingsSaved,
                                  );
                                }
                              },
                      ),
                      _Row(
                        key: const ValueKey('settings-members'),
                        title: l.settingsMembers,
                        onTap: () => context.push(Routes.family),
                      ),
                    ],
                  ),
                ),
                // ---------------------------------------------------- cooks
                KitchenSectionTitle(l.settingsCooks),
                const SizedBox(height: 6),
                const _CooksCard(),
                // ---------------------------------------------------- kitchen
                KitchenSectionTitle(l.settingsKitchen),
                const SizedBox(height: 6),
                KitchenCard(
                  child: Column(
                    children: [
                      _Row(
                        key: const ValueKey('settings-stock'),
                        title: l.stockTitle,
                        onTap: () => context.push(Routes.stock),
                      ),
                      _Row(
                        key: const ValueKey('settings-ration'),
                        title: l.rationTitle,
                        onTap: () => context.push(Routes.ration),
                      ),
                      _Toggle(
                        key: const ValueKey('toggle-auto-decrement'),
                        title: l.settingsAutoDecrement,
                        hint: l.settingsAutoDecrementHint,
                        value: h?.autoDecrement ?? false,
                        onChanged: h == null ? null : (v) => patch(HouseholdPatch(autoDecrement: v)),
                      ),
                      _Toggle(
                        key: const ValueKey('toggle-cook-swaps'),
                        title: l.settingsCookSwaps,
                        hint: l.settingsCookSwapsHint,
                        value: h?.cookCanApproveSwaps ?? true,
                        onChanged: h == null ? null : (v) => patch(HouseholdPatch(cookCanApproveSwaps: v)),
                      ),
                    ],
                  ),
                ),
                // ---------------------------------------------------- ratings
                KitchenSectionTitle(l.settingsRatings),
                const SizedBox(height: 6),
                KitchenCard(
                  child: Column(
                    children: [
                      _Toggle(
                        key: const ValueKey('toggle-ratings'),
                        title: l.settingsRatings,
                        hint: l.settingsRatingsHint,
                        value: h?.ratingsEnabled ?? true,
                        onChanged: h == null ? null : (v) => patch(HouseholdPatch(ratingsEnabled: v)),
                      ),
                      _Toggle(
                        key: const ValueKey('toggle-show-names'),
                        title: l.settingsShowNames,
                        hint: l.settingsShowNamesHint,
                        value: h?.showNamesToCook ?? false,
                        onChanged: h == null ? null : (v) => patch(HouseholdPatch(showNamesToCook: v)),
                      ),
                    ],
                  ),
                ),
                // ---------------------------------------------------- language
                KitchenSectionTitle(l.settingsLanguage),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (lg, label) in [
                      (AppLanguage.hinglish, l.langHinglish),
                      (AppLanguage.english, l.langEnglish),
                      (AppLanguage.hindi, l.langHindi),
                    ])
                      BChip(
                        key: ValueKey('lang-${lg.key}'),
                        label: label,
                        selected: lang == lg,
                        onTap: () => ref.read(localeProvider.notifier).set(lg),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l.settingsLanguageHint, style: BText.body(BType.caption, color: BColors.ink3)),
                // ---------------------------------------------------- notifications
                KitchenSectionTitle(l.settingsNotifications),
                const SizedBox(height: 6),
                const _PrefsCard(),
                // ---------------------------------------------------- plan
                KitchenSectionTitle(l.settingsSubscription),
                const SizedBox(height: 6),
                KitchenCard(
                  child: _Row(
                    key: const ValueKey('settings-plan'),
                    title: sub == null ? l.paywallTitle : '${l.paywallTitle} · ${l.subscriptionStatus(sub.status)}',
                    value: sub == null
                        ? null
                        : switch (sub.status) {
                            SubscriptionStatus.trial => l.paywallTrial(sub.trialDaysLeft(ref.read(clockProvider)())),
                            SubscriptionStatus.active => l.paywallActive,
                            SubscriptionStatus.grace => l.paywallGrace,
                            SubscriptionStatus.expired => l.planBandTitle,
                            SubscriptionStatus.unknown => l.subStatusUnknown,
                          },
                    onTap: () => context.push(Routes.paywall),
                  ),
                ),
                // ---------------------------------------------------- display
                KitchenSectionTitle(l.settingsDisplay),
                const SizedBox(height: 6),
                KitchenCard(
                  child: _Toggle(
                    key: const ValueKey('toggle-low-end'),
                    title: l.settingsLightAnimations,
                    hint: l.settingsLightAnimationsHint,
                    value: ref.watch(lowEndProvider),
                    onChanged: (v) => ref.read(lowEndProvider.notifier).set(v),
                  ),
                ),
                // ---------------------------------------------------- privacy
                KitchenSectionTitle(l.settingsPrivacy),
                const SizedBox(height: 6),
                KitchenCard(
                  child: Column(
                    children: [
                      _Row(
                        key: const ValueKey('settings-consent'),
                        title: l.settingsConsent,
                        onTap: () => context.push('${Routes.consent}?review=1'),
                      ),
                      _Row(
                        title: l.consentPrivacy,
                        onTap: () => ref.read(urlLauncherProvider)(Uri.parse(kPrivacyPolicyUrl)),
                      ),
                      _Row(title: l.settingsGrievance),
                      _Row(
                        key: const ValueKey('settings-export'),
                        title: l.settingsExport,
                        onTap: () => run(actions.export, ok: l.settingsExportToast),
                      ),
                      _Row(
                        key: const ValueKey('settings-delete-household'),
                        title: l.settingsDeleteHousehold,
                        danger: true,
                        onTap: h == null || h.pendingDeletion
                            ? null
                            : () async {
                                if (await _confirm(context, l.settingsDeleteHousehold, l.settingsDeleteHouseholdAsk)) {
                                  await run(actions.deleteHousehold);
                                }
                              },
                      ),
                      _Row(
                        key: const ValueKey('settings-delete-me'),
                        title: l.settingsDeleteMe,
                        danger: true,
                        onTap: () async {
                          if (!await _confirm(context, l.settingsDeleteMe, l.settingsDeleteMeAsk)) return;
                          var ok = false;
                          await run(() async {
                            await actions.deleteMe();
                            ok = true;
                          }, ok: l.settingsDeletedMe);
                          // Only a confirmed deletion leaves (and wipes the device copy).
                          if (!ok) return;
                          if (ref.read(dataSourceProvider) == DataSource.api) {
                            await ref.read(authControllerProvider.notifier).signOutAfterDeletion();
                          }
                          if (context.mounted) context.go(Routes.splash);
                        },
                      ),
                      if (ref.watch(dataSourceProvider) == DataSource.api)
                        _Row(
                          key: const ValueKey('settings-logout'),
                          title: l.settingsLogout,
                          onTap: () async {
                            await ref.read(authControllerProvider.notifier).logout();
                            if (context.mounted) context.go(Routes.phone);
                          },
                        ),
                    ],
                  ),
                ),
                // ---------------------------------------------------- demo
                // The cook-role switch is a sandbox tool for debug builds only.
                if (kDebugMode && ref.watch(dataSourceProvider) == DataSource.demo) const _DemoRole(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final l = AppLocalizations.of(context);
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const ValueKey('settings-text'), controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.settingsCancel)),
        TextButton(
          key: const ValueKey('settings-text-save'),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(l.settingsSave),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.settingsCancel)),
        TextButton(
          key: const ValueKey('confirm-yes'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.settingsDeleteConfirm, style: const TextStyle(color: BColors.noFg)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.title, this.value, this.action, this.onTap, this.danger = false});

  final String title;
  final String? value;
  final String? action;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: [title, ?value].join('. '),
      builder: (context, _) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: BText.body(BType.body, weight: FontWeight.w700, color: danger ? BColors.noFg : BColors.ink),
                  ),
                  if (value != null)
                    Text(
                      value!,
                      style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink3),
                    ),
                ],
              ),
            ),
            if (action != null)
              Text(
                action!,
                style: BText.body(BType.chip, weight: FontWeight.w800, color: BColors.green),
              )
            else if (onTap != null)
              const BIcon(BIcons.chevronRight, size: 16, color: BColors.ink4),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.title, this.hint, required this.value, this.onChanged});

  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BText.body(BType.body, weight: FontWeight.w700)),
                if (hint != null) Text(hint!, style: BText.body(BType.caption, color: BColors.ink3)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: BColors.green),
        ],
      ),
    );
  }
}

class _DeletionBanner extends StatelessWidget {
  const _DeletionBanner({required this.until, required this.onRestore});

  final DateTime? until;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final date = until == null ? '' : '${until!.day}/${until!.month}';
    return Container(
      key: const ValueKey('deletion-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BColors.noBg, borderRadius: BorderRadius.circular(BRadii.tile)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.settingsDeletePending(date),
              style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.noFg),
            ),
          ),
          BChip(key: const ValueKey('settings-restore'), label: l.settingsRestore, onTap: onRestore),
        ],
      ),
    );
  }
}

/// Cooks: primary / backup / remove, and "Hired cook jodo" (one max).
class _CooksCard extends ConsumerWidget {
  const _CooksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cooks = ref.watch(cooksProvider).value ?? const <Cook>[];
    final repo = ref.read(cooksRepositoryProvider);

    Future<void> run(Future<void> Function() f, {String? ok}) async {
      try {
        await f();
        ref.read(kitchenRevisionProvider.notifier).bump();
        if (ok != null && context.mounted) BToast.show(context, ok);
      } on KitchenError catch (e) {
        if (!context.mounted) return;
        BToast.show(context, switch (e.code) {
          'hired_cook_limit' => l.settingsHiredLimit,
          'phone_in_other_household' => l.settingsPhoneTaken,
          'invalid_phone' => l.settingsInvalidPhone,
          _ => l.toastError,
        });
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    Future<void> add() async {
      final r = await showDialog<(String, String)>(context: context, builder: (ctx) => const _AddCookDialog());
      if (r == null) return;
      await run(
        () => repo.addCook(kind: CookKind.hired, name: r.$1, phone: r.$2),
        ok: l.settingsCookAdded(r.$1),
      );
    }

    return KitchenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in cooks)
            Padding(
              key: ValueKey('settings-cook-${c.id}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [l.cookChip(c), if (c.phoneMasked.isNotEmpty) c.phoneMasked].join(' · '),
                    style: BText.body(BType.body, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BChip(
                        key: ValueKey('cook-primary-${c.id}'),
                        label: l.settingsCookPrimary,
                        selected: c.isPrimary,
                        onTap: c.isPrimary
                            ? null
                            : () => run(() => repo.patchCook(c.id, const CookPatch(isPrimary: true))),
                      ),
                      BChip(
                        key: ValueKey('cook-backup-${c.id}'),
                        label: l.settingsCookBackup,
                        selected: c.isBackup,
                        onTap: c.isBackup
                            ? null
                            : () => run(() => repo.patchCook(c.id, const CookPatch(isBackup: true, isPrimary: false))),
                      ),
                      BChip(
                        key: ValueKey('cook-remove-${c.id}'),
                        label: l.settingsCookRemove,
                        foreground: BColors.noFg,
                        onTap: () async {
                          if (await _confirm(context, l.settingsCookRemove, l.settingsCookRemoveAsk(c.name))) {
                            await run(() => repo.removeCook(c.id));
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          BGhostButton(
            key: const ValueKey('settings-add-cook'),
            label: l.settingsAddHiredCook,
            leading: BIcons.plus,
            onPressed: add,
          ),
        ],
      ),
    );
  }
}

class _AddCookDialog extends StatefulWidget {
  const _AddCookDialog();

  @override
  State<_AddCookDialog> createState() => _AddCookDialogState();
}

class _AddCookDialogState extends State<_AddCookDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.settingsAddHiredCook),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('cook-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l.settingsCookName),
          ),
          TextField(
            key: const ValueKey('cook-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.settingsCookPhone),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.settingsCancel)),
        TextButton(
          key: const ValueKey('cook-add-save'),
          onPressed: () => Navigator.pop(context, (_name.text.trim(), _phone.text.trim())),
          child: Text(l.settingsSave),
        ),
      ],
    );
  }
}

/// Per-event notification switches (PUT /v1/me/notification-prefs).
class _PrefsCard extends ConsumerWidget {
  const _PrefsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(notificationPrefsProvider).value ?? const <NotificationPref>[];
    return KitchenCard(
      child: Column(
        children: [
          for (final p in prefs)
            _Toggle(
              key: ValueKey('pref-${p.event}'),
              title: l.eventName(p.event),
              hint: p.mandatory ? l.settingsNotifMandatory : null,
              value: p.enabled,
              onChanged: p.mandatory
                  ? null
                  : (v) async {
                      try {
                        await ref.read(accountActionsProvider).setPref(prefs, p.event, v);
                      } catch (_) {
                        if (context.mounted) BToast.show(context, l.toastError);
                      }
                    },
            ),
        ],
      ),
    );
  }
}

/// Demo-only: which cook role the demo user holds (stands in for GET /v1/me).
class _DemoRole extends ConsumerWidget {
  const _DemoRole();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final role = ref.watch(demoCookRoleProvider);
    final cooks = ref.watch(cooksProvider).value ?? const <Cook>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenSectionTitle(l.settingsDemoCook),
        Text(l.settingsDemoCookHint, style: BText.body(BType.caption, color: BColors.ink3)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BChip(
              key: const ValueKey('role-none'),
              label: l.planAssigneeNone,
              selected: role == null,
              onTap: () => ref.read(demoCookRoleProvider.notifier).set(null),
            ),
            for (final c in cooks)
              BChip(
                key: ValueKey('role-${c.id}'),
                label: l.cookChip(c),
                selected: role == c.id,
                onTap: () => ref.read(demoCookRoleProvider.notifier).set(c.id),
              ),
          ],
        ),
      ],
    );
  }
}
