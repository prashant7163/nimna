import 'package:nimna/src/billing/entitlement_source.dart';

/// Scriptable [EntitlementSource] for host tests — the whole billing stack
/// (gate, paywall, BillingService) is exercised without a store or live
/// products (SESSION-17). Set [status] / [priceString] / [restoreOutcome] /
/// [purchaseOutcome] to script each permutation; every call is counted so
/// the permanence invariant ("existing channels never consult billing") can
/// assert ZERO queries.
class FakeEntitlementSource implements EntitlementSource {
  FakeEntitlementSource({
    this.status = EntitlementStatus.inactive,
    this.priceString = 'PRICE',
    this.restoreOutcome = RestoreOutcome.nothingFound,
    this.purchaseOutcome = PurchaseOutcome.cancelled,
  });

  EntitlementStatus status;
  String? priceString;
  RestoreOutcome restoreOutcome;
  PurchaseOutcome purchaseOutcome;

  int queryCount = 0;
  int restoreCount = 0;
  int priceCount = 0;
  int purchaseCount = 0;

  /// When a purchase/restore "succeeds", the store's signed cache flips to
  /// active — mirrors the real source, where the next query reflects it.
  @override
  Future<EntitlementStatus> hasActiveCreationEntitlement() async {
    queryCount++;
    return status;
  }

  @override
  Future<RestoreOutcome> restore() async {
    restoreCount++;
    if (restoreOutcome == RestoreOutcome.restored) {
      status = EntitlementStatus.active;
    }
    return restoreOutcome;
  }

  @override
  Future<String?> localizedPrice() async {
    priceCount++;
    return priceString;
  }

  @override
  Future<PurchaseOutcome> purchaseCreationSubscription() async {
    purchaseCount++;
    if (purchaseOutcome == PurchaseOutcome.purchased) {
      status = EntitlementStatus.active;
    }
    return purchaseOutcome;
  }
}
