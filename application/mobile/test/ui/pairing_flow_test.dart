import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/pairing/initiator/initiator_controller.dart';
import 'package:nimna/src/pairing/initiator/pairing_initiator_service.dart';
import 'package:nimna/src/ui/screens/pairing/code_ended_screen.dart';
import 'package:nimna/src/ui/screens/pairing/create_line_flow.dart';
import 'package:nimna/src/ui/screens/pairing/share_code_screen.dart';
import 'package:nimna/src/ui/widgets/qr_card.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// F2 widget slices: F2.1/F2.2+F2.4/F2.8 render their canonical ARB
/// strings (all five locales, EN fallback pre-S16), the code and its QR
/// are ONE simultaneous surface, Copy toasts, and the layout survives a
/// narrow 320 px frame without overflow.
void main() {
  final en = AppLocalizationsEn();
  late TestDevice device;
  late NimnaServices services;
  late FakeRelayConnector connector;
  late PairingInitiatorService pairing;

  setUp(() async {
    device = TestDevice.create();
    services = await device.boot();
    connector = FakeRelayConnector();
    pairing = PairingInitiatorService(
      sodium: await testSodium(),
      storage: services.storage,
      diag: services.diag,
      connector: connector,
    );
  });

  tearDown(() => device.dispose());

  Widget wrap(Widget child, {Locale? locale}) => MaterialApp(
    locale: locale,
    theme: nimnaTheme(Brightness.light),
    darkTheme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  for (final locale in const [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
  ]) {
    testWidgets('F2.1 renders canonical strings in $locale', (tester) async {
      await tester.pumpWidget(
        wrap(CreateLineFlow(pairing: pairing), locale: locale),
      );
      await tester.pumpAndSettle();

      // Each string renders THIS locale's crafted copy (S16 filled
      // DE/FR/ES/IT — F2.1 renders its own translation, not the EN template).
      final l10n = lookupAppLocalizations(locale);
      // Heading + primary action carry the same designed verb phrase.
      expect(find.text(l10n.pairing_createTitle), findsNWidgets(2));
      expect(find.text(l10n.pairing_createIntro), findsOneWidget);
      expect(find.text(l10n.pairing_ttlLabel), findsOneWidget);
      expect(find.text(l10n.pairing_ttlHint), findsOneWidget);
      // Default TTL is 24 h (locale-aware plural).
      expect(find.text(l10n.pairing_ttlHours(24)), findsOneWidget);
      // No offline line unless the edge occurred.
      expect(find.text(l10n.pairing_offlineError), findsNothing);
    });
  }

  testWidgets('F2.1 TTL sheet offers exactly the three presets', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(CreateLineFlow(pairing: pairing)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.pairing_ttlLabel));
    await tester.pumpAndSettle();
    expect(find.text(en.pairing_ttlHours(1)), findsOneWidget);
    expect(find.text(en.pairing_ttlHours(8)), findsOneWidget);
    expect(find.text(en.pairing_ttlHours(24)), findsNWidgets(2)); // row + sheet

    await tester.tap(find.text(en.pairing_ttlHours(1)));
    await tester.pumpAndSettle();
    expect(find.text(en.pairing_ttlHours(1)), findsOneWidget);
  });

  testWidgets('F2.1 offline edge renders the wireframe line, stays put', (
    tester,
  ) async {
    connector.failNextAttempts = 1;
    await tester.pumpWidget(wrap(CreateLineFlow(pairing: pairing)));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      // createCode runs to completion (fake connector fails synchronously).
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text(en.pairing_offlineError), findsOneWidget);
    expect(find.text(en.pairing_createIntro), findsOneWidget); // still F2.1
  });

  group('F2.2/F2.4 share surface', () {
    late CreateLineController controller;

    Future<void> pumpShareScreen(WidgetTester tester) async {
      controller = pairing.newController();
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        expect(await controller.createCode(), isTrue);
      });
      await tester.pumpWidget(wrap(ShareCodeScreen(controller: controller)));
      await tester.pumpAndSettle();
    }

    testWidgets('code and QR are one simultaneous surface', (tester) async {
      await pumpShareScreen(tester);

      // Simultaneous: the QR card AND the XXX-XXX-XXX text, one screen.
      expect(find.byType(QrCard), findsOneWidget);
      expect(find.text(controller.code!.display), findsOneWidget);

      // Canonical captions: string 13 verbatim + the hi-fi second line.
      expect(find.text(en.pairing_shareBriefing), findsOneWidget);
      expect(find.text(en.pairing_eitherFormPairs), findsOneWidget);

      // Waiting state with the dotted-line language + lifetime promise.
      expect(find.text(en.pairing_waitingForJoin), findsOneWidget);
      expect(find.text(en.pairing_waitLifetime(24)), findsOneWidget);
      expect(find.text(en.pairing_cancelCode), findsOneWidget);

      // Actions.
      expect(find.text(en.pairing_copyAction), findsOneWidget);
      expect(find.text(en.pairing_shareAction), findsOneWidget);
    });

    testWidgets('Copy toasts "Code copied." and auto-dismisses', (
      tester,
    ) async {
      await pumpShareScreen(tester);

      await tester.ensureVisible(find.text(en.pairing_copyAction));
      await tester.tap(find.text(en.pairing_copyAction));
      await tester.pump();
      expect(find.text(en.pairing_codeCopiedToast), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(en.pairing_codeCopiedToast), findsNothing);
    });

    testWidgets('F2.3 sheet carries string 13 as its header caption', (
      tester,
    ) async {
      await pumpShareScreen(tester);

      await tester.ensureVisible(find.text(en.pairing_shareAction));
      await tester.tap(find.text(en.pairing_shareAction));
      await tester.pumpAndSettle();

      expect(
        find.text(en.pairing_shareBriefing),
        findsNWidgets(2),
      ); // screen + sheet
      expect(find.text(en.pairing_shareAsText), findsOneWidget);
      expect(find.text(en.pairing_shareQrAsImage), findsOneWidget);
      expect(find.text(en.pairing_copyCode), findsOneWidget);
    });

    testWidgets('back asks the confirm question from designed vocabulary', (
      tester,
    ) async {
      await pumpShareScreen(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('Back')));
      await tester.pumpAndSettle();

      expect(find.text(en.pairing_stopWaitingConfirm), findsOneWidget);
      expect(find.text(en.pairing_notNow), findsOneWidget);
      expect(
        find.text(en.pairing_cancelCode),
        findsNWidgets(2),
      ); // ghost + confirm

      await tester.tap(find.text(en.pairing_notNow));
      await tester.pumpAndSettle();
      expect(find.text(en.pairing_stopWaitingConfirm), findsNothing);
      expect(controller.phase, CreateLinePhase.waiting);
    });

    testWidgets('layout survives a narrow 320 px frame', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpShareScreen(tester);
      // The framework throws on RenderFlex overflow; reaching here with
      // the full surface rendered is the assertion.
      expect(find.byType(QrCard), findsOneWidget);
      expect(find.text(controller.code!.display), findsOneWidget);
    });
  });

  testWidgets('F2.8 renders the expired edge verbatim', (tester) async {
    var restarted = false;
    await tester.pumpWidget(
      wrap(CodeEndedScreen.expired(onMakeNewCode: () => restarted = true)),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.pairing_expiredHeadline), findsOneWidget);
    expect(find.text(en.pairing_expiredBody), findsOneWidget);
    expect(find.text(en.pairing_notNow), findsOneWidget);

    await tester.tap(find.text(en.pairing_makeNewCode));
    expect(restarted, isTrue);
  });

  testWidgets('spent edge renders the F2.5 edge line verbatim', (tester) async {
    await tester.pumpWidget(wrap(CodeEndedScreen.spent(onMakeNewCode: () {})));
    await tester.pumpAndSettle();
    expect(find.text(en.pairing_spentBody), findsOneWidget);
    expect(find.text(en.pairing_expiredHeadline), findsNothing);
  });
}
