import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/billing/billing_service.dart';
import 'package:nimna/src/billing/entitlement_source.dart';

import '../helpers/fake_entitlement.dart';

/// BillingService orchestration over the abstract seam (S17). Pure Dart —
/// no store, no widgets.
void main() {
  test('the gate is true ONLY when the store cache is active', () async {
    for (final entry in <EntitlementStatus, bool>{
      EntitlementStatus.active: true,
      EntitlementStatus.inactive: false,
      // Offline / unresolved is fail-closed → gate false → paywall.
      EntitlementStatus.unresolved: false,
    }.entries) {
      final source = FakeEntitlementSource(status: entry.key);
      final billing = BillingService(source);
      expect(
        await billing.hasActiveCreationEntitlement(),
        entry.value,
        reason: '${entry.key} should map to gate=${entry.value}',
      );
    }
  });

  test('entitlementStatus surfaces the tri-state for the paywall', () async {
    final source = FakeEntitlementSource(status: EntitlementStatus.unresolved);
    final billing = BillingService(source);
    expect(await billing.entitlementStatus(), EntitlementStatus.unresolved);
  });

  test(
    'localizedPrice passes the store string through (never a number)',
    () async {
      final billing = BillingService(
        FakeEntitlementSource(priceString: '¥1,980'),
      );
      expect(await billing.localizedPrice(), '¥1,980');
    },
  );

  test('a null store price stays null (no hardcoded fallback)', () async {
    final billing = BillingService(FakeEntitlementSource(priceString: null));
    expect(await billing.localizedPrice(), isNull);
  });

  test('restore re-grants and the next query reports active', () async {
    final source = FakeEntitlementSource(
      status: EntitlementStatus.inactive,
      restoreOutcome: RestoreOutcome.restored,
    );
    final billing = BillingService(source);
    expect(await billing.hasActiveCreationEntitlement(), isFalse);
    expect(await billing.restore(), RestoreOutcome.restored);
    expect(await billing.hasActiveCreationEntitlement(), isTrue);
  });

  test('purchase success flips the cache to active', () async {
    final source = FakeEntitlementSource(
      status: EntitlementStatus.inactive,
      purchaseOutcome: PurchaseOutcome.purchased,
    );
    final billing = BillingService(source);
    expect(
      await billing.purchaseCreationSubscription(),
      PurchaseOutcome.purchased,
    );
    expect(await billing.hasActiveCreationEntitlement(), isTrue);
  });

  test(
    'a cancelled purchase leaves the cache inactive (calm return)',
    () async {
      final source = FakeEntitlementSource(
        status: EntitlementStatus.inactive,
        purchaseOutcome: PurchaseOutcome.cancelled,
      );
      final billing = BillingService(source);
      expect(
        await billing.purchaseCreationSubscription(),
        PurchaseOutcome.cancelled,
      );
      expect(await billing.hasActiveCreationEntitlement(), isFalse);
    },
  );
}
