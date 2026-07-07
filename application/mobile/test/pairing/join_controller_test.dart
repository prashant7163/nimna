import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/xxpsk2.dart';
import 'package:nimna/src/pairing/initiator/pending_pairing.dart';
import 'package:nimna/src/pairing/joiner/join_controller.dart';
import 'package:nimna/src/protocol/channel_identity.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/pairing_code.dart';
import 'package:nimna/src/protocol/rendezvous.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// The joiner state machine (F3) over an in-memory fake relay, driven end to
/// end against a REAL from-spec responder engine sharing the reduced-cost
/// Argon2id psk: entry → today+yesterday registration → XXpsk2 handshake →
/// safety phrase (identical on both ends) → match → name → persisted; plus
/// the self-join guard, the no-answer timeout (silence doctrine), the
/// fail-closed spent path, and the local-only mismatch discard (no wire
/// signal, nothing persisted).
void main() {
  late TestDevice device;
  late NimnaServices services;
  late FakeRelayConnector connector;
  late SodiumSumo sodium;
  late AtRestAead aead;
  late DateTime now;
  late List<String> wordlist;

  setUp(() async {
    device = TestDevice.create();
    connector = FakeRelayConnector();
    now = DateTime.utc(2026, 7, 7, 10);
    services = await device.boot();
    sodium = await testSodium();
    aead = AtRestAead(sodium);
    wordlist = File(
      '../../docs/test-vectors/wordlist-en-v1.txt',
    ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
  });

  tearDown(() => device.dispose());

  PendingPairingStore store() =>
      PendingPairingStore(storage: services.storage, sodium: sodium);

  JoinController makeController({
    Duration noAnswer = const Duration(seconds: 30),
  }) {
    final controller = JoinController(
      sodium: sodium,
      aead: aead,
      storage: services.storage,
      pendingStore: store(),
      connector: connector,
      diag: services.diag,
      clock: () => now,
      cost: Argon2Cost.reducedTestOnly,
      noAnswerTimeout: noAnswer,
      wordlistLoader: () async => wordlist,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> waitUntil(bool Function() cond) async {
    for (var i = 0; i < 200 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(cond(), isTrue);
  }

  List<OuterFrame> pairFrames(FakeRelayConnection c) =>
      c.sent.where((f) => f.type == FrameType.pairData).toList();

  test('four-way funnel: join drives the full handshake to a persisted '
      'channel; both ends derive the same safety phrase', () async {
    final controller = makeController();
    final code = PairingCode.canonicalize('7Q2M4K9XV')!;
    final today = utcDateString(now);
    final todaySecrets = deriveRendezvous(
      sodium: sodium,
      code: code,
      utcDate: today,
      cost: Argon2Cost.reducedTestOnly,
    );
    addTearDown(todaySecrets.dispose);

    await controller.join(code);
    final conn = connector.latest;

    // Two topics registered (today + yesterday), two Argon2id derivations.
    final registers = conn.sent
        .where((f) => f.type == FrameType.registerTopic)
        .toList();
    expect(registers, hasLength(2));
    expect(
      registers.map((f) => bytesToHex(f.routingId)),
      contains(bytesToHex(todaySecrets.topic)),
    );

    // The creator's responder engine, sharing today's psk.
    final creatorStatic = generateNoiseKeyPair(sodium);
    final creatorToken = TokenPayload.present(
      platform: PushPlatform.apns,
      token: Uint8List.fromList('apns-token'.codeUnits),
    );
    final responder = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: creatorStatic,
      psk: todaySecrets.psk,
      tokenPayload: creatorToken,
    );
    addTearDown(() {
      creatorStatic.dispose();
      responder.dispose();
    });

    // Bridge today's topic → the joiner sends M1.
    conn.deliver(
      OuterFrame(type: FrameType.topicBridged, routingId: todaySecrets.topic),
    );
    await settle();
    expect(pairFrames(conn), hasLength(1)); // M1
    responder.readM1(pairFrames(conn).single.payload);

    // M2 → the joiner sends M3.
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
        payload: responder.writeM2(),
      ),
    );
    await settle();
    expect(pairFrames(conn), hasLength(2)); // M1, M3
    responder.readM3(pairFrames(conn)[1].payload);

    // M4 → the joiner finalizes to the safety-phrase screen.
    final header = Uint8List.sublistView(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
      ).encode(),
      0,
      outerHeaderBytes,
    );
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
        payload: responder.writeM4(header),
      ),
    );
    await waitUntil(() => controller.phase == JoinPhase.verify);

    final creatorMat = responder.finalizeChannel();
    addTearDown(creatorMat.disposeSecret);
    final creatorWords = safetyPhraseWords(
      ss: creatorMat.ss,
      aPublic: creatorStatic.publicKey,
      bPublic: creatorMat.peerStaticPublic,
      wordlist: wordlist,
    );
    expect(controller.safetyPhrase, hasLength(3));
    expect(controller.safetyPhrase, creatorWords);

    // "They match" → name → Done persists (the SOLE persistence point).
    expect(services.storage.channels.all, isEmpty);
    controller.confirmMatch();
    expect(controller.phase, JoinPhase.naming);
    await controller.finish('Attic');
    expect(controller.phase, JoinPhase.done);

    final channels = services.storage.channels.all;
    expect(channels, hasLength(1));
    expect(channels.single.label, 'Attic');
    expect(channels.single.crid, creatorMat.crid);
    expect(channels.single.peerStaticPublic, creatorStatic.publicKey);
    // The peer's device-token rode the handshake and is stored (§3.2.1).
    expect(channels.single.peerDeviceToken, isNotNull);
    expect(channels.single.peerDeviceToken, creatorToken.token);
  });

  test('self-join guard: own OUTSTANDING code blocks Join; a foreign code '
      'does not', () async {
    final controller = makeController();
    final ownCode = PairingCode.canonicalize('7Q2M4K9XV')!;
    final keyPair = sodium.crypto.box.keyPair();
    await store().add(
      PendingPairing(
        code: ownCode,
        utcDate: utcDateString(now),
        ttl: const Duration(hours: 24),
        createdAt: now,
        publicKey: keyPair.publicKey,
        secretKey: keyPair.secretKey,
      ),
    );

    expect(await controller.checkSelfJoin(ownCode), isTrue);
    expect(controller.selfJoinBlocked, isTrue);

    // Join is a no-op while blocked — nothing reaches the relay.
    await controller.join(ownCode);
    expect(connector.attempts, 0);
    expect(controller.phase, JoinPhase.entry);

    // A different code is not the device's own.
    expect(
      await controller.checkSelfJoin(PairingCode.canonicalize('3F8P7RWT2')!),
      isFalse,
    );
    expect(controller.selfJoinBlocked, isFalse);
  });

  test('no-answer timeout: the one generic response after the joiner waits '
      '(silence doctrine)', () async {
    final controller = makeController(
      noAnswer: const Duration(milliseconds: 60),
    );
    await controller.join(PairingCode.canonicalize('7Q2M4K9XV')!);
    expect(controller.phase, JoinPhase.joining);
    await waitUntil(() => controller.phase == JoinPhase.entry);
    expect(controller.entryError, JoinEntryError.noMatch);
    expect(connector.latest.closedByClient, isTrue);
  });

  test('mismatch decline = local-only silent discard: nothing persisted, no '
      'wire signal', () async {
    final controller = makeController();
    final code = PairingCode.canonicalize('7Q2M4K9XV')!;
    final todaySecrets = deriveRendezvous(
      sodium: sodium,
      code: code,
      utcDate: utcDateString(now),
      cost: Argon2Cost.reducedTestOnly,
    );
    addTearDown(todaySecrets.dispose);

    await controller.join(code);
    final conn = connector.latest;
    final creatorStatic = generateNoiseKeyPair(sodium);
    final responder = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: creatorStatic,
      psk: todaySecrets.psk,
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      creatorStatic.dispose();
      responder.dispose();
    });

    conn.deliver(
      OuterFrame(type: FrameType.topicBridged, routingId: todaySecrets.topic),
    );
    await settle();
    responder.readM1(pairFrames(conn).single.payload);
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
        payload: responder.writeM2(),
      ),
    );
    await settle();
    responder.readM3(pairFrames(conn)[1].payload);
    final header = Uint8List.sublistView(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
      ).encode(),
      0,
      outerHeaderBytes,
    );
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: todaySecrets.topic,
        payload: responder.writeM4(header),
      ),
    );
    await waitUntil(() => controller.phase == JoinPhase.verify);

    final sentBefore = conn.sent.length; // M1, M3 already sent
    await controller.declineMismatch();

    expect(controller.phase, JoinPhase.mismatch);
    // Nothing persisted — persistence happens only after a match.
    expect(services.storage.channels.all, isEmpty);
    // No peer wire signal: nothing new was sent (USER 2026-07-07).
    expect(conn.sent.length, sentBefore);
  });

  test(
    'fail-closed spent: a malformed M2 discards everything (§3.1.6)',
    () async {
      final controller = makeController();
      final code = PairingCode.canonicalize('7Q2M4K9XV')!;
      final todaySecrets = deriveRendezvous(
        sodium: sodium,
        code: code,
        utcDate: utcDateString(now),
        cost: Argon2Cost.reducedTestOnly,
      );
      addTearDown(todaySecrets.dispose);

      await controller.join(code);
      final conn = connector.latest;
      conn.deliver(
        OuterFrame(type: FrameType.topicBridged, routingId: todaySecrets.topic),
      );
      await settle();
      expect(pairFrames(conn), hasLength(1)); // M1 sent

      // Garbage where M2 should be → readM2 fails → fail-closed spent.
      conn.deliver(
        OuterFrame(
          type: FrameType.pairData,
          routingId: todaySecrets.topic,
          payload: Uint8List.fromList(List.filled(132, 0)),
        ),
      );
      await waitUntil(() => controller.phase == JoinPhase.entry);
      expect(controller.entryError, JoinEntryError.spent);
      expect(services.storage.channels.all, isEmpty);
    },
  );

  test('offline edge: nothing sent, entry error set', () async {
    connector.failNextAttempts = 1;
    final controller = makeController();
    await controller.join(PairingCode.canonicalize('7Q2M4K9XV')!);
    expect(controller.phase, JoinPhase.entry);
    expect(controller.entryError, JoinEntryError.offline);
    expect(connector.connections, isEmpty);
  });
}
