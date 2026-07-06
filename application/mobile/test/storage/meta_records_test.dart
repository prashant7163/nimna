import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/storage/keys/key_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_env.dart';

/// Encrypted meta values (S8): round-trip, real erase, ciphertext-only at
/// rest, transplant rejection, sealed perimeter.
void main() {
  late TestDevice device;

  setUp(() async {
    device = TestDevice.create();
  });

  tearDown(() => device.dispose());

  test('round-trip, rewrite, and delete', () async {
    final services = await device.boot();
    final meta = services.storage.metaRecords;

    expect(await meta.read('test_value'), isNull);

    final v1 = Uint8List.fromList(List.generate(64, (i) => i));
    await meta.write('test_value', v1);
    expect(await meta.read('test_value'), v1);

    final v2 = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    await meta.write('test_value', v2);
    expect(await meta.read('test_value'), v2);

    await meta.delete('test_value');
    expect(await meta.read('test_value'), isNull);
  });

  test('value is ciphertext on disk and survives restart', () async {
    var services = await device.boot();
    const marker = 'META-MARKER-7Q2M4K9XV-END';
    await services.storage.metaRecords.write('test_value', asciiBytes(marker));
    await device.shutdown();

    // Raw scan: the marker never appears in any store file.
    for (final file in allFilesUnder(device.rootDir)) {
      expect(
        fileContainsMarker(file, marker),
        isFalse,
        reason: '${file.path} leaks the meta value',
      );
    }

    services = await device.boot();
    expect(
      await services.storage.metaRecords.read('test_value'),
      asciiBytes(marker),
    );
  });

  test(
    'ciphertext transplanted onto another key fails authentication',
    () async {
      var services = await device.boot();
      final meta = services.storage.metaRecords;
      await meta.write('test_value', asciiBytes('value-a'));
      await meta.write('other_key', asciiBytes('value-b'));
      final dbPath = device.storeRoot.dbPath;
      await device.shutdown();

      // Transplant test_value's sealed bytes onto other_key's row —
      // the attacker's move an AD-bound record must defeat.
      final raw = await databaseFactoryFfi.openDatabase(dbPath);
      final rows = await raw.query(
        'meta',
        where: 'k = ?',
        whereArgs: ['test_value'],
      );
      await raw.update(
        'meta',
        {'v': rows.single['v']},
        where: 'k = ?',
        whereArgs: ['other_key'],
      );
      await raw.close();

      services = await device.boot();
      expect(
        await services.storage.metaRecords.read('test_value'),
        asciiBytes('value-a'),
      );
      expect(
        () => services.storage.metaRecords.read('other_key'),
        throwsA(isA<AeadAuthError>()),
      );
    },
  );

  test('sealed perimeter: reads throw StorageSealedError', () async {
    final services = await device.boot();
    await services.storage.metaRecords.write('test_value', asciiBytes('x'));
    services.keyService.seal();
    expect(
      () => services.storage.metaRecords.read('test_value'),
      throwsA(isA<StorageSealedError>()),
    );
  });
}
