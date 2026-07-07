import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/media/transfer/media_chunker.dart';
import 'package:nimna/src/media/transfer/media_reassembler.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';

/// S11 media transfer — the chunker and reassembler against the FROZEN v0.2.1
/// codec (S10). Every envelope round-trips through InnerEnvelope.encode/decode
/// (proving zero wire change); the reassembler enforces the spec §5.1 error
/// taxonomy: discard + NO ACK on any transfer-integrity failure, never a
/// protocol error.
void main() {
  // A deterministic 16-byte id generator for chunk envelope msg_ids.
  int counter = 0;
  Uint8List seq(int length) {
    final out = Uint8List(length);
    out[length - 1] = counter++ & 0xFF;
    return out;
  }

  Uint8List body(int n, int seed) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = (i * 31 + seed) & 0xFF;
    }
    return out;
  }

  /// Serializes each frame and re-decodes it, exactly as the wire would — the
  /// reassembler only ever sees decoded envelopes.
  InnerEnvelope wire(InnerEnvelope env) => InnerEnvelope.decode(env.encode());

  final manifestId = Uint8List.fromList(List.generate(16, (i) => i + 1));

  MediaFrames build(
    Uint8List bytes, {
    String mime = 'image/jpeg',
    int? expirySeconds,
    Uint8List? replyTo,
  }) => MediaChunker.chunk(
    bytes: bytes,
    mime: mime,
    manifestMsgId: manifestId,
    timestampMs: 1720000000000,
    randomBytes: seq,
    expirySeconds: expirySeconds,
    replyTo: replyTo,
  );

  test('multi-chunk round trip reassembles byte-identical + hash verified', () {
    final bytes = body(mediaChunkPlaintextBytes * 2 + 777, 5); // 3 chunks
    final frames = build(bytes, expirySeconds: 900);
    expect(frames.chunks, hasLength(3));

    final r = MediaReassembler();
    final m = r.onEnvelope(wire(frames.manifest));
    expect(m.outcome, MediaReassemblyOutcome.buffered);

    MediaReassemblyResult? last;
    for (final chunk in frames.chunks) {
      last = r.onEnvelope(wire(chunk));
    }
    expect(last!.outcome, MediaReassemblyOutcome.complete);
    final t = last.transfer!;
    expect(t.bytes, equals(bytes));
    expect(t.mime, 'image/jpeg');
    expect(t.expirySeconds, 900);
    expect(
      Uint8List.fromList(crypto.sha256.convert(t.bytes).bytes),
      equals(Uint8List.fromList(crypto.sha256.convert(bytes).bytes)),
    );
  });

  test('manifest carries reply_to; the manifest is a replyable referent', () {
    final replyTo = Uint8List.fromList(List.generate(16, (i) => 200 - i));
    final frames = build(body(100, 1), replyTo: replyTo);
    final decoded = wire(frames.manifest);
    expect(decoded.manifest, isTrue);
    expect(decoded.replyTo, equals(replyTo));
  });

  test('single short chunk (< 64 KiB) completes', () {
    final bytes = body(1234, 9);
    final frames = build(bytes);
    expect(frames.chunks, hasLength(1));
    final r = MediaReassembler();
    r.onEnvelope(wire(frames.manifest));
    final done = r.onEnvelope(wire(frames.chunks.single));
    expect(done.outcome, MediaReassemblyOutcome.complete);
    expect(done.transfer!.bytes, equals(bytes));
  });

  test('chunk_count = ceil(total_len / 65536), ≤ 80 at the 5 MB cap', () {
    // Exactly 5 MB → 80 chunks (the spec §5.1 upper bound).
    final frames = build(Uint8List(5 * 1024 * 1024));
    expect(frames.chunks, hasLength(80));
    // One byte over a chunk boundary → +1 chunk.
    expect(build(Uint8List(mediaChunkPlaintextBytes + 1)).chunks, hasLength(2));
    expect(build(Uint8List(mediaChunkPlaintextBytes)).chunks, hasLength(1));
  });

  test('HASH MISMATCH → discard + NO complete (never a protocol error)', () {
    final bytes = body(mediaChunkPlaintextBytes + 10, 3);
    final frames = build(bytes);
    final r = MediaReassembler();
    r.onEnvelope(wire(frames.manifest));
    // Corrupt the LAST chunk's payload (structurally valid, content wrong).
    final good = ChunkBody.decode(frames.chunks.last.body);
    final tampered = Uint8List.fromList(good.data)..[0] ^= 0xFF;
    final badChunk = InnerEnvelope(
      type: InnerType.mediaChunk,
      msgId: seq(16),
      timestampMs: 0,
      body: ChunkBody(
        manifestMsgId: manifestId,
        chunkIndex: good.chunkIndex,
        data: tampered,
      ).encode(),
    );
    r.onEnvelope(wire(frames.chunks.first));
    final result = r.onEnvelope(wire(badChunk));
    expect(result.outcome, MediaReassemblyOutcome.discarded);
    expect(result.reason, MediaDiscardReason.hashMismatch);
    expect(result.transfer, isNull);
  });

  test('chunk BEFORE its manifest is ignored (nothing to discard)', () {
    final frames = build(body(100, 1));
    final r = MediaReassembler();
    final result = r.onEnvelope(wire(frames.chunks.single));
    expect(result.outcome, MediaReassemblyOutcome.ignored);
  });

  test('out-of-range chunk index → discard', () {
    final frames = build(body(100, 1)); // 1 chunk, valid index 0
    final r = MediaReassembler();
    r.onEnvelope(wire(frames.manifest));
    final bad = InnerEnvelope(
      type: InnerType.mediaChunk,
      msgId: seq(16),
      timestampMs: 0,
      body: ChunkBody(
        manifestMsgId: manifestId,
        chunkIndex: 9, // out of [0, 1)
        data: body(10, 0),
      ).encode(),
    );
    final result = r.onEnvelope(wire(bad));
    expect(result.outcome, MediaReassemblyOutcome.discarded);
    expect(result.reason, MediaDiscardReason.indexOutOfRange);
  });

  test('duplicate chunk index → discard', () {
    final bytes = body(mediaChunkPlaintextBytes + 10, 2); // 2 chunks
    final frames = build(bytes);
    final r = MediaReassembler();
    r.onEnvelope(wire(frames.manifest));
    r.onEnvelope(wire(frames.chunks[0]));
    final dup = r.onEnvelope(wire(frames.chunks[0])); // same index again
    expect(dup.outcome, MediaReassemblyOutcome.discarded);
    expect(dup.reason, MediaDiscardReason.duplicateChunk);
  });
}
