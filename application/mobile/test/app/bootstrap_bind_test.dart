import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/push/push_service.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';
import '../push/fake_push_source.dart';

/// The COMPOSITION-ROOT regression guard for the S15 forward-requirement
/// (architect Concern 1): a session built from the PRODUCTION composition
/// (`bootstrapNimna` → `NimnaServices.sessionLauncher()`) MUST fire
/// `pushService.bindSession`, or push is silently dead in production.
///
/// This lives beside the composition root deliberately. The hand-wired
/// `test/push/push_wire_test.dart` attaches the hook itself and would stay
/// green even if `bootstrapNimna` forgot to pass
/// `onSessionBound: pushService.bindSession`; only a bootstrap-level assertion
/// catches that regression.
class _SpyPushService extends PushService {
  _SpyPushService({required super.source, required super.isOptedIn});

  final List<Uint8List> bound = [];

  @override
  void bindSession(SessionController controller, Uint8List channelId) {
    bound.add(Uint8List.fromList(channelId));
    super.bindSession(controller, channelId);
  }
}

void main() {
  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  test(
    'bootstrap SessionLauncher fires pushService.bindSession on build',
    () async {
      // A spy PushService injected into the real composition root; opt-in is
      // irrelevant to the guard (bindSession runs regardless — the announce
      // inside is what is gated), so a trivial lookup keeps the test focused.
      final spy = _SpyPushService(
        source: FakePushSource(token: const TokenPayload.absent()),
        isOptedIn: (_) => false,
      );

      final device = TestDevice.create();
      addTearDown(device.dispose);
      final services = await device.boot(pushService: spy);

      // A stored channel with a real static keypair (the launcher reads its held
      // secret to build the session).
      final own = generateNoiseKeyPair(sodium);
      final peer = generateNoiseKeyPair(sodium);
      final channelId = aead.randomBytes(16);
      await services.storage.channels.create(
        ChannelRecord(
          id: channelId,
          ownStaticPrivate: own.secretKey.extractBytes(),
          ownStaticPublic: Uint8List.fromList(own.publicKey),
          peerStaticPublic: Uint8List.fromList(peer.publicKey),
          crid: aead.randomBytes(16),
          label: 'peer',
          cdk: aead.randomBytes(32),
          createdAtMs: 0,
        ),
      );

      // Build a session from the PRODUCTION composition root.
      final launcher = services.sessionLauncher();
      final controller = launcher.build(channelId, role: SessionRole.knocker);
      addTearDown(controller.dispose);

      expect(spy.bound, hasLength(1));
      expect(
        spy.bound.single,
        orderedEquals(channelId),
        reason:
            'the production SessionLauncher must attach onSessionBound: '
            'pushService.bindSession with the launched channel — else S15 push '
            'is dead in production',
      );
    },
  );
}
