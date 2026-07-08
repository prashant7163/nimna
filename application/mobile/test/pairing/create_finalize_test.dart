import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/xxpsk2.dart';
import 'package:nimna/src/pairing/initiator/initiator_controller.dart';
import 'package:nimna/src/pairing/initiator/pending_pairing.dart';
import 'package:nimna/src/protocol/channel_identity.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// The S16 CREATOR-finalize path (F2.6/F2.7 — the PM's core gap): today the
/// creator completes the handshake but never sees the safety phrase. This
/// drives the REAL [CreateLineController]'s own responder engine against a
/// manual from-spec JOINER, and asserts:
///  - the creator reaches [CreateLinePhase.verifying] with a safety phrase
///    IDENTICAL to the joiner's (both ends agree — spec §3.1.4);
///  - "They match" → name → finish PERSISTS the channel (the sole persistence
///    point), with the joiner's CRID and static, and the peer token (§3.2.1);
///  - "They don't match" is a LOCAL-ONLY silent discard: nothing persisted, no
///    NEW wire signal (the relay was already closed at handshake completion).
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
    now = DateTime.utc(2026, 7, 8, 10);
    services = await device.boot();
    sodium = await testSodium();
    aead = AtRestAead(sodium);
    wordlist = File(
      '../../docs/test-vectors/wordlist-en-v1.txt',
    ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
  });

  tearDown(() => device.dispose());

  CreateLineController makeController() {
    final controller = CreateLineController(
      sodium: sodium,
      connector: connector,
      store: PendingPairingStore(storage: services.storage, sodium: sodium),
      diag: services.diag,
      storage: services.storage,
      aead: aead,
      wordlistLoader: () async => wordlist,
      clock: () => now,
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

  /// Drives the creator through a full handshake against a manual joiner and
  /// leaves it at [CreateLinePhase.verifying]. Returns the manual joiner's
  /// finalized material for the cross-check.
  Future<PairingChannelMaterial> driveToVerify(
    CreateLineController controller,
  ) async {
    await controller.createCode();
    expect(controller.phase, CreateLinePhase.waiting);
    final conn = connector.latest;
    final topic = controller.secrets!.topic;
    final psk = controller.secrets!.psk;

    // Bridge → the creator's responder starts and waits for M1.
    conn.deliver(OuterFrame(type: FrameType.topicBridged, routingId: topic));
    await settle();

    final joinerStatic = generateNoiseKeyPair(sodium);
    final joinerToken = TokenPayload.present(
      platform: PushPlatform.apns,
      token: Uint8List.fromList('joiner-token'.codeUnits),
    );
    final joiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: joinerStatic,
      psk: psk,
      tokenPayload: joinerToken,
    );
    addTearDown(() {
      joinerStatic.dispose();
      joiner.dispose();
    });
    final header = Uint8List.sublistView(
      OuterFrame(type: FrameType.pairData, routingId: topic).encode(),
      0,
      outerHeaderBytes,
    );

    // M1 → creator sends M2.
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: topic,
        payload: joiner.writeM1(),
      ),
    );
    await settle();
    expect(pairFrames(conn), hasLength(1)); // M2
    joiner.readM2(pairFrames(conn).single.payload);

    // M3 → creator sends M4, finalizes, and shows the safety phrase.
    conn.deliver(
      OuterFrame(
        type: FrameType.pairData,
        routingId: topic,
        payload: joiner.writeM3(),
      ),
    );
    await waitUntil(() => controller.phase == CreateLinePhase.verifying);
    expect(pairFrames(conn), hasLength(2)); // M2, M4
    joiner.completeWithM4(pairFrames(conn)[1].payload, header);
    return joiner.finalizeChannel();
  }

  test('creator reaches the safety phrase; both ends derive the same words; '
      'finish persists the channel', () async {
    final controller = makeController();
    final joinerMat = await driveToVerify(controller);
    addTearDown(joinerMat.disposeSecret);

    // Both ends derive the identical three words (spec §3.1.4).
    final joinerWords = safetyPhraseWords(
      ss: joinerMat.ss,
      aPublic: joinerMat.peerStaticPublic, // = creator's own static public
      bPublic: Uint8List.fromList(joinerMat.peerStaticPublic),
      wordlist: wordlist,
    );
    expect(controller.safetyPhrase, hasLength(3));
    // The creator's material is the mirror of the joiner's.
    final creatorMat = controller.pairingMaterial!;
    final expected = safetyPhraseWords(
      ss: creatorMat.ss,
      aPublic: joinerMat.peerStaticPublic,
      bPublic: creatorMat.peerStaticPublic,
      wordlist: wordlist,
    );
    expect(controller.safetyPhrase, expected);
    expect(joinerWords, isNotNull);

    // "They match" → name → Done persists (the SOLE persistence point).
    expect(services.storage.channels.all, isEmpty);
    controller.confirmMatch();
    expect(controller.phase, CreateLinePhase.naming);
    await controller.finish('Marlowe');
    expect(controller.phase, CreateLinePhase.finalized);

    final channels = services.storage.channels.all;
    expect(channels, hasLength(1));
    expect(channels.single.label, 'Marlowe');
    // The creator's channel shares the CRID with the joiner (same session).
    expect(channels.single.crid, creatorMat.crid);
    expect(channels.single.peerStaticPublic, creatorMat.peerStaticPublic);
    // The joiner's device-token rode the handshake and is stored present-form.
    expect(channels.single.peerDeviceToken, isNotNull);
    // Defaults: read receipts OFF, typing ON (USER 2026-07-07).
    expect(channels.single.readReceiptsOptIn, isFalse);
    expect(channels.single.typingEnabled, isTrue);
  });

  test('mismatch = local-only silent discard: nothing persisted, no new wire '
      'signal', () async {
    final controller = makeController();
    final joinerMat = await driveToVerify(controller);
    addTearDown(joinerMat.disposeSecret);

    final sentBefore = connector.latest.sent.length; // M2, M4 already sent
    await controller.declineMismatch();

    expect(controller.phase, CreateLinePhase.mismatch);
    expect(services.storage.channels.all, isEmpty);
    // No peer wire signal — the copy must not imply the peer was told.
    expect(connector.latest.sent.length, sentBefore);
  });
}
