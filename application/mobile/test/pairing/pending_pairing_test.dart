import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/pairing/initiator/pending_pairing.dart';
import 'package:nimna/src/protocol/pairing_code.dart';
import 'package:sodium/sodium.dart';

import '../helpers/test_env.dart';

/// The at-rest pending-pairings record (S8 intake §6): round-trip incl.
/// the X25519 keypair, discard-erases (row deleted, no residue on disk),
/// multi-entry behavior for the §3.1 self-join guard.
void main() {
  late TestDevice device;

  setUp(() {
    device = TestDevice.create();
  });

  tearDown(() => device.dispose());

  Future<PendingPairing> makeEntry(
    Sodium sodium, {
    String code = '7Q2M4K9XV',
    String date = '2026-07-04',
  }) async {
    final keyPair = sodium.crypto.box.keyPair();
    return PendingPairing(
      code: PairingCode.canonicalize(code)!,
      utcDate: date,
      ttl: const Duration(hours: 24),
      createdAt: DateTime.utc(2026, 7, 4, 12, 30),
      publicKey: keyPair.publicKey,
      secretKey: keyPair.secretKey,
    );
  }

  test('round-trip across restart: all fields incl. keypair', () async {
    var services = await device.boot();
    final sodium = await testSodium();
    final store = PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    );
    final entry = await makeEntry(sodium);
    final pub = Uint8List.fromList(entry.publicKey);
    final sec = entry.secretKey.runUnlockedSync(Uint8List.fromList);
    await store.add(entry);
    entry.dispose();
    await device.shutdown();

    services = await device.boot();
    final reloaded = await PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    ).readAll();
    expect(reloaded, hasLength(1));
    final got = reloaded.single;
    expect(got.code.canonical, '7Q2M4K9XV');
    expect(got.utcDate, '2026-07-04');
    expect(got.ttl, const Duration(hours: 24));
    expect(got.createdAt, DateTime.utc(2026, 7, 4, 12, 30));
    expect(got.publicKey, pub);
    expect(got.secretKey.runUnlockedSync(Uint8List.fromList), sec);
    expect(got.expiresAt, DateTime.utc(2026, 7, 5, 12, 30));
    expect(got.isExpired(DateTime.utc(2026, 7, 5, 12, 29)), isFalse);
    expect(got.isExpired(DateTime.utc(2026, 7, 5, 12, 30)), isTrue);
    for (final e in reloaded) {
      e.dispose();
    }
  });

  test('code and key bytes are never plaintext on disk', () async {
    final services = await device.boot();
    final sodium = await testSodium();
    final store = PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    );
    final entry = await makeEntry(sodium);
    final pub = Uint8List.fromList(entry.publicKey);
    final sec = entry.secretKey.runUnlockedSync(Uint8List.fromList);
    await store.add(entry);
    entry.dispose();
    await device.shutdown();

    for (final file in allFilesUnder(device.rootDir)) {
      expect(
        fileContainsMarker(file, '7Q2M4K9XV'),
        isFalse,
        reason: '${file.path} leaks the canonical code',
      );
      expect(
        fileContainsBytes(file, pub),
        isFalse,
        reason: '${file.path} leaks the public key',
      );
      expect(
        fileContainsBytes(file, sec),
        isFalse,
        reason: '${file.path} leaks the secret key',
      );
    }
  });

  test('remove is a real erase: last entry deletes the row outright', () async {
    final services = await device.boot();
    final sodium = await testSodium();
    final store = PendingPairingStore(
      storage: services.storage,
      sodium: sodium,
    );
    final a = await makeEntry(sodium);
    final b = await makeEntry(sodium, code: 'ZZZZZZZZZ', date: '2026-12-31');
    await store.add(a);
    await store.add(b);
    a.dispose();
    b.dispose();

    var entries = await store.readAll();
    expect(entries.map((e) => e.code.canonical), ['7Q2M4K9XV', 'ZZZZZZZZZ']);
    for (final e in entries) {
      e.dispose();
    }

    await store.remove(PairingCode.canonicalize('7Q2M4K9XV')!);
    entries = await store.readAll();
    expect(entries.map((e) => e.code.canonical), ['ZZZZZZZZZ']);
    for (final e in entries) {
      e.dispose();
    }

    await store.remove(PairingCode.canonicalize('ZZZZZZZZZ')!);
    expect(await store.readAll(), isEmpty);
    // The meta row itself is gone — no residue.
    expect(
      await services.storage.metaRecords.read(PendingPairingStore.metaKey),
      isNull,
    );
  });
}
