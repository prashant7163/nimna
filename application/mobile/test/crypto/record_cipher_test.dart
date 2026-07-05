import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/crypto/record_cipher.dart';
import 'package:sodium/sodium.dart';

import '../helpers/test_env.dart';

/// The §2 record format: nonce ‖ ct, AD-bound to store id, schema epoch,
/// and record id; per-record keys by derivation; fresh nonce per write.
void main() {
  late RecordCipher cipher;
  late SecureKey baseKey;

  setUpAll(() async {
    cipher = await testCipher();
    baseKey = cipher.sodium.secureRandom(AtRestAead.keyBytes);
  });

  tearDownAll(() {
    baseKey.dispose();
  });

  test('seal/open round-trip', () {
    final recordId = cipher.newRecordId();
    final plaintext = asciiBytes('record body bytes');
    final sealed = cipher.seal(
      baseKey: baseKey,
      storeId: StoreId.channels,
      recordId: recordId,
      plaintext: plaintext,
    );
    expect(
      sealed.length,
      AtRestAead.nonceBytes + plaintext.length + AtRestAead.macBytes,
    );
    expect(
      cipher.open(
        baseKey: baseKey,
        storeId: StoreId.channels,
        recordId: recordId,
        sealed: sealed,
      ),
      plaintext,
    );
  });

  test('AD binds the store id — cross-store transplant fails', () {
    final recordId = cipher.newRecordId();
    final sealed = cipher.seal(
      baseKey: baseKey,
      storeId: StoreId.channels,
      recordId: recordId,
      plaintext: asciiBytes('body'),
    );
    expect(
      () => cipher.open(
        baseKey: baseKey,
        storeId: StoreId.messages,
        recordId: recordId,
        sealed: sealed,
      ),
      throwsA(isA<AeadAuthError>()),
    );
  });

  test('AD binds the schema epoch', () {
    final recordId = cipher.newRecordId();
    final sealed = cipher.seal(
      baseKey: baseKey,
      storeId: StoreId.meta,
      recordId: recordId,
      plaintext: asciiBytes('body'),
    );
    expect(
      () => cipher.open(
        baseKey: baseKey,
        storeId: StoreId.meta,
        recordId: recordId,
        sealed: sealed,
        schemaVersion: kSchemaVersion + 1,
      ),
      throwsA(isA<AeadAuthError>()),
    );
  });

  test('record id binds — cross-row transplant fails', () {
    final recordId = cipher.newRecordId();
    final otherId = cipher.newRecordId();
    final sealed = cipher.seal(
      baseKey: baseKey,
      storeId: StoreId.messages,
      recordId: recordId,
      plaintext: asciiBytes('body'),
    );
    expect(
      () => cipher.open(
        baseKey: baseKey,
        storeId: StoreId.messages,
        recordId: otherId,
        sealed: sealed,
      ),
      throwsA(isA<AeadAuthError>()),
    );
  });

  test('wrong base key fails', () {
    final recordId = cipher.newRecordId();
    final other = cipher.sodium.secureRandom(AtRestAead.keyBytes);
    final sealed = cipher.seal(
      baseKey: baseKey,
      storeId: StoreId.mediaBlob,
      recordId: recordId,
      plaintext: asciiBytes('body'),
    );
    expect(
      () => cipher.open(
        baseKey: other,
        storeId: StoreId.mediaBlob,
        recordId: recordId,
        sealed: sealed,
      ),
      throwsA(isA<AeadAuthError>()),
    );
    other.dispose();
  });

  test('nonce freshness: N rewrites of one record → N distinct nonces', () {
    const n = 64;
    final recordId = cipher.newRecordId();
    final plaintext = asciiBytes('same body every time');
    final nonces = <String>{};
    for (var i = 0; i < n; i++) {
      final sealed = cipher.seal(
        baseKey: baseKey,
        storeId: StoreId.messages,
        recordId: recordId,
        plaintext: plaintext,
      );
      nonces.add(
        bytesToHex(Uint8List.sublistView(sealed, 0, AtRestAead.nonceBytes)),
      );
    }
    expect(nonces.length, n);
  });

  test('per-record keys differ by derivation', () {
    final idA = cipher.newRecordId();
    final idB = cipher.newRecordId();
    final keyA = cipher.deriveRecordKey(baseKey, idA);
    final keyB = cipher.deriveRecordKey(baseKey, idB);
    expect(
      keyA.runUnlockedSync(bytesToHex),
      isNot(keyB.runUnlockedSync(bytesToHex)),
    );
    keyA.dispose();
    keyB.dispose();
  });

  test('buildAd layout is exactly label ‖ store ‖ ver ‖ record id', () {
    final recordId = Uint8List.fromList(List.generate(16, (i) => i));
    final ad = RecordCipher.buildAd(
      storeId: StoreId.diag,
      recordId: recordId,
      schemaVersion: 3,
    );
    expect(ad.length, 'nimna/app/ad/v1'.length + 1 + 1 + 16);
    expect(String.fromCharCodes(ad.sublist(0, 15)), 'nimna/app/ad/v1');
    expect(ad[15], StoreId.diag);
    expect(ad[16], 3);
    expect(ad.sublist(17), recordId);
  });
}
