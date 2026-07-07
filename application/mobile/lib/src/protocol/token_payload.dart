/// `token_payload` — the push device-token carried INSIDE E2E payloads only
/// (spec §5.7), vector-locked to the `token_payload.encoded` fields of
/// `docs/test-vectors/pairing-handshake.json`.
///
/// Used in the pairing handshake payloads M2/M3 (§3.1.3) and, from S15, in
/// the CONTROL token-refresh (§5.5). Pure codec, no I/O, locale-independent.
/// This is pairing-plane surface ONLY — it is the §5.7 leaf, not the
/// §5.5–§5.8 inner-envelope codec (S10's), which references it but is not
/// implemented here.
///
/// Wire (spec §5.7):
/// ```
/// absent / revoke : 0x00
/// present         : 0x01 ‖ platform(1) ‖ token_len(2 BE) ‖ token
/// ```
library;

import 'dart:typed_data';

/// Push platform byte (spec §5.7 / §5.4 KNOCK).
enum PushPlatform {
  apns(0x01),
  fcm(0x02);

  const PushPlatform(this.wire);

  final int wire;

  static PushPlatform? fromWire(int wire) {
    for (final p in PushPlatform.values) {
      if (p.wire == wire) {
        return p;
      }
    }
    return null;
  }
}

/// Raised on a malformed `token_payload` (a structural handshake failure).
class TokenPayloadError extends Error {
  @override
  String toString() => 'TokenPayloadError';
}

/// A decoded `token_payload`: either absent (push off / revoke) or a present
/// platform token.
class TokenPayload {
  /// The "absent" form (`0x00`) — push disabled, or a revoke (spec §5.7).
  const TokenPayload.absent() : platform = null, token = null;

  /// The "present" form.
  TokenPayload.present({
    required PushPlatform this.platform,
    required Uint8List this.token,
  }) {
    if (token!.length > 0xFFFF) {
      throw ArgumentError('token exceeds 65535 bytes');
    }
  }

  /// Non-null only for the present form.
  final PushPlatform? platform;

  /// Non-null only for the present form.
  final Uint8List? token;

  bool get isPresent => platform != null;

  /// Encodes to wire bytes (spec §5.7).
  Uint8List encode() {
    if (!isPresent) {
      return Uint8List.fromList(const [0x00]);
    }
    final t = token!;
    final out = Uint8List(1 + 1 + 2 + t.length);
    out[0] = 0x01;
    out[1] = platform!.wire;
    ByteData.sublistView(out).setUint16(2, t.length);
    out.setAll(4, t);
    return out;
  }

  /// Decodes wire bytes (spec §5.7). Throws [TokenPayloadError] on any
  /// malformation, including trailing bytes.
  static TokenPayload decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw TokenPayloadError();
    }
    switch (bytes[0]) {
      case 0x00:
        if (bytes.length != 1) {
          throw TokenPayloadError();
        }
        return const TokenPayload.absent();
      case 0x01:
        if (bytes.length < 4) {
          throw TokenPayloadError();
        }
        final platform = PushPlatform.fromWire(bytes[1]);
        if (platform == null) {
          throw TokenPayloadError();
        }
        final len = ByteData.sublistView(bytes).getUint16(2);
        if (bytes.length != 4 + len) {
          throw TokenPayloadError();
        }
        return TokenPayload.present(
          platform: platform,
          token: Uint8List.fromList(Uint8List.sublistView(bytes, 4, 4 + len)),
        );
      default:
        throw TokenPayloadError();
    }
  }
}
