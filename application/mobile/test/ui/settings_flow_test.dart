import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/ui/screens/settings/app_lock_setup_screen.dart';
import 'package:nimna/src/ui/screens/settings/settings_root_screen.dart';
import 'package:nimna/src/ui/widgets/destructive_hold_button.dart';
import 'package:nimna/src/ui/widgets/nimna_toggle.dart';

import '../helpers/test_env.dart';

/// F8 flows: settings root renders from the ARB (five locales), the
/// app-lock setup enrolls choose→confirm, mismatch restarts, turning off
/// requires the current PIN, and the wipe row raises the string-8 sheet.
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

  Future<void> openSettings(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(NimnaApp(services: services, locale: locale));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.settings_title));
    await tester.pumpAndSettle();
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.widgetWithText(GestureDetector, d).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final locale in const [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
  ]) {
    testWidgets('settings root renders the F8.1 rows from the ARB in '
        '$locale', (tester) async {
      await openSettings(tester, locale: locale);

      expect(find.byType(SettingsRootScreen), findsOneWidget);
      expect(find.text(en.settings_rowAppLock), findsOneWidget);
      expect(find.text(en.settings_rowAppLockOff), findsOneWidget);
      expect(find.text(en.settings_rowNotifications), findsOneWidget);
      expect(find.text(en.settings_rowRelay), findsOneWidget);
      expect(find.text(en.settings_rowRelayCaption), findsOneWidget);
      expect(find.text(en.settings_rowLicenses), findsOneWidget);
      expect(find.text(en.settings_rowWipeEverything), findsOneWidget);
      expect(find.text(en.settings_rowWipeEverythingCaption), findsOneWidget);
    });
  }

  testWidgets('choose → Next → confirm enrolls; row caption flips to On', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.tap(find.text(en.settings_rowAppLock));
    await tester.pumpAndSettle();

    expect(find.byType(AppLockSetupScreen), findsOneWidget);
    expect(find.text(en.lock_choosePinTitle), findsOneWidget);
    expect(find.text(en.lock_choosePinCaption), findsOneWidget);
    expect(find.text(en.lock_noRecoveryCaption), findsOneWidget);
    // No biometric hardware → the toggle row is hidden (F8.2 edge).
    expect(find.byType(NimnaToggle), findsNothing);

    await tapDigits(tester, '2468');
    await tester.tap(find.text(en.lock_actionNext));
    await tester.pumpAndSettle();
    expect(find.text(en.lock_confirmPinTitle), findsOneWidget);

    await tapDigits(tester, '2468');
    await tester.pumpAndSettle();

    // Enrolled and popped back to F8.1; caption is the on-state.
    expect(services.lockController.enabled, isTrue);
    expect(find.byType(SettingsRootScreen), findsOneWidget);
    expect(find.text(en.settings_rowAppLockOn), findsOneWidget);
  });

  testWidgets('confirm mismatch restarts the choose step with the notice', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.tap(find.text(en.settings_rowAppLock));
    await tester.pumpAndSettle();

    await tapDigits(tester, '1234');
    await tester.tap(find.text(en.lock_actionNext));
    await tester.pumpAndSettle();
    await tapDigits(tester, '1235');
    await tester.pumpAndSettle();

    expect(services.lockController.enabled, isFalse);
    expect(find.text(en.lock_choosePinTitle), findsOneWidget);
    expect(find.text(en.lock_confirmPinMismatch), findsOneWidget);
  });

  testWidgets('biometric toggle ships ON when hardware exists', (tester) async {
    device.biometricGate.available = true;
    await openSettings(tester);
    await tester.tap(find.text(en.settings_rowAppLock));
    await tester.pumpAndSettle();

    expect(find.text(en.lock_biometricToggleLabel), findsOneWidget);
    expect(find.text(en.lock_biometricToggleCaption), findsOneWidget);
    final toggle = tester.widget<NimnaToggle>(find.byType(NimnaToggle));
    expect(toggle.value, isTrue, reason: 'recommended-on posture (spec §6)');

    await tapDigits(tester, '9753');
    await tester.tap(find.text(en.lock_actionNext));
    await tester.pumpAndSettle();
    await tapDigits(tester, '9753');
    await tester.pumpAndSettle();

    expect(services.lockController.enabled, isTrue);
    expect(services.lockController.biometricEnabled, isTrue);
    expect(find.text(en.settings_rowAppLockOnBiometric), findsOneWidget);
  });

  testWidgets('turning off requires the current PIN first', (tester) async {
    await services.lockController.enableLock(
      pin: '1379',
      biometricEnabled: false,
    );
    await openSettings(tester);
    await tester.tap(find.text(en.settings_rowAppLock));
    await tester.pumpAndSettle();

    // The current-PIN gate (F8.2 edge), not the setup flow.
    expect(find.text(en.lock_enterPinTitle), findsOneWidget);
    expect(find.text(en.lock_actionTurnOff), findsNothing);

    // Wrong PIN keeps the gate.
    await tapDigits(tester, '0000');
    expect(find.text(en.lock_enterPinTitle), findsOneWidget);
    expect(services.lockController.enabled, isTrue);

    // Correct PIN reaches manage; Turn off removes the lock.
    await tapDigits(tester, '1379');
    expect(find.text(en.lock_actionTurnOff), findsOneWidget);
    await tester.tap(find.text(en.lock_actionTurnOff));
    await tester.pumpAndSettle();

    expect(services.lockController.enabled, isFalse);
    expect(find.byType(SettingsRootScreen), findsOneWidget);
    expect(find.text(en.settings_rowAppLockOff), findsOneWidget);
  });

  testWidgets('Wipe everything raises the string-8 sheet; Keep dismisses '
      'untouched', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text(en.settings_rowWipeEverything));
    await tester.pumpAndSettle();

    expect(find.text(en.wipe_fullBody), findsOneWidget);
    expect(find.text(en.wipe_holdToWipe), findsOneWidget);
    expect(find.text(en.wipe_fullHoldCaption), findsOneWidget);
    final button = tester.widget<DestructiveHoldButton>(
      find.byType(DestructiveHoldButton),
    );
    expect(button.holdDuration, const Duration(milliseconds: 2500));

    await tester.tap(find.text(en.wipe_actionKeep));
    await tester.pumpAndSettle();
    expect(find.text(en.wipe_fullBody), findsNothing);
    expect(find.byType(SettingsRootScreen), findsOneWidget);
  });
}
