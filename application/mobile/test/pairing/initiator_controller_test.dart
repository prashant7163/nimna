import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/pairing/initiator/initiator_controller.dart';
import 'package:nimna/src/pairing/initiator/pending_pairing.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/pairing_code.dart';
import 'package:nimna/src/protocol/rendezvous.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// The initiator state machine over an in-memory fake relay:
/// create → register → bridged → hold (PAIR_DATA buffered opaquely);
/// offline edge; disconnect → polite re-register (no retry storm); TTL
/// expiry live and discovered-on-resume; cancel discards; bridged drop is
/// fail-closed (spent).
void main() {
  late TestDevice device;
  late NimnaServices services;
  late FakeRelayConnector connector;
  late DateTime now;

  setUp(() async {
    device = TestDevice.create();
    connector = FakeRelayConnector();
    now = DateTime.utc(2026, 7, 7, 10);
    services = await device.boot();
  });

  tearDown(() => device.dispose());

  Future<CreateLineController> makeController({
    Duration grace = const Duration(seconds: 30),
  }) async {
    final controller = CreateLineController(
      sodium: await testSodium(),
      connector: connector,
      store: PendingPairingStore(
        storage: services.storage,
        sodium: await testSodium(),
      ),
      diag: services.diag,
      clock: () => now,
      backgroundGrace: grace,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Waits until stream events delivered via the fake settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Polls until [condition] holds (async discard paths run through the
  /// real store).
  Future<void> waitUntil(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  test('create: connect → generate → derive → register → persist', () async {
    final controller = await makeController();
    expect(controller.phase, CreateLinePhase.setup);

    expect(await controller.createCode(), isTrue);
    expect(controller.phase, CreateLinePhase.waiting);
    expect(controller.offline, isFalse);

    final code = controller.code!;
    expect(
      code.display,
      matches(RegExp(r'^[0-9A-Z]{3}-[0-9A-Z]{3}-[0-9A-Z]{3}$')),
    );

    // Exactly one REGISTER_TOPIC with the derived topic, nothing else.
    final conn = connector.latest;
    expect(conn.sent, hasLength(1));
    expect(conn.sent.single.type, FrameType.registerTopic);
    final secrets = deriveRendezvous(
      sodium: await testSodium(),
      code: code,
      utcDate: utcDateString(now),
    );
    addTearDown(secrets.dispose);
    expect(conn.sent.single.routingId, secrets.topic);
    expect(conn.sent.single.payload, isEmpty);

    // Persisted for restart-resume and the self-join guard.
    final entries = await PendingPairingStore(
      storage: services.storage,
      sodium: await testSodium(),
    ).readAll();
    expect(entries.single.code, code);
    expect(entries.single.ttl, defaultTtl);
    for (final e in entries) {
      e.dispose();
    }
  });

  test('offline edge: nothing generated, no phantom code', () async {
    connector.failNextAttempts = 1;
    final controller = await makeController();
    expect(await controller.createCode(), isFalse);
    expect(controller.phase, CreateLinePhase.setup);
    expect(controller.offline, isTrue);
    expect(controller.code, isNull);
    expect(
      await PendingPairingStore(
        storage: services.storage,
        sodium: await testSodium(),
      ).readAll(),
      isEmpty,
    );
    // Retry after connectivity returns succeeds from the same setup phase.
    expect(await controller.createCode(), isTrue);
    expect(controller.offline, isFalse);
  });

  test(
    'TOPIC_BRIDGED on OUR topic → hold; PAIR_DATA buffered opaquely',
    () async {
      final controller = await makeController();
      await controller.createCode();
      final conn = connector.latest;
      final topic = conn.sent.single.routingId;

      // A bridge on a FOREIGN topic is dropped.
      conn.deliver(
        OuterFrame(type: FrameType.topicBridged, routingId: Uint8List(16)),
      );
      await settle();
      expect(controller.phase, CreateLinePhase.waiting);

      conn.deliver(OuterFrame(type: FrameType.topicBridged, routingId: topic));
      await settle();
      expect(controller.phase, CreateLinePhase.bridged);

      // Opaque M1-style bytes are buffered in order; S8 never replies.
      final m1 = Uint8List.fromList(List.generate(80, (i) => i));
      final m3 = Uint8List.fromList(List.generate(48, (i) => 200 - i));
      conn.deliver(
        OuterFrame(type: FrameType.pairData, routingId: topic, payload: m1),
      );
      conn.deliver(
        OuterFrame(type: FrameType.pairData, routingId: topic, payload: m3),
      );
      await settle();
      expect(controller.pairDataFrames, [m1, m3]);
      expect(
        conn.sent,
        hasLength(1),
        reason: 'the app must not fabricate replies',
      );
      expect(controller.secrets, isNotNull, reason: 'psk held for S9');
      expect(
        controller.pending,
        isNotNull,
        reason: 'static keypair held for S9',
      );
    },
  );

  test(
    'drop while waiting → backoff re-register, never a tight loop',
    () async {
      final controller = await makeController();
      await controller.createCode();
      final first = connector.latest;
      final topic = first.sent.single.routingId;

      await first.drop();
      await settle();
      expect(controller.phase, CreateLinePhase.waiting);
      expect(connector.attempts, 1, reason: 'no immediate reconnect');

      // First backoff step is 2 s: nothing at +1 s, reconnected by +2.5 s.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(connector.attempts, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(connector.attempts, 2);
      final second = connector.latest;
      expect(second.sent.single.type, FrameType.registerTopic);
      expect(
        second.sent.single.routingId,
        topic,
        reason: 'same topic re-registered',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('TTL expiry while open: discard, no residue, F2.8 state', () async {
    final controller = await makeController();
    await controller.createCode();
    final conn = connector.latest;

    now = now.add(const Duration(hours: 24, minutes: 1));
    await controller.checkExpiryNow();

    expect(controller.phase, CreateLinePhase.expired);
    expect(controller.code, isNull);
    expect(controller.secrets, isNull);
    expect(conn.closedByClient, isTrue, reason: 'stop re-registering');
    expect(
      await PendingPairingStore(
        storage: services.storage,
        sodium: await testSodium(),
      ).readAll(),
      isEmpty,
    );
  });

  test(
    'resume within TTL re-registers the ORIGINAL creation-date topic',
    () async {
      // Created yesterday 23:00 UTC; resumed today: the creator derives with
      // its code-creation date (spec §3.1.2), never today's.
      final sodium = await testSodium();
      final store = PendingPairingStore(
        storage: services.storage,
        sodium: sodium,
      );
      final keyPair = sodium.crypto.box.keyPair();
      final code = PairingCode.canonicalize('7Q2M4K9XV')!;
      final createdAt = DateTime.utc(2026, 7, 6, 23);
      final entry = PendingPairing(
        code: code,
        utcDate: '2026-07-06',
        ttl: const Duration(hours: 24),
        createdAt: createdAt,
        publicKey: keyPair.publicKey,
        secretKey: keyPair.secretKey,
      );
      await store.add(entry);

      final controller = await makeController();
      now = DateTime.utc(2026, 7, 7, 10);
      final reloaded = await store.readAll();
      await controller.resume(reloaded.single);

      expect(controller.phase, CreateLinePhase.waiting);
      final expected = deriveRendezvous(
        sodium: sodium,
        code: code,
        utcDate: '2026-07-06',
      );
      addTearDown(expected.dispose);
      expect(connector.latest.sent.single.routingId, expected.topic);
      entry.dispose();
    },
  );

  test('resume after lapse-while-away: straight to expired, erased', () async {
    final sodium = await testSodium();
    final store = PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    );
    final keyPair = sodium.crypto.box.keyPair();
    final entry = PendingPairing(
      code: PairingCode.canonicalize('7Q2M4K9XV')!,
      utcDate: '2026-07-01',
      ttl: const Duration(hours: 1),
      createdAt: DateTime.utc(2026, 7, 1, 8),
      publicKey: keyPair.publicKey,
      secretKey: keyPair.secretKey,
    );
    await store.add(entry);

    final controller = await makeController();
    final reloaded = await store.readAll();
    await controller.resume(reloaded.single);

    expect(controller.phase, CreateLinePhase.expired);
    expect(connector.attempts, 0, reason: 'a dead code is never registered');
    expect(await store.readAll(), isEmpty);
    entry.dispose();
  });

  test('cancel: discard; the joiner gets silence (topic dies with the '
      'registration, nothing else is sent)', () async {
    final controller = await makeController();
    await controller.createCode();
    final conn = connector.latest;

    await controller.cancel();
    expect(controller.phase, CreateLinePhase.cancelled);
    expect(conn.closedByClient, isTrue);
    expect(conn.sent, hasLength(1), reason: 'no teardown chatter — silence');
    expect(
      await PendingPairingStore(
        storage: services.storage,
        sodium: await testSodium(),
      ).readAll(),
      isEmpty,
    );
  });

  test(
    'bridge lost before the handshake finishes → spent (fail-closed)',
    () async {
      final controller = await makeController();
      await controller.createCode();
      final conn = connector.latest;
      conn.deliver(
        OuterFrame(
          type: FrameType.topicBridged,
          routingId: conn.sent.single.routingId,
        ),
      );
      await settle();
      expect(controller.phase, CreateLinePhase.bridged);

      await conn.drop();
      await waitUntil(() => controller.phase == CreateLinePhase.spent);
      expect(controller.code, isNull);
      expect(
        await PendingPairingStore(
          storage: services.storage,
          sodium: await testSodium(),
        ).readAll(),
        isEmpty,
        reason: 'spec §3.1.6: the code dies with the failed handshake window',
      );
    },
  );

  test('background grace: socket held ~grace then closed; resume '
      're-registers', () async {
    final controller = await makeController(
      grace: const Duration(milliseconds: 100),
    );
    await controller.createCode();
    final conn = connector.latest;

    controller.onAppPaused();
    expect(conn.closedByClient, isFalse, reason: 'held through the grace');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(conn.closedByClient, isTrue, reason: 'listening STOPS after grace');
    expect(controller.phase, CreateLinePhase.waiting);

    controller.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connector.attempts, 2, reason: 'one polite re-register on resume');
    expect(connector.latest.sent.single.type, FrameType.registerTopic);
  });

  test('diag never contains code/topic/key material (events only)', () async {
    final controller = await makeController();
    await controller.createCode();
    final events = services.diag.readAll().map((r) => r.event).toList();
    expect(events, contains(DiagEvent.pairingCodeCreated));
    expect(events, contains(DiagEvent.pairingTopicRegistered));
    // The Diag API is structurally string-free; the standing marker audit
    // (test/privacy) covers the byte-level absence guarantee.
  });
}
