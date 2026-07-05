import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/storage/keys/key_service.dart';
import 'package:nimna/src/storage/keys/master_key_store.dart';
import 'package:sodium/sodium.dart';

import '../helpers/test_env.dart';

void main() {
  late Sodium sodium;
  late AtRestAead aead;

  setUpAll(() async {
    sodium = await testSodium();
    aead = AtRestAead(sodium);
  });

  KeyService newService(FakeMasterKeyStore store) => KeyService(
    sodium: sodium,
    keyStore: store,
    diag: Diag(aead: aead),
  );

  test('first open mints a 32-byte master key; reopen loads it', () async {
    final store = FakeMasterKeyStore();
    final service = newService(store);

    expect(await service.open(), isTrue, reason: 'first launch generates');
    expect(store.stored, hasLength(KeyService.masterKeyBytes));

    final firstChannelsKey = service.channelsKey.runUnlockedSync(bytesToHex);
    service.seal();

    expect(await service.open(), isFalse, reason: 'second open loads');
    expect(
      service.channelsKey.runUnlockedSync(bytesToHex),
      firstChannelsKey,
      reason: 'derived keys are deterministic from the stored MK',
    );
    service.seal();
  });

  test('store keys are distinct per label', () async {
    final service = newService(FakeMasterKeyStore());
    await service.open();
    final hexes = {
      service.channelsKey.runUnlockedSync(bytesToHex),
      service.mediaIndexKey.runUnlockedSync(bytesToHex),
      service.metaKey.runUnlockedSync(bytesToHex),
      service.takeDiagKey().runUnlockedSync(bytesToHex),
    };
    expect(hexes.length, 4);
    service.seal();
  });

  test('sealed service throws StorageSealedError everywhere', () async {
    final service = newService(FakeMasterKeyStore());
    expect(() => service.channelsKey, throwsA(isA<StorageSealedError>()));
    expect(() => service.mediaIndexKey, throwsA(isA<StorageSealedError>()));
    expect(() => service.metaKey, throwsA(isA<StorageSealedError>()));
    expect(() => service.takeDiagKey(), throwsA(isA<StorageSealedError>()));

    await service.open();
    expect(service.sealed, isFalse);
    service.seal();
    expect(service.sealed, isTrue);
    expect(() => service.channelsKey, throwsA(isA<StorageSealedError>()));
  });

  test('seal notifies listeners (LockGate contract)', () async {
    final service = newService(FakeMasterKeyStore());
    var notifications = 0;
    service.addListener(() => notifications++);
    await service.open();
    expect(notifications, 1);
    service.seal();
    expect(notifications, 2);
  });

  test('destroyMasterKey + reopen mints a DIFFERENT key', () async {
    final store = FakeMasterKeyStore();
    final service = newService(store);
    await service.open();
    final before = service.channelsKey.runUnlockedSync(bytesToHex);

    await service.destroyMasterKey();
    service.seal();
    expect(store.stored, isNull);

    expect(await service.open(), isTrue);
    expect(service.channelsKey.runUnlockedSync(bytesToHex), isNot(before));
    service.seal();
  });

  test('iOS keychain accessibility is pinned to first_unlock_this_device', () {
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — ThisDeviceOnly is
    // load-bearing: non-migratable, never in iCloud Keychain or backups
    // (app-architecture.md §3). Changing this constant is a review event.
    expect(
      SecureStorageMasterKeyStore.pinnedIosAccessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
    final store = SecureStorageMasterKeyStore();
    expect(
      store.storage.iOptions.accessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
  });
}
