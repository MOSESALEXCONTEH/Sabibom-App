import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/network/authenticated_api_client.dart';

final playBillingServiceProvider = Provider<PlayBillingService>((ref) {
  return PlayBillingService();
});

final billingVerificationServiceProvider = Provider<BillingVerificationService>(
  (ref) => BillingVerificationService(),
);

class PlayBillingService {
  PlayBillingService({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  Stream<List<PurchaseDetails>> get purchaseUpdates => _store.purchaseStream;

  Future<bool> isAvailable() => _store.isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) {
    return _store.queryProductDetails(productIds);
  }

  Future<bool> purchase(ProductDetails product) {
    return _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> restore() => _store.restorePurchases();

  Future<void> complete(PurchaseDetails purchase) {
    return _store.completePurchase(purchase);
  }
}

class BillingVerificationService {
  BillingVerificationService({AuthenticatedApiClient? client})
    : _client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient _client;

  Future<void> verifyGooglePlayPurchase({
    required String businessId,
    required PurchaseDetails purchase,
  }) async {
    await _client.postJson(
      '/api/billing/verify-google-play',
      body: <String, dynamic>{
        'businessId': businessId,
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
      },
      timeout: const Duration(seconds: 45),
    );
  }
}
