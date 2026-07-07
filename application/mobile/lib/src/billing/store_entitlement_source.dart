import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show InAppPurchaseAndroidPlatformAddition;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart'
    show SK2Transaction;

import 'entitlement_source.dart';
import 'product_ids.dart';

/// The ONLY file in the app allowed to import `package:in_app_purchase*`
/// (fenced by test/billing/billing_fences_test.dart). It realises the
/// [EntitlementSource] seam over the platform store — StoreKit on iOS, Play
/// Billing on Android — reading the platform's SIGNED on-device entitlement
/// cache and never a Nimna flag or server (spec §10).
///
/// **The gate reads SILENTLY.** [hasActiveCreationEntitlement] never calls
/// `restorePurchases()` — that can surface an App Store login sheet at every
/// creation intent, a nag the doctrine forbids ("calm, never a nag", spec
/// §10). Instead it reads the signed local cache with no user prompt:
///
/// - iOS: StoreKit 2 `Transaction.all` via `SK2Transaction.transactions()`
///   (SK2 is the plugin default; this wrapper calls the SK2 host API
///   directly). The current entitlement is derived from the unexpired
///   transaction for our product — no `AppStore.sync()`, no prompt.
/// - Android: `queryPurchasesAsync` (past-purchases) via the platform
///   addition's `queryPastPurchases()` — never prompts; expired subs drop
///   off, so a returned owned purchase IS the active entitlement.
///
/// `restorePurchases()` is reserved EXCLUSIVELY for the user-tapped Restore
/// button ([restore]) — the single call site (billing_fences_test pins it).
///
/// The S7 OS floor is iOS 17, so StoreKit 2 is guaranteed available. Host
/// `flutter test` never constructs this class (the tests inject a fake); the
/// real-device silent-check + sandbox subscribe/lapse/restore is the QA
/// done-check hand step (`ios/nimna_creation.storekit` / Play static
/// responses).
class StoreEntitlementSource implements EntitlementSource {
  StoreEntitlementSource({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  static const Duration _purchaseTimeout = Duration(seconds: 90);
  static const Duration _restoreSettle = Duration(seconds: 3);

  StreamSubscription<List<PurchaseDetails>>? _sub;

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
      _resolvePurchaseCompleter(purchase);
      // The store requires each delivered purchase to be acknowledged, or it
      // is refunded / re-delivered. No content is unlocked by this call —
      // entitlement is the store's, checked fresh (and silently) at each
      // creation intent.
      if (purchase.pendingCompletePurchase) {
        unawaited(_iap.completePurchase(purchase));
      }
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

  // --- THE GATE: silent signed-cache read, NEVER restorePurchases() ---

  @override
  Future<EntitlementStatus> hasActiveCreationEntitlement() async {
    _ensureListening();
    try {
      if (!await _iap.isAvailable()) {
        return EntitlementStatus.unresolved;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return await _appleSilentEntitlement();
        case TargetPlatform.android:
          return await _playSilentEntitlement();
        // ignore: no_default_cases
        default:
          return EntitlementStatus.unresolved;
      }
    } catch (_) {
      return EntitlementStatus.unresolved;
    }
  }

  /// iOS: StoreKit 2 `Transaction.all`, read silently (no sync, no prompt).
  /// Active iff there is an unexpired transaction for our product.
  Future<EntitlementStatus> _appleSilentEntitlement() async {
    final transactions = await SK2Transaction.transactions();
    final now = DateTime.now();
    final active = transactions.any(
      (t) =>
          t.productId == BillingProducts.creationYearly &&
          _appleUnexpired(t.expirationDate, now),
    );
    return active ? EntitlementStatus.active : EntitlementStatus.inactive;
  }

  static bool _appleUnexpired(String? expiration, DateTime now) {
    if (expiration == null || expiration.isEmpty) {
      return true; // a non-expiring entitlement (not our yearly, but safe)
    }
    final iso = DateTime.tryParse(expiration);
    if (iso != null) {
      return iso.isAfter(now);
    }
    final ms = int.tryParse(expiration);
    if (ms != null) {
      return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(now);
    }
    return true; // unparseable → never strand a paying user on the gate
  }

  /// Android: `queryPurchasesAsync` (past-purchases), which never prompts.
  Future<EntitlementStatus> _playSilentEntitlement() async {
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) {
      return EntitlementStatus.unresolved;
    }
    final active = response.pastPurchases.any(
      (p) =>
          p.productID == BillingProducts.creationYearly &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored),
    );
    return active ? EntitlementStatus.active : EntitlementStatus.inactive;
  }

  // --- RESTORE: the ONLY restorePurchases() call, user-initiated (F9.5) ---

  @override
  Future<RestoreOutcome> restore() async {
    _ensureListening();
    try {
      if (!await _iap.isAvailable()) {
        return RestoreOutcome.storeUnreachable;
      }
      // The single restorePurchases() call site — an explicit user action on
      // the Restore button, where a login prompt is expected and welcome.
      await _iap.restorePurchases();
    } catch (_) {
      return RestoreOutcome.storeUnreachable;
    }
    // Let the platform settle the re-delivered transactions, then re-read the
    // signed cache silently to report the outcome.
    await Future<void>.delayed(_restoreSettle);
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
