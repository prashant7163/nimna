import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/ui/screens/channel_list_screen.dart';
import 'package:nimna/src/ui/widgets/pin_pad.dart';

import '../helpers/test_env.dart';

/// S13 gate widget tier: seal-on-`hidden` (zero-leak subtree replacement,
/// extending the S7 test), `inactive` never seals, PIN-pad unlock restores
/// the tree, biometric auto-prompt, escalating-delay pad disarm.
void main() {
  final en = AppLocalizationsEn();
  late TestDevice device;
  late NimnaServices services;

  const pin = '2580';

  setUp(() async {
    device = TestDevice.create();
    device.observeLifecycle = true;
    services = await device.boot();
    await services.lockController.enableLock(pin: pin, biometricEnabled: false);
  });

  tearDown(() async {
    await device.dispose();
  });

  /// Backgrounds the app (inactive → hidden — the seal point, before the
  /// OS snapshot) and returns to foreground. The test binding disables
  /// frame production while hidden, so assertions run after `resumed`;
  /// the perimeter stays sealed until the gate passes regardless.
  Future<void> goHiddenAndReturn(WidgetTester tester) async {
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      // storage.seal() does real DB I/O — let it finish.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        services.keyService.sealed,
        isTrue,
        reason: 'sealed at hidden, before the switcher snapshot',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester tester, String digits) async {
    await tester.runAsync(() async {
      for (final d in digits.split('')) {
        await tester.tap(find.widgetWithText(GestureDetector, d).first);
        await tester.pump();
        // Argon2id + storage.open() I/O on the last digit.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('hidden seals; the lock surface replaces the whole subtree '
      'with zero content widgets', (tester) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelListScreen), findsOneWidget);

    await goHiddenAndReturn(tester);

    expect(services.keyService.sealed, isTrue);
    // Zero-leak: no content widget, no navigator, no copy — only the
    // symbol, the dots, and the pad (screen 12 carries no strings).
    expect(find.byType(ChannelListScreen), findsNothing);
    expect(find.byType(Navigator), findsNothing);
    expect(find.text(en.channelListEmptyHeadline), findsNothing);
    expect(find.text(en.appTitle), findsNothing);
    expect(find.byType(PinPad), findsOneWidget);
    expect(find.byType(PinDots), findsOneWidget);
  });

  testWidgets('inactive never seals (biometric prompts, pickers, shade)', (
    tester,
  ) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(services.keyService.sealed, isFalse);
    expect(find.byType(ChannelListScreen), findsOneWidget);
  });

  testWidgets('the correct PIN on the pad unlocks and restores the tree', (
    tester,
  ) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();
    await goHiddenAndReturn(tester);
    expect(find.byType(PinPad), findsOneWidget);

    // A wrong PIN clears the dots and stays sealed.
    await tapPin(tester, '1111');
    expect(services.keyService.sealed, isTrue);
    expect(find.byType(PinPad), findsOneWidget);

    // The right PIN auto-submits at full length and opens.
    await tapPin(tester, pin);
    expect(services.keyService.sealed, isFalse);
    expect(find.byType(ChannelListScreen), findsOneWidget);
  });

  testWidgets('biometric auto-prompt unlocks without the pad', (tester) async {
    await services.lockController.setBiometricEnabled(true);
    device.biometricGate
      ..available = true
      ..nextResult = true;

    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();

    // Background → seal → foreground: the lock surface appears and
    // auto-prompts; the biometric verdict opens the perimeter without a
    // single pad tap.
    await goHiddenAndReturn(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(device.biometricGate.prompts, isNotEmpty);
    expect(
      device.biometricGate.prompts.last,
      en.lock_biometricPromptReason,
      reason: 'the OS prompt reason comes from the ARB',
    );
    expect(services.keyService.sealed, isFalse);
    expect(find.byType(ChannelListScreen), findsOneWidget);
  });
}
