import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:sodium/sodium.dart';

import '../helpers/test_env.dart';

/// Proves the at-rest AEAD is exactly ChaCha20-Poly1305-IETF (RFC 8439,
/// 96-bit nonce) — the S2-locked primitive — and that authentication
/// binds key, nonce, AD, and ciphertext.
void main() {
  late Sodium sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  test('RFC 8439 §2.8.2 test vector (locks the IETF construction)', () {
    final key = SecureKey.fromList(
      sodium,
      hexToBytes(
        '808182838485868788898a8b8c8d8e8f'
        '909192939495969798999a9b9c9d9e9f',
      ),
    );
    final nonce = hexToBytes('070000004041424344454647');
    final aad = hexToBytes('50515253c0c1c2c3c4c5c6c7');
    final plaintext = ascii.encode(
      "Ladies and Gentlemen of the class of '99: "
      'If I could offer you only one tip for the future, '
      'sunscreen would be it.',
    );

    final out = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: plaintext,
      additionalData: aad,
    );

    const expectedCiphertext =
        'd31a8d34648e60db7b86afbc53ef7ec2'
        'a4aded51296e08fea9e2b5a736ee62d6'
        '3dbea45e8ca9671282fafb69da92728b'
        '1a71de0a9e060b2905d6a5b67ecd3b36'
        '92ddbd7f2d778b8c9803aee328091b58'
        'fab324e4fad675945585808b4831d7bc'
        '3ff4def08e4b7a9de576d26586cec64b'
        '6116';
    const expectedTag = '1ae10b594f09e26a7e902ecbd0600691';

    expect(bytesToHex(out), expectedCiphertext + expectedTag);

    final roundTrip = aead.decrypt(
      key: key,
      nonce: nonce,
      ciphertext: out,
      additionalData: aad,
    );
    expect(roundTrip, plaintext);
    key.dispose();
  });

  test('round-trip with associated data', () {
    final key = aead.newKey();
    final nonce = aead.newNonce();
    final plaintext = asciiBytes('the plaintext body');
    final ad = asciiBytes('the associated data');

    final sealed = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: plaintext,
      additionalData: ad,
    );
    expect(sealed.length, plaintext.length + AtRestAead.macBytes);
    expect(
      aead.decrypt(
        key: key,
        nonce: nonce,
        ciphertext: sealed,
        additionalData: ad,
      ),
      plaintext,
    );
    key.dispose();
  });

  test('wrong key fails authentication', () {
    final key = aead.newKey();
    final other = aead.newKey();
    final nonce = aead.newNonce();
    final sealed = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: asciiBytes('secret'),
      additionalData: asciiBytes('ad'),
    );
    expect(
      () => aead.decrypt(
        key: other,
        nonce: nonce,
        ciphertext: sealed,
        additionalData: asciiBytes('ad'),
      ),
      throwsA(isA<AeadAuthError>()),
    );
    key.dispose();
    other.dispose();
  });

  test('wrong nonce fails authentication', () {
    final key = aead.newKey();
    final nonce = aead.newNonce();
    final sealed = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: asciiBytes('secret'),
      additionalData: asciiBytes('ad'),
    );
    expect(
      () => aead.decrypt(
        key: key,
        nonce: aead.newNonce(),
        ciphertext: sealed,
        additionalData: asciiBytes('ad'),
      ),
      throwsA(isA<AeadAuthError>()),
    );
    key.dispose();
  });

  test('wrong associated data fails authentication', () {
    final key = aead.newKey();
    final nonce = aead.newNonce();
    final sealed = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: asciiBytes('secret'),
      additionalData: asciiBytes('ad-one'),
    );
    expect(
      () => aead.decrypt(
        key: key,
        nonce: nonce,
        ciphertext: sealed,
        additionalData: asciiBytes('ad-two'),
      ),
      throwsA(isA<AeadAuthError>()),
    );
    key.dispose();
  });

  test('tampered ciphertext fails authentication', () {
    final key = aead.newKey();
    final nonce = aead.newNonce();
    final sealed = aead.encrypt(
      key: key,
      nonce: nonce,
      plaintext: asciiBytes('secret'),
      additionalData: asciiBytes('ad'),
    );
    sealed[0] ^= 0x01;
    expect(
      () => aead.decrypt(
        key: key,
        nonce: nonce,
        ciphertext: sealed,
        additionalData: asciiBytes('ad'),
      ),
      throwsA(isA<AeadAuthError>()),
    );
    key.dispose();
  });

  test('truncated ciphertext fails cleanly', () {
    final key = aead.newKey();
    expect(
      () => aead.decrypt(
        key: key,
        nonce: aead.newNonce(),
        ciphertext: asciiBytes('short'),
        additionalData: asciiBytes('ad'),
      ),
      throwsA(isA<AeadAuthError>()),
    );
    key.dispose();
  });
}
