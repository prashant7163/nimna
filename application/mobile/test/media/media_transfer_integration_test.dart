import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/domain/media_repository.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/media/model/media_attachment.dart';
import 'package:nimna/src/media/transfer/media_transfer_controller.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/session/connection/session_controller.dart';
import 'package:nimna/src/transport/relay_socket.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// S11 media round-trip between two live SessionControllers over the S10
/// bridge-relay harness. Real KK transport, the FROZEN v0.2.1 codec, real
/// at-rest AEAD blobs. Proves: photo + PDF reassemble byte-identical with the
/// manifest ACKed; a hash-mismatch discards with NO ACK and NO session kill;
/// expiry deletes the media_ix row + blob + message on BOTH ends.
void main() {
  // Media persistence writes/reads real blob files (dart:io), so settling
  // needs real event-loop time — microtask drains alone don't advance I/O.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  late SodiumSumo sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  Uint8List jpeg() {
    final image = img.Image(width: 300, height: 200);
    img.fill(image, color: img.ColorRgb8(120, 40, 200));
    return img.encodeJpg(image);
  }

  Uint8List multiChunkBytes() {
    // > 64 KiB so it spans multiple MEDIA_CHUNK frames.
    final out = Uint8List(150000);
    for (var i = 0; i < out.length; i++) {
      out[i] = (i * 7 + 3) & 0xFF;
    }
    return out;
  }

  test(
    'photo round trip: reassembles byte-identical + manifest ACKed',
    () async {
      final s = await _Session.establish(sodium, aead);
      addTearDown(s.dispose);

      final bytes = jpeg();
      await s.knocker.controller.sendMedia(
        MediaAttachment(bytes: bytes, mime: 'image/jpeg'),
      );
      await settle();

      // The accepter reassembled + persisted exactly one image message.
      final views = s.accepter.controller.messages;
      expect(views, hasLength(1));
      expect(views.single.isMedia, isTrue);
      expect(views.single.isMediaImage, isTrue);
      expect(views.single.outbound, isFalse);

      // The receiver's decrypted blob == the sender's post-strip plaintext.
      final rxId = views.single.mediaId!;
      final rxBlob = await s.accepter.storageMedia.readBlob(
        channelId: s.accepter.channelId,
        id: rxId,
      );
      expect(rxBlob, equals(bytes));

      // The sender kept its own encrypted copy, and the manifest was ACKed.
      final txView = s.knocker.controller.messages.single;
      final txBlob = await s.knocker.storageMedia.readBlob(
        channelId: s.knocker.channelId,
        id: txView.mediaId!,
      );
      expect(txBlob, equals(bytes));
      expect(txView.deliveryState, DeliveryState.delivered);
    },
  );

  test('multi-chunk PDF round trip + non-image bubble kind', () async {
    final s = await _Session.establish(sodium, aead);
    addTearDown(s.dispose);

    final bytes = multiChunkBytes();
    await s.knocker.controller.sendMedia(
      MediaAttachment(bytes: bytes, mime: 'application/pdf'),
    );
    await settle();

    final view = s.accepter.controller.messages.single;
    expect(view.isMedia, isTrue);
    expect(view.isMediaImage, isFalse);
    expect(view.mediaMime, 'application/pdf');
    final blob = await s.accepter.storageMedia.readBlob(
      channelId: s.accepter.channelId,
      id: view.mediaId!,
    );
    expect(blob, equals(bytes));
    expect(
      s.knocker.controller.messages.single.deliveryState,
      DeliveryState.delivered,
    );
  });

  test('a manifest is a replyable referent (spec §5.8)', () async {
    final s = await _Session.establish(sodium, aead);
    addTearDown(s.dispose);

    await s.knocker.controller.sendMedia(
      MediaAttachment(bytes: jpeg(), mime: 'image/jpeg'),
    );
    await settle();
    final photo = s.accepter.controller.messages.single;

    await s.accepter.controller.sendReply('about that photo', photo.msgId!);
    await settle();

    final reply = s.knocker.controller.messages.last;
    expect(reply.text, 'about that photo');
    expect(reply.reply!.tombstone, isFalse);
    expect(reply.reply!.kind.toString(), contains('photo'));
  });

  test('HASH MISMATCH → discarded, NO ACK, session stays live', () async {
    final s = await _Session.establish(sodium, aead);
    addTearDown(s.dispose);

    final data = multiChunkBytes();
    final mid = aead.randomBytes(16);
    // A manifest whose content_hash is deliberately WRONG.
    final manifest = InnerEnvelope(
      type: InnerType.mediaChunk,
      manifest: true,
      msgId: mid,
      timestampMs: 1,
      body: ManifestBody(
        chunkCount: (data.length + 65535) ~/ 65536,
        totalLen: data.length,
        contentHash: aead.randomBytes(32), // never matches
        mime: 'image/jpeg',
      ).encode(),
    );
    expect(s.knocker.controller.sealForTest(manifest), isTrue);
    var off = 0;
    var index = 0;
    while (off < data.length) {
      final end = off + 65536 < data.length ? off + 65536 : data.length;
      s.knocker.controller.sealForTest(
        InnerEnvelope(
          type: InnerType.mediaChunk,
          msgId: aead.randomBytes(16),
          timestampMs: 1,
          body: ChunkBody(
            manifestMsgId: mid,
            chunkIndex: index++,
            data: Uint8List.sublistView(data, off, end),
          ).encode(),
        ),
      );
      off = end;
    }
    await settle();

    // Discarded: no media message persisted, no session kill on either side.
    expect(s.accepter.controller.messages, isEmpty);
    expect(s.accepter.controller.isLive, isTrue);
    expect(s.knocker.controller.isLive, isTrue);
    // No ACK went back for that manifest — no delivery chrome anywhere.
    expect(s.knocker.controller.messages, isEmpty);
  });

  test('expired media vanishes on BOTH ends (row + blob + message)', () async {
    var now = DateTime.utc(2026, 7, 7, 12);
    final s = await _Session.establish(sodium, aead, clock: () => now);
    addTearDown(s.dispose);

    final bytes = jpeg();
    await s.knocker.controller.sendMedia(
      MediaAttachment(bytes: bytes, mime: 'image/jpeg'),
      expirySeconds: 60,
    );
    await settle();

    final txId = s.knocker.controller.messages.single.mediaId!;
    final rxId = s.accepter.controller.messages.single.mediaId!;

    // Advance past the purge deadline and sweep both devices.
    now = now.add(const Duration(minutes: 2));
    await s.knocker.controller.purgeExpiredMedia();
    await s.accepter.controller.purgeExpiredMedia();
    await settle();

    // Threads emptied on both ends.
    expect(s.knocker.controller.messages, isEmpty);
    expect(s.accepter.controller.messages, isEmpty);

    // media_ix rows gone on both ends.
    expect(
      await s.knocker.storageMedia.indexByChannel(s.knocker.channelId),
      isEmpty,
    );
    expect(
      await s.accepter.storageMedia.indexByChannel(s.accepter.channelId),
      isEmpty,
    );

    // Blob files gone on both ends.
    expect(
      () => s.knocker.storageMedia.readBlob(
        channelId: s.knocker.channelId,
        id: txId,
      ),
      throwsA(anything),
    );
    expect(
      () => s.accepter.storageMedia.readBlob(
        channelId: s.accepter.channelId,
        id: rxId,
      ),
      throwsA(anything),
    );
  });

  test('over-cap manifest is discarded (no OOM), session stays LIVE', () async {
    final s = await _Session.establish(sodium, aead);
    addTearDown(s.dispose);

    // A hostile manifest: chunk_count = 2^32-1, total_len ~= 2^63. If the
    // receiver allocated from these it would OOM; instead it discards, stays
    // live, and never ACKs.
    final mid = aead.randomBytes(16);
    final manifest = InnerEnvelope(
      type: InnerType.mediaChunk,
      manifest: true,
      msgId: mid,
      timestampMs: 1,
      body: ManifestBody(
        chunkCount: 0xFFFFFFFF,
        totalLen: 0x7FFFFFFFFFFFFFFF,
        contentHash: aead.randomBytes(32),
        mime: 'image/jpeg',
      ).encode(),
    );
    expect(s.knocker.controller.sealForTest(manifest), isTrue);
    await settle();

    expect(s.accepter.controller.messages, isEmpty);
    expect(s.accepter.controller.isLive, isTrue);
    expect(s.knocker.controller.isLive, isTrue);
  });

  test(
    'receiver expiry uses the RECEIVER clock, not the wire timestamp',
    () async {
      // Sender clock is a YEAR in the future; the receiver clock is "now". A
      // forged future manifest timestamp must NOT be able to defeat disappearing
      // media — the receiver keys expiry to its OWN receive time.
      var receiverNow = DateTime.utc(2026, 7, 7, 12);
      final senderFuture = DateTime.utc(2027, 7, 7, 12);
      final s = await _Session.establish(
        sodium,
        aead,
        knockerClock: () => senderFuture,
        accepterClock: () => receiverNow,
      );
      addTearDown(s.dispose);

      await s.knocker.controller.sendMedia(
        MediaAttachment(bytes: jpeg(), mime: 'image/jpeg'),
        expirySeconds: 60,
      );
      await settle();
      final rxId = s.accepter.controller.messages.single.mediaId!;

      // Advance the RECEIVER's own clock 2 min past receipt, then sweep.
      receiverNow = receiverNow.add(const Duration(minutes: 2));
      await s.accepter.controller.purgeExpiredMedia();
      await settle();

      // Purged on the receiver's schedule despite the sender's future timestamp.
      expect(s.accepter.controller.messages, isEmpty);
      expect(
        await s.accepter.storageMedia.indexByChannel(s.accepter.channelId),
        isEmpty,
      );
      expect(
        () => s.accepter.storageMedia.readBlob(
          channelId: s.accepter.channelId,
          id: rxId,
        ),
        throwsA(anything),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Two-party harness: a bridge relay + two media-attached SessionControllers.
// ---------------------------------------------------------------------------

class _Session {
  _Session({required this.knocker, required this.accepter});

  final _Party knocker;
  final _Party accepter;

  static Future<_Session> establish(
    SodiumSumo sodium,
    AtRestAead aead, {
    DateTime Function()? clock,
    DateTime Function()? knockerClock,
    DateTime Function()? accepterClock,
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
      clock: knockerClock ?? clock,
    );
    final accepter = await _Party.create(
      sodium: sodium,
      aead: aead,
      role: SessionRole.accepter,
      ownStatic: accepterStatic,
      peerStaticPublic: knockerStatic.publicKey,
      crid: crid,
      connector: _BridgeConnector(bridge, knocker: false),
      clock: accepterClock ?? clock,
    );

    await accepter.controller.start();
    await knocker.controller.start();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return _Session(knocker: knocker, accepter: accepter);
  }

  Future<void> dispose() async {
    await knocker.dispose();
    await accepter.dispose();
  }
}

class _Party {
  _Party({
    required this.device,
    required this.controller,
    required this.channelId,
    required this.storageMedia,
  });

  final TestDevice device;
  final SessionController controller;
  final Uint8List channelId;
  final MediaRepository storageMedia;

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
    final diag = Diag(aead: aead);
    final clk = clock ?? DateTime.now;
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
      diag: diag,
      clock: clock,
    );
    controller.attachMedia(
      MediaTransferController(
        media: services.storage.media,
        channelId: channelId,
        randomBytes: aead.randomBytes,
        sealFrame: controller.sealMediaFrame,
        onInboundComplete: controller.ingestReceivedMedia,
        // The controller's clock must match the session's (same source).
        nowMs: () => clk().toUtc().millisecondsSinceEpoch,
        diag: diag,
      ),
    );
    return _Party(
      device: device,
      controller: controller,
      channelId: channelId,
      storageMedia: services.storage.media,
    );
  }

  Future<void> dispose() async {
    await controller.dispose();
    await device.dispose();
  }
}

class _BridgeRelay {
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

  @override
  Future<void> close() async {
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }
}
