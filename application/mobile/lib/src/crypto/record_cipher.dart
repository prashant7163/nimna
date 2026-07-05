import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'at_rest_aead.dart';
import 'hkdf.dart';

/// Store identifiers bound into every record's associated data
/// (app-architecture.md §2 — normative).
abstract final class StoreId {
  static const int channels = 0x01;
  static const int messages = 0x02;
  static const int mediaIndex = 0x03;
  static const int mediaBlob = 0x04;
  static const int diag = 0x05;
  static const int meta = 0x06;
}

/// Current at-rest schema epoch, bound into every record's AD and kept in
/// `meta.schema_version`. Pre-launch: a mismatch is a destructive reset
/// (app-architecture.md §4).
const int kSchemaVersion = 1;

/// The at-rest record cipher (app-architecture.md §2/§3 — normative).
///
/// Stored value = `nonce(12) ‖ ct`, where
/// `ct = ChaCha20-Poly1305-IETF(key = k_rec, nonce, ad, plaintext)` and
/// `ad = "nimna/app/ad/v1" ‖ store_id(1) ‖ schema_ver(1) ‖ record_id(16)`.
/// Every ciphertext is bound to its store, schema epoch, and row —
/// cross-row/cross-store transplants fail authentication.
///
/// Per-record keys: `k_rec = HKDF(base, info = "nimna/app/rec/v1" ‖
/// record_id)` — unique per record by derivation, and every write draws a
/// fresh random nonce on top (the two independent nonce belts).
class RecordCipher {
  RecordCipher(this._aead);

  static const int recordIdBytes = 16;
  static final Uint8List _adLabel = ascii.encode('nimna/app/ad/v1');
  static final Uint8List _recLabel = ascii.encode('nimna/app/rec/v1');

  final AtRestAead _aead;

  /// The underlying libsodium instance (for SecureKey allocation).
  Sodium get sodium => _aead.sodium;

  /// Mints a fresh random 16-byte record id (libsodium `randombytes`).
  Uint8List newRecordId() => _aead.randomBytes(recordIdBytes);

  /// Fresh random bytes (libsodium `randombytes`).
  Uint8List randomBytes(int length) => _aead.randomBytes(length);

  /// Builds the associated data for a record (normative layout above).
  static Uint8List buildAd({
    required int storeId,
    required Uint8List recordId,
    int schemaVersion = kSchemaVersion,
  }) {
    if (recordId.length != recordIdBytes) {
      throw ArgumentError.value(
        recordId.length,
        'recordId',
        'must be $recordIdBytes bytes',
      );
    }
    final ad = BytesBuilder(copy: false)
      ..add(_adLabel)
      ..addByte(storeId)
      ..addByte(schemaVersion)
      ..add(recordId);
    return ad.takeBytes();
  }

  /// Derives the per-record key from [base] (a store key or a channel CDK).
  /// Enforces the 16-byte record id like [buildAd] does (review N3).
  SecureKey deriveRecordKey(SecureKey base, Uint8List recordId) {
    if (recordId.length != recordIdBytes) {
      throw ArgumentError.value(
        recordId.length,
        'recordId',
        'must be $recordIdBytes bytes',
      );
    }
    final info = BytesBuilder(copy: false)
      ..add(_recLabel)
      ..add(recordId);
    return base.runUnlockedSync((baseBytes) {
      final okm = hkdfSha256(
        ikm: baseBytes,
        info: info.takeBytes(),
        length: AtRestAead.keyBytes,
      );
      final key = SecureKey.fromList(_aead.sodium, okm);
      okm.fillRange(0, okm.length, 0);
      return key;
    });
  }

  /// Encrypts [plaintext] as the stored value `nonce(12) ‖ ct`.
  Uint8List seal({
    required SecureKey baseKey,
    required int storeId,
    required Uint8List recordId,
    required Uint8List plaintext,
    int schemaVersion = kSchemaVersion,
  }) {
    final recordKey = deriveRecordKey(baseKey, recordId);
    try {
      final nonce = _aead.newNonce();
      final ct = _aead.encrypt(
        key: recordKey,
        nonce: nonce,
        plaintext: plaintext,
        additionalData: buildAd(
          storeId: storeId,
          recordId: recordId,
          schemaVersion: schemaVersion,
        ),
      );
      final out = BytesBuilder(copy: false)
        ..add(nonce)
        ..add(ct);
      return out.takeBytes();
    } finally {
      recordKey.dispose();
    }
  }

  /// Decrypts a stored value `nonce(12) ‖ ct`; throws [AeadAuthError] on any
  /// authentication failure.
  Uint8List open({
    required SecureKey baseKey,
    required int storeId,
    required Uint8List recordId,
    required Uint8List sealed,
    int schemaVersion = kSchemaVersion,
  }) {
    if (sealed.length < AtRestAead.nonceBytes + AtRestAead.macBytes) {
      throw AeadAuthError();
    }
    final nonce = Uint8List.sublistView(sealed, 0, AtRestAead.nonceBytes);
    final ct = Uint8List.sublistView(sealed, AtRestAead.nonceBytes);
    final recordKey = deriveRecordKey(baseKey, recordId);
    try {
      return _aead.decrypt(
        key: recordKey,
        nonce: nonce,
        ciphertext: ct,
        additionalData: buildAd(
          storeId: storeId,
          recordId: recordId,
          schemaVersion: schemaVersion,
        ),
      );
    } finally {
      recordKey.dispose();
    }
  }
}
