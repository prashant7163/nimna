import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/lock/lock_controller.dart';
import 'package:nimna/src/storage/keys/key_service.dart';
import 'package:nimna/src/storage/keys/master_key_store.dart';

import '../helpers/test_env.dart';

/// A MasterKeyStore wrapper that records every keystore operation — the
/// intake §7 "fake keystore records access order" instrument.
class RecordingMasterKeyStore implements MasterKeyStore {
  RecordingMasterKeyStore(this.inner);

  final MasterKeyStore inner;
  final List<String> ops = [];

  @override
  Future<Uint8List?> read() {
    ops.add('read');
    return inner.read();
  }

  @override
  Future<void> write(Uint8List key) {
    ops.add('write');
    return inner.write(key);
  }

  @override
  Future<void> delete() {
    ops.add('delete');
    return inner.delete();
  }
}

void main() {
  late TestDevice device;

  setUp(() {
    device = TestDevice.create();
  });

  tearDown(() async {
    await device.dispose();
  });

  /// Boots once with no lock, enrolls [pin], and "kills the process".
  Future<void> enrollAndShutdown(
    String pin, {
    bool biometricEnabled = false,
  }) async {
    final services = await device.boot();
    await services.lockController.enableLock(
      pin: pin,
      biometricEnabled: biometricEnabled,
    );
    await device.shutdown();
  }

  test('lock-enabled cold start never reads the keystore before a '
      'successful verify', () async {
    await enrollAndShutdown('9137');

    final recorder = RecordingMasterKeyStore(device.keyStore);
    final services = await device.boot(masterKeyStore: recorder);

    // Boot left the perimeter sealed and the keystore untouched.
    expect(services.keyService.sealed, isTrue);
    expect(services.storage.isOpen, isFalse);
    expect(recorder.ops, isEmpty);

    // A wrong PIN leaves everything sealed — still zero keystore access.
    expect(await services.lockController.submitPin('9138'), isFalse);
    expect(services.keyService.sealed, isTrue);
    expect(recorder.ops, isEmpty);
    expect(
      () => services.keyService.channelsKey,
      throwsA(isA<StorageSealedError>()),
    );

    // The correct PIN opens; only now is the keystore read.
    expect(await services.lockController.submitPin('9137'), isTrue);
    expect(services.keyService.sealed, isFalse);
    expect(services.storage.isOpen, isTrue);
    expect(recorder.ops, contains('read'));
  });

  test('no-lock boot opens storage (S7 upgrade path is automatic)', () async {
    final services = await device.boot();
    expect(services.lockController.enabled, isFalse);
    expect(services.keyService.sealed, isFalse);
    expect(services.storage.isOpen, isTrue);
  });

  test('escalating delay schedule: free through 4, 1 s doubling, 30 s cap', () {
    expect(LockController.delayForFailures(0), Duration.zero);
    expect(LockController.delayForFailures(4), Duration.zero);
    expect(LockController.delayForFailures(5), const Duration(seconds: 1));
    expect(LockController.delayForFailures(6), const Duration(seconds: 2));
    expect(LockController.delayForFailures(7), const Duration(seconds: 4));
    expect(LockController.delayForFailures(8), const Duration(seconds: 8));
    expect(LockController.delayForFailures(9), const Duration(seconds: 16));
    expect(LockController.delayForFailures(10), const Duration(seconds: 30));
    expect(LockController.delayForFailures(64), const Duration(seconds: 30));
  });

  test(
    '5th consecutive failure disarms the pad until the delay elapses',
    () async {
      final scheduled = <(Duration, void Function())>[];
      device.lockScheduler = (delay, callback) =>
          scheduled.add((delay, callback));
      await enrollAndShutdown('2468');
      final services = await device.boot();
      final lock = services.lockController;

      for (var i = 0; i < 4; i++) {
        expect(await lock.submitPin('0000'), isFalse);
        expect(lock.padArmed, isTrue, reason: 'failure ${i + 1} is free');
      }
      expect(await lock.submitPin('0000'), isFalse);
      expect(lock.padArmed, isFalse, reason: '5th failure disarms');
      expect(scheduled.single.$1, const Duration(seconds: 1));

      // A disarmed pad ignores input — even the correct PIN.
      expect(await lock.submitPin('2468'), isFalse);
      expect(services.keyService.sealed, isTrue);

      // The delay elapses; the pad re-arms; the correct PIN opens.
      scheduled.single.$2();
      expect(lock.padArmed, isTrue);
      expect(await lock.submitPin('2468'), isTrue);
      expect(services.keyService.sealed, isFalse);

      // Success reset the counter: the next failure is free again.
      expect(scheduled, hasLength(1));
    },
  );

  test('biometric verdict gates open() exactly as a correct PIN', () async {
    await enrollAndShutdown('7777', biometricEnabled: true);
    device.biometricGate
      ..available = true
      ..nextResult = true;
    final services = await device.boot();
    expect(services.keyService.sealed, isTrue);

    final ok = await services.lockController.tryBiometric(
      reason: 'test-reason',
    );
    expect(ok, isTrue);
    expect(services.keyService.sealed, isFalse);
    expect(device.biometricGate.prompts, ['test-reason']);
  });

  test(
    'biometric failure leaves the perimeter sealed (PIN pad fallback)',
    () async {
      await enrollAndShutdown('7777', biometricEnabled: true);
      device.biometricGate
        ..available = true
        ..nextResult = false;
      final services = await device.boot();

      expect(await services.lockController.tryBiometric(reason: 'r'), isFalse);
      expect(services.keyService.sealed, isTrue);
      expect(await services.lockController.submitPin('7777'), isTrue);
    },
  );

  test('turning lock off requires the current PIN', () async {
    final services = await device.boot();
    final lock = services.lockController;
    await lock.enableLock(pin: '135790', biometricEnabled: false);
    expect(lock.enabled, isTrue);

    expect(await lock.disableLock(pin: '000000'), isFalse);
    expect(lock.enabled, isTrue);
    expect(device.lockStore.stored, isNotNull);

    expect(await lock.disableLock(pin: '135790'), isTrue);
    expect(lock.enabled, isFalse);
    expect(device.lockStore.stored, isNull);
  });

  test('biometric flag flips without re-enrollment', () async {
    final services = await device.boot();
    final lock = services.lockController;
    await lock.enableLock(pin: '1470', biometricEnabled: false);
    expect(lock.biometricEnabled, isFalse);

    await lock.setBiometricEnabled(true);
    expect(lock.biometricEnabled, isTrue);
    // The PIN still verifies — salt/verifier untouched.
    expect(await lock.confirmPin('1470'), isTrue);
  });
}
