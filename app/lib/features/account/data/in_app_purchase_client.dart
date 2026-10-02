import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'billing_adapter.dart';

/// [StoreClient] over the `in_app_purchase` plugin (Google Play Billing).
/// Nothing touches the plugin until a method is called.
class InAppPurchaseStoreClient implements StoreClient {
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  /// Play lists one [GooglePlayProductDetails] per subscription offer: pick
  /// the base plan [basePlanId] without a promotional offer (else any offer
  /// of that base plan).
  @override
  Future<Object?> offer(String productId, String basePlanId) async {
    final res = await _iap.queryProductDetails({productId});
    final offers = res.productDetails.whereType<GooglePlayProductDetails>().where((d) {
      final i = d.subscriptionIndex;
      final all = d.productDetails.subscriptionOfferDetails;
      return d.id == productId && i != null && all != null && all[i].basePlanId == basePlanId;
    }).toList();
    if (offers.isEmpty) return null;
    offers.sort((a, b) {
      final ao = a.productDetails.subscriptionOfferDetails![a.subscriptionIndex!].offerId == null ? 0 : 1;
      final bo = b.productDetails.subscriptionOfferDetails![b.subscriptionIndex!].offerId == null ? 0 : 1;
      return ao - bo;
    });
    return offers.first;
  }

  @override
  Future<void> buy(Object offer) async {
    final d = offer as GooglePlayProductDetails;
    await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(productDetails: d, offerToken: d.offerToken),
    );
  }

  @override
  Stream<List<StorePurchase>> get purchases => _iap.purchaseStream.map((list) => [for (final p in list) _map(p)]);

  static StorePurchase _map(PurchaseDetails p) => StorePurchase(
    productId: p.productID,
    status: switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    },
    token: p.verificationData.serverVerificationData.isEmpty ? null : p.verificationData.serverVerificationData,
    pendingComplete: p.pendingCompletePurchase,
    error: p.error?.message,
    handle: p,
  );

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(StorePurchase purchase) async {
    final p = purchase.handle;
    if (p is PurchaseDetails && p.pendingCompletePurchase) await _iap.completePurchase(p);
  }
}
