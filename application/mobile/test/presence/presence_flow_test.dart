import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/domain/channel_repository.dart';
import 'package:nimna/src/domain/message_repository.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/presence/peer_token_store.dart';
import 'package:nimna/src/presence/push_opt_in.dart';
import 'package:nimna/src/presence/reconnect_coordinator.dart';
import 'package:nimna/src/presence/session_launcher.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:nimna/src/session/model/chat_event.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// S12 presence flows over the two-party bridge harness — knock-accept gating,
/// the offline-compose outbox (text + reactions), device-token refresh, the
/// KNOCK push payload, and bounded live-drop reconnect. Every assertion drives
/// real SessionControllers built through the launcher over an in-memory relay.
void main() {
  // Waits until [done] on a real WALL-CLOCK deadline, polling with a small
  // NON-ZERO delay. This is deliberately NOT a fixed count of
  // `Future.delayed(Duration.zero)` ticks: a zero-duration delay does not
  // yield the CPU, so on an oversubscribed host the main isolate burns the
  // whole cap near-instantly while a descheduled sqflite FFI isolate never
  // gets to commit the trailing delivery-state / persistence write — the
  // assertion then fires early (the residual flake QA caught at ~1/32). A
  // real 1 ms delay actually yields the CPU, so a starved isolate gets
  // scheduled and its write lands well before the generous deadline; a
  // healthy run resolves in a few milliseconds and never approaches it.
  Future<void> pumpUntil(
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
    }
  }

  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  // ---- offline-compose outbox --------------------------------------------

  test(
    'compose-offline → knock → accept → ordered text backlog delivers',
    () async {
      final env = await _Env.create(sodium, aead);
      addTearDown(env.dispose);

      // Knocker offline: connect fails, so start() settles to offline and the
      // composer still works (spec §3.4).
      final offline = env.knocker.launcher(_OfflineConnector());
      final composing = offline.build(
        env.knocker.channelId,
        role: SessionRole.knocker,
      );
      await composing.start();
      expect(composing.lineState, SessionLineState.offline);
      await composing.sendText('one');
      await composing.sendText('two');
      await composing.sendText('three');
      // All three wait locally in the outbox.
      expect(
        composing.messages.map((m) => m.deliveryState),
        everyElement(DeliveryState.waiting),
      );
      await composing.dispose();

      // Bring both online: a FRESH knocker (reconnect model, §3.3.1) loads the
      // 3 waiting texts and flushes them on the live transition.
      final accepter = env.accepter.build(SessionRole.accepter);
      final knocker = env.knocker.build(SessionRole.knocker);
      _autoAccept(accepter);
      await accepter.start();
      await knocker.start(
        knockPushPayload: env.knocker.launcherDefault.knockPayloadFor(
          env.knocker.channelId,
        ),
      );
      // Wait on the ACTUAL end state — all three received AND every one ACKed
      // back to `delivered` — not a fixed number of event-loop turns. Under
      // full-suite CPU load the trailing ACK round-trip can land many turns
      // later; a fixed settle() fired the assertion (and teardown) early.
      await pumpUntil(
        () =>
            accepter.messages.length == 3 &&
            knocker.messages.length == 3 &&
            knocker.messages.every(
              (m) => m.deliveryState == DeliveryState.delivered,
            ),
      );

      // The accepter received exactly the three, in seq order.
      expect(accepter.messages.map((m) => m.text).toList(), [
        'one',
        'two',
        'three',
      ]);
      // The knocker walked all three waiting → sent → delivered (peer ACKs).
      expect(
        knocker.messages.map((m) => m.deliveryState).toList(),
        everyElement(DeliveryState.delivered),
      );
    },
  );

  test('offline-composed reaction re-sends on the next bridge', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    // A live session so both ends share a referent message.
    final accepter = env.accepter.build(SessionRole.accepter);
    final knocker = env.knocker.build(SessionRole.knocker);
    _autoAccept(accepter);
    await accepter.start();
    await knocker.start();
    await pumpUntil(() => knocker.isLive);
    await knocker.sendText('the referent');
    await pumpUntil(() => accepter.messages.length == 1);
    final referent = accepter.messages.single;
    expect(referent.text, 'the referent');

    // Drop the knocker's line, then react while NOT live → the reaction rides
    // the outbox (pending marker), not the wire.
    await env.bridge.killKnocker();
    await pumpUntil(() => !knocker.isLive);
    final ownMsgId = knocker.messages.single.msgId!;
    await knocker.sendReaction(ownMsgId, '🔥');
    expect(knocker.pendingReactions, hasLength(1));

    // Reconnect = a fresh knocker seeded with the pending reaction, against a
    // fresh online accepter (both ends re-establish after a drop). On live the
    // reaction flushes and the accepter's referent gains the peer reaction.
    final pending = knocker.pendingReactions;
    await knocker.dispose();
    final freshAccepter = env.accepter.build(SessionRole.accepter);
    _autoAccept(freshAccepter);
    await freshAccepter.start();
    final fresh = env.knocker.build(
      SessionRole.knocker,
      seedPendingReactions: pending,
    );
    await fresh.start();
    await pumpUntil(
      () => fresh.isLive && freshAccepter.messages.single.peerReaction == '🔥',
    );
    expect(fresh.isLive, isTrue);
    expect(freshAccepter.messages.single.peerReaction, '🔥');
  });

  // ---- knock-accept gating (F6) ------------------------------------------

  test(
    'accepter does NOT auto-ACCEPT; explicit pick-up opens the line',
    () async {
      final env = await _Env.create(sodium, aead);
      addTearDown(env.dispose);

      final accepter = env.accepter.build(SessionRole.accepter);
      final knocker = env.knocker.build(SessionRole.knocker);
      final events = <ChatEvent>[];
      accepter.events.listen(events.add);
      await accepter.start();
      await knocker.start();
      await pumpUntil(() => accepter.incomingKnockPending);

      // The knock surfaced as an IncomingKnock — NOT auto-answered.
      expect(events.whereType<IncomingKnock>(), isNotEmpty);
      expect(accepter.incomingKnockPending, isTrue);
      expect(
        env.bridge.accepterSent.any((f) => f.type == FrameType.accept),
        isFalse,
        reason: 'no ACCEPT before an explicit pick-up',
      );
      expect(knocker.isLive, isFalse);

      // Pick up → ACCEPT → bridge → both live.
      await accepter.acceptKnock();
      await pumpUntil(() => knocker.isLive && accepter.isLive);
      expect(
        env.bridge.accepterSent.any((f) => f.type == FrameType.accept),
        isTrue,
      );
      expect(knocker.isLive, isTrue);
      expect(accepter.isLive, isTrue);
    },
  );

  test('ignore is pure silence — no ACCEPT, no wire signal', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    final accepter = env.accepter.build(SessionRole.accepter);
    final knocker = env.knocker.build(SessionRole.knocker);
    await accepter.start();
    await knocker.start();
    await pumpUntil(() => accepter.incomingKnockPending);
    expect(accepter.incomingKnockPending, isTrue);

    await accepter.ignoreKnock();
    expect(accepter.incomingKnockPending, isFalse);
    // No ACCEPT and no other frame beyond the initial REGISTER_CRID.
    expect(
      env.bridge.accepterSent.where((f) => f.type == FrameType.accept),
      isEmpty,
    );
    expect(knocker.isLive, isFalse);
  });

  // ---- device-token refresh (§5.5 / §5.7) --------------------------------

  test(
    'a peer token-refresh CONTROL is persisted (rotate then revoke)',
    () async {
      final env = await _Env.create(sodium, aead);
      addTearDown(env.dispose);

      final accepter = env.accepter.build(SessionRole.accepter);
      final knocker = env.knocker.build(SessionRole.knocker);
      _autoAccept(accepter);
      await accepter.start();
      await knocker.start();
      await pumpUntil(() => knocker.isLive);

      // Accepter rotates its token → knocker persists the present-form bytes.
      final rotated = TokenPayload.present(
        platform: PushPlatform.apns,
        token: Uint8List.fromList(utf8.encode('rotated-token')),
      );
      accepter.sendTokenRefresh(rotated);
      await pumpUntil(
        () =>
            env.knocker.channels.byId(env.knocker.channelId)!.peerDeviceToken !=
            null,
      );
      expect(
        env.knocker.channels.byId(env.knocker.channelId)!.peerDeviceToken,
        rotated.encode(),
      );

      // A subsequent KNOCK (push on) carries the rotated token (§5.4 payload).
      await env.knocker.pushOn();
      final knockPayload = env.knocker.pushOptIn.knockPayloadFor(
        env.knocker.channelId,
      );
      expect(knockPayload, rotated.encode().sublist(1));

      // Accepter revokes (absent) → knocker clears the stored token.
      accepter.sendTokenRefresh(const TokenPayload.absent());
      await pumpUntil(
        () =>
            env.knocker.channels.byId(env.knocker.channelId)!.peerDeviceToken ==
            null,
      );
      expect(
        env.knocker.channels.byId(env.knocker.channelId)!.peerDeviceToken,
        isNull,
      );
    },
  );

  // ---- KNOCK push payload -------------------------------------------------

  test('push-off = empty KNOCK payload (pure burner-line)', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    // Even with a stored peer token, push OFF ⇒ empty payload; the sent KNOCK
    // frame carries nothing.
    await env.knocker.storePeerToken(
      TokenPayload.present(
        platform: PushPlatform.fcm,
        token: Uint8List.fromList(utf8.encode('fcm-token')),
      ),
    );
    expect(env.knocker.pushOptIn.isEnabled(env.knocker.channelId), isFalse);

    final knocker = env.knocker.build(SessionRole.knocker);
    await knocker.start(
      knockPushPayload: env.knocker.pushOptIn.knockPayloadFor(
        env.knocker.channelId,
      ),
    );
    await pumpUntil(
      () => env.bridge.knockerSent.any((f) => f.type == FrameType.knock),
    );
    final knock = env.bridge.knockerSent.firstWhere(
      (f) => f.type == FrameType.knock,
    );
    expect(knock.payload, isEmpty);
  });

  test('push-on carries platform‖len‖token in the KNOCK payload', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    final token = TokenPayload.present(
      platform: PushPlatform.apns,
      token: Uint8List.fromList(utf8.encode('apns-token')),
    );
    await env.knocker.storePeerToken(token);
    await env.knocker.pushOn();

    final knocker = env.knocker.build(SessionRole.knocker);
    await knocker.start(
      knockPushPayload: env.knocker.pushOptIn.knockPayloadFor(
        env.knocker.channelId,
      ),
    );
    await pumpUntil(
      () => env.bridge.knockerSent.any((f) => f.type == FrameType.knock),
    );
    final knock = env.bridge.knockerSent.firstWhere(
      (f) => f.type == FrameType.knock,
    );
    // Present-form bytes minus the 0x01 presence byte (§5.4 KNOCK payload).
    expect(knock.payload, token.encode().sublist(1));
  });

  // ---- bounded live-drop reconnect ----------------------------------------

  test('reconnect recovers a live-session drop within the window', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    // Live, then the knocker's bridge dies.
    final accepter0 = env.accepter.build(SessionRole.accepter);
    final knocker0 = env.knocker.build(SessionRole.knocker);
    _autoAccept(accepter0);
    await accepter0.start();
    await knocker0.start();
    await pumpUntil(() => knocker0.isLive);
    expect(knocker0.isLive, isTrue);

    // A standing accepter that will pick up the re-knock.
    final coordinator = ReconnectCoordinator(
      rebuild: (seed) =>
          env.knocker.build(SessionRole.knocker, seedPendingReactions: seed),
      knockPayload: () =>
          env.knocker.launcherDefault.knockPayloadFor(env.knocker.channelId),
      diag: env.knocker.diag,
      window: const Duration(seconds: 20),
      sleeper: (d) async => env.advance(d),
      clock: env.clock,
    );
    addTearDown(coordinator.dispose);
    coordinator.adopt(knocker0);

    // A fresh online accepter for the re-knock to reach.
    final accepter1 = env.accepter.build(SessionRole.accepter);
    _autoAccept(accepter1);
    await accepter1.start();

    final phases = <ReconnectPhase>[];
    coordinator.phases.listen(phases.add);

    await env.bridge.killKnocker();
    await pumpUntil(() => coordinator.phase == ReconnectPhase.recovered);

    expect(phases, contains(ReconnectPhase.reconnecting));
    expect(phases.last, ReconnectPhase.recovered);
    expect(coordinator.controller!.isLive, isTrue);
  });

  test('reconnect exhausts to terminal loss when nobody answers', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    final accepter0 = env.accepter.build(SessionRole.accepter);
    final knocker0 = env.knocker.build(SessionRole.knocker);
    _autoAccept(accepter0);
    await accepter0.start();
    await knocker0.start();
    await pumpUntil(() => knocker0.isLive);
    expect(knocker0.isLive, isTrue);

    final coordinator = ReconnectCoordinator(
      rebuild: (seed) =>
          env.knocker.build(SessionRole.knocker, seedPendingReactions: seed),
      knockPayload: () => Uint8List(0),
      diag: env.knocker.diag,
      window: const Duration(seconds: 20),
      sleeper: (d) async => env.advance(d),
      clock: env.clock,
    );
    addTearDown(coordinator.dispose);
    coordinator.adopt(knocker0);

    final phases = <ReconnectPhase>[];
    coordinator.phases.listen(phases.add);

    // No online accepter → the re-knocks never bridge → exhaustion → lost.
    await env.bridge.killKnocker();
    await pumpUntil(() => coordinator.phase == ReconnectPhase.lost);

    expect(phases, contains(ReconnectPhase.reconnecting));
    expect(phases.last, ReconnectPhase.lost);
    expect(coordinator.controller!.isLive, isFalse);
  });

  test('a cold knock that drops before going live does NOT reconnect', () async {
    final env = await _Env.create(sodium, aead);
    addTearDown(env.dispose);

    // A knock with nobody to pick it up: the knocker reaches `waiting` and
    // never goes live (a COLD knock — never auto-retried, spec §4).
    final knocker = env.knocker.build(SessionRole.knocker);
    addTearDown(knocker.dispose);
    await knocker.start();
    await pumpUntil(() => knocker.lineState == SessionLineState.waiting);
    expect(knocker.lineState, SessionLineState.waiting);
    expect(knocker.isLive, isFalse);

    final coordinator = ReconnectCoordinator(
      rebuild: (seed) =>
          env.knocker.build(SessionRole.knocker, seedPendingReactions: seed),
      knockPayload: () => Uint8List(0),
      diag: env.knocker.diag,
      window: const Duration(seconds: 20),
      sleeper: (d) async => env.advance(d),
      clock: env.clock,
    );
    addTearDown(coordinator.dispose);
    coordinator.adopt(knocker);

    final phases = <ReconnectPhase>[];
    coordinator.phases.listen(phases.add);

    // The socket dies mid-knock → connectionLost, but the line was NEVER live.
    await env.bridge.killKnocker();
    await pumpUntil(() => knocker.lineState == SessionLineState.connectionLost);
    // Give the coordinator's listener real wall-clock time to run (it decides
    // NOT to reconnect). A real delay yields the CPU so the main isolate drains
    // the SessionEnded event; if the `_hasBeenLive` gate were removed, the
    // listener would synchronously flip the phase to `reconnecting` here.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(knocker.lineState, SessionLineState.connectionLost);
    // The cold-vs-live gate (`_hasBeenLive`) blocks recovery entirely: the
    // coordinator stays idle, emits no phase, and re-knocks nothing. (Fails if
    // `&& _hasBeenLive` is dropped from the reconnect trigger — the cold knock
    // would then be auto-retried, violating spec §4.)
    expect(coordinator.phase, ReconnectPhase.idle);
    expect(phases, isEmpty);
    expect(
      env.bridge.knockerSent.where((f) => f.type == FrameType.knock),
      hasLength(1),
      reason: 'no second KNOCK — the cold knock is never auto-retried',
    );
  });
}

// ---------------------------------------------------------------------------
// Harness: two parties (each its own device + launcher) over a rebuildable
// in-memory bridge, plus a virtual clock the reconnect sleeper advances.
// ---------------------------------------------------------------------------

class _Env {
  _Env({required this.bridge, required this.knocker, required this.accepter});

  final _Bridge bridge;
  final _Party knocker;
  final _Party accepter;

  DateTime _now = DateTime.utc(2026, 7, 7, 12);
  DateTime clock() => _now;
  void advance(Duration d) => _now = _now.add(d);

  static Future<_Env> create(SodiumSumo sodium, AtRestAead aead) async {
    final knockerStatic = generateNoiseKeyPair(sodium);
    final accepterStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final bridge = _Bridge();

    final knocker = await _Party.create(
      sodium: sodium,
      aead: aead,
      ownStatic: knockerStatic,
      peerStaticPublic: accepterStatic.publicKey,
      crid: crid,
      bridge: bridge,
      isKnocker: true,
    );
    final accepter = await _Party.create(
      sodium: sodium,
      aead: aead,
      ownStatic: accepterStatic,
      peerStaticPublic: knockerStatic.publicKey,
      crid: crid,
      bridge: bridge,
      isKnocker: false,
    );
    return _Env(bridge: bridge, knocker: knocker, accepter: accepter);
  }

  Future<void> dispose() async {
    // Drain trailing fire-and-forget persistence before the sqflite DBs close.
    // Production persists received messages, delivery-state advances, reaction
    // updates, and token refreshes via `unawaited(...)`; closing the DB while
    // one is in flight throws `database has already been closed`. Yield real
    // wall-clock time (NON-ZERO delays — a starved sqflite FFI isolate only
    // gets scheduled by real time, not by zero-duration ticks) so any
    // multi-step write progresses through its awaits, then a serialized DB read
    // per party flushes anything still queued (sqflite runs one op at a time,
    // FIFO — a read completes only behind prior writes). TEARDOWN hygiene only;
    // assertions wait on real state via `pumpUntil`.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await knocker.drainWrites();
    await accepter.drainWrites();
    await knocker.dispose();
    await accepter.dispose();
  }
}

class _Party {
  _Party({
    required this.device,
    required this.sodium,
    required this.aead,
    required this.channels,
    required this.messages,
    required this.diag,
    required this.channelId,
    required this.bridge,
    required this.isKnocker,
  }) : pushOptIn = PushOptIn(channels),
       peerTokenStore = PeerTokenStore(channels);

  final TestDevice device;
  final SodiumSumo sodium;
  final AtRestAead aead;
  final ChannelRepository channels;
  final MessageRepository messages;
  final Diag diag;
  final Uint8List channelId;
  final _Bridge bridge;
  final bool isKnocker;
  final PushOptIn pushOptIn;
  final PeerTokenStore peerTokenStore;

  /// The launcher over the live bridge connector (used by all normal builds).
  late final SessionLauncher launcherDefault = launcher(
    _BridgeConnector(bridge, knocker: isKnocker),
  );

  static Future<_Party> create({
    required SodiumSumo sodium,
    required AtRestAead aead,
    required NoiseKeyPair ownStatic,
    required Uint8List peerStaticPublic,
    required Uint8List crid,
    required _Bridge bridge,
    required bool isKnocker,
  }) async {
    final device = TestDevice.create();
    final services = await device.boot();
    final channelId = aead.randomBytes(16);
    await services.storage.channels.create(
      ChannelRecord(
        id: channelId,
        ownStaticPrivate: ownStatic.secretKey.extractBytes(),
        ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
        peerStaticPublic: Uint8List.fromList(peerStaticPublic),
        crid: Uint8List.fromList(crid),
        label: 'peer',
        cdk: aead.randomBytes(32),
        createdAtMs: 0,
      ),
    );
    return _Party(
      device: device,
      sodium: sodium,
      aead: aead,
      channels: services.storage.channels,
      messages: services.storage.messages,
      diag: services.diag,
      channelId: channelId,
      bridge: bridge,
      isKnocker: isKnocker,
    );
  }

  SessionLauncher launcher(RelayConnector connector) => SessionLauncher(
    sodium: sodium,
    aead: aead,
    connector: connector,
    channels: channels,
    messages: messages,
    diag: diag,
    pushOptIn: pushOptIn,
    peerTokenStore: peerTokenStore,
  );

  SessionController build(
    SessionRole role, {
    List<PendingReaction> seedPendingReactions = const [],
  }) => launcherDefault.build(
    channelId,
    role: role,
    seedPendingReactions: seedPendingReactions,
  );

  Future<void> pushOn() => pushOptIn.setEnabled(channelId, enabled: true);

  Future<void> storePeerToken(TokenPayload token) =>
      peerTokenStore.onPeerTokenRefresh(channelId, token);

  /// Flushes this party's DB op queue: a serialized read completes only behind
  /// every write enqueued before it (sqflite runs one op at a time), so any
  /// fire-and-forget append/update/persist has committed once this returns.
  Future<void> drainWrites() async {
    await messages.byChannel(channelId);
  }

  Future<void> dispose() => device.dispose();
}

/// Auto-answers an incoming knock (a standing, online accepter).
void _autoAccept(SessionController accepter) {
  accepter.events.listen((event) {
    if (event is IncomingKnock) {
      unawaited(accepter.acceptKnock());
    }
  });
}

/// In-memory relay bridging two CRID endpoints; supports RE-connection (a
/// fresh controller replaces its role's endpoint).
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

  Future<void> killKnocker() async => knockerEp?.kill();
  Future<void> killAccepter() async => accepterEp?.kill();
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

  Future<void> kill() async {
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }

  @override
  Future<void> close() async {
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }
}

/// A connector that always fails — the offline-compose case (§3.4).
class _OfflineConnector implements RelayConnector {
  @override
  Future<RelayConnection> connect() async => throw RelayUnreachableError();
}
