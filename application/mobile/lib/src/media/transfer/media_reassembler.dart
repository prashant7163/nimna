/// Receiver-side MEDIA_CHUNK reassembly (spec §5.1). Pure, stateless outside
/// its per-transfer buffers; consumes the FROZEN codec verbatim. Structural
/// codec violations never reach here — the session's `_onSessionData` already
/// killed the session on any [InnerEnvelopeError] (§3.3.1). This layer decides
/// only TRANSFER-LEVEL outcomes, and its ONLY failure action is **discard the
/// transfer + NO ACK** (spec §5.1: "a resend is the sender's call") — never a
/// protocol error.
///
/// Buffers chunks by index under the manifest's `msg_id`; on completeness it
/// verifies `SHA-256 == content_hash` before signalling [complete].
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../protocol/inner_envelope.dart';
import 'media_chunker.dart' show mediaChunkPlaintextBytes;

/// Receiver-side HARD bounds on UNTRUSTED manifest values (spec §5.1). The
/// frozen codec validates only STRUCTURE, never magnitude — a hostile/buggy
/// peer can put `chunk_count` up to 2^32-1 and `total_len` up to 2^64-1 in a
/// well-formed manifest. The sender-side 5 MB cap does NOT protect the
/// receiver, so these bounds gate every allocation, BEFORE it happens.
const int maxMediaTotalLen = 5 * 1024 * 1024; // spec §5.1 cap
const int maxMediaChunkCount = 80; // ceil(5 MB / 65536) — the §5.1 upper bound

/// What a fed envelope produced.
enum MediaReassemblyOutcome {
  /// A chunk was buffered; the transfer is not yet complete.
  buffered,

  /// All chunks arrived and `SHA-256 == content_hash`: [MediaReassemblyResult.
  /// transfer] carries the assembled attachment.
  complete,

  /// A transfer-level failure (hash/length mismatch, out-of-range or duplicate
  /// index): the transfer was dropped — **no ACK**. [MediaReassemblyResult.
  /// reason] says why.
  discarded,

  /// A chunk arrived with no manifest buffered (chunk-before-manifest): dropped
  /// silently, no transfer to discard.
  ignored,
}

/// Why a transfer was discarded (diagnostics only; never user-surfaced).
enum MediaDiscardReason {
  hashMismatch,
  lengthMismatch,
  indexOutOfRange,
  duplicateChunk,

  /// The manifest's `chunk_count` / `total_len` exceed the §5.1 bounds, or are
  /// mutually inconsistent — rejected BEFORE any buffer is allocated (an OOM
  /// guard against untrusted manifest values).
  manifestOutOfBounds,
}

/// A completed transfer's assembled payload + manifest header fields.
class CompletedMediaTransfer {
  const CompletedMediaTransfer({
    required this.manifestMsgId,
    required this.bytes,
    required this.mime,
    required this.timestampMs,
    this.expirySeconds,
    this.replyTo,
  });

  final Uint8List manifestMsgId;
  final Uint8List bytes;
  final String mime;
  final int timestampMs;
  final int? expirySeconds;
  final Uint8List? replyTo;
}

/// The result of feeding one MEDIA_CHUNK envelope.
class MediaReassemblyResult {
  const MediaReassemblyResult(
    this.outcome, {
    this.transfer,
    this.reason,
    this.manifestMsgId,
    this.progress = 0,
  });

  final MediaReassemblyOutcome outcome;

  /// Present iff [outcome] is [MediaReassemblyOutcome.complete].
  final CompletedMediaTransfer? transfer;

  /// Present iff [outcome] is [MediaReassemblyOutcome.discarded].
  final MediaDiscardReason? reason;

  /// The transfer this result concerns (null when [MediaReassemblyOutcome.
  /// ignored] — a chunk with no manifest).
  final Uint8List? manifestMsgId;

  /// 0..1 received fraction (advisory; components.md progress line).
  final double progress;
}

class _PendingTransfer {
  _PendingTransfer({
    required this.manifestMsgId,
    required this.chunkCount,
    required this.totalLen,
    required this.contentHash,
    required this.mime,
    required this.timestampMs,
    this.expirySeconds,
    this.replyTo,
  }) : chunks = List<Uint8List?>.filled(chunkCount, null),
       received = 0;

  final Uint8List manifestMsgId;
  final int chunkCount;
  final int totalLen;
  final Uint8List contentHash;
  final String mime;
  final int timestampMs;
  final int? expirySeconds;
  final Uint8List? replyTo;

  final List<Uint8List?> chunks;
  int received;

  double get progress => chunkCount == 0 ? 1 : received / chunkCount;
}

/// Per-session reassembly buffer. One instance per [MediaReassembler] holder
/// (the session's media controller).
class MediaReassembler {
  final Map<String, _PendingTransfer> _pending = {};

  /// Feeds one structurally-valid MEDIA_CHUNK envelope (manifest or chunk).
  MediaReassemblyResult onEnvelope(InnerEnvelope env) {
    return env.manifest ? _onManifest(env) : _onChunk(env);
  }

  MediaReassemblyResult _onManifest(InnerEnvelope env) {
    final body = ManifestBody.decode(env.body);
    // Enforce the §5.1 envelope on UNTRUSTED manifest values BEFORE allocating
    // `List.filled(chunkCount)` / `Uint8List(totalLen)` — otherwise a peer's
    // `chunk_count = 0xFFFFFFFF` / `total_len = 2^64-1` is an instant OOM. This
    // is a TRANSFER-LEVEL discard (no ACK, session stays live) — a policy bound,
    // not a §3.3.1 structural codec error.
    if (!_manifestWithinBounds(body)) {
      return MediaReassemblyResult(
        MediaReassemblyOutcome.discarded,
        manifestMsgId: env.msgId,
        reason: MediaDiscardReason.manifestOutOfBounds,
      );
    }
    final pending = _PendingTransfer(
      manifestMsgId: env.msgId,
      chunkCount: body.chunkCount,
      totalLen: body.totalLen,
      contentHash: body.contentHash,
      mime: body.mime,
      timestampMs: env.timestampMs,
      expirySeconds: env.expirySeconds,
      replyTo: env.replyTo,
    );
    // A manifest resend restarts the transfer (idempotent; the sender's call).
    _pending[_hex(env.msgId)] = pending;
    // A zero-chunk manifest (empty attachment) completes immediately.
    if (pending.chunkCount == 0) {
      return _tryComplete(pending);
    }
    return MediaReassemblyResult(
      MediaReassemblyOutcome.buffered,
      manifestMsgId: env.msgId,
      progress: pending.progress,
    );
  }

  MediaReassemblyResult _onChunk(InnerEnvelope env) {
    final body = ChunkBody.decode(env.body);
    final key = _hex(body.manifestMsgId);
    final pending = _pending[key];
    if (pending == null) {
      // Chunk before manifest: nothing to discard, drop silently (spec §5.1).
      return MediaReassemblyResult(
        MediaReassemblyOutcome.ignored,
        manifestMsgId: body.manifestMsgId,
      );
    }
    if (body.chunkIndex < 0 || body.chunkIndex >= pending.chunkCount) {
      return _discard(key, pending, MediaDiscardReason.indexOutOfRange);
    }
    if (pending.chunks[body.chunkIndex] != null) {
      return _discard(key, pending, MediaDiscardReason.duplicateChunk);
    }
    pending.chunks[body.chunkIndex] = body.data;
    pending.received++;
    if (pending.received == pending.chunkCount) {
      return _tryComplete(pending);
    }
    return MediaReassemblyResult(
      MediaReassemblyOutcome.buffered,
      manifestMsgId: pending.manifestMsgId,
      progress: pending.progress,
    );
  }

  MediaReassemblyResult _tryComplete(_PendingTransfer pending) {
    final key = _hex(pending.manifestMsgId);
    final assembled = Uint8List(pending.totalLen);
    var off = 0;
    for (final chunk in pending.chunks) {
      if (chunk == null) {
        // Unreachable when received == chunkCount, but fail closed regardless.
        return _discard(key, pending, MediaDiscardReason.lengthMismatch);
      }
      if (off + chunk.length > pending.totalLen) {
        return _discard(key, pending, MediaDiscardReason.lengthMismatch);
      }
      assembled.setAll(off, chunk);
      off += chunk.length;
    }
    if (off != pending.totalLen) {
      return _discard(key, pending, MediaDiscardReason.lengthMismatch);
    }
    final hash = Uint8List.fromList(crypto.sha256.convert(assembled).bytes);
    if (!_constantTimeEquals(hash, pending.contentHash)) {
      return _discard(key, pending, MediaDiscardReason.hashMismatch);
    }
    _pending.remove(key);
    return MediaReassemblyResult(
      MediaReassemblyOutcome.complete,
      manifestMsgId: pending.manifestMsgId,
      progress: 1,
      transfer: CompletedMediaTransfer(
        manifestMsgId: pending.manifestMsgId,
        bytes: assembled,
        mime: pending.mime,
        timestampMs: pending.timestampMs,
        expirySeconds: pending.expirySeconds,
        replyTo: pending.replyTo,
      ),
    );
  }

  MediaReassemblyResult _discard(
    String key,
    _PendingTransfer pending,
    MediaDiscardReason reason,
  ) {
    _pending.remove(key);
    return MediaReassemblyResult(
      MediaReassemblyOutcome.discarded,
      manifestMsgId: pending.manifestMsgId,
      reason: reason,
    );
  }

  /// Drops all buffered partial transfers (session end / teardown).
  void clear() => _pending.clear();

  /// True iff the manifest's magnitudes are within the §5.1 envelope AND
  /// mutually consistent. `total_len` is a decoded uint64 — values above 2^63
  /// come back negative in Dart, which this rejects. `chunk_count` must equal
  /// `ceil(total_len / 65536)` (an over-large count would over-allocate).
  static bool _manifestWithinBounds(ManifestBody body) {
    if (body.totalLen < 0 || body.totalLen > maxMediaTotalLen) {
      return false;
    }
    if (body.chunkCount < 0 || body.chunkCount > maxMediaChunkCount) {
      return false;
    }
    final expected =
        (body.totalLen + mediaChunkPlaintextBytes - 1) ~/
        mediaChunkPlaintextBytes;
    return body.chunkCount == expected;
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _hex(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out
        ..write(digits[(b >> 4) & 0x0F])
        ..write(digits[b & 0x0F]);
    }
    return out.toString();
  }
}
