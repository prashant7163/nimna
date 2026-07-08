import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/presence/push_opt_in.dart';
import 'package:nimna/src/ui/screens/settings/channel_notifications_screen.dart';
import 'package:nimna/src/ui/screens/settings/notifications_directory_screen.dart';
import 'package:nimna/src/ui/widgets/nimna_toggle.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// The reachable push mount (requirement 4): Settings → Notifications (per-line
/// directory) → a line → the F7 push toggle. Proves the previously-inert
/// PushOptInTile is now wired live — flipping it persists the per-channel
/// opt-in — and that the always-visible string-18 disclosure renders. Push
/// stays OFF by default; the source is inert on the host, so no third party
/// is touched.
void main() {
  final en = AppLocalizationsEn();
  late TestDevice device;
  late NimnaServices services;
  late SodiumSumo sodium;
  late AtRestAead aead;
  late Uint8List channelId;

  setUp(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
    device = TestDevice.create();
    services = await device.boot();
    channelId = aead.randomBytes(16);
    final own = generateNoiseKeyPair(sodium);
    await services.storage.channels.create(
      ChannelRecord(
        id: channelId,
        ownStaticPrivate: own.secretKey.extractBytes(),
        ownStaticPublic: Uint8List.fromList(own.publicKey),
        peerStaticPublic: aead.randomBytes(32),
        crid: aead.randomBytes(16),
        label: 'Marlowe',
        cdk: aead.randomBytes(32),
        createdAtMs: 0,
      ),
    );
  });

  tearDown(() async {
    await device.dispose();
  });

  testWidgets('Settings → Notifications → line → push toggle flips opt-in', (
    tester,
  ) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();

    // F4 → Settings.
    await tester.tap(find.text(en.settings_title));
    await tester.pumpAndSettle();

    // Settings → the per-line notifications directory.
    await tester.tap(find.text(en.settings_rowNotifications));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsDirectoryScreen), findsOneWidget);
    expect(find.text(en.settings_rowNotificationsCaption), findsOneWidget);
    expect(find.text('Marlowe'), findsOneWidget);

    // Directory → the line's push settings.
    await tester.tap(find.text('Marlowe'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelNotificationsScreen), findsOneWidget);
    // The string-18 disclosure is always visible (the caption IS the
    // disclosure, never a one-time dialog).
    expect(find.text(en.push_toggleLabel), findsOneWidget);
    expect(find.textContaining('New activity'), findsOneWidget);
    expect(find.textContaining('touches Apple or Google'), findsOneWidget);

    bool enabled() => PushOptIn(services.storage.channels).isEnabled(channelId);

    // Lets the fire-and-forget setEnabled DB write (sqflite FFI, real async)
    // land before asserting on the persisted state.
    Future<void> settleWrites() async {
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
    }

    // Default OFF, then flip ON — persisted inside the channel record.
    expect(enabled(), isFalse);
    await tester.tap(
      find.byType(NimnaToggle).first,
    ); // F7 now has 3 toggles; the push toggle is first
    await tester.pump();
    await settleWrites();
    expect(enabled(), isTrue);

    // Flip back OFF — the unilateral opt-out.
    await tester.tap(
      find.byType(NimnaToggle).first,
    ); // F7 now has 3 toggles; the push toggle is first
    await tester.pump();
    await settleWrites();
    expect(enabled(), isFalse);
  });
}
