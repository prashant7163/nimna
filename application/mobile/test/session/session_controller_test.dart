import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:nimna/src/session/model/chat_event.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// SessionController — the live text path (S10). Two real controllers run a
/// full §3.3.1 KK handshake over an in-memory bridge relay and exchange real
/// transport traffic; every assertion below drives the actual send/receive
/// loop, delivery FSM, §5.8 reaction/reply rules, typing, HANGUP, and the
/// protocol-error kill path.
/// Waits until [done] on a real WALL-CLOCK deadline, polling with a small
/// NON-ZERO delay. Deliberately NOT a fixed count of `Future.delayed(Duration
/// .zero)` ticks: a zero-duration delay does not yield the CPU, so on an
/// oversubscribed host the main isolate burns the whole cap near-instantly
/// while a descheduled sqflite FFI isolate never gets to commit the trailing
/// write — the wait then completes before the state is ready and the test
/// proceeds into a half-established session (the flake QA caught at ~1/45 in
/// `establish`). A real 1 ms delay actually yields; a healthy run resolves in
/// a few ms and never approaches the deadline. Mirrors `presence_flow_test`.
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

void main() {
  // A bounded settle for waits with no single observable condition. Uses a
  // real (non-zero) delay so a descheduled sqflite FFI isolate is actually
  // scheduled under host load — see pumpUntil's rationale.
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  Future<_Session> liveSession() async => _Session.establish(sodium, aead);

  test('full round trip: delivery FSM waiting → sent → delivered', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final events = <ChatEvent>[];
    s.knocker.controller.events.listen(events.add);

    await s.knocker.controller.sendText('Just did. On the line now.');
    await settle();

    // The accepter received it.
    expect(s.accepter.controller.messages, hasLength(1));
    expect(
      s.accepter.controller.messages.single.text,
      'Just did. On the line now.',
    );
    expect(s.accepter.controller.messages.single.outbound, isFalse);

    // The knocker walked waiting → sent → delivered (the peer ACKed).
    final states = events
        .whereType<DeliveryChanged>()
        .map((e) => e.state)
        .toList();
    expect(states, [DeliveryState.sent, DeliveryState.delivered]);
    expect(
      s.knocker.controller.messages.single.deliveryState,
      DeliveryState.delivered,
    );
  });

  test('typing send/recv: CONTROL 0x01 → PeerTyping, silent', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final events = <ChatEvent>[];
    s.accepter.controller.events.listen(events.add);

    s.knocker.controller.setTyping();
    await settle();

    expect(events.whereType<PeerTyping>(), isNotEmpty);
    expect(s.accepter.controller.peerTyping, isTrue);
    // Typing never becomes a message (no text string, USER 2026-07-07).
    expect(s.accepter.controller.messages, isEmpty);
  });

  test('screenshot round trip: CONTROL 0x03 → peer system line, own recorded '
      '(S14, spec §5.2)', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    // Give both sides a message so the notice anchors to a real record.
    await s.knocker.controller.sendText('Here it is.');
    await settle();

    final peerEvents = <ChatEvent>[];
    s.accepter.controller.events.listen(peerEvents.add);
    final ownEvents = <ChatEvent>[];
    s.knocker.controller.events.listen(ownEvents.add);

    // The knocker took a screenshot while content was on screen.
    s.knocker.controller.noticeLocalScreenshot();
    await settle();

    // Own side recorded exactly one own-notice, anchored after the last record.
    expect(s.knocker.controller.screenshotNotices, hasLength(1));
    final own = s.knocker.controller.screenshotNotices.single;
    expect(own.own, isTrue);
    expect(own.anchorRecordId, s.knocker.controller.messages.single.recordId);
    expect(ownEvents.whereType<ScreenshotNoticed>().single.own, isTrue);

    // The peer received exactly one peer-notice (own == false) — the bare
    // "They took a screenshot." system line; never a message.
    expect(s.accepter.controller.screenshotNotices, hasLength(1));
    expect(s.accepter.controller.screenshotNotices.single.own, isFalse);
    expect(peerEvents.whereType<ScreenshotNoticed>().single.own, isFalse);
    // A screenshot notice is never speech: the thread still holds one message.
    expect(s.accepter.controller.messages, hasLength(1));
  });

  test(
    'screenshot notice is a no-op when the line is not live (S14)',
    () async {
      final s = await liveSession();
      addTearDown(s.dispose);

      // Hang up → not live. A subsequent detection must seal nothing and record
      // nothing (spec §5.2: fires only while content is on screen inside a live
      // session).
      await s.knocker.controller.hangup();
      await settle();

      s.knocker.controller.noticeLocalScreenshot();
      await settle();

      expect(s.knocker.controller.screenshotNotices, isEmpty);
    },
  );

  test('reaction round trip sets the peer slot; never ACKed', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    await s.knocker.controller.sendText('Long. Tell you tonight.');
    await settle();
    final referent = s.accepter.controller.messages.single;

    await s.accepter.controller.sendReaction(referent.msgId!, '👍');
    await settle();

    // The knocker sees the peer's reaction on its own message.
    expect(s.knocker.controller.messages.single.peerReaction, '👍');
    // A reaction is never a message and never ACKed: still one message total.
    expect(s.knocker.controller.messages, hasLength(1));
    expect(s.accepter.controller.messages, hasLength(1));
  });

  test('reaction on an unknown referent is SILENTLY dropped', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final events = <ChatEvent>[];
    s.accepter.controller.events.listen(events.add);

    // Knocker reacts to a msg_id the accepter never saw.
    await s.knocker.controller.sendReaction(aead.randomBytes(16), '🔥');
    await settle();

    // No error, no notice, no change anywhere.
    expect(events.whereType<ReactionArrived>(), isEmpty);
    expect(s.accepter.controller.lineState, SessionLineState.live);
    expect(s.knocker.controller.lineState, SessionLineState.live);
  });

  test('reaction on an expired referent is SILENTLY dropped', () async {
    // Frozen clock so the referent is already past its purge deadline.
    var now = DateTime.utc(2026, 7, 7, 12);
    final s = await _Session.establish(sodium, aead, clock: () => now);
    addTearDown(s.dispose);

    // A disappearing message read 2 min ago with a 60 s timer is expired.
    await s.knocker.controller.sendText('gone soon', expirySeconds: 60);
    await settle();
    final referent = s.accepter.controller.messages.single;
    now = now.add(const Duration(minutes: 2));

    final events = <ChatEvent>[];
    s.accepter.controller.events.listen(events.add);
    await s.knocker.controller.sendReaction(referent.msgId!, '👍');
    await settle();

    expect(events.whereType<ReactionArrived>(), isEmpty);
  });

  test('reply resolves a present referent from the LOCAL copy', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    await s.knocker.controller.sendText('the original');
    await settle();
    final referent = s.accepter.controller.messages.single;

    await s.accepter.controller.sendReply('a reply', referent.msgId!);
    await settle();

    // The knocker holds the referent locally → the quote resolves to it.
    final reply = s.knocker.controller.messages.last;
    expect(reply.text, 'a reply');
    expect(reply.reply, isNotNull);
    expect(reply.reply!.tombstone, isFalse);
    expect(reply.reply!.excerpt, 'the original');
  });

  test('reply to an unknown referent renders the neutral tombstone', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    // Reply naming a msg_id the accepter never held.
    await s.knocker.controller.sendReply('orphan reply', aead.randomBytes(16));
    await settle();

    final reply = s.accepter.controller.messages.single;
    expect(reply.text, 'orphan reply'); // The reply itself still displays.
    expect(reply.reply, isNotNull);
    expect(reply.reply!.tombstone, isTrue); // Never says why.
  });

  test('a HANGUP ends BOTH sides as "ended" (not connection lost)', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final knEvents = <ChatEvent>[];
    final acEvents = <ChatEvent>[];
    s.knocker.controller.events.listen(knEvents.add);
    s.accepter.controller.events.listen(acEvents.add);

    await s.knocker.controller.hangup();
    await settle();

    expect(s.knocker.controller.lineState, SessionLineState.endedByYou);
    expect(s.accepter.controller.lineState, SessionLineState.endedByPeer);
    for (final events in [knEvents, acEvents]) {
      final ended = events.whereType<SessionEnded>().toList();
      expect(ended, isNotEmpty);
      expect(ended.last.reason, SessionEndReason.ended);
    }
    // A relay TEARDOWN was sent (spec §3.3).
    expect(
      s.bridge.knockerSent.any((f) => f.type == FrameType.teardown),
      isTrue,
    );
  });

  test('a bridge dying without HANGUP is "connection lost"', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final events = <ChatEvent>[];
    s.knocker.controller.events.listen(events.add);

    await s.bridge.killKnocker(); // The socket dies with no HANGUP.
    await settle();

    expect(s.knocker.controller.lineState, SessionLineState.connectionLost);
    final ended = events.whereType<SessionEnded>().toList();
    expect(ended.single.reason, SessionEndReason.connectionLost);
  });

  test('a tampered transport frame kills the session (§3.3.1)', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    final events = <ChatEvent>[];
    s.accepter.controller.events.listen(events.add);

    // A garbage SESSION_DATA frame: the AEAD fails, the receive key is
    // destroyed, and the whole session dies — TEARDOWN + connection lost.
    s.bridge.deliverToAccepter(
      OuterFrame(
        type: FrameType.sessionData,
        routingId: s.crid,
        payload: aead.randomBytes(64),
      ),
    );
    await settle();

    expect(s.accepter.controller.lineState, SessionLineState.connectionLost);
    expect(
      events.whereType<SessionEnded>().single.reason,
      SessionEndReason.connectionLost,
    );
    expect(s.accepter.controller.isLive, isFalse);
    expect(
      s.bridge.accepterSent.any((f) => f.type == FrameType.teardown),
      isTrue,
    );
  });

  test(
    'an inbound TEXT with a non-UTF-8 body kills the session (§3.3.1)',
    () async {
      final s = await liveSession();
      addTearDown(s.dispose);

      final events = <ChatEvent>[];
      s.accepter.controller.events.listen(events.add);

      // A transport-valid, envelope-valid TEXT whose body is a lone 0x80 —
      // the codec deliberately does NOT validate TEXT bodies as UTF-8 (it
      // mirrors the Go stack), so this seals + decrypts + decodes cleanly and
      // only fails when the session tries to read the text. Per §3.3.1 that
      // malformed frame must fail CLOSED, not open.
      final env = InnerEnvelope(
        type: InnerType.text,
        msgId: aead.randomBytes(msgIdBytes),
        timestampMs: 0,
        body: Uint8List.fromList([0x80]),
      );
      expect(s.knocker.controller.sealForTest(env), isTrue);
      await settle();

      // The session died: keys destroyed, TEARDOWN sent, connection LOST
      // (never "ended" — the peer authenticated no end).
      expect(s.accepter.controller.isLive, isFalse);
      expect(s.accepter.controller.lineState, SessionLineState.connectionLost);
      expect(
        events.whereType<SessionEnded>().single.reason,
        SessionEndReason.connectionLost,
      );
      expect(
        s.bridge.accepterSent.any((f) => f.type == FrameType.teardown),
        isTrue,
      );
      // The malformed TEXT never became a message.
      expect(s.accepter.controller.messages, isEmpty);
    },
  );

  test(
    'a disappearing message mirrors purge_at into the plaintext column',
    () async {
      var now = DateTime.utc(2026, 7, 7, 12);
      final s = await _Session.establish(sodium, aead, clock: () => now);
      addTearDown(s.dispose);

      await s.knocker.controller.sendText('bye', expirySeconds: 900);
      await settle();

      // The received copy computed its own purge deadline from read_at.
      final view = s.accepter.controller.messages.single;
      expect(view.expirySeconds, 900);
      expect(view.purgeAtMs, now.millisecondsSinceEpoch + 900 * 1000);
    },
  );

  test('local delete drops the message from the thread', () async {
    final s = await liveSession();
    addTearDown(s.dispose);

    await s.knocker.controller.sendText('regret');
    await settle();
    final id = s.knocker.controller.messages.single.recordId;

    await s.knocker.controller.deleteMessage(id);
    expect(s.knocker.controller.messages, isEmpty);
  });
}

// ---------------------------------------------------------------------------
// Two-party test harness: a bridge relay + two live SessionControllers.
// ---------------------------------------------------------------------------

class _Session {
  _Session({
    required this.bridge,
    required this.knocker,
    required this.accepter,
    required this.crid,
  });

  final _BridgeRelay bridge;
  final _Party knocker;
  final _Party accepter;
  final Uint8List crid;

  static Future<_Session> establish(
    SodiumSumo sodium,
    AtRestAead aead, {
    DateTime Function()? clock,
  }) async {
    final knockerStatic = generateNoiseKeyPair(sodium);
    final accepterStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final bridge = _BridgeRelay();

    final knocker = await _Party.create(
      sodium: sodium,
      aead: aead,
      role: SessionRole.knocker,
      ownStatic: knockerStatic,
      peerStaticPublic: accepterStatic.publicKey,
      crid: crid,
      connector: _BridgeConnector(bridge, knocker: true),
      clock: clock,
    );
    final accepter = await _Party.create(
      sodium: sodium,
      aead: aead,
      role: SessionRole.accepter,
      ownStatic: accepterStatic,
      peerStaticPublic: knockerStatic.publicKey,
      crid: crid,
      connector: _BridgeConnector(bridge, knocker: false),
      clock: clock,
    );

    // Accepter registers/listens first, then the knocker knocks. S12: the
    // accepter no longer auto-ACCEPTs (knock-accept gating) — it surfaces an
    // IncomingKnock and waits for an explicit pick-up. Answer it, then the
    // relay bridges and both run S1/S2.
    await accepter.controller.start();
    await knocker.controller.start();
    // Condition waits, not fixed ticks: wait for the forwarded knock to
    // actually surface before answering it, then for BOTH sides to reach the
    // live KK session before the test body sends any traffic. An under-wait
    // here dispatched a frame into a not-yet-live controller and threw in
    // _dispatchInbound under load (the ~1/45 flake).
    await pumpUntil(() => accepter.controller.incomingKnockPending);
    await accepter.controller.acceptKnock();
    await pumpUntil(
      () => knocker.controller.isLive && accepter.controller.isLive,
    );
    return _Session(
      bridge: bridge,
      knocker: knocker,
      accepter: accepter,
      crid: crid,
    );
  }

  Future<void> dispose() async {
    await knocker.dispose();
    await accepter.dispose();
  }
}

class _Party {
  _Party({required this.device, required this.controller});

  final TestDevice device;
  final SessionController controller;

  static Future<_Party> create({
    required SodiumSumo sodium,
    required AtRestAead aead,
    required SessionRole role,
    required NoiseKeyPair ownStatic,
    required Uint8List peerStaticPublic,
    required Uint8List crid,
    required RelayConnector connector,
    DateTime Function()? clock,
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
    final controller = SessionController(
      sodium: sodium,
      aead: aead,
      connector: connector,
      messages: services.storage.messages,
      channelId: channelId,
      ownStatic: ownStatic,
      peerStaticPublic: peerStaticPublic,
      crid: crid,
      role: role,
      diag: Diag(aead: aead),
      clock: clock,
    );
    return _Party(device: device, controller: controller);
  }

  Future<void> dispose() async {
    await controller.dispose();
    await device.dispose();
  }
}

/// An in-memory relay that bridges exactly two endpoints by CRID and forwards
/// frames per §5.4 semantics (KNOCK → KNOCK_FWD, ACCEPT → SESSION_BRIDGED to
/// both, SESSION_DATA/TEARDOWN → the peer).
class _BridgeRelay {
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
        break; // Registration noted implicitly by attach.
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

  void deliverToAccepter(OuterFrame frame) => accepterEp?.deliver(frame);
  void deliverToKnocker(OuterFrame frame) => knockerEp?.deliver(frame);

  Future<void> killKnocker() async => knockerEp?.kill();
  Future<void> killAccepter() async => accepterEp?.kill();
}

class _BridgeConnector implements RelayConnector {
  _BridgeConnector(this._bridge, {required this.knocker});

  final _BridgeRelay _bridge;
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

  final _BridgeRelay _bridge;
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
