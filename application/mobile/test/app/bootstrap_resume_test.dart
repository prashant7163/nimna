import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/pairing/initiator/pending_pairing.dart';
import 'package:nimna/src/protocol/pairing_code.dart';

import '../helpers/test_env.dart';

/// The post-unlock pending-pairing resume hook (SESSION-9 item 5): the boot
/// read of `pending_pairings` (F2.4/F2.8 relaunch) is extracted into a
/// one-shot loader that runs at boot when the store is open (lock disabled)
/// AND on the first sealed→unsealed LockController transition (lock
/// enrolled), fired EXACTLY once by an idempotency latch.
void main() {
  late TestDevice device;

  setUp(() => device = TestDevice.create());
  tearDown(() => device.dispose());

  Future<void> seedPending(TestDevice d) async {
    final services = await d.boot();
    final sodium = await testSodium();
    final store = PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    );
    final kp = sodium.crypto.box.keyPair();
    await store.add(
      PendingPairing(
        code: PairingCode.canonicalize('7Q2M4K9XV')!,
        utcDate: '2026-07-07',
        ttl: const Duration(hours: 24),
        createdAt: DateTime.utc(2026, 7, 7, 9),
        publicKey: kp.publicKey,
        secretKey: kp.secretKey,
      ),
    );
  }

  test('lock disabled: the pending pairing is adopted at boot, once', () async {
    await seedPending(device);
    await device.shutdown();

    final services = await device.boot();
    final entry = services.pairing.takeInitialResume();
    expect(entry, isNotNull);
    expect(entry!.code, PairingCode.canonicalize('7Q2M4K9XV')!);
    entry.dispose();

    // Idempotency: the one-shot is consumed.
    expect(services.pairing.takeInitialResume(), isNull);
  });

  test(
    'lock enrolled: NOT adopted at sealed boot; adopted on first unlock',
    () async {
      // Seed a pending pairing, then enroll a lock and seal.
      final seed = await device.boot();
      final sodium = await testSodium();
      final store = PendingPairingStore(storage: seed.storage, sodium: sodium);
      final kp = sodium.crypto.box.keyPair();
      await store.add(
        PendingPairing(
          code: PairingCode.canonicalize('7Q2M4K9XV')!,
          utcDate: '2026-07-07',
          ttl: const Duration(hours: 24),
          createdAt: DateTime.utc(2026, 7, 7, 9),
          publicKey: kp.publicKey,
          secretKey: kp.secretKey,
        ),
      );
      await seed.lockController.enableLock(
        pin: '246813',
        biometricEnabled: false,
      );
      await device.shutdown();

      // Reboot with the lock enrolled → the perimeter is sealed; the boot read
      // cannot run.
      final services = await device.boot();
      expect(services.lockController.locked, isTrue);
      expect(services.storage.isOpen, isFalse);
      expect(services.pairing.takeInitialResume(), isNull);

      // Unlock → the first sealed→unsealed transition fires the one-shot
      // loader (unawaited); give it a beat to read the now-open store. The
      // read is a single reduced-cost decrypt, well under this window.
      expect(await services.lockController.submitPin('246813'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final entry = services.pairing.takeInitialResume();
      expect(
        entry,
        isNotNull,
        reason: 'the post-unlock hook must adopt the pending pairing',
      );
      entry!.dispose();
      // Adopted exactly once — the latch prevents a re-adopt.
      expect(services.pairing.takeInitialResume(), isNull);
    },
  );
}
