import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/noise_transport.dart';

import '../helpers/test_env.dart';

/// The post-Split transport discipline (§3.3.1, §5.6): nonce encoding,
/// per-message rekey, strict counter, the forbidden counter, and fail-closed
/// receiver enforcement (any AEAD failure destroys the key + raises
/// TransportError).
void main() {
  test('nonce = direction(4 BE) ‖ counter(8 BE)', () {
    expect(
      bytesToHex(transportNonce(0x00000000, 0)),
      '000000000000000000000000',
    );
    expect(
      bytesToHex(transportNonce(0x00000001, 0)),
      '000000010000000000000000',
    );
    expect(
      bytesToHex(transportNonce(0x00000000, 1)),
      '000000000000000000000001',
    );
    // The REKEY nonce: 0x00000000 ‖ 0xFFFFFFFFFFFFFFFF (endian-agnostic ones).
    expect(
      bytesToHex(transportNonce(0, forbiddenCounter)),
      '00000000ffffffffffffffff',
    );
  });

  test('direction constants match the spec', () {
    expect(TransportDirection.initiatorToResponder.constant, 0x00000000);
    expect(TransportDirection.responderToInitiator.constant, 0x00000001);
  });

  test('seal → open round-trips and advances counters with rekey', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final key = aead.randomBytes(32);
    final ad = aead.randomBytes(18);

    final sender = NoiseTransport(
      aead: aead,
      key: key,
      direction: TransportDirection.initiatorToResponder,
    );
    final receiver = NoiseTransport(
      aead: aead,
      key: key,
      direction: TransportDirection.initiatorToResponder,
    );
    addTearDown(() {
      sender.destroy();
      receiver.destroy();
    });

    for (var i = 0; i < 5; i++) {
      final pt = Uint8List.fromList(utf8.encode('frame $i'));
      expect(sender.counter, i);
      expect(receiver.counter, i);
      final ct = sender.seal(outerHeader: ad, plaintext: pt);
      // Ciphertext = plaintext ‖ tag(16); it is not the plaintext.
      expect(ct.length, pt.length + AtRestAead.macBytes);
      expect(receiver.open(outerHeader: ad, ciphertext: ct), pt);
    }
    expect(sender.counter, 5);
    expect(receiver.counter, 5);
  });

  test(
    'a tampered ciphertext fails closed: TransportError + key destroyed',
    () async {
      final sodium = await testSodium();
      final aead = AtRestAead(sodium);
      final key = aead.randomBytes(32);
      final ad = aead.randomBytes(18);
      final sender = NoiseTransport(
        aead: aead,
        key: key,
        direction: TransportDirection.responderToInitiator,
      );
      final receiver = NoiseTransport(
        aead: aead,
        key: key,
        direction: TransportDirection.responderToInitiator,
      );
      addTearDown(() {
        sender.destroy();
        receiver.destroy();
      });

      final ct = sender.seal(
        outerHeader: ad,
        plaintext: Uint8List.fromList(utf8.encode('hello')),
      );
      final tampered = Uint8List.fromList(ct)..[0] ^= 0xFF;
      expect(
        () => receiver.open(outerHeader: ad, ciphertext: tampered),
        throwsA(isA<TransportError>()),
      );
      // Fail-closed: the receiver's key is gone; it cannot be reused.
      expect(receiver.isLive, isFalse);
      expect(
        () => receiver.open(outerHeader: ad, ciphertext: ct),
        throwsA(isA<TransportError>()),
      );
    },
  );

  test('wrong outer-header (ad) fails closed', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final key = aead.randomBytes(32);
    final sender = NoiseTransport(
      aead: aead,
      key: key,
      direction: TransportDirection.initiatorToResponder,
    );
    final receiver = NoiseTransport(
      aead: aead,
      key: key,
      direction: TransportDirection.initiatorToResponder,
    );
    addTearDown(() {
      sender.destroy();
      receiver.destroy();
    });
    final ct = sender.seal(
      outerHeader: aead.randomBytes(18),
      plaintext: Uint8List.fromList(utf8.encode('bound')),
    );
    expect(
      () => receiver.open(outerHeader: aead.randomBytes(18), ciphertext: ct),
      throwsA(isA<TransportError>()),
    );
  });

  test(
    'a counter gap fails closed (receiver only tries its own next counter)',
    () async {
      final sodium = await testSodium();
      final aead = AtRestAead(sodium);
      final key = aead.randomBytes(32);
      final ad = aead.randomBytes(18);
      final sender = NoiseTransport(
        aead: aead,
        key: key,
        direction: TransportDirection.initiatorToResponder,
      );
      final receiver = NoiseTransport(
        aead: aead,
        key: key,
        direction: TransportDirection.initiatorToResponder,
      );
      addTearDown(() {
        sender.destroy();
        receiver.destroy();
      });
      // Sender skips ahead: seal frame 0 (discarded), then frame 1 — the
      // receiver, still at counter 0, cannot open frame 1.
      sender.seal(outerHeader: ad, plaintext: Uint8List(1));
      final frame1 = sender.seal(outerHeader: ad, plaintext: Uint8List(1));
      expect(
        () => receiver.open(outerHeader: ad, ciphertext: frame1),
        throwsA(isA<TransportError>()),
      );
    },
  );

  test('destroy is idempotent and disables the channel', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final tx = NoiseTransport(
      aead: aead,
      key: aead.randomBytes(32),
      direction: TransportDirection.initiatorToResponder,
    );
    tx.destroy();
    tx.destroy();
    expect(tx.isLive, isFalse);
    expect(
      () => tx.seal(outerHeader: aead.randomBytes(18), plaintext: Uint8List(0)),
      throwsA(isA<TransportError>()),
    );
  });
}
