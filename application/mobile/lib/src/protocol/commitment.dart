/// M0 commitment prologue — spec §3.1.3, vector-locked to
/// `docs/test-vectors/pairing-handshake.json` (`commitment.m0`).
///
/// `M0 = SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub)` over the JOINER's
/// fresh ephemeral and static public keys. Both sides use M0 as the Noise
/// prologue; the joiner commits to its contributions before the creator
/// reveals anything, so neither side (nor a bridging MITM) can grind key
/// material against the safety phrase (§9). Pure, no I/O, locale-independent
/// — SHA-256 is `package:crypto` (S2 suite). This is pairing-plane surface
/// ONLY; nothing here touches the §5.5–§5.8 inner-envelope codec (S10).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// ASCII label for the commitment preimage (spec §3.1.3, 15 bytes).
const String commitmentLabel = 'nimna/commit/v1';

/// Computes `M0` from the joiner's ephemeral and static public keys
/// (spec §3.1.3). Both must be 32 bytes.
Uint8List commitmentM0({
  required Uint8List joinerEphemeralPublic,
  required Uint8List joinerStaticPublic,
}) {
  if (joinerEphemeralPublic.length != 32 || joinerStaticPublic.length != 32) {
    throw ArgumentError('commitment inputs must be 32-byte public keys');
  }
  final preimage = <int>[
    ...ascii.encode(commitmentLabel),
    ...joinerEphemeralPublic,
    ...joinerStaticPublic,
  ];
  return Uint8List.fromList(sha256.convert(preimage).bytes);
}
