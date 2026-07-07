/// Store product identifiers for the creation subscription (spec §10).
///
/// Sandbox values now; the production IDs and the price tier are set by the
/// USER at the S19 store-console hand step (SESSION-17 intake — do NOT
/// reopen the numberless-price lock: no number ever lives in the app, the
/// paywall renders `ProductDetails.price` from the store).
abstract final class BillingProducts {
  /// The auto-renewable subscription group (StoreKit) / base-plan parent
  /// (Play `subs`). One group, so entitlement is a single active/inactive
  /// question — no per-line counters (F9.1 edge: wiping channels cannot
  /// interact with the paywall).
  static const String subscriptionGroup = 'nimna_creation';

  /// The yearly creation subscription product.
  static const String creationYearly = 'nimna_creation_yearly';

  /// The set queried from the store (`queryProductDetails`).
  static const Set<String> queryIds = {creationYearly};
}
