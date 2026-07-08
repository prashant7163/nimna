import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/screenshot/screenshot_detector.dart';
import 'package:nimna/src/sensitive/sensitive_content_analyzer.dart';
import 'package:nimna/src/session/chat/chat_screen.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// S14 — the ChatScreen screenshot-detector LIFECYCLE, the load-bearing "only
/// while content is on screen inside the app" privacy gate (spec §5.2). A FAKE
/// detector (a controllable stream, no platform channel) proves the
/// composition end-to-end: start-on-mount, stop()+dispose()-on-unmount, and a
/// screenshot emitted while the line is NOT live records no system line (and
/// therefore seals no CONTROL frame — the controller's seal + record are one
/// gated step). A regression that drops `stop()`/`dispose()` from the screen's
/// `dispose`, or the liveness gate, fails here.
void main() {
  late TestDevice device;
  late NimnaServices services;
  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  setUp(() async {
    device = TestDevice.create();
    services = await device.boot();
  });

  tearDown(() async {
    await device.dispose();
  });

  /// A not-live SessionController (constructed, never bridged) — `isLive` is
  /// false, exactly the state the §5.2 gate must refuse to notice.
  Future<SessionController> makeController() async {
    final ownStatic = generateNoiseKeyPair(sodium);
    final peerStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final channelId = aead.randomBytes(16);
    await services.storage.channels.create(
      ChannelRecord(
        id: channelId,
        ownStaticPrivate: ownStatic.secretKey.extractBytes(),
        ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
        peerStaticPublic: Uint8List.fromList(peerStatic.publicKey),
        crid: Uint8List.fromList(crid),
        label: 'peer',
        cdk: aead.randomBytes(32),
        createdAtMs: 0,
      ),
    );
    return SessionController(
      sodium: sodium,
      aead: aead,
      connector: FakeRelayConnector(),
      messages: services.storage.messages,
      channelId: channelId,
      ownStatic: ownStatic,
      peerStaticPublic: peerStatic.publicKey,
      crid: crid,
      role: SessionRole.knocker,
      diag: Diag(aead: aead),
    );
  }

  Widget host(Widget child) => MaterialApp(
    theme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets('detector: start on mount, stop+dispose on unmount, no notice '
      'while not live', (tester) async {
    // A generous surface: the full-screen status Row can log a spurious
    // overflow while the header relayouts under degenerate teardown
    // constraints (a flutter_test artifact for full Scaffolds, not app
    // behaviour). Extra width removes it.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late SessionController controller;
    final detector = _FakeScreenshotDetector();
    await tester.runAsync(() async {
      controller = await makeController();
    });
    addTearDown(() async => controller.dispose());

    // Mount/unmount ChatScreen via a toggle so the surrounding MaterialApp /
    // MediaQuery stays stable — swapping the whole app home relayouts the
    // disposing tree with stale constraints (a harness-only overflow).
    var mounted = true;
    late StateSetter toggle;
    final chat = ChatScreen(
      controller: controller,
      label: 'peer',
      screenshotDetector: detector,
      sensitiveAnalyzer: const NoOpSensitiveContentAnalyzer(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              toggle = setState;
              return mounted ? chat : const SizedBox.shrink();
            },
          ),
        ),
      );
      // Let the post-frame auto-start (fake connector, never bridges) + the
      // empty-history hydration settle without ever going live.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // (a) start-on-mount registered the observer; nothing torn down yet.
    expect(detector.startCount, 1);
    expect(detector.stopCount, 0);
    expect(detector.disposed, isFalse);

    // (c) a screenshot while NOT live records no system line (and seals no
    // CONTROL frame — the gate refuses both together).
    expect(controller.isLive, isFalse);
    detector.emit();
    await tester.pump();
    expect(controller.screenshotNotices, isEmpty);

    // (b) unmount tears the observer down: stop() then dispose().
    toggle(() => mounted = false);
    await tester.pump();
    expect(detector.stopCount, 1);
    expect(detector.disposed, isTrue);
  });
}

/// A controllable [ScreenshotDetector] with no platform channel: records the
/// lifecycle calls and lets the test emit a screenshot at will.
class _FakeScreenshotDetector implements ScreenshotDetector {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  bool disposed = false;

  @override
  Stream<void> get onScreenshot => _controller.stream;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void emit() => _controller.add(null);
}
