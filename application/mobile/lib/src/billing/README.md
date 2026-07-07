# lib/src/billing — subscription & creation gate (S17)

The paywall's engine (spec §10 monetization doctrine). Initiators pay via a
platform **auto-renewing yearly subscription**; receivers never do. The
subscription is consulted ONLY on the initiator's device, ONLY at creation
intent — there is no Nimna account, no Nimna server, and no persisted
entitlement flag anywhere. **Permanence is structural:** channels are
keypairs; a lapse gates creating *new* lines only; the send/receive/session
path never references this module (asserted by `billing_fences_test`).

## Files

```
entitlement_source.dart        Abstract seam + enums (EntitlementStatus,
                               RestoreOutcome, PurchaseOutcome). Everything
                               above this line is pure Dart and
                               store-agnostic → fully fake-injectable.
store_entitlement_source.dart  The ONLY file importing package:in_app_purchase
                               (fenced). Reads the platform's SIGNED
                               on-device entitlement cache (StoreKit 2
                               currentEntitlements / Play queryPurchasesAsync)
                               and drives purchase/restore/price. Never a
                               Nimna flag or server.
billing_service.dart           Pure-Dart orchestrator in NimnaServices.
                               Exposes the gate bool + the paywall's
                               tri-state query, price, purchase, restore.
                               Not a ChangeNotifier; caches no entitlement.
product_ids.dart               group `nimna_creation`, product
                               `nimna_creation_yearly` (sandbox; prod at S19).
```

## The gate (the single intercept)

`lib/src/pairing/initiator/create_line_entry.dart::startCreateLine` — and
nowhere else — calls `billing.hasActiveCreationEntitlement()` before creating.
Not entitled (or unresolved → **fail-closed**) opens the paywall
(`lib/src/ui/screens/paywall/paywall_screen.dart`, route `Routes.paywall`);
on a non-dismiss result creation proceeds. `resumeCreateLineIfPending` and all
joiner code stay UNGATED — receivers are never paywalled.

## Invariants (test-enforced)

- **No hardcoded price, ever** — the CTA renders `ProductDetails.price` from
  the store (numberless lock, spec §10). A missing price shows the reconnect
  state, never a fabricated number.
- **in_app_purchase is fenced** to `store_entitlement_source.dart`
  (`billing_fences_test`).
- **No billing on the session/storage path** (`billing_fences_test`) —
  permanence cannot be forged or re-checked.
- **Offline = fail-closed** — an unresolved query blocks only creation, never
  USE of existing channels.

Restore is store-mediated end to end (reinstall / new-device-same-account);
cross-platform does not restore (FAQ only, no code path); Family Sharing is
disabled at product config. Sandbox subscribe/lapse/restore on device is the
QA done-check hand step (`ios/nimna_creation.storekit` / Play static
responses).

## Pre-merge blocker

The paywall's store-mandated auto-renew disclosure copy
(`billing_autoRenewDisclosure`) is **PROVISIONAL — awaiting USER sign-off**.
See `progress/SESSION-17.md`.
