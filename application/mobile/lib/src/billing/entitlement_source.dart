/// The billing abstraction seam (S17). Everything above this line is
/// pure-Dart and store-agnostic: [BillingService], the paywall, and the
/// creation gate talk ONLY to this interface, so they are fully unit- and
/// widget-testable against a fake. Everything below it — the real
/// `in_app_purchase` integration — lives in the single concrete
/// implementation `store_entitlement_source.dart`, which is the app's only
/// file allowed to import `package:in_app_purchase` (fenced by
/// test/billing/billing_fences_test.dart).
///
/// The intake named the two core methods
/// ([hasActiveCreationEntitlement] + [restore]); [localizedPrice] and
/// [purchaseCreationSubscription] are carried on the same seam so the store
/// I/O stays fenced to one module AND the paywall stays fake-injectable
/// (SESSION-17 implementation note).
///
/// Doctrine (spec §10): the subscription is consulted ONLY here, ONLY on the
/// initiator's device, ONLY at creation intent. There is no Nimna flag and
/// no Nimna server — the truth is the platform's on-device SIGNED
/// entitlement cache (StoreKit 2 `Transaction.currentEntitlements` /
/// Play `queryPurchasesAsync`). Nimna persists ZERO entitlement state, so a
/// panic wipe cannot touch the paywall and there is no local unlock to
/// forge.
library;

/// The tri-state answer to "may this device create a channel right now?".
enum EntitlementStatus {
  /// The platform's signed on-device cache holds an active creation
  /// subscription. Creation proceeds.
  active,

  /// The store resolved and holds NO active creation subscription — the
  /// paywall's buy state (a fresh install or a lapsed subscription).
  inactive,

  /// The platform entitlement query could not resolve (store unavailable /
  /// unreachable). Fail-closed: the gate treats this as not-entitled and the
  /// paywall shows the calm reconnect state — it NEVER blocks USING existing
  /// channels, only creating new ones (CODE decision, SESSION-17).
  unresolved,
}

/// Outcome of a user-initiated restore (F9.5).
enum RestoreOutcome {
  /// The store found an active subscription for this store account.
  restored,

  /// The store resolved but has no subscription for this account
  /// (different store account, or never purchased).
  nothingFound,

  /// The store could not be reached to answer.
  storeUnreachable,
}

/// Outcome of launching the platform purchase sheet (F9.3 → F9.4/F9.6).
enum PurchaseOutcome {
  /// The subscription is now active.
  purchased,

  /// The user dismissed the store sheet without buying (F9.6 calm return).
  cancelled,

  /// The store accepted the request but settlement is deferred (e.g. Ask to
  /// Buy). The next entitlement query reflects the truth once it settles.
  pending,

  /// The purchase failed inside the store (the store showed its own dialog).
  failed,

  /// The store could not be reached to start the purchase.
  storeUnreachable,
}

/// The seam over the platform's on-device signed entitlement cache. The one
/// and only place the subscription is ever consulted (spec §10).
abstract class EntitlementSource {
  /// Queries the platform's signed on-device entitlement cache. Never a
  /// Nimna flag, never a server. Offline / store-unavailable ⇒
  /// [EntitlementStatus.unresolved] (fail-closed).
  Future<EntitlementStatus> hasActiveCreationEntitlement();

  /// Store-mediated restore: native `restorePurchases()` → re-query the
  /// signed cache (F9.5). Covers reinstall and new-device-same-store-account.
  /// Cross-platform does NOT restore (iOS ↔ Android is a new purchase) — no
  /// code path attempts it (FAQ only, spec §10).
  Future<RestoreOutcome> restore();

  /// The store's localized price string for the creation subscription
  /// (`ProductDetails.price`), or `null` if it can't be fetched. NEVER a
  /// hardcoded number — the store is the only place a price exists (spec §10,
  /// numberless-price lock 2026-07-04).
  Future<String?> localizedPrice();

  /// Launches the platform subscription sheet for the creation product and
  /// resolves once the store settles the request.
  Future<PurchaseOutcome> purchaseCreationSubscription();
}
