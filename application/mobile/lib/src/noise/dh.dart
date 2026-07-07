/// X25519 for the Noise engine — the ONLY use of libsodium's sumo
/// `crypto_scalarmult` in the app, deliberately fenced to `lib/src/noise`
/// (SESSION-9 intake: sumo scalarmult stays inside the Noise layer). The DH
/// is RFC 7748 X25519 (the S2-locked key-agreement primitive); libsodium
/// computes it, this file only marshals bytes. Pure, locale-independent.
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// An ephemeral or static X25519 keypair used inside a handshake. The
/// secret lives in native ([SecureKey]) memory; [dispose] zeroizes it.
class NoiseKeyPair {
  NoiseKeyPair({required this.publicKey, required this.secretKey});

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  /// 32-byte X25519 secret key (native memory).
  final SecureKey secretKey;

  void dispose() => secretKey.dispose();
}

/// Generates a fresh X25519 keypair (libsodium `crypto_box_keypair`, which
/// is X25519 — the same call the initiator uses for static keys).
NoiseKeyPair generateNoiseKeyPair(SodiumSumo sodium) {
  final kp = sodium.crypto.box.keyPair();
  return NoiseKeyPair(publicKey: kp.publicKey, secretKey: kp.secretKey);
}

/// `DH(scalar, point)` = X25519(own secret, peer public) — libsodium
/// `crypto_scalarmult`. Returns the 32-byte shared secret as a `Uint8List`;
/// the caller MUST zeroize it after mixing it in (it is key material).
Uint8List x25519({
  required SodiumSumo sodium,
  required SecureKey scalar,
  required Uint8List point,
}) {
  final shared = sodium.crypto.scalarmult(n: scalar, p: point);
  try {
    return shared.runUnlockedSync((bytes) => Uint8List.fromList(bytes));
  } finally {
    shared.dispose();
  }
}
