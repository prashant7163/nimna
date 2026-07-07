/// Rendezvous derivation: topic and psk from the canonical code bytes —
/// spec §3.1.2, vector-locked to `docs/test-vectors/topic-derivation.json`.
///
/// Pure derivation, no I/O, locale-independent. Every cryptographic byte is
/// computed by audited code: SHA-256 by `package:crypto` (S2 suite),
/// Argon2id by libsodium's `crypto_pwhash` (sumo API of the existing
/// `sodium` package), HKDF-SHA-256 by the vector-locked in-repo
/// composition (`lib/src/crypto/hkdf.dart`). No Dart-land Argon2 exists or
/// may ever exist here (crypto lock).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/hkdf.dart';
import 'pairing_code.dart';

/// ASCII label for the salt preimage and the topic HKDF info (spec §3.1.2).
const String topicLabel = 'nimna/topic/v1';

/// ASCII label for the psk HKDF info (spec §3.1.2).
const String pskLabel = 'nimna/psk/v1';

/// Topic length in bytes (spec §3.1.2).
const int topicBytes = 16;

/// psk length in bytes (spec §3.1.2).
const int pskBytes = 32;

/// Argon2id cost parameters. The production constants are fixed protocol
/// constants (spec §3.1.2: t = 3, m = 64 MiB, p = 1, Argon2 v1.3; p = 1 is
/// libsodium's `crypto_pwhash` parallelism, keeping both stacks
/// byte-identical). libsodium takes the memory limit in bytes.
@immutable
class Argon2Cost {
  const Argon2Cost._({required this.opsLimit, required this.memLimitBytes});

  /// The protocol constants — the default and the only cost reachable from
  /// app code.
  static const Argon2Cost production = Argon2Cost._(
    opsLimit: 3,
    memLimitBytes: 64 * 1024 * 1024,
  );

  /// REDUCED COST — FOR FAST UNIT TESTS ONLY (vectors'
  /// `argon2id_reduced_test_only`: t = 1, m = 8 MiB). Never used by the
  /// protocol; exists so test suites can exercise the pipeline cheaply.
  @visibleForTesting
  static const Argon2Cost reducedTestOnly = Argon2Cost._(
    opsLimit: 1,
    memLimitBytes: 8 * 1024 * 1024,
  );

  final int opsLimit;
  final int memLimitBytes;
}

/// The derived rendezvous secrets. The topic is relay-visible routing; the
/// psk is a secret held in native memory ([SecureKey]) for the S9 pairing
/// handshake — nothing consumes it in S8. Callers own [dispose].
class RendezvousSecrets {
  RendezvousSecrets({required this.topic, required this.psk});

  /// 16-byte rendezvous topic — the frame routing_id (§5.4).
  final Uint8List topic;

  /// 32-byte pre-shared key, mixed into the §3.1.3 handshake (S9).
  final SecureKey psk;

  void dispose() => psk.dispose();
}

/// Formats a UTC instant as the spec's 10-ASCII-byte `YYYY-MM-DD` date.
String utcDateString(DateTime instant) {
  final utc = instant.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// `salt = SHA-256("nimna/topic/v1|" + date)[0:16]` (spec §3.1.2). The salt
/// is pre-hashed to 16 bytes because libsodium's pwhash API takes exactly
/// 16 salt bytes.
Uint8List rendezvousSalt(String utcDate) {
  final digest = sha256.convert(ascii.encode('$topicLabel|$utcDate'));
  return Uint8List.fromList(digest.bytes.sublist(0, 16));
}

/// Derives topic and psk from the canonical code bytes and the creation
/// UTC date (spec §3.1.2):
///
/// ```
/// seed  = Argon2id(password = canonical_code_bytes, salt,
///                  t = 3, m = 64 MiB, p = 1, out = 32)
/// topic = HKDF-SHA-256(ikm = seed, salt = empty, info = "nimna/topic/v1")[0:16]
/// psk   = HKDF-SHA-256(ikm = seed, salt = empty, info = "nimna/psk/v1")[0:32]
/// ```
///
/// The creator passes its code-creation date; a cost other than
/// [Argon2Cost.production] is reachable only from tests.
RendezvousSecrets deriveRendezvous({
  required SodiumSumo sodium,
  required PairingCode code,
  required String utcDate,
  Argon2Cost cost = Argon2Cost.production,
}) {
  final salt = rendezvousSalt(utcDate);
  final password = Int8List.fromList(code.canonicalBytes);
  final SecureKey seed;
  try {
    seed = sodium.crypto.pwhash(
      outLen: pskBytes,
      password: password,
      salt: salt,
      opsLimit: cost.opsLimit,
      memLimit: cost.memLimitBytes,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  } finally {
    password.fillRange(0, password.length, 0);
  }

  try {
    return seed.runUnlockedSync((seedBytes) {
      final topic = hkdfSha256(
        ikm: seedBytes,
        info: ascii.encode(topicLabel),
        length: topicBytes,
      );
      final pskBytesOut = hkdfSha256(
        ikm: seedBytes,
        info: ascii.encode(pskLabel),
        length: pskBytes,
      );
      final psk = SecureKey.fromList(sodium, pskBytesOut);
      pskBytesOut.fillRange(0, pskBytesOut.length, 0);
      return RendezvousSecrets(topic: topic, psk: psk);
    });
  } finally {
    seed.dispose();
  }
}
