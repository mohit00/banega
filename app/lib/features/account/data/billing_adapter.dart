// Store billing for the ₹50/week subscription (FRD §3 pricing, F-3-03).
//
// - Sandbox: [DemoBillingAdapter] (a stub token, the demo plan flips to active).
// - API mode on Android: [PlayBillingAdapter] over `in_app_purchase`: product
//   `banega_weekly_50`, base plan `weekly`. The purchase token goes to
//   POST /v1/subscription/restore {store: 'play', purchase_token}; the server
//   verifies it with the Play Developer API (and acknowledges it), then the
//   app completes the purchase. RTDN keeps the status current after that.
// - Anything else (iOS / web for now): [StoreBillingAdapter], unavailable.

import 'dart:async';

/// Result of a purchase attempt: the store and token to hand to the server.
typedef PurchaseToken = ({String store, String token});

/// The store said the payment is pending (e.g. UPI / cash): the plan starts
/// when it completes (the background listener sends it to the server).
class BillingPending implements Exception {
  const BillingPending();
}

/// The store is unreachable, the product is not set up, or it failed.
class BillingUnavailable implements Exception {
  const BillingUnavailable([this.reason]);

  final String? reason;

  @override
  String toString() => 'BillingUnavailable($reason)';
}

abstract interface class BillingAdapter {
  /// Whether real purchases are possible in this build.
  bool get available;

  /// Buys the weekly plan; null when cancelled. Throws [BillingPending] /
  /// [BillingUnavailable].
  Future<PurchaseToken?> purchaseWeekly();

  /// A token for "Restore purchases" (the store's active purchase), or null.
  Future<PurchaseToken?> restoreToken();

  /// After the server verified [token]: finish the store transaction.
  Future<void> finish(PurchaseToken token);

  /// Purchases that arrive outside [purchaseWeekly] (a pending payment that
  /// completed, a purchase from a previous session) are handed to [onPurchase]
  /// (which posts them to the server) and then finished.
  void listen(Future<void> Function(PurchaseToken token) onPurchase);
}

/// Demo / dev: pretends the store answered with a stub token.
class DemoBillingAdapter implements BillingAdapter {
  const DemoBillingAdapter();

  static const stubToken = 'demo-stub-purchase-token';

  @override
  bool get available => true;

  @override
  Future<PurchaseToken?> purchaseWeekly() async => (store: 'play', token: stubToken);

  @override
  Future<PurchaseToken?> restoreToken() async => (store: 'play', token: stubToken);

  @override
  Future<void> finish(PurchaseToken token) async {}

  @override
  void listen(Future<void> Function(PurchaseToken token) onPurchase) {}
}

/// No store billing on this platform (iOS / web until wired): purchase and
/// restore are unavailable and a stub token never reaches the real backend.
class StoreBillingAdapter implements BillingAdapter {
  const StoreBillingAdapter();

  @override
  bool get available => false;

  @override
  Future<PurchaseToken?> purchaseWeekly() async => null;

  @override
  Future<PurchaseToken?> restoreToken() async => null;

  @override
  Future<void> finish(PurchaseToken token) async {}

  @override
  void listen(Future<void> Function(PurchaseToken token) onPurchase) {}
}

// ------------------------------------------------------------------ store seam

enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

/// One purchase update from the store (a thin copy of `PurchaseDetails`).
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.token,
    this.pendingComplete = false,
    this.error,
    this.handle,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// Play: the purchase token (`serverVerificationData`).
  final String? token;

  /// The transaction still has to be completed (acknowledged).
  final bool pendingComplete;
  final String? error;

  /// The plugin's own object, passed back to [StoreClient.complete].
  final Object? handle;
}

/// What [PlayBillingAdapter] needs from `in_app_purchase` (faked in tests).
abstract interface class StoreClient {
  Future<bool> isAvailable();

  /// The offer to buy for [productId] / [basePlanId] (an opaque handle), or
  /// null when the product is not set up in the store.
  Future<Object?> offer(String productId, String basePlanId);

  /// Starts the store's purchase flow; the outcome arrives on [purchases].
  Future<void> buy(Object offer);
  Stream<List<StorePurchase>> get purchases;

  /// Re-emits owned purchases on [purchases] (status restored).
  Future<void> restore();
  Future<void> complete(StorePurchase purchase);
}

/// Google Play billing through [StoreClient].
class PlayBillingAdapter implements BillingAdapter {
  PlayBillingAdapter(
    this.client, {
    this.productId = kWeeklyProductId,
    this.basePlanId = kWeeklyBasePlanId,
    this.purchaseTimeout = const Duration(minutes: 10),
    this.restoreWindow = const Duration(seconds: 4),
  });

  static const kWeeklyProductId = 'banega_weekly_50';
  static const kWeeklyBasePlanId = 'weekly';

  final StoreClient client;
  final String productId;
  final String basePlanId;
  final Duration purchaseTimeout;

  /// How long restore collects re-emitted purchases.
  final Duration restoreWindow;

  StreamSubscription<List<StorePurchase>>? _sub;
  Completer<StorePurchase>? _buying;
  final List<StorePurchase> _restored = [];
  bool _restoring = false;
  final Map<String, StorePurchase> _toComplete = {};
  Future<void> Function(PurchaseToken token)? _onPurchase;

  @override
  bool get available => true;

  void _ensureListening() {
    _sub ??= client.purchases.listen(_onUpdates, onError: (Object _) {});
  }

  @override
  void listen(Future<void> Function(PurchaseToken token) onPurchase) {
    _onPurchase = onPurchase;
    _ensureListening();
  }

  void _onUpdates(List<StorePurchase> updates) {
    for (final p in updates) {
      if (p.productId != productId) continue;
      final token = p.token;
      if (token != null && p.pendingComplete) _toComplete[token] = p;
      final buying = _buying;
      if (buying != null && !buying.isCompleted && p.status != StorePurchaseStatus.restored) {
        buying.complete(p);
        continue;
      }
      if (_restoring && (p.status == StorePurchaseStatus.restored || p.status == StorePurchaseStatus.purchased)) {
        _restored.add(p);
        continue;
      }
      if (p.status == StorePurchaseStatus.purchased && token != null) unawaited(_background(token));
    }
  }

  Future<void> _background(String token) async {
    final handler = _onPurchase;
    if (handler == null) return;
    final t = (store: 'play', token: token);
    try {
      await handler(t);
      await finish(t);
    } catch (_) {
      // Not finished: Play redelivers it on the next start.
    }
  }

  @override
  Future<PurchaseToken?> purchaseWeekly() async {
    if (!await client.isAvailable()) throw const BillingUnavailable('store');
    final offer = await client.offer(productId, basePlanId);
    if (offer == null) throw const BillingUnavailable('product');
    _ensureListening();
    final buying = Completer<StorePurchase>();
    _buying = buying;
    try {
      await client.buy(offer);
      final p = await buying.future.timeout(purchaseTimeout);
      return switch (p.status) {
        StorePurchaseStatus.purchased ||
        StorePurchaseStatus.restored when p.token != null => (store: 'play', token: p.token!),
        StorePurchaseStatus.canceled => null,
        StorePurchaseStatus.pending => throw const BillingPending(),
        _ => throw BillingUnavailable(p.error ?? 'purchase'),
      };
    } on TimeoutException {
      throw const BillingUnavailable('timeout');
    } finally {
      if (identical(_buying, buying)) _buying = null;
    }
  }

  @override
  Future<PurchaseToken?> restoreToken() async {
    if (!await client.isAvailable()) throw const BillingUnavailable('store');
    _ensureListening();
    _restored.clear();
    _restoring = true;
    try {
      await client.restore();
      await Future<void>.delayed(restoreWindow);
    } finally {
      _restoring = false;
    }
    final found = _restored.where((p) => p.token != null).toList();
    if (found.isEmpty) return null;
    return (store: 'play', token: found.last.token!);
  }

  @override
  Future<void> finish(PurchaseToken token) async {
    final p = _toComplete.remove(token.token);
    if (p != null) await client.complete(p);
  }

  Future<void> dispose() async => _sub?.cancel();
}
