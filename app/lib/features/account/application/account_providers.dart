import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_source.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../data/account_api.dart';
import '../data/account_repositories.dart';
import '../data/billing_adapter.dart';
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

/// Store billing: the demo adapter flips the demo plan to active; the real
/// adapter is a TODO (billing_adapter.dart).
final billingAdapterProvider = Provider<BillingAdapter>(
  (ref) => ref.watch(dataSourceProvider) == DataSource.demo ? const DemoBillingAdapter() : const StoreBillingAdapter(),
);

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

  /// Buys the weekly plan through the store adapter and has the server
  /// verify it. Returns false when billing is not available in this build.
  Future<bool> subscribe() async {
    final billing = ref.read(billingAdapterProvider);
    if (!billing.available) return false;
    final token = await billing.purchaseWeekly();
    if (token == null) return false;
    if (ref.read(dataSourceProvider) == DataSource.demo) {
      ref.read(demoKitchenProvider).account.subscribe();
    } else {
      await ref.read(subscriptionRepositoryProvider).restore(store: token.store, purchaseToken: token.token);
    }
    _changed();
    return true;
  }

  /// POST /v1/subscription/restore with the store's token. Null when billing
  /// is not available in this build (nothing is sent).
  Future<Subscription?> restore() async {
    final billing = ref.read(billingAdapterProvider);
    if (!billing.available) return null;
    final token = await billing.restoreToken();
    if (token == null) return null;
    final s = await ref.read(subscriptionRepositoryProvider).restore(store: token.store, purchaseToken: token.token);
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
