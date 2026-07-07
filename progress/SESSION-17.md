# SESSION 17 — Subscription & paywall (G2, ∥ S9)

Worktree `session-17-subscription-paywall`, branched off main. Non-protocol,
file-disjoint from the concurrent S9. Append here during the session; the
orchestrator folds into canonical TASKS/PROGRESS/DECISIONS at merge. Must merge
before S16 (polish sweep covers the paywall).

## Intake (architect + PM, 2026-07-07 12:24 +0200)

**Authority resolution:** spec §10 (rank 1) + voice guide §9 (binding-for-UI) agree —
the product is an **auto-renewing yearly subscription**, priced by regional store
tiers, no number ever hardcoded (app renders `{STORE_PRICE}`). "one-time unlock / one
payment" is stale terminology retired by the voice-guide word-ban, NOT a competing
product type (USER-confirmed superseded, 2026-07-07 12:24).

**Structural facts:** relay/​server learn nothing — entitlement checked ONLY on the
initiator's device at creation time (§10). Permanence is structural, not enforced —
channels are keypairs in storage; the only billing state is store-held (Nimna persists
ZERO entitlement flag → wipe cannot touch the paywall, no local unlock to forge). Lapse
gates creation of NEW channels only; existing channels are untouched forever (enforced
by ABSENCE of any re-check).

**Owns:** `lib/src/billing` (`entitlement_source.dart` abstract seam;
`store_entitlement_source.dart` over the platform's on-device SIGNED entitlement cache —
StoreKit 2 `Transaction.currentEntitlements` / Play `queryPurchasesAsync`, offline-capable,
never a Nimna flag/server; `billing_service.dart` orchestration + `{STORE_PRICE}` fetch;
`product_ids.dart`), the paywall screen
(`lib/src/ui/screens/paywall/paywall_screen.dart` — designs screen 09 + `.light` / F9:
calm full-screen, two-card + full-width permanence band + store badges, voice string 9,
`{STORE_PRICE}` from `productDetails.price`, no hardcoded number), and the gate wiring.

**Gate — the single intercept:** edit ONLY `lib/src/pairing/initiator/create_line_entry.dart::startCreateLine`
(its docstring already reserves this). Before the create nav:
`if (!await services.billing.hasActiveCreationEntitlement()) → push PaywallScreen; on
success continue`. `resumeCreateLineIfPending` stays UNGATED. No second creation door —
`test/pairing/single_call_site_test.dart` test 1 stays green (gate lives inside the entry
function, not at the call site). S9 joiner tree untouched; receivers never gated.

**Restore:** first-class (§10). `BillingService.restore()` → native `restorePurchases()`
→ re-query entitlements. Covers reinstall + new-device-same-store-account. Family Sharing
disabled at product-config level. Cross-platform does NOT restore (iOS↔Android = new
purchase) — FAQ, no code path.

## Decisions carried in

- **USER 2026-07-07 12:24 — model = auto-renewing yearly subscription canonical;
  "one-time unlock/one payment" superseded.** Implement as StoreKit auto-renewable
  subscription group / Play `subs`, NOT a non-consumable. Fix screen 09's residual
  "nimna — unlock" header label (voice-guide word-ban implementation fix, not USER copy).
- **USER 2026-07-07 12:24 — paywall gains store-mandated auto-renew disclosure +
  Terms/Privacy links.** PM drafts minimal, calm secondary-text copy (renewal terms,
  charges the store account, how to cancel) + Terms of Use (EULA) + Privacy Policy links
  below the CTA, to the voice-guide honesty bar. **USER SIGNS OFF the wording BEFORE it
  lands (in-flight checkpoint — do not finalize without it).** Enters the S16 crafted
  translation pass. The designed paywall carries none today; this is net-new promissory
  copy needing PM claim-accuracy review.
- **USER 2026-07-07 12:24 — Restore = paywall-only; honest-limits FAQ → website S19.**
  No in-app subscription-status screen and no in-app FAQ in v1. S17 stays scoped to
  paywall + purchase + restore + on-device entitlement gate.
- **CODE — offline entitlement = fail-closed:** if the platform entitlement query genuinely
  can't resolve, show a calm "reconnect to verify your subscription" state on the paywall
  (never blocks USING existing channels — only creation).
- **CODE — sandbox tier = local `.storekit` StoreKit Configuration / Play static-response**
  placeholder (dev artifact, never shipped, app still reads `{STORE_PRICE}` from the store
  API). Real tier + prod product IDs deferred to the S19 store-console hand step. Do NOT
  reopen the numberless-price lock.
- **CODE — product IDs:** group `nimna_creation`, product `nimna_creation_yearly` (sandbox
  now; USER ratifies prod at S19).

## Dependency proposal (SIGNED OFF in principle — pending pin-time transitive audit)

`in_app_purchase` + `in_app_purchase_storekit` + `in_app_purchase_android`
(+ `_platform_interface` transitive) — first-party Flutter-team, canonical IAP path,
light transitive graph. **No-SDK doctrine PASS conditional on a pin-time
`flutter pub deps` + grep audit for any analytics/firebase/beacon surface** (same rigor as
S8 `share_plus`). Pin exact stable minors (no floating `^`), justify in pubspec + fold into
`app-architecture.md §1` (billing currently absent from §1 = genuine new-dependency review
event). iOS StoreKit capability + `.storekit` test config; Android `com.android.vending.BILLING`.

## Cross-lane / hotspots (fold serially at merge)

- **File-disjoint from S9: confirmed.** S17 = `create_line_entry.dart` + `lib/src/billing`
  + paywall + app_scope/routes; S9 never touches these. S9's write-seam is on
  `initiator_controller.dart`, which S17 does NOT touch.
- Add `BillingService` to `NimnaServices`/`app_scope.dart`; add `Routes.paywall = '/paywall'`
  (Navigator-1.0 named route, matching settings/app-lock). Merge-fold hotspots.
- ARB namespace `billing_*` (voice §9 canonical, no number, permanence headline; zero
  hardcoded strings). pubspec union: three `in_app_purchase*` pins + `.storekit` config.

## Done-check (from plan)

Sandbox subscribe/lapse/restore behave per §10 on both platforms; a lapsed account's
existing channels work forever.

---

## Implementation (CODE, 2026-07-07)

### ⚠ PRE-MERGE BLOCKER — provisional disclosure copy (USER checkpoint)

The store-mandated auto-renew disclosure beside the CTA is built as STRUCTURE
+ a clearly-flagged PLACEHOLDER, not final copy. ARB key
`billing_autoRenewDisclosure` carries an `@_comment`: *"PROVISIONAL — awaiting
USER sign-off, do not translate/ship as final."* The paywall layout holds the
disclosure block + `Terms of Use` / `Privacy Policy` link affordances
(destinations are a `TODO(S19)` no-op — legal/FAQ live on the website at S19,
USER 2026-07-07). **This session MUST NOT merge until PM's drafted disclosure
wording is USER-approved and swapped in** (then it enters the S16 crafted
translation pass). No final legal copy was invented.

### Files created

- `lib/src/billing/entitlement_source.dart` — abstract seam
  (`hasActiveCreationEntitlement`, `restore`, + `localizedPrice`,
  `purchaseCreationSubscription`) and the `EntitlementStatus` /
  `RestoreOutcome` / `PurchaseOutcome` enums.
- `lib/src/billing/store_entitlement_source.dart` — the ONLY file importing
  `package:in_app_purchase`; reads the platform signed on-device entitlement
  cache, drives purchase/restore/price.
- `lib/src/billing/billing_service.dart` — pure-Dart orchestrator in
  `NimnaServices`; gate bool + tri-state query + price + purchase + restore.
- `lib/src/billing/product_ids.dart` — group `nimna_creation`, product
  `nimna_creation_yearly` (sandbox).
- `lib/src/billing/README.md`.
- `lib/src/ui/screens/paywall/paywall_screen.dart` — F9 paywall + `PaywallResult`.
- `ios/nimna_creation.storekit` — dev-only StoreKit config (placeholder tier,
  `familyShareable:false`, `P1Y`; never shipped).
- Tests: `test/helpers/fake_entitlement.dart`,
  `test/billing/billing_service_test.dart`,
  `test/billing/billing_fences_test.dart`,
  `test/billing/paywall_gate_test.dart`.

### Files edited

- `lib/src/pairing/initiator/create_line_entry.dart` — **the gate, inside
  `startCreateLine` only.** Entitlement check in front of the create push;
  on a non-dismiss `PaywallResult`, one toast (F9.4 `Subscription started.` /
  F9.5 `Purchase restored.`) then create. `resumeCreateLineIfPending`
  untouched (UNGATED). No second call site — `single_call_site_test` test 1
  stays green.
- `lib/src/app/{app_scope,bootstrap,routes}.dart` — `billing` in
  `NimnaServices`; injectable `entitlementSource` (prod →
  `StoreEntitlementSource`); `Routes.paywall`.
- `lib/src/ui/widgets/glyphs.dart` — `CloseGlyph` (✕, screen 09 navbar).
- `lib/l10n/app_en.arb` — `billing_*` namespace (non-EN stay `@@locale`-only
  until S16).
- `test/helpers/test_env.dart` — `TestDevice.entitlement` fake wired into boot.
- `android/.../AndroidManifest.xml` — `com.android.vending.BILLING`.
- `pubspec.yaml` + `docs/architecture/app-architecture.md §1` — dep block.
- `test/README.md`.

### Dependency audit outcome — PASS

`in_app_purchase` **3.2.4**, `in_app_purchase_storekit` **0.4.10+1**,
`in_app_purchase_android` **0.4.0+11** — pinned EXACT (no caret). Pin-time
`flutter pub deps` + grep (analytics/firebase/crashlytics/sentry/beacon/
telemetry/amplitude/mixpanel/segment/…) → **CLEAN**. Transitive additions:
`in_app_purchase_platform_interface`, `plugin_platform_interface`,
`collection`, `meta`, `json_annotation` — all boring/first-party. Native
frameworks pulled are Apple StoreKit + Google Play Billing client (the
payment substrate itself), not SDKs. No-telemetry doctrine holds absolutely.

### Verification

- `flutter analyze` — **No issues found.**
- `flutter test` — **+222, all passed** (17 new billing tests).
- `dart format --set-exit-if-changed` — clean.
- single_call_site_test test 1 (one create call site) — **green**; no second
  creation door; receivers never gated; `billing_fences_test` proves the
  session/storage path never references billing (permanence structural).

### Reconciliations / flags for reviewer + PM

1. **Binding hi-fi (screen 09) implemented verbatim, over looser prose.** The
   intake described "two-card + full-width permanence band + store badges" —
   the actual binding artifact `designs/screens/09-paywall.html(.light)` has
   NEITHER cards nor store badges; it is a headline + 4 feature rows + bottom
   CTA/Restore. Per "implement, don't reinterpret," I built the hi-fi as
   drawn. No store badges were invented (F9.3 anno: "nimna draws none of
   this").
2. **screen 09 vs voice string 9 divergence — PM please confirm.** Screen 09
   condenses voice-guide string 9's paragraphs into 4 short feature rows;
   both are design artifacts. I took the hi-fi (most specific) verbatim as
   the `billing_*` ARB. The S16 crafted-translation pass should reconcile
   against the voice guide.
3. **"unlock" fix.** The banned word lived ONLY in the mockup's `<title>` —
   it was never a rendered on-screen label. The Flutter paywall renders no
   such label (navbar is the ✕ only); a widget test asserts no "unlock" text.
4. **Restore label = "Restore"** (binding screen 09 ghost button), not the
   intake's paraphrase "Already subscribed? Restore".
5. **Seam extended beyond the two named methods.** `EntitlementSource` also
   carries `localizedPrice` + `purchaseCreationSubscription` so
   `in_app_purchase` stays fenced to ONE module AND `BillingService`/paywall
   stay fully fake-injectable. Engineering call; noted for the reviewer.
6. **Store integration is device-validated at the done-check.** Host tests
   use the fake; `StoreEntitlementSource` is written to the plugin's public
   API but sandbox subscribe/lapse/restore on a real simulator/device
   (`ios/nimna_creation.storekit` / Play static responses) is the QA hand
   step, plus the S19 store-console product/tier setup + iOS StoreKit
   capability / scheme config.

### Hand steps deferred to S19 (store console / Xcode)

Real product IDs + price tier (numberless lock untouched — app renders
`ProductDetails.price`); iOS In-App-Purchase capability + scheme StoreKit
config; Terms/Privacy destinations; honest-limits FAQ (website).
