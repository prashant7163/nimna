/// REACTION body (spec v0.2.1 §5.5, §5.8) — the sixth inner-envelope type's
/// body: `ref_msg_id(16) ‖ op(1) ‖ emoji_len(1) ‖ emoji(emoji_len)`. Pure,
/// stateless, I/O-free, locale-independent; byte-identical to the Go stack.
///
/// Receivers never grapheme-segment (spec §5.5: protocol behavior must not
/// depend on Unicode segmentation tables). The only content check is UTF-8
/// validity; the sender-side single-grapheme rule is compose-time, never
/// receiver-validated. Structural violations throw [InnerEnvelopeError] — a
/// §3.3.1 protocol error, exactly as any malformed frame (§5.8).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'inner_envelope.dart';

/// REACTION add/remove op (spec §5.5). `remove` clears the sender's reaction
/// unconditionally, whatever emoji it carries (§5.8).
enum ReactionOp {
  /// `0x00` — remove.
  remove(0x00),

  /// `0x01` — add (set or replace the sender's reaction).
  add(0x01);

  const ReactionOp(this.wire);

  final int wire;

  static ReactionOp? fromWire(int wire) {
    for (final op in ReactionOp.values) {
      if (op.wire == wire) {
        return op;
      }
    }
    return null;
  }
}

/// A decoded REACTION body (spec §5.8).
class ReactionBody {
  /// Constructs and validates a REACTION body. [emoji] must be 1–64 bytes of
  /// valid UTF-8 (spec §5.5). Throws [InnerEnvelopeError] on any structural
  /// violation.
  factory ReactionBody({
    required Uint8List refMsgId,
    required ReactionOp op,
    required Uint8List emoji,
  }) {
    if (refMsgId.length != msgIdBytes) {
      throw ArgumentError.value(
        refMsgId.length,
        'refMsgId',
        'must be 16 bytes',
      );
    }
    _validateEmoji(emoji);
    return ReactionBody._(
      refMsgId: Uint8List.fromList(refMsgId),
      op: op,
      emoji: Uint8List.fromList(emoji),
    );
  }

  ReactionBody._({
    required this.refMsgId,
    required this.op,
    required this.emoji,
  });

  /// Minimum body length: `ref_msg_id(16) ‖ op(1) ‖ emoji_len(1)` with a
  /// 1-byte emoji floor makes 18 the true minimum (spec §5.8: `body < 18` is
  /// malformed).
  static const int minBodyBytes = 18;

  /// The `msg_id` this reaction references — a TEXT or MEDIA_CHUNK manifest
  /// (§5.8). Unknown/deleted/expired referents are the receiver's SILENT-DROP
  /// concern (§5.8), never a structural error handled here.
  final Uint8List refMsgId;

  /// Add or remove (spec §5.8).
  final ReactionOp op;

  /// 1–64 bytes of valid UTF-8; exactly one emoji grapheme by the
  /// (compose-time) sender rule, never receiver-segmented.
  final Uint8List emoji;

  Uint8List encode() {
    _validateEmoji(emoji);
    final out = Uint8List(minBodyBytes + emoji.length);
    out.setAll(0, refMsgId);
    out[16] = op.wire;
    out[17] = emoji.length;
    out.setAll(18, emoji);
    return out;
  }

  static ReactionBody decode(Uint8List body) {
    validate(body);
    return ReactionBody._(
      refMsgId: Uint8List.fromList(Uint8List.sublistView(body, 0, 16)),
      op: ReactionOp.fromWire(body[16])!,
      emoji: Uint8List.fromList(Uint8List.sublistView(body, 18)),
    );
  }

  /// Structural rules (spec §5.8): `body ≥ 18`; `op ∈ {0x00, 0x01}`;
  /// `emoji_len ∈ [1, 64]`; `emoji_len` equals the remaining length; the
  /// emoji is valid UTF-8. Any REACTION flag bit is rejected at the envelope
  /// layer ([InnerEnvelope]) before this runs.
  static void validate(Uint8List body) {
    if (body.length < minBodyBytes) {
      throw InnerEnvelopeError();
    }
    if (ReactionOp.fromWire(body[16]) == null) {
      throw InnerEnvelopeError();
    }
    final emojiLen = body[17];
    if (emojiLen < 1 || emojiLen > 64) {
      throw InnerEnvelopeError();
    }
    final emoji = Uint8List.sublistView(body, 18);
    if (emoji.length != emojiLen) {
      throw InnerEnvelopeError();
    }
    _checkUtf8(emoji);
  }

  static void _validateEmoji(Uint8List emoji) {
    if (emoji.isEmpty || emoji.length > 64) {
      throw InnerEnvelopeError();
    }
    _checkUtf8(emoji);
  }

  static void _checkUtf8(Uint8List bytes) {
    try {
      utf8.decode(bytes);
    } on FormatException {
      throw InnerEnvelopeError();
    }
  }
}
