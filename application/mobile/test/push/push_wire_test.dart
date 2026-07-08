import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/presence/peer_token_store.dart';
import 'package:nimna/src/presence/push_opt_in.dart';
import 'package:nimna/src/presence/session_launcher.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/push/push_service.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:nimna/src/session/model/chat_event.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';
import 'fake_push_source.dart';

/// The S15 own-token WIRE path, end to end over the two-party bridge: when a
/// line is opted into push, this device's OWN token (acquired from the push
/// source) is announced to the peer via a token-refresh CONTROL the instant
/// the line goes live — and the peer persists it (so a future KNOCK can wake
/// this device). Opting the line back out sends the absent-form REVOKE and the
/// peer deletes the address (spec §3.2.1, §5.5, §5.7).
void main() {
  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  Future<void> pumpUntil(
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  test('opted-in ⇒ own token announced on live; opt-out ⇒ revoke', () async {
    final knockerStatic = generateNoiseKeyPair(sodium);
    final accepterStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final bridge = _Bridge();

    final knockerDev = TestDevice.create();
    final accepterDev = TestDevice.create();
    addTearDown(() async {
      // Let trailing fire-and-forget persistence commit before DBs close.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await knockerDev.dispose();
      await accepterDev.dispose();
    });

    final knockerSvc = await knockerDev.boot();
    final accepterSvc = await accepterDev.boot();
    final knockerChannels = knockerSvc.storage.channels;
    final accepterChannels = accepterSvc.storage.channels;

    final knockerChannelId = aead.randomBytes(16);
    final accepterChannelId = aead.randomBytes(16);
    await knockerChannels.create(
      _record(
        aead,
        knockerChannelId,
        knockerStatic,
        accepterStatic.publicKey,
        crid,
      ),
    );
    await accepterChannels.create(
      _record(
        aead,
        accepterChannelId,
        accepterStatic,
        knockerStatic.publicKey,
        crid,
      ),
    );

    // The knocker opts THIS line into push and holds a real own token.
    final knockerPushOptIn = PushOptIn(knockerChannels);
    await knockerPushOptIn.setEnabled(knockerChannelId, enabled: true);
    final ownToken = TokenPayload.present(
      platform: PushPlatform.apns,
      token: Uint8List.fromList(utf8.encode('knocker-own-token')),
    );
    final source = FakePushSource(token: ownToken);
    final pushService = PushService(
      source: source,
      isOptedIn: knockerPushOptIn.isEnabled,
    );
    addTearDown(pushService.dispose);

    final knockerLauncher = SessionLauncher(
      sodium: sodium,
      aead: aead,
      connector: _BridgeConnector(bridge, knocker: true),
      channels: knockerChannels,
      messages: knockerSvc.storage.messages,
      media: knockerSvc.storage.media,
      diag: knockerSvc.diag,
      pushOptIn: knockerPushOptIn,
      peerTokenStore: PeerTokenStore(knockerChannels),
      onSessionBound: pushService.bindSession,
    );
    final accepterLauncher = SessionLauncher(
      sodium: sodium,
      aead: aead,
      connector: _BridgeConnector(bridge, knocker: false),
      channels: accepterChannels,
      messages: accepterSvc.storage.messages,
      media: accepterSvc.storage.media,
      diag: accepterSvc.diag,
      pushOptIn: PushOptIn(accepterChannels),
      peerTokenStore: PeerTokenStore(accepterChannels),
    );

    final accepter = accepterLauncher.build(
      accepterChannelId,
      role: SessionRole.accepter,
    );
    accepter.events.listen((e) {
      if (e is IncomingKnock) {
        unawaited(accepter.acceptKnock());
      }
    });
    final knocker = knockerLauncher.build(
      knockerChannelId,
      role: SessionRole.knocker,
    );

    await accepter.start();
    await knocker.start();
    await pumpUntil(() => knocker.isLive);

    // The accepter received the knocker's OWN token via token-refresh and
    // persisted it (so it can wake the knocker later).
    await pumpUntil(
      () => accepterChannels.byId(accepterChannelId)!.peerDeviceToken != null,
    );
    expect(
      accepterChannels.byId(accepterChannelId)!.peerDeviceToken,
      ownToken.encode(),
      reason: 'the peer stores THIS device\'s own token, present-form',
    );
    expect(
      source.acquireCalls,
      greaterThanOrEqualTo(1),
      reason: 'the own token was acquired from the platform source',
    );

    // Opting OUT sends the absent-form REVOKE; the peer clears the address.
    await knockerPushOptIn.setEnabled(knockerChannelId, enabled: false);
    await pushService.onOptInChanged(knockerChannelId, enabled: false);
    await pumpUntil(
      () => accepterChannels.byId(accepterChannelId)!.peerDeviceToken == null,
    );
    expect(
      accepterChannels.byId(accepterChannelId)!.peerDeviceToken,
      isNull,
      reason: 'opt-out is a unilateral, permanent revoke',
    );
  });

  test('opted-OUT line announces nothing (pure burner-line)', () async {
    final knockerStatic = generateNoiseKeyPair(sodium);
    final accepterStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    final bridge = _Bridge();

    final knockerDev = TestDevice.create();
    final accepterDev = TestDevice.create();
    addTearDown(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await knockerDev.dispose();
      await accepterDev.dispose();
    });

    final knockerSvc = await knockerDev.boot();
    final accepterSvc = await accepterDev.boot();
    final knockerChannels = knockerSvc.storage.channels;
    final accepterChannels = accepterSvc.storage.channels;
    final knockerChannelId = aead.randomBytes(16);
    final accepterChannelId = aead.randomBytes(16);
    await knockerChannels.create(
      _record(
        aead,
        knockerChannelId,
        knockerStatic,
        accepterStatic.publicKey,
        crid,
      ),
    );
    await accepterChannels.create(
      _record(
        aead,
        accepterChannelId,
        accepterStatic,
        knockerStatic.publicKey,
        crid,
      ),
    );

    // Push OFF (default) — a real token exists but must never leave.
    final knockerPushOptIn = PushOptIn(knockerChannels);
    final source = FakePushSource(
      token: TokenPayload.present(
        platform: PushPlatform.apns,
        token: Uint8List.fromList(utf8.encode('secret')),
      ),
    );
    final pushService = PushService(
      source: source,
      isOptedIn: knockerPushOptIn.isEnabled,
    );
    addTearDown(pushService.dispose);

    final knockerLauncher = SessionLauncher(
      sodium: sodium,
      aead: aead,
      connector: _BridgeConnector(bridge, knocker: true),
      channels: knockerChannels,
      messages: knockerSvc.storage.messages,
      media: knockerSvc.storage.media,
      diag: knockerSvc.diag,
      pushOptIn: knockerPushOptIn,
      peerTokenStore: PeerTokenStore(knockerChannels),
      onSessionBound: pushService.bindSession,
    );
    final accepterLauncher = SessionLauncher(
      sodium: sodium,
      aead: aead,
      connector: _BridgeConnector(bridge, knocker: false),
      channels: accepterChannels,
      messages: accepterSvc.storage.messages,
      media: accepterSvc.storage.media,
      diag: accepterSvc.diag,
      pushOptIn: PushOptIn(accepterChannels),
      peerTokenStore: PeerTokenStore(accepterChannels),
    );

    final accepter = accepterLauncher.build(
      accepterChannelId,
      role: SessionRole.accepter,
    );
    accepter.events.listen((e) {
      if (e is IncomingKnock) {
        unawaited(accepter.acceptKnock());
      }
    });
    final knocker = knockerLauncher.build(
      knockerChannelId,
      role: SessionRole.knocker,
    );
    await accepter.start();
    await knocker.start();
    await pumpUntil(() => knocker.isLive);
    // Give any (erroneous) announce ample time to land.
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(
      accepterChannels.byId(accepterChannelId)!.peerDeviceToken,
      isNull,
      reason: 'push off ⇒ nothing about this line touches the peer',
    );
    expect(source.acquireCalls, 0, reason: 'no token acquired when off');
  });
}

ChannelRecord _record(
  AtRestAead aead,
  Uint8List id,
  NoiseKeyPair own,
  List<int> peerPublic,
  Uint8List crid,
) => ChannelRecord(
  id: id,
  ownStaticPrivate: own.secretKey.extractBytes(),
  ownStaticPublic: Uint8List.fromList(own.publicKey),
  peerStaticPublic: Uint8List.fromList(peerPublic),
  crid: Uint8List.fromList(crid),
  label: 'peer',
  cdk: aead.randomBytes(32),
  createdAtMs: 0,
);

// ---- in-memory two-CRID bridge (compact copy of the presence harness) -----

class _Bridge {
  _BridgeEndpoint? knockerEp;
  _BridgeEndpoint? accepterEp;

  void attach(_BridgeEndpoint ep, {required bool knocker}) {
    if (knocker) {
      knockerEp = ep;
    } else {
      accepterEp = ep;
    }
  }

  void route(_BridgeEndpoint from, OuterFrame frame) {
    final fromKnocker = identical(from, knockerEp);
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
