import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/routes.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/presence/incoming_knock_controller.dart';
import 'package:nimna/src/presence/peer_token_store.dart';
import 'package:nimna/src/presence/push_opt_in.dart';
import 'package:nimna/src/presence/reconnect_coordinator.dart';
import 'package:nimna/src/presence/session_launcher.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/screenshot/screenshot_detector.dart';
import 'package:nimna/src/sensitive/sensitive_content_analyzer.dart';
import 'package:nimna/src/session/chat/chat_screen.dart';
import 'package:nimna/src/session/chat/line_presence.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// S16 Phase 2.5 — the foreground presence-mount & navigation choreography.
/// These drive the ACTUAL coordinating widget ([LinePresence]) and the F4 list,
/// asserting the spec-fidelity traps hold: line-open connects LISTENING; Knock
/// disposes the listener BEFORE the knocker connects (the one-CRID invariant);
/// a lapse settles to "No answer." and re-listens; an inbound KNOCK_FWD surfaces
/// F6 and requires an EXPLICIT pick-up (no auto-ACCEPT); the reconnect phases
/// render the three captions. Zero codec touch — composition only.
void main() {
  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  // A generous surface so the full-screen Scaffolds never log a harness-only
  // overflow while relaying out (same precedent as chat_screen_test).
  void widenView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget child, {NimnaServices? services}) {
    final app = MaterialApp(
      theme: nimnaTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
    return services == null ? app : AppScope(services: services, child: app);
  }

  // ---- F4 populates from channels.all and taps into a line ------------------

  testWidgets('F4 populates from channels.all and a row taps into /line', (
    tester,
  ) async {
    widenView(tester);
    final device = TestDevice.create();
    addTearDown(device.dispose);
    late NimnaServices services;
    await tester.runAsync(() async {
      services = await device.boot();
    });
    final channelId = aead.randomBytes(16);
    await tester.runAsync(() async {
      await services.storage.channels.create(_record(sodium, aead, channelId));
    });

    RouteSettings? pushed;
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: nimnaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: Routes.channelList,
          onGenerateRoute: (settings) {
            if (settings.name == Routes.line) {
              pushed = settings;
              // A placeholder for the pushed target — this test asserts the F4
              // wiring/args, not LinePresence's internals (covered below).
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const SizedBox.shrink(),
              );
            }
            return onGenerateRoute(settings);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The row shows the label and the per-open-line-scope "Quiet" status.
    expect(find.text('Marlowe'), findsOneWidget);
    expect(find.text('Quiet'), findsOneWidget);

    await tester.tap(find.text('Marlowe'));
    await tester.pumpAndSettle();

    expect(pushed?.name, Routes.line);
    final args = pushed!.arguments as LinePresenceArgs;
    expect(args.label, 'Marlowe');
    expect(args.channelId, channelId);
  });

  // ---- line-open → LISTENING; Knock → one-CRID handoff; lapse → No answer ---

  testWidgets('open→listening (accepter); Knock disposes the listener before '
      'the knocker connects (one-CRID); lapse → No answer → re-listen', (
    tester,
  ) async {
    widenView(tester);
    final device = TestDevice.create();
    addTearDown(device.dispose);
    late NimnaServices services;
    await tester.runAsync(() async {
      services = await device.boot();
    });
    final channelId = aead.randomBytes(16);
    await tester.runAsync(() async {
      await services.storage.channels.create(_record(sodium, aead, channelId));
    });
    final connector = FakeRelayConnector();
    final launcher = _launcher(sodium, aead, services, connector);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        host(
          LinePresence(
            launcher: launcher,
            diag: services.diag,
            channelId: channelId,
            label: 'Marlowe',
            knockWindow: const Duration(milliseconds: 60),
            screenshotDetector: _FakeDetector(),
            sensitiveAnalyzer: const NoOpSensitiveContentAnalyzer(),
          ),
        ),
      );
      await tester.pump(); // first frame: listening surface
      await Future<void>.delayed(
        const Duration(milliseconds: 30),
      ); // accepter start()
    });
    await tester.pump();

    // Listening: exactly ONE connection (the accepter). It registered a CRID
    // and — being an accepter — sent NO knock.
    expect(connector.connections, hasLength(1));
    expect(
      connector.connections[0].sent.any((f) => f.type == FrameType.knock),
      isFalse,
      reason: 'a listening accepter never knocks',
    );
    // The F5 surface: "Not on the line" + the Knock affordance.
    expect(find.text('Knock'), findsOneWidget);

    // Human presses Knock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Knock'));
      await tester.pump();
      await Future<void>.delayed(
        const Duration(milliseconds: 30),
      ); // knocker start()
    });
    await tester.pump();

    // THE ONE-CRID INVARIANT: the listening connection was disposed (closed by
    // the client) BEFORE the knocker's connection was opened — the CRID is
    // never registered on two live connections from one device.
    expect(connector.connections, hasLength(2));
    expect(
      connector.connections[0].closedByClient,
      isTrue,
      reason: 'the listener must be torn down before the knocker connects',
    );
    expect(
      connector.connections[1].sent.any((f) => f.type == FrameType.knock),
      isTrue,
      reason: 'the fresh knocker sends the one KNOCK',
    );

    // Let the 60 ms knock window lapse unanswered (FakeRelayConnector never
    // bridges). It settles to "No answer." and re-opens a listening connection.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });
    await tester.pump();

    expect(find.text('No answer.'), findsOneWidget);
    // Re-listening: a fresh accepter connection was opened, so the line stays
    // receivable. And the affordance is now the manual "Knock again".
    expect(connector.connections.length, greaterThanOrEqualTo(3));
    expect(
      connector.connections.last.sent.any((f) => f.type == FrameType.knock),
      isFalse,
      reason: 're-listen is an accepter, not an auto-retry knock',
    );
    expect(find.text('Knock again'), findsOneWidget);
  });

  // ---- inbound KNOCK_FWD → F6, explicit pick-up only (no auto-ACCEPT) -------

  // The behaviour is split across two levels to stay deterministic: the
  // controller stack (the exact IncomingKnockController + launcher LinePresence
  // mounts) proves the no-auto-ACCEPT gate over the real two-party bridge, and a
  // plain widget test proves the F6 surface renders. Driving the widget THROUGH
  // the bridge is avoided on purpose — pumping a widget while the two-party
  // in-memory bridge delivers cross-controller stream events deadlocks the
  // flutter_test binding (the DB forces real async; the render forces pump).

  test('inbound KNOCK_FWD surfaces on the listener with NO auto-ACCEPT; only '
      'an explicit pick-up sends the ACCEPT', () async {
    final env = await _TwoParty.create(sodium, aead);
    addTearDown(env.dispose);

    // Party A: the accepter/listener LinePresence mounts — plus the SAME
    // IncomingKnockController the widget attaches.
    final listener = env.accepterLauncher.build(
      env.channelId,
      role: SessionRole.accepter,
    );
    final incoming = IncomingKnockController(controller: listener);
    addTearDown(incoming.dispose);
    addTearDown(() async => listener.dispose());
    await listener.start();

    // Party B knocks; the relay forwards KNOCK_FWD to A's live listener.
    final knocker = env.knockerLauncher.build(
      env.channelId,
      role: SessionRole.knocker,
    );
    addTearDown(() async => knocker.dispose());
    await knocker.start();

    await _pumpUntil(() => incoming.knocking);

    // Surfaced as an incoming knock — and NOT auto-answered.
    expect(incoming.knocking, isTrue);
    expect(
      env.bridge.accepterSent.any((f) => f.type == FrameType.accept),
      isFalse,
      reason: 'no auto-ACCEPT — a knock waits on an explicit human pick-up',
    );
    expect(knocker.isLive, isFalse);

    // Explicit pick-up → ACCEPT.
    await incoming.pickUp();
    await _pumpUntil(
      () => env.bridge.accepterSent.any((f) => f.type == FrameType.accept),
    );
    expect(
      env.bridge.accepterSent.any((f) => f.type == FrameType.accept),
      isTrue,
      reason: 'the pick-up (never anything before it) sends the ACCEPT',
    );
  });

  testWidgets('the F6 incoming-knock view renders the label, prompt, countdown '
      'and the two verbs', (tester) async {
    widenView(tester);
    var pickedUp = false;
    var ignored = false;
    await tester.pumpWidget(
      host(
        IncomingKnockView(
          label: 'Marlowe',
          remainingSeconds: 42,
          onPickUp: () => pickedUp = true,
          onIgnore: () => ignored = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Marlowe'), findsWidgets);
    expect(find.text('Marlowe is knocking.'), findsOneWidget);
    expect(find.text('Lapses in 42s'), findsOneWidget);
    expect(find.text('Pick up'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);

    await tester.tap(find.text('Pick up'));
    expect(pickedUp, isTrue);
    await tester.tap(find.text('Ignore'));
    expect(ignored, isTrue);
  });

  // ---- reconnect phases render the three captions ---------------------------

  testWidgets('reconnect phases render the three status captions', (
    tester,
  ) async {
    widenView(tester);
    final device = TestDevice.create();
    addTearDown(device.dispose);
    late NimnaServices services;
    await tester.runAsync(() async {
      services = await device.boot();
    });
    final channelId = aead.randomBytes(16);
    await tester.runAsync(() async {
      await services.storage.channels.create(_record(sodium, aead, channelId));
    });
    late SessionController controller;
    await tester.runAsync(() async {
      controller = _launcher(
        sodium,
        aead,
        services,
        FakeRelayConnector(),
      ).build(channelId, role: SessionRole.knocker);
    });
    addTearDown(() async => controller.dispose());

    Future<void> pumpPhase(ReconnectPhase phase) async {
      await tester.pumpWidget(
        host(
          ChatScreen(
            controller: controller,
            label: 'Marlowe',
            autoStart: false,
            reconnectPhase: phase,
            screenshotDetector: _FakeDetector(),
            sensitiveAnalyzer: const NoOpSensitiveContentAnalyzer(),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpPhase(ReconnectPhase.reconnecting);
    expect(find.text('The line dropped. Trying to reconnect…'), findsOneWidget);

    await pumpPhase(ReconnectPhase.recovered);
    expect(find.text("You're both here."), findsOneWidget);

    await pumpPhase(ReconnectPhase.lost);
    expect(find.text('The line dropped.'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Waits on real wall-clock time (a non-zero poll yields the CPU so a starved
/// sqflite FFI isolate gets scheduled) — the presence_flow_test discipline.
Future<void> _pumpUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

ChannelRecord _record(SodiumSumo sodium, AtRestAead aead, Uint8List channelId) {
  final own = generateNoiseKeyPair(sodium);
  final peer = generateNoiseKeyPair(sodium);
  return ChannelRecord(
    id: channelId,
    ownStaticPrivate: own.secretKey.extractBytes(),
    ownStaticPublic: Uint8List.fromList(own.publicKey),
    peerStaticPublic: Uint8List.fromList(peer.publicKey),
    crid: aead.randomBytes(16),
    label: 'Marlowe',
    cdk: aead.randomBytes(32),
    createdAtMs: 0,
  );
}

SessionLauncher _launcher(
  SodiumSumo sodium,
  AtRestAead aead,
  NimnaServices services,
  RelayConnector connector,
) => SessionLauncher(
  sodium: sodium,
  aead: aead,
  connector: connector,
  channels: services.storage.channels,
  messages: services.storage.messages,
  media: services.storage.media,
  diag: services.diag,
  pushOptIn: PushOptIn(services.storage.channels),
  peerTokenStore: PeerTokenStore(services.storage.channels),
);

/// A controllable [ScreenshotDetector] with no platform channel.
class _FakeDetector implements ScreenshotDetector {
  final StreamController<void> _c = StreamController<void>.broadcast();
  @override
  Stream<void> get onScreenshot => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    if (!_c.isClosed) {
      await _c.close();
    }
  }
}

// ---- two-party in-memory bridge (mirrors presence_flow_test's harness) -----

class _TwoParty {
  _TwoParty({
    required this.bridge,
    required this.channelId,
    required this.accepterLauncher,
    required this.knockerLauncher,
    required this.accepterDiag,
    required this.accepterDevice,
    required this.knockerDevice,
  });

  final _Bridge bridge;
  final Uint8List channelId;
  final SessionLauncher accepterLauncher;
  final SessionLauncher knockerLauncher;
  final Diag accepterDiag;
  final TestDevice accepterDevice;
  final TestDevice knockerDevice;

  static Future<_TwoParty> create(SodiumSumo sodium, AtRestAead aead) async {
    final accepterStatic = generateNoiseKeyPair(sodium);
    final knockerStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final channelId = aead.randomBytes(16);
    final bridge = _Bridge();

    Future<(TestDevice, NimnaServices)> boot(
      NoiseKeyPair own,
      Uint8List peerPub,
    ) async {
      final device = TestDevice.create();
      final services = await device.boot();
      await services.storage.channels.create(
        ChannelRecord(
          id: channelId,
          ownStaticPrivate: own.secretKey.extractBytes(),
          ownStaticPublic: Uint8List.fromList(own.publicKey),
          peerStaticPublic: Uint8List.fromList(peerPub),
          crid: Uint8List.fromList(crid),
          label: 'peer',
          cdk: aead.randomBytes(32),
          createdAtMs: 0,
        ),
      );
      return (device, services);
    }

    final (accepterDevice, accepterServices) = await boot(
      accepterStatic,
      knockerStatic.publicKey,
    );
    final (knockerDevice, knockerServices) = await boot(
      knockerStatic,
      accepterStatic.publicKey,
    );

    SessionLauncher launcher(NimnaServices services, {required bool knocker}) =>
        SessionLauncher(
          sodium: sodium,
          aead: aead,
          connector: _BridgeConnector(bridge, knocker: knocker),
          channels: services.storage.channels,
          messages: services.storage.messages,
          media: services.storage.media,
          diag: services.diag,
          pushOptIn: PushOptIn(services.storage.channels),
          peerTokenStore: PeerTokenStore(services.storage.channels),
        );

    return _TwoParty(
      bridge: bridge,
      channelId: channelId,
      accepterLauncher: launcher(accepterServices, knocker: false),
      knockerLauncher: launcher(knockerServices, knocker: true),
      accepterDiag: accepterServices.diag,
      accepterDevice: accepterDevice,
      knockerDevice: knockerDevice,
    );
  }

  Future<void> dispose() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await accepterDevice.dispose();
    await knockerDevice.dispose();
  }
}

class _Bridge {
  _BridgeEndpoint? knockerEp;
  _BridgeEndpoint? accepterEp;
  final List<OuterFrame> knockerSent = [];
  final List<OuterFrame> accepterSent = [];

  void attach(_BridgeEndpoint ep, {required bool knocker}) {
    if (knocker) {
      knockerEp = ep;
    } else {
      accepterEp = ep;
    }
  }

  void route(_BridgeEndpoint from, OuterFrame frame) {
    final fromKnocker = identical(from, knockerEp);
    (fromKnocker ? knockerSent : accepterSent).add(frame);
    final other = fromKnocker ? accepterEp : knockerEp;
    switch (frame.type) {
      case FrameType.registerCrid:
        break;
      case FrameType.knock:
        other?.deliver(
          OuterFrame(type: FrameType.knockFwd, routingId: frame.routingId),
        );
      case FrameType.accept:
        final bridged = OuterFrame(
          type: FrameType.sessionBridged,
          routingId: frame.routingId,
        );
        knockerEp?.deliver(bridged);
        accepterEp?.deliver(bridged);
      case FrameType.sessionData:
      case FrameType.teardown:
        other?.deliver(frame);
      default:
        break;
    }
  }
}

class _BridgeConnector implements RelayConnector {
  _BridgeConnector(this._bridge, {required this.knocker});

  final _Bridge _bridge;
  final bool knocker;

  @override
  Future<RelayConnection> connect() async {
    final ep = _BridgeEndpoint(_bridge, knocker: knocker);
    _bridge.attach(ep, knocker: knocker);
    return ep;
  }
}

class _BridgeEndpoint implements RelayConnection {
  _BridgeEndpoint(this._bridge, {required this.knocker});

  final _Bridge _bridge;
  final bool knocker;
  final StreamController<OuterFrame> _inbound = StreamController<OuterFrame>();

  @override
  Stream<OuterFrame> get frames => _inbound.stream;

  @override
  void send(OuterFrame frame) => _bridge.route(this, frame);

  void deliver(OuterFrame frame) {
    if (!_inbound.isClosed) {
      _inbound.add(frame);
    }
  }

  @override
  Future<void> close() async {
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }
}
