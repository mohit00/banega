// Store billing seam for the ₹50/week subscription (FRD §3 pricing,
// F-3-03). Only the demo adapter works today.
//
// TODO(billing): implement [StoreBillingAdapter] with `in_app_purchase`:
// query the weekly product, launch the purchase for the admin, then send the
// purchase token (Play) / receipt (App Store) to POST /v1/subscription/restore
// so the server verifies it; RTDN / App Store Server Notifications keep the
// status current after that.

/// Result of a purchase attempt: the store and token to hand to the server.
typedef PurchaseToken = ({String store, String token});

abstract interface class BillingAdapter {
  /// Whether real purchases are possible in this build.
  bool get available;

  /// Buys the weekly plan; null when cancelled.
  Future<PurchaseToken?> purchaseWeekly();

  /// A token for "Restore purchases" (the store's last purchase).
  Future<PurchaseToken?> restoreToken();
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
}

/// Real store billing: not wired yet (see the TODO at the top of this file).
class StoreBillingAdapter implements BillingAdapter {
  const StoreBillingAdapter();

  @override
  bool get available => false;

  @override
  Future<PurchaseToken?> purchaseWeekly() async => null;

  /// Nothing to restore until in_app_purchase is wired: a stub token must
  /// never reach the real backend.
  @override
  Future<PurchaseToken?> restoreToken() async => null;
}
