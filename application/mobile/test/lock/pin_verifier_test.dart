import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/lock/lock_config_store.dart';
import 'package:nimna/src/lock/pin_verifier.dart';

import '../helpers/test_env.dart';

/// PIN verifier (SESSION-13 intake §2/§7): Argon2id gate-not-key. The
/// reduced-cost lane covers behavior; the tagged `production-cost` test
/// runs the spec §7 parameters verbatim; structural tests pin the
/// parameters and the no-byte-returning-API fence.
void main() {
  late AtRestAead aead;
  late FakeLockConfigStore store;
  late PinVerifier verifier;

  setUp(() async {
    final sodium = await testSodium();
    aead = AtRestAead(sodium);
    store = FakeLockConfigStore();
    verifier = PinVerifier(
      sodium: sodium,
      aead: aead,
      store: store,
      opsLimit: testPinOpsLimit,
      memLimit: testPinMemLimit,
    );
  });

  test('enrollment/verify round-trip; wrong PIN rejects', () async {
    await verifier.enroll(pin: '4712', biometricEnabled: true);
    expect(store.stored, isNotNull);

    expect(await verifier.verify('4712'), isTrue);
    expect(await verifier.verify('4713'), isFalse);
    expect(await verifier.verify('47122'), isFalse);
    expect(await verifier.verify('471'), isFalse, reason: 'shape-invalid');

    final config = (await store.read())!;
    expect(config.pinEnabled, isTrue);
    expect(config.biometricEnabled, isTrue);
    expect(config.pinLength, 4);
    expect(config.salt, hasLength(LockConfig.saltBytes));
    expect(config.verifier, hasLength(LockConfig.verifierBytes));
  });

  test('PIN shape is 4-8 digits (design-settled)', () async {
    for (final bad in ['123', '123456789', 'abcd', '12 34', '']) {
      expect(
        () => verifier.enroll(pin: bad, biometricEnabled: false),
        throwsArgumentError,
        reason: '"$bad" must not enroll',
      );
    }
    for (final good in ['0000', '12345678']) {
      await verifier.enroll(pin: good, biometricEnabled: false);
      expect(await verifier.verify(good), isTrue);
    }
  });

  test('fresh salt per enrollment; verifier differs per salt', () async {
    await verifier.enroll(pin: '13579', biometricEnabled: false);
    final first = (await store.read())!;
    final firstSalt = List<int>.of(first.salt);
    final firstVerifier = List<int>.of(first.verifier);

    await verifier.enroll(pin: '13579', biometricEnabled: false);
    final second = (await store.read())!;

    expect(second.salt, isNot(equals(firstSalt)));
    expect(second.verifier, isNot(equals(firstVerifier)));
    expect(await verifier.verify('13579'), isTrue);
  });

  test('verify is false with no enrolled config (no cost, no throw)', () async {
    expect(await verifier.verify('1234'), isFalse);
  });

  test('spec §7 parameters are pinned verbatim (t=3, m=64 MiB)', () {
    // Argon2id v1.3 via libsodium ALG_ARGON2ID13; libsodium's Argon2id is
    // p=1 by construction. These constants are the production defaults —
    // the reduced-cost constructor lane exists only for tests.
    expect(PinVerifier.specOpsLimit, 3);
    expect(PinVerifier.specMemLimitBytes, 64 * 1024 * 1024);
  });

  test('production-cost lane: spec-parameter round-trip', () async {
    final sodium = await testSodium();
    final prodStore = FakeLockConfigStore();
    final prod = PinVerifier(
      sodium: sodium,
      aead: aead,
      store: prodStore,
    ); // defaults = spec §7 params
    await prod.enroll(pin: '314159', biometricEnabled: false);
    expect(await prod.verify('314159'), isTrue);
    expect(await prod.verify('314158'), isFalse);
  }, tags: ['production-cost']);

  group('structural fence (source scan)', () {
    final source = File('lib/src/lock/pin_verifier.dart').readAsStringSync();

    test('pin_verifier.dart exports no byte-returning API', () {
      // Public members returning key-material-capable types are forbidden
      // — the verifier is a gate, never a key (intake §2).
      final byteReturning = RegExp(
        r'^\s*(?:Future<)?(?:Uint8List|Int8List|List<int>|SecureKey)>?\s+'
        r'(?!_)\w+\s*[({=]',
        multiLine: true,
      );
      expect(
        byteReturning.hasMatch(source),
        isFalse,
        reason: 'public byte-returning member found in pin_verifier.dart',
      );
    });

    test('compare goes through the constant-time fence helper', () {
      expect(source, contains('constantTimeEquals'));
      expect(source.contains('listEquals'), isFalse);
      expect(RegExp(r'==\s*config\.verifier').hasMatch(source), isFalse);
    });

    test('crypto_pwhash is reached only from its sanctioned call sites', () {
      // The two spec-sanctioned Argon2id (crypto_pwhash) consumers, each a
      // gate/derivation over the shared sumo instance:
      //   - lock/pin_verifier.dart      — PIN verifier, spec §7 (S13)
      //   - protocol/rendezvous.dart    — topic/psk derivation, spec §3.1.2
      //     (S8, vector-locked). Present after the S8↔S13 merge; the fence
      //     stays tight around any NEW/unexpected call site.
      const allowed = ['lock/pin_verifier.dart', 'protocol/rendezvous.dart'];
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        if (allowed.any(entity.path.endsWith)) {
          continue;
        }
        // Comments don't call anything — scan code only.
        final code = entity.readAsStringSync().replaceAll(
          RegExp(r'//[^\n]*'),
          '',
        );
        if (code.contains('pwhash')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
