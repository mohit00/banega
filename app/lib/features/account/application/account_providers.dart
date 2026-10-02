import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_source.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../data/account_api.dart';
import '../data/account_repositories.dart';
import '../../auth/application/auth_controller.dart';
import '../data/billing_adapter.dart';
import '../data/in_app_purchase_client.dart';
import '../domain/account_models.dart';

// ------------------------------------------------------------------ repositories

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).account;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiAccountRepository(ref.watch(dioProvider));
});

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).account;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiSubscriptionRepository(ref.watch(dioProvider));
});

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider).account;
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiRatingsRepository(ref.watch(dioProvider));
});

/// Whether this platform has a real store adapter (Google Play on Android).
final storeBillingSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

/// The `in_app_purchase` seam (tests plug a fake store in).
final storeClientProvider = Provider<StoreClient>((ref) => InAppPurchaseStoreClient());

/// Store billing: the sandbox uses the demo adapter; API mode on Android uses
/// Google Play; anything else has no store billing yet.
final billingAdapterProvider = Provider<BillingAdapter>((ref) {
  if (ref.watch(dataSourceProvider) == DataSource.demo) return const DemoBillingAdapter();
  if (!ref.watch(storeBillingSupportedProvider)) return const StoreBillingAdapter();
  final adapter = PlayBillingAdapter(ref.watch(storeClientProvider));
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// API mode, signed in: purchases that complete outside the paywall (a
/// pending UPI payment, an unfinished purchase from an earlier session) are
/// verified by the server, then finished.
final billingListenerProvider = Provider<void>((ref) {
  if (ref.watch(dataSourceProvider) != DataSource.api) return;
  if (!ref.watch(authControllerProvider.select((s) => s.signedIn))) return;
  final billing = ref.watch(billingAdapterProvider);
  if (!billing.available) return;
  billing.listen((token) async {
    await ref.read(subscriptionRepositoryProvider).restore(store: token.store, purchaseToken: token.token);
    ref.read(kitchenRevisionProvider.notifier).bump();
  });
});

/// What a subscribe attempt ended with (one toast each on the paywall).
enum PurchaseOutcome { subscribed, cancelled, pending, unavailable }

// ------------------------------------------------------------------ reads

/// GET /v1/subscription, read on app start and after any write.
final subscriptionProvider = FutureProvider<Subscription?>((ref) async {
  ref.watch(kitchenRevisionProvider);
  try {
    return await ref.watch(subscriptionRepositoryProvider).subscription();
  } catch (_) {
    // Not fail-open to "active"/"trial": the status is unknown (the server
    // still enforces read-only on its side).
    return const Subscription(status: SubscriptionStatus.unknown);
  }
}, retry: (_, _) => null);

/// Expired plan → read-only family side (F-5.1-05).
final readOnlyProvider = Provider<bool>((ref) => ref.watch(subscriptionProvider).value?.readOnly ?? false);

final householdSettingsProvider = FutureProvider<HouseholdSettings?>((ref) async {
  ref.watch(kitchenRevisionProvider);
  try {
    return await ref.watch(accountRepositoryProvider).household();
  } catch (_) {
    return null;
  }
}, retry: (_, _) => null);

final notificationPrefsProvider = FutureProvider<List<NotificationPref>>((ref) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(accountRepositoryProvider).notificationPrefs();
}, retry: (_, _) => null);

final weeklyInsightsProvider = FutureProvider<WeeklyInsights?>((ref) async {
  ref.watch(kitchenRevisionProvider);
  try {
    return await ref.watch(accountRepositoryProvider).weekly();
  } catch (_) {
    return null;
  }
}, retry: (_, _) => null);

final ratingSummaryProvider = FutureProvider.family<RatingSummary?, String>((ref, recipeId) async {
  ref.watch(kitchenRevisionProvider);
  try {
    return await ref.watch(ratingsRepositoryProvider).summary(recipeId);
  } catch (_) {
    return null;
  }
}, retry: (_, _) => null);

// ------------------------------------------------------------------ writes

class AccountActions {
  AccountActions(this.ref);

  final Ref ref;

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  void _changed() => ref.read(kitchenRevisionProvider.notifier).bump();

  Future<HouseholdSettings> patch(HouseholdPatch p) async {
    final h = await _repo.patchHousehold(p);
    _changed();
    return h;
  }

  Future<DeletionInfo> deleteHousehold() async {
    final d = await _repo.deleteHousehold();
    _changed();
    return d;
  }

  Future<void> restoreHousehold() async {
    await _repo.restoreHousehold();
    _changed();
  }

  Future<DeletionInfo> deleteMe() => _repo.deleteMe();

  Future<void> setPref(List<NotificationPref> all, String event, bool enabled) async {
    await _repo.putNotificationPrefs([
      for (final p in all)
        if (p.event == event) p.withEnabled(enabled),
    ]);
    _changed();
  }

  Future<void> export() => _repo.export().then((_) => _changed());

  Future<Ticket?> rate(String ticketId, List<RatingInput> ratings) async {
    final t = await ref.read(ratingsRepositoryProvider).rate(ticketId, ratings);
    _changed();
    return t;
  }

  /// Buys the weekly plan through the store adapter, has the server verify
  /// it (POST /v1/subscription/restore), then finishes the store purchase.
  Future<PurchaseOutcome> subscribe() async {
    final billing = ref.read(billingAdapterProvider);
    if (!billing.available) return PurchaseOutcome.unavailable;
    final PurchaseToken? token;
    try {
      token = await billing.purchaseWeekly();
    } on BillingPending {
      return PurchaseOutcome.pending;
    } on BillingUnavailable {
      return PurchaseOutcome.unavailable;
    }
    if (token == null) return PurchaseOutcome.cancelled;
    if (ref.read(dataSourceProvider) == DataSource.demo) {
      ref.read(demoKitchenProvider).account.subscribe();
    } else {
      await ref.read(subscriptionRepositoryProvider).restore(store: token.store, purchaseToken: token.token);
      await billing.finish(token);
    }
    _changed();
    return PurchaseOutcome.subscribed;
  }

  /// "Restore purchases": the store's active purchase → POST
  /// /v1/subscription/restore. Null when billing is unavailable in this build
  /// or the store has nothing to restore (nothing is sent).
  Future<Subscription?> restore() async {
    final billing = ref.read(billingAdapterProvider);
    if (!billing.available) return null;
    final PurchaseToken? token;
    try {
      token = await billing.restoreToken();
    } on BillingUnavailable {
      return null;
    }
    if (token == null) return null;
    final s = await ref.read(subscriptionRepositoryProvider).restore(store: token.store, purchaseToken: token.token);
    await billing.finish(token);
    _changed();
    return s;
  }
}

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

// ------------------------------------------------------------------ consent

/// Version of the consent text (`Household.consent.version`).
const kConsentVersion = '2026-09';

/// Whether this device has accepted the DPDP consent (null while loading).
/// Stored locally so the screen does not repeat; POST /v1/consent too.
final consentProvider = NotifierProvider<ConsentController, bool?>(ConsentController.new);

class ConsentController extends Notifier<bool?> {
  static const storeKey = 'consent.version';

  @override
  bool? build() {
    Future.microtask(_load);
    return null;
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(keyValueStoreProvider).get(storeKey);
      if (ref.mounted && state == null) state = v == kConsentVersion;
    } catch (_) {
      if (ref.mounted && state == null) state = false;
    }
  }

  Future<void> accept() async {
    state = true;
    try {
      await ref.read(keyValueStoreProvider).set(storeKey, kConsentVersion);
    } catch (_) {}
    try {
      await ref.read(accountRepositoryProvider).consent(kConsentVersion);
    } catch (_) {
      // Stored locally; the server copy is best effort here.
    }
  }
}
