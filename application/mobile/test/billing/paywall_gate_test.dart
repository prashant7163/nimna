import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/billing/entitlement_source.dart';
import 'package:nimna/src/ui/screens/pairing/create_line_flow.dart';
import 'package:nimna/src/ui/screens/paywall/paywall_screen.dart';

import '../helpers/test_env.dart';

/// F9 gate + paywall done-check (S17): the entitlement check intercepts
/// creation when unentitled and lets it through when entitled; buy and
/// restore both re-grant and continue to creating; the calm reconnect state
/// covers offline; and existing state never consults billing.
///
/// [TestDevice.boot] runs native (sodium/sqlite) async, so it is done in
/// setUp (outside the testWidgets FakeAsync zone). The billing fake is a
/// mutable object shared with the running services, so each test scripts it
/// BEFORE tapping — the gate reads it at creation intent, not at boot.
void main() {
  final en = AppLocalizationsEn();
  late TestDevice device;
  late NimnaServices services;

  setUp(() async {
    device = TestDevice.create();
    services = await device.boot();
  });

  tearDown(() async {
    await device.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();
  }

  Future<void> tapCreate(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, en.actionCreateCode));
    await tester.pumpAndSettle();
  }

  testWidgets('showing the channel list never consults billing (permanence)', (
    tester,
  ) async {
    await pumpApp(tester);

    // Existing state renders with ZERO entitlement queries — a lapse can
    // only ever be discovered at creation intent (spec §10).
    expect(device.entitlement.queryCount, 0);
    expect(find.byType(PaywallScreen), findsNothing);
  });

  testWidgets('unentitled: Create intercepts to the paywall, not creation', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.inactive;
    device.entitlement.priceString = 'PRICE';
    await pumpApp(tester);

    await tapCreate(tester);

    // F9.2 — the paywall, NOT the F2 create flow.
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(CreateLineFlow), findsNothing);
    expect(find.text(en.billing_headline), findsOneWidget);
    expect(find.text(en.billing_subhead), findsOneWidget);
    // The CTA renders the STORE price string — never a hardcoded number.
    expect(find.text(en.billing_ctaStart('PRICE')), findsOneWidget);
    // Permanence guarantee is present at feature prominence.
    expect(find.text(en.billing_pointPermanenceTitle), findsOneWidget);
    // The banned word never appears on-voice ("unlock" was only the mockup
    // page title, never a rendered label).
    expect(find.textContaining('unlock'), findsNothing);

    // Store-mandated disclosure (final, USER-approved) with {store} resolved
    // to the running platform's brand + the final Terms/Privacy labels.
    final store = defaultTargetPlatform == TargetPlatform.android
        ? 'Google Play'
        : 'App Store';
    expect(find.text(en.billing_autoRenewDisclosure(store)), findsOneWidget);
    expect(find.text(en.billing_termsLabel), findsOneWidget);
    expect(find.text(en.billing_privacyLabel), findsOneWidget);
    // No provisional placeholder text survives on the rendered paywall.
    expect(find.textContaining('PROVISIONAL'), findsNothing);

    // Calm, never a nag: neither the gate nor the paywall load ever triggers
    // restore — that stays reserved for the user-tapped Restore button.
    expect(device.entitlement.restoreCount, 0);
  });

  testWidgets('entitled: Create goes straight to the create flow', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.active;
    await pumpApp(tester);

    await tapCreate(tester);

    expect(find.byType(CreateLineFlow), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text(en.pairing_createIntro), findsOneWidget);
    // The gate consulted the silent entitlement query, never restore.
    expect(device.entitlement.queryCount, greaterThan(0));
    expect(device.entitlement.restoreCount, 0);
  });

  testWidgets('dismiss (✕): calm return to the list, nothing created', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.inactive;
    device.entitlement.priceString = 'PRICE';
    await pumpApp(tester);

    await tapCreate(tester);
    expect(find.byType(PaywallScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.byType(CreateLineFlow), findsNothing);
    expect(find.text(en.channelListEmptyHeadline), findsOneWidget);
  });

  testWidgets('buy success: subscribe then straight on to creating', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.inactive;
    device.entitlement.priceString = 'PRICE';
    device.entitlement.purchaseOutcome = PurchaseOutcome.purchased;
    await pumpApp(tester);

    await tapCreate(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, en.billing_ctaStart('PRICE')),
    );
    await tester.pumpAndSettle();

    // F9.4: the create flow, plus the calm one-shot toast.
    expect(find.byType(CreateLineFlow), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text(en.billing_subscriptionStartedToast), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush the toast timer
  });

  testWidgets('restore success: re-grant then on to creating', (tester) async {
    device.entitlement.status = EntitlementStatus.inactive;
    device.entitlement.priceString = 'PRICE';
    device.entitlement.restoreOutcome = RestoreOutcome.restored;
    await pumpApp(tester);

    await tapCreate(tester);
    // Restore runs ONLY on the explicit user tap.
    expect(device.entitlement.restoreCount, 0);
    await tester.tap(find.widgetWithText(TextButton, en.billing_restore));
    await tester.pumpAndSettle();

    expect(find.byType(CreateLineFlow), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text(en.billing_restoreSuccessToast), findsOneWidget);
    expect(device.entitlement.restoreCount, 1);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('restore finds nothing: factual line, page holds', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.inactive;
    device.entitlement.priceString = 'PRICE';
    device.entitlement.restoreOutcome = RestoreOutcome.nothingFound;
    await pumpApp(tester);

    await tapCreate(tester);
    await tester.tap(find.widgetWithText(TextButton, en.billing_restore));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsOneWidget); // stays put
    expect(find.text(en.billing_restoreNothing), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('offline (unresolved): calm reconnect state, no CTA', (
    tester,
  ) async {
    device.entitlement.status = EntitlementStatus.unresolved;
    await pumpApp(tester);

    await tapCreate(tester);

    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.text(en.billing_reconnectToVerify), findsOneWidget);
    expect(find.text(en.billing_tryAgain), findsOneWidget);
    // Fail-closed never blocks USING channels — it only withholds the buy
    // CTA (no price was ever fetched).
    expect(device.entitlement.priceCount, 0);
    expect(find.textContaining('start'), findsNothing);
  });
}
