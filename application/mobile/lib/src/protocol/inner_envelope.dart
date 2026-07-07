/// §5.5–§5.8 inner envelope — the plaintext of every transport AEAD (spec
/// v0.2.1 §5.5), the S10 codec checkpoint. Pure, stateless, I/O-free,
/// locale-independent; byte-identical to the Go stack and vector-locked to
/// `docs/test-vectors/framing.json`.
///
/// This file is the frozen §5.5 surface: the header codec, the six inner
/// types, and the per-type body codecs (ACK / CONTROL / MEDIA_CHUNK
/// manifest+chunk). REACTION (§5.8) bodies live in `reaction_body.dart`.
/// Transport-key STATE lives in `lib/src/noise` — the codec here stays pure.
///
/// All integers big-endian. No serialization library (crypto/framing lock).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'reaction_body.dart';
import 'token_payload.dart';

/// Inner-envelope version byte (spec §5.5).
const int innerVersion = 0x01;

/// `msg_id` / `reply_to` / `acked_msg_id` length — 16 bytes everywhere.
const int msgIdBytes = 16;

/// Base header length: `ver(1) ‖ type(1) ‖ flags(1) ‖ msg_id(16) ‖
/// timestamp(8)` (spec §5.5). `expiry_s` adds 4, `reply_to` adds 16.
const int baseHeaderBytes = 27;

/// flags bit 0 — `expiry_s` present (TEXT and MEDIA_CHUNK-manifest only).
const int flagExpiry = 0x01;

/// flags bit 1 — MEDIA_CHUNK manifest (MEDIA_CHUNK only).
const int flagManifest = 0x02;

/// flags bit 2 (v0.2.1) — `reply_to` present (TEXT and MEDIA_CHUNK-manifest
/// only).
const int flagReplyTo = 0x04;

/// Reserved flag bits (mask 0xF8) — must be 0 (spec §5.5).
const int reservedFlagMask = 0xF8;

/// The six inner-envelope types (spec §5.5). Wire values are spec-fixed;
/// never renumber.
enum InnerType {
  /// `0x01` — UTF-8 message body (§5.5, §5).
  text(0x01),

  /// `0x02` — `acked_msg_id(16)` (§5.5).
  ack(0x02),

  /// `0x03` — `control_type(1) ‖ control_payload` (§5.5).
  control(0x03),

  /// `0x04` — authenticated end-of-session marker; body empty (§3.3, §5.5).
  hangup(0x04),

  /// `0x05` — chunked media manifest/chunk bodies (§5.1).
  mediaChunk(0x05),

  /// `0x06` (v0.2.1) — single-emoji reaction on a referenced message (§5.8).
  reaction(0x06);

  const InnerType(this.wire);

  /// Spec-fixed wire value.
  final int wire;

  static final Map<int, InnerType> _byWire = {
    for (final t in InnerType.values) t.wire: t,
  };

  static InnerType? fromWire(int wire) => _byWire[wire];
}

/// CONTROL `control_type` values (spec §5.5). The wire is a raw byte;
/// unknown values decode OK and are ignored (forward compatibility).
enum ControlType {
  /// `0x01` typing indicator — empty payload.
  typing(0x01),

  /// `0x02` read receipt — `msg_id(16)` payload.
  readReceipt(0x02),

  /// `0x03` screenshot notice — empty payload (§5.2).
  screenshot(0x03),

  /// `0x04` device-token refresh — `token_payload` (§5.7; "absent" revokes).
  tokenRefresh(0x04);

  const ControlType(this.wire);

  final int wire;

  static ControlType? fromWire(int wire) {
    for (final c in ControlType.values) {
      if (c.wire == wire) {
        return c;
      }
    }
    return null;
  }
}

/// Raised on any structural violation of §5.5–§5.8 — a §3.3.1 protocol
/// error the session layer acts on (destroy keys + TEARDOWN). Carries NO
/// frame bytes by design (mirrors [OuterFrameError]/[TokenPayloadError]).
class InnerEnvelopeError extends Error {
  @override
  String toString() => 'InnerEnvelopeError';
}

Uint8List _copy(Uint8List src, [int? start, int? end]) =>
    Uint8List.fromList(Uint8List.sublistView(src, start ?? 0, end));

/// One decoded inner envelope (spec §5.5). Header fields are typed; [body] is
/// the raw per-type body — decode it with the matching body codec ([AckBody],
/// [ControlBody], [ManifestBody]/[ChunkBody], [ReactionBody]). Optional
/// header fields are modeled by nullable [expirySeconds]/[replyTo] and the
/// [manifest] flag; the raw flags byte is derived, never stored.
class InnerEnvelope {
  /// Constructs and structurally validates an envelope (spec §5.5–§5.8).
  /// Throws [InnerEnvelopeError] on any structural rule; [ArgumentError] only
  /// for a wrong-length [msgId]/[replyTo] (caller misuse, never on the wire).
  factory InnerEnvelope({
    required InnerType type,
    required Uint8List msgId,
    required int timestampMs,
    int? expirySeconds,
    Uint8List? replyTo,
    bool manifest = false,
    required Uint8List body,
  }) {
    if (msgId.length != msgIdBytes) {
      throw ArgumentError.value(msgId.length, 'msgId', 'must be 16 bytes');
    }
    if (replyTo != null && replyTo.length != msgIdBytes) {
      throw ArgumentError.value(replyTo.length, 'replyTo', 'must be 16 bytes');
    }
    _validateFlags(
      type: type,
      manifest: manifest,
      hasExpiry: expirySeconds != null,
      hasReply: replyTo != null,
    );
    _validateBody(type, manifest, body);
    return InnerEnvelope._(
      type: type,
      msgId: _copy(msgId),
      timestampMs: timestampMs,
      expirySeconds: expirySeconds,
      replyTo: replyTo == null ? null : _copy(replyTo),
      manifest: manifest,
      body: _copy(body),
    );
  }

  InnerEnvelope._({
    required this.type,
    required this.msgId,
    required this.timestampMs,
    required this.expirySeconds,
    required this.replyTo,
    required this.manifest,
    required this.body,
  });

  final InnerType type;

  /// Client-generated, 16 random bytes, unique per message.
  final Uint8List msgId;

  /// Sender local time, Unix milliseconds (uint64).
  final int timestampMs;

  /// Present only when flags bit 0 is set (TEXT / MEDIA_CHUNK manifest).
  final int? expirySeconds;

  /// Present only when flags bit 2 is set — the `msg_id` this replies to
  /// (§5.8). 16 bytes.
  final Uint8List? replyTo;

  /// flags bit 1 — this MEDIA_CHUNK envelope is the transfer's manifest.
  final bool manifest;

  /// The raw per-type body (spec §5.5); decode with the matching body codec.
  final Uint8List body;

  /// The reconstructed flags byte (derived, spec §5.5).
  int get flags =>
      (expirySeconds != null ? flagExpiry : 0) |
      (manifest ? flagManifest : 0) |
      (replyTo != null ? flagReplyTo : 0);

  /// Serializes to wire bytes (spec §5.5). Optional fields appear in flag-bit
  /// order: `expiry_s` then `reply_to`.
  Uint8List encode() {
    final hasExpiry = expirySeconds != null;
    final hasReply = replyTo != null;
    final headerLen =
        baseHeaderBytes + (hasExpiry ? 4 : 0) + (hasReply ? 16 : 0);
    final out = Uint8List(headerLen + body.length);
    out[0] = innerVersion;
    out[1] = type.wire;
    out[2] = flags;
    out.setAll(3, msgId);
    final bd = ByteData.sublistView(out);
    bd.setUint64(19, timestampMs);
    var off = baseHeaderBytes;
    if (hasExpiry) {
      bd.setUint32(off, expirySeconds!);
      off += 4;
    }
    if (hasReply) {
      out.setAll(off, replyTo!);
      off += 16;
    }
    out.setAll(off, body);
    return out;
  }

  /// Parses and structurally validates an inner envelope (spec §5.5–§5.8).
  /// Throws [InnerEnvelopeError] on any violation.
  static InnerEnvelope decode(Uint8List bytes) {
    if (bytes.length < baseHeaderBytes) {
      throw InnerEnvelopeError();
    }
    if (bytes[0] != innerVersion) {
      throw InnerEnvelopeError();
    }
    final type = InnerType.fromWire(bytes[1]);
    if (type == null) {
      throw InnerEnvelopeError();
    }
    final flags = bytes[2];
    if (flags & reservedFlagMask != 0) {
      throw InnerEnvelopeError();
    }
    final hasExpiry = flags & flagExpiry != 0;
    final manifest = flags & flagManifest != 0;
    final hasReply = flags & flagReplyTo != 0;
    _validateFlags(
      type: type,
      manifest: manifest,
      hasExpiry: hasExpiry,
      hasReply: hasReply,
    );

    final bd = ByteData.sublistView(bytes);
    final timestampMs = bd.getUint64(19);
    var off = baseHeaderBytes;
    int? expirySeconds;
    if (hasExpiry) {
      if (bytes.length < off + 4) {
        throw InnerEnvelopeError();
      }
      expirySeconds = bd.getUint32(off);
      off += 4;
    }
    Uint8List? replyTo;
    if (hasReply) {
      if (bytes.length < off + 16) {
        throw InnerEnvelopeError();
      }
      replyTo = _copy(bytes, off, off + 16);
      off += 16;
    }
    final body = _copy(bytes, off);
    _validateBody(type, manifest, body);
    return InnerEnvelope._(
      type: type,
      msgId: _copy(bytes, 3, 19),
      timestampMs: timestampMs,
      expirySeconds: expirySeconds,
      replyTo: replyTo,
      manifest: manifest,
      body: body,
    );
  }

  /// Flag legality (spec §5.5): reserved bits already rejected by the caller.
  /// bit 0 (expiry) and bit 2 (reply_to) are legal ONLY on TEXT or a
  /// MEDIA_CHUNK manifest (identical predicate); bit 1 (manifest) only on
  /// MEDIA_CHUNK.
  static void _validateFlags({
    required InnerType type,
    required bool manifest,
    required bool hasExpiry,
    required bool hasReply,
  }) {
    if (manifest && type != InnerType.mediaChunk) {
      throw InnerEnvelopeError();
    }
    final optionalLegal =
        type == InnerType.text || (type == InnerType.mediaChunk && manifest);
    if ((hasExpiry || hasReply) && !optionalLegal) {
      throw InnerEnvelopeError();
    }
  }

  /// Per-type body structural rules (spec §5.5, §5.1, §5.8). TEXT has no
  /// structural constraint (the 5000-char cap is compose-time, not on the
  /// wire).
  static void _validateBody(InnerType type, bool manifest, Uint8List body) {
    switch (type) {
      case InnerType.text:
        break;
      case InnerType.ack:
        if (body.length != msgIdBytes) {
          throw InnerEnvelopeError();
        }
      case InnerType.control:
        ControlBody.validate(body);
      case InnerType.hangup:
        if (body.isNotEmpty) {
          throw InnerEnvelopeError();
        }
      case InnerType.mediaChunk:
        if (manifest) {
          ManifestBody.validate(body);
        } else {
          ChunkBody.validate(body);
        }
      case InnerType.reaction:
        ReactionBody.validate(body);
    }
  }
}

/// ACK body (spec §5.5): `acked_msg_id(16)` exactly.
class AckBody {
  AckBody({required Uint8List ackedMsgId}) : ackedMsgId = _copy(ackedMsgId) {
    if (ackedMsgId.length != msgIdBytes) {
      throw ArgumentError.value(
        ackedMsgId.length,
        'ackedMsgId',
        'must be 16 bytes',
      );
    }
  }

  /// The `msg_id` this ACK confirms.
  final Uint8List ackedMsgId;

  Uint8List encode() => _copy(ackedMsgId);

  static AckBody decode(Uint8List body) {
    if (body.length != msgIdBytes) {
      throw InnerEnvelopeError();
    }
    return AckBody(ackedMsgId: body);
  }
}

/// CONTROL body (spec §5.5): `control_type(1) ‖ control_payload`. Unknown
/// control types decode OK and are ignored — never an error (forward
/// compatibility, §5.5). [controlType] is null for an unknown/forward wire
/// value; [rawType] carries the byte.
class ControlBody {
  ControlBody({required this.rawType, required Uint8List payload})
    : payload = _copy(payload);

  /// The raw `control_type` byte (spec §5.5).
  final int rawType;

  /// The `control_payload` (per `control_type`).
  final Uint8List payload;

  /// The known [ControlType], or null for a forward-compat unknown value.
  ControlType? get controlType => ControlType.fromWire(rawType);

  Uint8List encode() {
    final out = Uint8List(1 + payload.length);
    out[0] = rawType;
    out.setAll(1, payload);
    return out;
  }

  static ControlBody decode(Uint8List body) {
    validate(body);
    return ControlBody(rawType: body[0], payload: _copy(body, 1));
  }

  /// Structural rules (spec §5.5): body carries at least `control_type`;
  /// typing/screenshot payloads are empty; read-receipt is `msg_id(16)`;
  /// token-refresh is a valid `token_payload` (§5.7). Unknown `control_type`
  /// values pass (ignored, never an error).
  static void validate(Uint8List body) {
    if (body.isEmpty) {
      throw InnerEnvelopeError();
    }
    final payload = Uint8List.sublistView(body, 1);
    switch (ControlType.fromWire(body[0])) {
      case ControlType.typing:
      case ControlType.screenshot:
        if (payload.isNotEmpty) {
          throw InnerEnvelopeError();
        }
      case ControlType.readReceipt:
        if (payload.length != msgIdBytes) {
          throw InnerEnvelopeError();
        }
      case ControlType.tokenRefresh:
        try {
          TokenPayload.decode(Uint8List.fromList(payload));
        } on TokenPayloadError {
          throw InnerEnvelopeError();
        }
      case null:
        // Unknown control_type: decodes OK, ignored (§5.5).
        break;
    }
  }
}

/// MEDIA_CHUNK manifest body (spec §5.1): `chunk_count(4) ‖ total_len(8) ‖
/// content_hash(32) ‖ mime_len(1) ‖ mime`.
class ManifestBody {
  ManifestBody({
    required this.chunkCount,
    required this.totalLen,
    required Uint8List contentHash,
    required this.mime,
  }) : contentHash = _copy(contentHash) {
    if (contentHash.length != _hashBytes) {
      throw ArgumentError.value(
        contentHash.length,
        'contentHash',
        'must be 32 bytes',
      );
    }
    if (_mimeBytes(mime).length > 0xFF) {
      throw ArgumentError.value(mime, 'mime', 'exceeds 255 bytes');
    }
  }

  static const int _hashBytes = 32;

  /// `ceil(total_len / 65536)` (§5.1) — a structural count, not re-derived
  /// here (reassembly is the receiver's job, S11).
  final int chunkCount;

  /// Total attachment plaintext length (post-compression, post-strip).
  final int totalLen;

  /// SHA-256 of the complete reassembled attachment plaintext.
  final Uint8List contentHash;

  /// The attachment MIME type (UTF-8).
  final String mime;

  static Uint8List _mimeBytes(String mime) =>
      Uint8List.fromList(utf8.encode(mime));

  Uint8List encode() {
    final mimeBytes = _mimeBytes(mime);
    final out = Uint8List(45 + mimeBytes.length);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, chunkCount);
    bd.setUint64(4, totalLen);
    out.setAll(12, contentHash);
    out[44] = mimeBytes.length;
    out.setAll(45, mimeBytes);
    return out;
  }

  static ManifestBody decode(Uint8List body) {
    validate(body);
    final bd = ByteData.sublistView(body);
    return ManifestBody(
      chunkCount: bd.getUint32(0),
      totalLen: bd.getUint64(4),
      contentHash: _copy(body, 12, 44),
      mime: utf8.decode(Uint8List.sublistView(body, 45)),
    );
  }

  /// Structural rules (spec §5.1): at least the 45 fixed bytes, and
  /// `mime_len` matches the remaining length exactly.
  static void validate(Uint8List body) {
    if (body.length < 45) {
      throw InnerEnvelopeError();
    }
    final mimeLen = body[44];
    if (body.length != 45 + mimeLen) {
      throw InnerEnvelopeError();
    }
  }
}

/// MEDIA_CHUNK chunk body (spec §5.1): `manifest_msg_id(16) ‖
/// chunk_index(4, 0-based) ‖ chunk_data`.
class ChunkBody {
  ChunkBody({
    required Uint8List manifestMsgId,
    required this.chunkIndex,
    required Uint8List data,
  }) : manifestMsgId = _copy(manifestMsgId),
       data = _copy(data) {
    if (manifestMsgId.length != msgIdBytes) {
      throw ArgumentError.value(
        manifestMsgId.length,
        'manifestMsgId',
        'must be 16 bytes',
      );
    }
  }

  static const int _headerBytes = 20;

  /// The manifest's `msg_id` — names the transfer this chunk belongs to.
  final Uint8List manifestMsgId;

  /// 0-based chunk index.
  final int chunkIndex;

  /// The chunk plaintext (65,536 bytes for every chunk but the last — a
  /// transfer-level rule, not enforced here per-frame).
  final Uint8List data;

  Uint8List encode() {
    final out = Uint8List(_headerBytes + data.length);
    out.setAll(0, manifestMsgId);
    ByteData.sublistView(out).setUint32(16, chunkIndex);
    out.setAll(_headerBytes, data);
    return out;
  }

  static ChunkBody decode(Uint8List body) {
    validate(body);
    return ChunkBody(
      manifestMsgId: _copy(body, 0, 16),
      chunkIndex: ByteData.sublistView(body).getUint32(16),
      data: _copy(body, _headerBytes),
    );
  }

  /// Structural rule (spec §5.1): at least the 20 fixed bytes.
  static void validate(Uint8List body) {
    if (body.length < _headerBytes) {
      throw InnerEnvelopeError();
    }
  }
}
