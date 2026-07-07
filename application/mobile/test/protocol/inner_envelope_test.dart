import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';
import 'package:nimna/src/protocol/reaction_body.dart';
import 'package:nimna/src/protocol/token_payload.dart';

import '../helpers/test_env.dart';

/// §5.5–§5.8 inner-envelope codec: every valid round-trip, the FULL
/// structural-error set (mirrors the Go framing_test cases), and a
/// vector-conformance harness over docs/test-vectors/framing.json (decode +
/// re-encode byte parity for valid cases; InnerEnvelopeError for invalid).
void main() {
  final msgId = hexToBytes('0957be2eec3b1c31de4484daa4b7d1f4');
  final other = hexToBytes('a3fe63928854403e30c0a7342aa600ee');
  const ts = 1783166400100;

  Uint8List roundTrip(InnerEnvelope e) =>
      InnerEnvelope.decode(e.encode()).encode();

  group('valid round-trips', () {
    test('TEXT (min, empty, utf8, expiry, reply, expiry+reply)', () {
      final cases = <InnerEnvelope>[
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          body: Uint8List.fromList(utf8.encode('hi')),
        ),
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          body: Uint8List(0),
        ),
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          body: Uint8List.fromList(utf8.encode('héllo 🙂 grüße')),
        ),
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          expirySeconds: 300,
          body: Uint8List.fromList(utf8.encode('poof')),
        ),
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          replyTo: other,
          body: Uint8List.fromList(utf8.encode('re')),
        ),
        InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          expirySeconds: 60,
          replyTo: other,
          body: Uint8List.fromList(utf8.encode('both')),
        ),
      ];
      for (final e in cases) {
        expect(bytesToHex(roundTrip(e)), bytesToHex(e.encode()));
        expect(InnerEnvelope.decode(e.encode()).flags, e.flags);
      }
    });

    test('flag-bit field order: reply_to follows expiry_s (offset 31)', () {
      final e = InnerEnvelope(
        type: InnerType.text,
        msgId: msgId,
        timestampMs: ts,
        expirySeconds: 42,
        replyTo: other,
        body: Uint8List(0),
      );
      final bytes = e.encode();
      expect(bytes[2], flagExpiry | flagReplyTo); // 0x05
      // expiry_s at 27..31, reply_to at 31..47.
      expect(ByteData.sublistView(bytes).getUint32(27), 42);
      expect(
        bytesToHex(Uint8List.sublistView(bytes, 31, 47)),
        bytesToHex(other),
      );
      final back = InnerEnvelope.decode(bytes);
      expect(back.expirySeconds, 42);
      expect(bytesToHex(back.replyTo!), bytesToHex(other));
    });

    test('ACK / HANGUP', () {
      final ack = InnerEnvelope(
        type: InnerType.ack,
        msgId: msgId,
        timestampMs: ts,
        body: AckBody(ackedMsgId: other).encode(),
      );
      expect(bytesToHex(roundTrip(ack)), bytesToHex(ack.encode()));
      expect(
        bytesToHex(AckBody.decode(ack.body).ackedMsgId),
        bytesToHex(other),
      );

      final hangup = InnerEnvelope(
        type: InnerType.hangup,
        msgId: msgId,
        timestampMs: ts,
        body: Uint8List(0),
      );
      expect(bytesToHex(roundTrip(hangup)), bytesToHex(hangup.encode()));
    });

    test('CONTROL (typing/read-receipt/screenshot/token-refresh/unknown)', () {
      final bodies = <Uint8List>[
        ControlBody(
          rawType: ControlType.typing.wire,
          payload: Uint8List(0),
        ).encode(),
        ControlBody(
          rawType: ControlType.readReceipt.wire,
          payload: other,
        ).encode(),
        ControlBody(
          rawType: ControlType.screenshot.wire,
          payload: Uint8List(0),
        ).encode(),
        ControlBody(
          rawType: ControlType.tokenRefresh.wire,
          payload: TokenPayload.present(
            platform: PushPlatform.apns,
            token: Uint8List.fromList(utf8.encode('apns-token')),
          ).encode(),
        ).encode(),
        ControlBody(
          rawType: ControlType.tokenRefresh.wire,
          payload: const TokenPayload.absent().encode(),
        ).encode(),
        // Unknown control_type with arbitrary payload — decodes OK, ignored.
        Uint8List.fromList([0x7f, 1, 2, 3]),
      ];
      for (final body in bodies) {
        final e = InnerEnvelope(
          type: InnerType.control,
          msgId: msgId,
          timestampMs: ts,
          body: body,
        );
        expect(bytesToHex(roundTrip(e)), bytesToHex(e.encode()));
      }
      final unknown = ControlBody.decode(Uint8List.fromList([0x7f, 9]));
      expect(unknown.controlType, isNull);
      expect(unknown.rawType, 0x7f);
    });

    test('MEDIA_CHUNK manifest (+expiry, +reply) and chunk', () {
      final hash = hexToBytes(
        '6c42397f3afe613d9ebabc186ebff9c6a23957b5b72fe54805ed859528ce4ec1',
      );
      final manifestBody = ManifestBody(
        chunkCount: 1,
        totalLen: 63,
        contentHash: hash,
        mime: 'text/plain',
      ).encode();
      final manifest = InnerEnvelope(
        type: InnerType.mediaChunk,
        msgId: msgId,
        timestampMs: ts,
        manifest: true,
        expirySeconds: 300,
        replyTo: other,
        body: manifestBody,
      );
      expect(bytesToHex(roundTrip(manifest)), bytesToHex(manifest.encode()));
      final decodedManifest = ManifestBody.decode(manifest.body);
      expect(decodedManifest.chunkCount, 1);
      expect(decodedManifest.totalLen, 63);
      expect(decodedManifest.mime, 'text/plain');
      expect(bytesToHex(decodedManifest.contentHash), bytesToHex(hash));

      final chunk = InnerEnvelope(
        type: InnerType.mediaChunk,
        msgId: other,
        timestampMs: ts,
        body: ChunkBody(
          manifestMsgId: msgId,
          chunkIndex: 0,
          data: Uint8List.fromList(utf8.encode('payload')),
        ).encode(),
      );
      expect(bytesToHex(roundTrip(chunk)), bytesToHex(chunk.encode()));
      final decodedChunk = ChunkBody.decode(chunk.body);
      expect(decodedChunk.chunkIndex, 0);
      expect(bytesToHex(decodedChunk.manifestMsgId), bytesToHex(msgId));
    });

    test('REACTION add / remove / multi-byte emoji', () {
      for (final op in ReactionOp.values) {
        final e = InnerEnvelope(
          type: InnerType.reaction,
          msgId: msgId,
          timestampMs: ts,
          body: ReactionBody(
            refMsgId: other,
            op: op,
            emoji: Uint8List.fromList(utf8.encode('🎉')),
          ).encode(),
        );
        expect(bytesToHex(roundTrip(e)), bytesToHex(e.encode()));
        final rb = ReactionBody.decode(e.body);
        expect(rb.op, op);
        expect(utf8.decode(rb.emoji), '🎉');
        expect(bytesToHex(rb.refMsgId), bytesToHex(other));
      }
    });
  });

  group('structural errors (each throws InnerEnvelopeError)', () {
    Uint8List header({
      int ver = innerVersion,
      required int type,
      int flags = 0,
      int extra = 0,
    }) {
      final b = Uint8List(baseHeaderBytes + extra);
      b[0] = ver;
      b[1] = type;
      b[2] = flags;
      b.setAll(3, msgId);
      ByteData.sublistView(b).setUint64(19, ts);
      return b;
    }

    void throws(Uint8List bytes) => expect(
      () => InnerEnvelope.decode(bytes),
      throwsA(isA<InnerEnvelopeError>()),
    );

    test('ver != 0x01', () => throws(header(ver: 0x02, type: 0x01)));

    test('undefined type (0x00 and >= 0x07)', () {
      throws(header(type: 0x00));
      throws(header(type: 0x07));
      throws(header(type: 0xFF));
    });

    test('reserved flag bits (mask 0xF8)', () {
      throws(header(type: 0x01, flags: 0x08));
      throws(header(type: 0x01, flags: 0x80));
    });

    test('flag-on-wrong-type', () {
      // expiry on ACK; reply_to on ACK.
      throws(
        header(type: InnerType.ack.wire, flags: flagExpiry, extra: 4 + 16),
      );
      throws(header(type: InnerType.ack.wire, flags: flagReplyTo, extra: 16));
      // manifest on TEXT.
      throws(header(type: InnerType.text.wire, flags: flagManifest));
      // expiry on CONTROL.
      throws(
        header(type: InnerType.control.wire, flags: flagExpiry, extra: 4 + 1),
      );
      // reply_to on a MEDIA_CHUNK chunk (manifest bit clear).
      throws(
        header(
          type: InnerType.mediaChunk.wire,
          flags: flagReplyTo,
          extra: 16 + 20,
        ),
      );
      // any flag bit on REACTION.
      throws(
        header(type: InnerType.reaction.wire, flags: flagExpiry, extra: 4 + 18),
      );
      throws(
        header(
          type: InnerType.reaction.wire,
          flags: flagReplyTo,
          extra: 16 + 18,
        ),
      );
      throws(
        header(type: InnerType.reaction.wire, flags: flagManifest, extra: 18),
      );
    });

    test('buffer shorter than the base header', () {
      throws(Uint8List.sublistView(header(type: 0x01), 0, 26));
    });

    test('bit0 (expiry) set but frame ends before expiry_s', () {
      // 27-byte base header + expiry flag, no expiry bytes → < 31.
      throws(header(type: InnerType.text.wire, flags: flagExpiry));
      // 30 bytes: still one short of expiry_s.
      throws(header(type: InnerType.text.wire, flags: flagExpiry, extra: 3));
    });

    test('bit2 (reply_to) set but frame ends before reply_to', () {
      throws(header(type: InnerType.text.wire, flags: flagReplyTo));
      throws(header(type: InnerType.text.wire, flags: flagReplyTo, extra: 15));
    });

    test('ACK body != 16', () {
      throws(header(type: InnerType.ack.wire, extra: 15));
      throws(header(type: InnerType.ack.wire, extra: 17));
      throws(header(type: InnerType.ack.wire)); // body empty
    });

    test('HANGUP body != 0', () {
      throws(header(type: InnerType.hangup.wire, extra: 1));
    });

    test('CONTROL body < 1', () {
      throws(header(type: InnerType.control.wire)); // empty body
    });

    test('read-receipt payload != 16', () {
      Uint8List control(List<int> body) {
        final h = header(type: InnerType.control.wire, extra: body.length);
        h.setAll(baseHeaderBytes, body);
        return h;
      }

      throws(control([ControlType.readReceipt.wire, 1, 2, 3]));
      throws(control([ControlType.readReceipt.wire])); // empty payload
      // typing/screenshot with a non-empty payload.
      throws(control([ControlType.typing.wire, 1]));
      throws(control([ControlType.screenshot.wire, 1]));
      // token-refresh carrying a malformed token_payload.
      throws(control([ControlType.tokenRefresh.wire, 0x02]));
    });

    test('REACTION structural set', () {
      Uint8List reaction(List<int> body) {
        final h = header(type: InnerType.reaction.wire, extra: body.length);
        h.setAll(baseHeaderBytes, body);
        return h;
      }

      final ref = List<int>.filled(16, 7);
      // body < 18.
      throws(reaction([...ref, 0x01]));
      // op not in {0, 1}.
      throws(reaction([...ref, 0x02, 0x01, 0x41]));
      // emoji_len 0 and > 64.
      throws(reaction([...ref, 0x01, 0x00]));
      throws(reaction([...ref, 0x01, 65, ...List<int>.filled(65, 0x41)]));
      // emoji_len disagrees with remaining length.
      throws(reaction([...ref, 0x01, 0x02, 0x41]));
      // invalid UTF-8 (lone continuation byte).
      throws(reaction([...ref, 0x01, 0x01, 0x80]));
    });
  });

  group('constructor rejects the same structural rules', () {
    test('manifest flag on a non-MEDIA_CHUNK type', () {
      expect(
        () => InnerEnvelope(
          type: InnerType.text,
          msgId: msgId,
          timestampMs: ts,
          manifest: true,
          body: Uint8List(0),
        ),
        throwsA(isA<InnerEnvelopeError>()),
      );
    });

    test('expiry/reply on an illegal type', () {
      expect(
        () => InnerEnvelope(
          type: InnerType.ack,
          msgId: msgId,
          timestampMs: ts,
          expirySeconds: 1,
          body: other,
        ),
        throwsA(isA<InnerEnvelopeError>()),
      );
    });

    test('wrong-length msg_id is caller misuse (ArgumentError)', () {
      expect(
        () => InnerEnvelope(
          type: InnerType.text,
          msgId: Uint8List(15),
          timestampMs: ts,
          body: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('vector conformance (docs/test-vectors/framing.json)', () {
    final vectors =
        jsonDecode(
              File('../../docs/test-vectors/framing.json').readAsStringSync(),
            )
            as Map<String, dynamic>;

    test('every envelope case decodes/encodes or rejects per the vector', () {
      final envelopes = (vectors['envelopes'] as List)
          .cast<Map<String, dynamic>>();
      expect(envelopes, isNotEmpty);
      for (final c in envelopes) {
        final bytes = hexToBytes(c['encoded'] as String);
        if (c['valid'] as bool) {
          final env = InnerEnvelope.decode(bytes);
          expect(
            bytesToHex(env.encode()),
            (c['encoded'] as String).toLowerCase(),
            reason: 'valid case "${c['name']}" must re-encode identically',
          );
        } else {
          expect(
            () => InnerEnvelope.decode(bytes),
            throwsA(isA<InnerEnvelopeError>()),
            reason: 'invalid case "${c['name']}" must throw',
          );
        }
      }
    });

    test('media_transfers manifest + chunk envelopes round-trip', () {
      final transfers =
          (vectors['media_transfers'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      for (final mt in transfers) {
        final manifestEnc =
            (mt['manifest_envelope'] as Map)['encoded'] as String;
        final manifest = InnerEnvelope.decode(hexToBytes(manifestEnc));
        expect(manifest.type, InnerType.mediaChunk);
        expect(manifest.manifest, isTrue);
        expect(bytesToHex(manifest.encode()), manifestEnc.toLowerCase());
        for (final ce in (mt['chunk_envelopes'] as List).cast<Map>()) {
          final enc = ce['encoded'] as String;
          final chunk = InnerEnvelope.decode(hexToBytes(enc));
          expect(chunk.manifest, isFalse);
          expect(bytesToHex(chunk.encode()), enc.toLowerCase());
        }
      }
    });
  });
}
