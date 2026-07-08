/// §5.4 outer frame — the fixed 18-byte header every WebSocket binary
/// frame carries on both planes, vector-locked to
/// `docs/test-vectors/framing.json` (`outer_frames`).
///
/// Pure codec, no I/O, locale-independent. This file is outer-frame surface
/// ONLY: payload meaning stays out (S8 sends/receives empty relay-plane
/// payloads and treats PAIR_DATA as opaque bytes; §5.5–§5.8 are S10's
/// codec — the checkpoint).
library;

import 'dart:typed_data';

/// Protocol version byte (spec §5.4).
const int protocolVersion = 0x01;

/// routing_id length: rendezvous frames carry the topic (§3.1.2), channel
/// frames the CRID (§3.1.5).
const int routingIdBytes = 16;

/// Outer-frame header length: `ver(1) ‖ frame_type(1) ‖ routing_id(16)`.
const int outerHeaderBytes = 2 + routingIdBytes;

/// Maximum total frame size (header + payload) the client accepts — the §4
/// mirror of the relay's `wire.MaxFrame` (default 128 KiB, sized to carry a
/// full 65,536-byte MEDIA_CHUNK). A frame larger than this is rejected at
/// decode, matching the relay's `ErrOversize`.
const int outerMaxFrame = 128 * 1024;

/// The complete §5.4 frame-type enum — relay-plane and data-plane. Wire
/// values are spec-fixed; never renumber.
enum FrameType {
  /// `0x01` c→r, routing_id = topic, payload empty.
  registerTopic(0x01),

  /// `0x02` c→r, routing_id = CRID, payload empty (one frame per CRID).
  registerCrid(0x02),

  /// `0x03` c→r, routing_id = CRID; payload empty (no push) or
  /// `platform(1) ‖ token_len(2) ‖ token` (§3.2.1).
  knock(0x03),

  /// `0x04` c→r, routing_id = CRID, payload empty.
  accept(0x04),

  /// `0x05` both directions, routing_id = CRID, payload empty.
  /// Disconnection is an implicit TEARDOWN.
  teardown(0x05),

  /// `0x10` r→c, routing_id = topic, payload empty — sent to both ends
  /// when a topic's second registrant arrives; the joiner then sends M1.
  topicBridged(0x10),

  /// `0x11` r→c, routing_id = CRID, payload empty — the relay strips any
  /// token before forwarding (§3.2).
  knockFwd(0x11),

  /// `0x12` r→c, routing_id = CRID, payload empty — sent to both ends on
  /// ACCEPT; the knocker then sends S1.
  sessionBridged(0x12),

  /// `0x20` data-plane, routing_id = topic — opaque pairing-handshake
  /// bytes M1–M4 (§3.1.3; S9 gives them meaning).
  pairData(0x20),

  /// `0x21` data-plane, routing_id = CRID — opaque S1/S2 and transport
  /// ciphertext (§3.3.1; S10's codec).
  sessionData(0x21);

  const FrameType(this.wire);

  /// Spec-fixed wire value.
  final int wire;

  static final Map<int, FrameType> _byWire = {
    for (final t in FrameType.values) t.wire: t,
  };

  static FrameType? fromWire(int wire) => _byWire[wire];
}

/// Raised by [OuterFrame.decode] on any malformed frame. Carries no frame
/// data by design.
class OuterFrameError extends Error {
  @override
  String toString() => 'OuterFrameError';
}

/// One §5.4 frame: `ver(1) ‖ frame_type(1) ‖ routing_id(16) ‖ payload`.
/// All integers big-endian (single bytes here; the rule is inherited by
/// every layout).
class OuterFrame {
  OuterFrame({required this.type, required this.routingId, Uint8List? payload})
    : payload = payload ?? Uint8List(0) {
    if (routingId.length != routingIdBytes) {
      throw ArgumentError.value(
        routingId.length,
        'routingId',
        'must be $routingIdBytes bytes',
      );
    }
  }

  final FrameType type;

  /// Topic (rendezvous plane) or CRID (channel plane) — 16 bytes.
  final Uint8List routingId;

  /// Per frame type; opaque to the relay for data-plane types.
  final Uint8List payload;

  /// Encodes the frame as wire bytes.
  Uint8List encode() {
    final out = Uint8List(outerHeaderBytes + payload.length);
    out[0] = protocolVersion;
    out[1] = type.wire;
    out.setAll(2, routingId);
    out.setAll(outerHeaderBytes, payload);
    return out;
  }

  /// Decodes wire bytes; throws [OuterFrameError] on a short header, a frame
  /// larger than [outerMaxFrame], a version other than `0x01`, or an unknown
  /// frame type (checked in that order, mirroring the relay). The relay parses
  /// exactly 18 bytes and routes; a client is no more lenient.
  static OuterFrame decode(Uint8List bytes) {
    if (bytes.length < outerHeaderBytes) {
      throw OuterFrameError();
    }
    if (bytes.length > outerMaxFrame) {
      throw OuterFrameError();
    }
    if (bytes[0] != protocolVersion) {
      throw OuterFrameError();
    }
    final type = FrameType.fromWire(bytes[1]);
    if (type == null) {
      throw OuterFrameError();
    }
    return OuterFrame(
      type: type,
      routingId: Uint8List.fromList(bytes.sublist(2, outerHeaderBytes)),
      payload: Uint8List.fromList(bytes.sublist(outerHeaderBytes)),
    );
  }
}
