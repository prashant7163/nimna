import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/presence/background_grace.dart';
import 'package:nimna/src/presence/knock_controller.dart';
import 'package:nimna/src/presence/peer_token_store.dart';
import 'package:nimna/src/presence/push_opt_in.dart';
import 'package:nimna/src/presence/session_launcher.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_relay.dart';
import '../helpers/test_env.dart';

/// S12 presence units — background grace, the cold-knock lapse/never-retry
/// controller, push opt-in payload derivation, and the peer-token store — all
/// on injected clocks/timers so they are deterministic.
void main() {
  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  // ---- background grace ---------------------------------------------------

  group('BackgroundGrace', () {
    test('expiry fires onExpired + logs, once', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final services = await device.boot();
      final captured = <void Function()>[];
      var expired = 0;
      final grace = BackgroundGrace(
        onExpired: () => expired++,
        diag: services.diag,
        timerFactory: (d, cb) {
          captured.add(cb);
          return Timer(const Duration(days: 1), () {}); // inert real timer
        },
      );

      grace.onBackground();
      expect(grace.pending, isTrue);
      captured.single(); // fire the "30 s" timer
      expect(expired, 1);
      expect(grace.pending, isFalse);
      expect(
        services.diag.readAll().map((r) => r.event),
        contains(DiagEvent.backgroundGraceExpired),
      );
    });

    test('foreground within the window cancels silently', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final services = await device.boot();
      var expired = 0;
      final grace = BackgroundGrace(
        onExpired: () => expired++,
        diag: services.diag,
        timerFactory: (d, cb) => Timer(const Duration(days: 1), () {}),
      );
      grace.onBackground();
      grace.onForeground();
      expect(grace.pending, isFalse);
      expect(expired, 0);
      expect(
        services.diag.readAll().map((r) => r.event),
        isNot(contains(DiagEvent.backgroundGraceExpired)),
      );
    });
  });

  // ---- push opt-in payload ------------------------------------------------

  group('PushOptIn', () {
    // The KNOCK carries the PEER's token so the relay can wake the PEER; it is
    // gated SOLELY on a stored present-form peer token (which already encodes
    // the peer's opt-in), NEVER on the knocker's own opt-in. Push is per-side
    // (spec §3.2.1 / voice string 18). CODE, 2026-07-08 (S15 review fix).
    test('knock carries the peer token whenever one is stored — independent of '
        'the knocker OWN opt-in', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final services = await device.boot();
      final channels = services.storage.channels;
      final channelId = aead.randomBytes(16);
      final ownStatic = generateNoiseKeyPair(sodium);
      // The PEER (B) opted in and shared its token; it is stored present-form.
      final token = TokenPayload.present(
        platform: PushPlatform.apns,
        token: Uint8List.fromList(utf8.encode('tok')),
      );
      await channels.create(
        ChannelRecord(
          id: channelId,
          ownStaticPrivate: ownStatic.secretKey.extractBytes(),
          ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
          peerStaticPublic: aead.randomBytes(32),
          crid: aead.randomBytes(16),
          label: 'peer',
          cdk: aead.randomBytes(32),
          createdAtMs: 0,
          peerDeviceToken: token.encode(),
        ),
      );
      final push = PushOptIn(channels);

      // THE DEFECT-CASE: A opted OUT + B opted IN ⇒ A holds B's token ⇒ the
      // knock MUST carry it so B, who asked to be woken, is woken.
      expect(push.isEnabled(channelId), isFalse);
      expect(push.knockPayloadFor(channelId), token.encode().sublist(1));

      // A opting in changes nothing here (that direction is A's OWN token, via
      // the token-refresh CONTROL) — the knock still carries B's token.
      await push.setEnabled(channelId, enabled: true);
      expect(push.isEnabled(channelId), isTrue);
      expect(push.knockPayloadFor(channelId), token.encode().sublist(1));
    });

    test(
      'a revoked/absent peer token ⇒ empty knock (burner-line wake)',
      () async {
        final device = TestDevice.create();
        addTearDown(device.dispose);
        final services = await device.boot();
        final channels = services.storage.channels;
        final channelId = aead.randomBytes(16);
        final ownStatic = generateNoiseKeyPair(sodium);
        // No stored peer token (peer never opted in, or revoked).
        await channels.create(
          ChannelRecord(
            id: channelId,
            ownStaticPrivate: ownStatic.secretKey.extractBytes(),
            ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
            peerStaticPublic: aead.randomBytes(32),
            crid: aead.randomBytes(16),
            label: 'peer',
            cdk: aead.randomBytes(32),
            createdAtMs: 0,
          ),
        );
        final push = PushOptIn(channels);

        // Empty regardless of the knocker's own opt-in — nothing to carry.
        expect(push.knockPayloadFor(channelId), isEmpty);
        await push.setEnabled(channelId, enabled: true);
        expect(push.knockPayloadFor(channelId), isEmpty);
      },
    );
  });

  // ---- peer-token store ---------------------------------------------------

  group('PeerTokenStore', () {
    test('present stores encoded form; absent revokes', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final services = await device.boot();
      final channels = services.storage.channels;
      final channelId = aead.randomBytes(16);
      final ownStatic = generateNoiseKeyPair(sodium);
      await channels.create(
        ChannelRecord(
          id: channelId,
          ownStaticPrivate: ownStatic.secretKey.extractBytes(),
          ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
          peerStaticPublic: aead.randomBytes(32),
          crid: aead.randomBytes(16),
          label: 'peer',
          cdk: aead.randomBytes(32),
          createdAtMs: 0,
        ),
      );
      final store = PeerTokenStore(channels);
      final token = TokenPayload.present(
        platform: PushPlatform.fcm,
        token: Uint8List.fromList(utf8.encode('fcm')),
      );

      await store.onPeerTokenRefresh(channelId, token);
      expect(channels.byId(channelId)!.peerDeviceToken, token.encode());

      await store.onPeerTokenRefresh(channelId, const TokenPayload.absent());
      expect(channels.byId(channelId)!.peerDeviceToken, isNull);
    });
  });

  // ---- cold-knock lapse + never-auto-retry --------------------------------

  group('KnockController', () {
    Future<KnockController> makeController(
      TestDevice device, {
      required List<void Function()> lapseCallbacks,
    }) async {
      final services = await device.boot();
      final channelId = aead.randomBytes(16);
      final ownStatic = generateNoiseKeyPair(sodium);
      await services.storage.channels.create(
        ChannelRecord(
          id: channelId,
          ownStaticPrivate: ownStatic.secretKey.extractBytes(),
          ownStaticPublic: Uint8List.fromList(ownStatic.publicKey),
          peerStaticPublic: aead.randomBytes(32),
          crid: aead.randomBytes(16),
          label: 'peer',
          cdk: aead.randomBytes(32),
          createdAtMs: 0,
        ),
      );
      // A connector that bridges nowhere: the knock is sent and simply never
      // answered (offline-vs-ignored is indistinguishable).
      final connector = _SilentConnector();
      final launcher = SessionLauncher(
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
      return KnockController(
        launcher: launcher,
        channelId: channelId,
        diag: services.diag,
        timerFactory: (d, cb) {
          lapseCallbacks.add(cb);
          return Timer(const Duration(days: 1), () {});
        },
      );
    }

    test('lapse → No answer.; the app never auto-retries', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final lapses = <void Function()>[];
      final knock = await makeController(device, lapseCallbacks: lapses);
      addTearDown(knock.dispose);

      await knock.knock();
      expect(knock.state, KnockState.waiting);
      expect(knock.deadline, isNotNull);
      expect(lapses, hasLength(1)); // exactly ONE lapse timer — one knock.

      // Fire the 60 s lapse: state → lapsed, NO second knock timer armed.
      lapses.single();
      expect(knock.state, KnockState.lapsed);
      expect(lapses, hasLength(1), reason: 'no auto-retry: no new timer');
      expect(knock.deadline, isNull);

      // Manual "Knock again" is the ONLY way forward — a deliberate re-knock.
      await knock.knockAgain();
      expect(knock.state, KnockState.waiting);
      expect(lapses, hasLength(2)); // a NEW window, only on the manual act.
    });

    test('stale hint surfaces only after repeated unanswered knocks', () async {
      final device = TestDevice.create();
      addTearDown(device.dispose);
      final lapses = <void Function()>[];
      final knock = await makeController(device, lapseCallbacks: lapses);
      addTearDown(knock.dispose);

      await knock.knock();
      lapses.last(); // first lapse
      expect(knock.staleHint, isFalse);
      await knock.knockAgain();
      lapses.last(); // second lapse
      expect(knock.staleHint, isTrue);
    });
  });
}

/// A connector whose socket accepts the KNOCK but never bridges — the knock
/// simply lapses (offline vs ignored is indistinguishable by construction).
class _SilentConnector implements RelayConnector {
  @override
  Future<RelayConnection> connect() async => FakeRelayConnection();
}
