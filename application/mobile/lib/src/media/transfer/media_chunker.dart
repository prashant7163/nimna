/// Attachment plaintext → one MEDIA_CHUNK manifest + ordered chunk envelopes
/// (spec §5.1), using the FROZEN v0.2.1 codec verbatim (S10). Pure, stateless,
/// I/O-free, locale-independent — it adds NO wire behavior beyond the codec.
///
/// - `content_hash` = SHA-256 of the complete attachment plaintext (the exact
///   bytes `MediaRepository.add` also hashes), so the manifest matches the
///   sender's stored blob and the receiver's reassembly byte-for-byte.
/// - Chunk plaintext is 65,536 B for every chunk but the last;
///   `chunk_count = ceil(total_len / 65536)` (≤ 80 at the 5 MB cap).
/// - The manifest carries the transfer's `msg_id`, plus optional `expiry_s`
///   (flags bit 0) and `reply_to` (flags bit 2); chunks carry neither.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../protocol/inner_envelope.dart';

/// Chunk plaintext size (spec §5.1): 65,536 B for all but the last chunk.
const int mediaChunkPlaintextBytes = 65536;

/// The frames for one attachment: the manifest then its ordered chunks. Sealed
/// and sent in this order (manifest first) so the receiver buffers before any
/// chunk arrives.
class MediaFrames {
  const MediaFrames({required this.manifest, required this.chunks});

  final InnerEnvelope manifest;
  final List<InnerEnvelope> chunks;

  /// Manifest + chunks — the total number of SESSION_DATA frames.
  int get frameCount => 1 + chunks.length;
}

/// Splits an attachment into MEDIA_CHUNK envelopes (spec §5.1). Pure.
abstract final class MediaChunker {
  /// Builds the [MediaFrames] for [bytes]/[mime]. [manifestMsgId] names the
  /// transfer (and is the media message's `msg_id`); every chunk envelope gets
  /// its own fresh random `msg_id` (spec §5.5) via [randomBytes]. [timestampMs]
  /// is the sender's compose time; [expirySeconds]/[replyTo] ride the manifest.
  static MediaFrames chunk({
    required Uint8List bytes,
    required String mime,
    required Uint8List manifestMsgId,
    required int timestampMs,
    required Uint8List Function(int length) randomBytes,
    int? expirySeconds,
    Uint8List? replyTo,
  }) {
    final contentHash = Uint8List.fromList(crypto.sha256.convert(bytes).bytes);
    final chunkCount =
        (bytes.length + mediaChunkPlaintextBytes - 1) ~/
        mediaChunkPlaintextBytes;

    final manifest = InnerEnvelope(
      type: InnerType.mediaChunk,
      manifest: true,
      msgId: manifestMsgId,
      timestampMs: timestampMs,
      expirySeconds: expirySeconds,
      replyTo: replyTo,
      body: ManifestBody(
        chunkCount: chunkCount,
        totalLen: bytes.length,
        contentHash: contentHash,
        mime: mime,
      ).encode(),
    );

    final chunks = <InnerEnvelope>[];
    for (var i = 0; i < chunkCount; i++) {
      final start = i * mediaChunkPlaintextBytes;
      final end = start + mediaChunkPlaintextBytes < bytes.length
          ? start + mediaChunkPlaintextBytes
          : bytes.length;
      chunks.add(
        InnerEnvelope(
          type: InnerType.mediaChunk,
          msgId: randomBytes(msgIdBytes),
          timestampMs: timestampMs,
          body: ChunkBody(
            manifestMsgId: manifestMsgId,
            chunkIndex: i,
            data: Uint8List.sublistView(bytes, start, end),
          ).encode(),
        ),
      );
    }
    return MediaFrames(manifest: manifest, chunks: chunks);
  }
}
