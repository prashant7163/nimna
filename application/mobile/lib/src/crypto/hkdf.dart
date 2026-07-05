import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 5869 HKDF-SHA-256 (extract + expand).
///
/// The one key-derivation function of the locked suite (spec §7). Composed
/// from the Dart-team `crypto` package's HMAC-SHA-256 per RFC 5869 and locked
/// to the RFC test vectors plus the Go-generated values committed in
/// `docs/test-vectors/` (see test/crypto/hkdf_test.dart).
///
/// Conventions (app-architecture.md §3): the empty [salt] default is the
/// RFC 5869 zero-string-of-HashLen; all app-storage `info` labels live under
/// the `nimna/app/…` namespace, structurally disjoint from the protocol's
/// `nimna/topic|psk|phrase|crid/…` labels.
Uint8List hkdfSha256({
  required List<int> ikm,
  List<int> salt = const [],
  required List<int> info,
  required int length,
}) {
  if (length <= 0 || length > 255 * 32) {
    throw ArgumentError.value(length, 'length', 'must be in 1..8160');
  }

  // Extract: PRK = HMAC-SHA-256(salt, IKM); empty salt = HashLen zero bytes.
  final effectiveSalt = salt.isEmpty ? Uint8List(32) : salt;
  final prk = Hmac(sha256, effectiveSalt).convert(ikm).bytes;

  // Expand: T(i) = HMAC-SHA-256(PRK, T(i-1) | info | i).
  final blocks = (length + 31) ~/ 32;
  final okm = BytesBuilder(copy: false);
  var previous = const <int>[];
  for (var i = 1; i <= blocks; i++) {
    previous = Hmac(sha256, prk).convert([...previous, ...info, i]).bytes;
    okm.add(previous);
  }
  final out = okm.takeBytes();
  if (out.length == length) {
    return out;
  }
  // Return an exact-length COPY and zeroize the full multi-block buffer
  // (review N3): a sublist view would let callers' fillRange leave the
  // trailing OKM bytes alive in the underlying buffer.
  final exact = Uint8List.fromList(Uint8List.sublistView(out, 0, length));
  out.fillRange(0, out.length, 0);
  return exact;
}
