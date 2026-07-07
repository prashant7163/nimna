import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'entitlement_source.dart';
import 'product_ids.dart';

/// The ONLY file in the app allowed to import `package:in_app_purchase`
/// (fenced by test/billing/in_app_purchase_fence_test.dart). It realises the
/// [EntitlementSource] seam over the platform store — StoreKit on iOS, Play
/// Billing on Android — reading the platform's SIGNED on-device entitlement
/// cache and never a Nimna flag or server (spec §10).
///
/// The plugin surfaces the signed cache (StoreKit 2
/// `Transaction.currentEntitlements` / Play `queryPurchasesAsync`) by
/// re-emitting current purchases on [InAppPurchase.purchaseStream] in
/// response to [InAppPurchase.restorePurchases]. We therefore keep one
/// persistent stream subscription that tracks the currently-entitled product
/// ids, and re-query the cache within a bounded settle window.
///
/// Host `flutter test` never constructs this class — the tests inject a fake
/// [EntitlementSource]. Sandbox subscribe / lapse / restore on a real
/// simulator or device (the committed `.storekit` config / Play static
/// responses) is the done-check hand step (SESSION-17).
class StoreEntitlementSource implements EntitlementSource {
  StoreEntitlementSource({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  static const Duration _settleTimeout = Duration(seconds: 6);
  static const Duration _purchaseTimeout = Duration(seconds: 90);

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Product ids the platform's signed cache currently reports as entitled.
  final Set<String> _entitledProductIds = <String>{};

  /// Completed by the stream listener on the first delivery after a re-query.
  Completer<void>? _deliveryWaiter;

  /// Completed by the stream listener when an in-flight purchase settles.
  Completer<PurchaseOutcome>? _purchaseCompleter;

  void _ensureListening() {
    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object _) {},
    );
  }

  void _onPurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _entitledProductIds.add(purchase.productID);
        case PurchaseStatus.pending:
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          break;
      }
      _resolvePurchaseCompleter(purchase);
      // The store requires each delivered purchase to be acknowledged, or it
      // is refunded / re-delivered. No content is unlocked by this call —
      // entitlement is the store's, checked fresh at each creation intent.
      if (purchase.pendingCompletePurchase) {
        unawaited(_iap.completePurchase(purchase));
      }
    }
    final waiter = _deliveryWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  void _resolvePurchaseCompleter(PurchaseDetails purchase) {
    final completer = _purchaseCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (purchase.productID != BillingProducts.creationYearly) {
      return;
    }
    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _purchaseCompleter = null;
        completer.complete(PurchaseOutcome.purchased);
      case PurchaseStatus.canceled:
        _purchaseCompleter = null;
        completer.complete(PurchaseOutcome.cancelled);
      case PurchaseStatus.error:
        _purchaseCompleter = null;
        completer.complete(PurchaseOutcome.failed);
      case PurchaseStatus.pending:
        break; // keep waiting — the sheet is still open.
    }
  }

  /// Clears and re-reads the platform's signed cache. Returns `false` only
  /// when the store itself could not answer (→ unresolved); an empty result
  /// after a clean query is a legitimate "not entitled".
  Future<bool> _requerySignedCache() async {
    _entitledProductIds.clear();
    final waiter = Completer<void>();
    _deliveryWaiter = waiter;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      _deliveryWaiter = null;
      return false;
    }
    await waiter.future.timeout(_settleTimeout, onTimeout: () {});
    _deliveryWaiter = null;
    return true;
  }

  Future<ProductDetails?> _fetchProduct() async {
    try {
      final response = await _iap.queryProductDetails(BillingProducts.queryIds);
      if (response.error != null) {
        return null;
      }
      for (final product in response.productDetails) {
        if (product.id == BillingProducts.creationYearly) {
          return product;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<EntitlementStatus> hasActiveCreationEntitlement() async {
    _ensureListening();
    bool available;
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      return EntitlementStatus.unresolved;
    }
    if (!available) {
      return EntitlementStatus.unresolved;
    }
    final settled = await _requerySignedCache();
    if (!settled) {
      return EntitlementStatus.unresolved;
    }
    return _entitledProductIds.contains(BillingProducts.creationYearly)
        ? EntitlementStatus.active
        : EntitlementStatus.inactive;
  }

  @override
  Future<RestoreOutcome> restore() async {
    switch (await hasActiveCreationEntitlement()) {
      case EntitlementStatus.active:
        return RestoreOutcome.restored;
      case EntitlementStatus.inactive:
        return RestoreOutcome.nothingFound;
      case EntitlementStatus.unresolved:
        return RestoreOutcome.storeUnreachable;
    }
  }

  @override
  Future<String?> localizedPrice() async {
    _ensureListening();
    final product = await _fetchProduct();
    return product?.price;
  }

  @override
  Future<PurchaseOutcome> purchaseCreationSubscription() async {
    _ensureListening();
    bool available;
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      return PurchaseOutcome.storeUnreachable;
    }
    if (!available) {
      return PurchaseOutcome.storeUnreachable;
    }
    final product = await _fetchProduct();
    if (product == null) {
      return PurchaseOutcome.storeUnreachable;
    }
    final completer = Completer<PurchaseOutcome>();
    _purchaseCompleter = completer;
    try {
      // Auto-renewing subscriptions go through buyNonConsumable on both
      // platforms (plugin guidance); the store manages renewal.
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      _purchaseCompleter = null;
      return PurchaseOutcome.failed;
    }
    return completer.future.timeout(
      _purchaseTimeout,
      onTimeout: () {
        _purchaseCompleter = null;
        return PurchaseOutcome.pending;
      },
    );
  }

  /// Releases the stream subscription (not used in the app's steady state —
  /// the source lives for the process — but keeps the class tidy for tests).
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
