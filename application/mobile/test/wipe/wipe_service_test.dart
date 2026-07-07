import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/crypto/record_cipher.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/storage/keys/key_service.dart';
import 'package:nimna/src/storage/keys/master_key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_env.dart';

/// A keystore whose delete() takes a snapshot of the store root at the
/// exact destruction moment — proving the keystore entry dies BEFORE any
/// file deletion (intake §7: destruction ORDER asserted via fakes).
class OrderProbeKeyStore implements MasterKeyStore {
  OrderProbeKeyStore(this.inner, this.rootDir);

  final MasterKeyStore inner;
  final Directory rootDir;
  int? filesPresentAtDelete;
  bool? dbPresentAtDelete;

  @override
  Future<Uint8List?> read() => inner.read();

  @override
  Future<void> write(Uint8List key) => inner.write(key);

  @override
  Future<void> delete() {
    final files = allFilesUnder(rootDir);
    filesPresentAtDelete = files.length;
    dbPresentAtDelete = files.any((f) => f.path.endsWith('nimna.db'));
    return inner.delete();
  }
}

/// A keystore whose delete() succeeds and then throws — the interrupted
/// wipe: step 1 (MK destruction) landed, everything after was cut off.
class InterruptAfterDeleteKeyStore implements MasterKeyStore {
  InterruptAfterDeleteKeyStore(this.inner);

  final MasterKeyStore inner;

  @override
  Future<Uint8List?> read() => inner.read();

  @override
  Future<void> write(Uint8List key) => inner.write(key);

  @override
  Future<void> delete() async {
    await inner.delete();
    throw StateError('interrupted after keystore destruction');
  }
}

void main() {
  const markerLabel = 'NIMNA_WIPE_MARKER_LABEL_ZQXJKVBWP';
  const markerMessage = 'NIMNA_WIPE_MARKER_MSG_ZQXJKVBWP';
  const markerMedia = 'NIMNA_WIPE_MARKER_MEDIA_ZQXJKVBWP';

  late TestDevice device;

  setUp(() {
    device = TestDevice.create();
  });

  tearDown(() async {
    await device.dispose();
  });

  Future<Uint8List> seedChannel(dynamic services, {String suffix = ''}) async {
    final storage = services.storage;
    final cipher = storage.cipher as RecordCipher;
    final record = ChannelRecord(
      id: cipher.newRecordId(),
      ownStaticPrivate: cipher.randomBytes(32),
      ownStaticPublic: cipher.randomBytes(32),
      peerStaticPublic: cipher.randomBytes(32),
      crid: asciiBytes('CRID$suffix'),
      label: markerLabel + suffix,
      cdk: cipher.randomBytes(32),
      createdAtMs: DateTime.utc(2026, 7, 7).millisecondsSinceEpoch,
    );
    await storage.channels.create(record);
    await storage.messages.append(
      record.id,
      MessageRecord(
        id: cipher.newRecordId(),
        direction: MessageDirection.sent,
        timestampMs: 1751800000000,
        type: MessageType.text,
        text: markerMessage + suffix,
      ),
    );
    await storage.media.add(
      channelId: record.id,
      mime: 'image/png',
      bytes: asciiBytes((markerMedia + suffix) * 20),
    );
    return record.id;
  }

  test('full wipe: keystore + lock config destroyed, zero residual markers, '
      'reopened fresh-install state', () async {
    final services = await device.boot();
    final lock = services.lockController;
    await lock.enableLock(pin: '8642', biometricEnabled: false);
    await seedChannel(services);
    final mkBefore = bytesToHex(device.keyStore.stored!);

    await services.wipe.fullWipe();

    // Keystore MK entry gone and re-minted at reopen; lock config gone —
    // fresh-install indistinguishability, including "App lock: Off".
    expect(bytesToHex(device.keyStore.stored!), isNot(mkBefore));
    expect(device.lockStore.stored, isNull);
    expect(lock.enabled, isFalse);

    // Reopened to the F4.4 empty list.
    expect(services.storage.isOpen, isTrue);
    expect(services.keyService.sealed, isFalse);
    expect(services.storage.channels.all, isEmpty);

    // Planted-marker audit: recursive raw-byte scan of the store root.
    for (final file in allFilesUnder(device.rootDir)) {
      for (final marker in [markerLabel, markerMessage, markerMedia]) {
        expect(
          fileContainsMarker(file, marker),
          isFalse,
          reason: 'marker "$marker" survived in ${file.path}',
        );
      }
    }

    // The pre-wipe diag ring died with the store (step 2): the reopened
    // log holds only fresh-install-shaped events — no channelWiped, no
    // event predating the new MK, nothing that betrays a wipe happened.
    final events = services.diag.readAll().map((r) => r.event).toList();
    expect(events, isNot(contains(DiagEvent.channelWiped)));
    expect(events, contains(DiagEvent.masterKeyGenerated));
  });

  test(
    'destruction ORDER: keystore entry dies before any file deletion',
    () async {
      var services = await device.boot();
      await seedChannel(services);
      await device.shutdown();

      final probe = OrderProbeKeyStore(device.keyStore, device.rootDir);
      services = await device.boot(masterKeyStore: probe);

      await services.wipe.fullWipe();

      expect(
        probe.dbPresentAtDelete,
        isTrue,
        reason: 'DB must still exist at the keystore-destruction moment',
      );
      expect(probe.filesPresentAtDelete, greaterThan(0));
      // …and afterwards the reopened store is fresh (the old files died
      // between the keystore delete and the reopen).
      expect(services.storage.channels.all, isEmpty);
      expect(bytesToHex(device.keyStore.stored!).isNotEmpty, isTrue);
    },
  );

  test('interrupted wipe after step 1: every surviving ciphertext is '
      'undecryptable', () async {
    var services = await device.boot();
    await seedChannel(services);
    await device.shutdown();

    final interrupting = InterruptAfterDeleteKeyStore(device.keyStore);
    services = await device.boot(masterKeyStore: interrupting);

    await expectLater(services.wipe.fullWipe(), throwsStateError);

    // The boundary held: the MK is gone even though deletion never ran.
    expect(device.keyStore.stored, isNull);
    final survivors = allFilesUnder(device.rootDir);
    expect(survivors, isNotEmpty, reason: 'deletion was interrupted');

    // Recompute the key hierarchy the way any future process would — the
    // keystore is empty, so opening mints a brand-new MK — and prove the
    // surviving channel rows fail authentication: dead ciphertext.
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final cipher = RecordCipher(aead);
    final futureProcessKeys = KeyService(
      sodium: sodium,
      keyStore: device.keyStore, // MK entry destroyed above
      diag: Diag(aead: aead),
    );
    expect(await futureProcessKeys.open(), isTrue, reason: 'new MK minted');

    final db = await databaseFactoryFfi.openDatabase(device.storeRoot.dbPath);
    final rows = await db.query('channels');
    await db.close();
    expect(rows, isNotEmpty, reason: 'interrupted before row deletion');
    for (final row in rows) {
      expect(
        () => cipher.open(
          baseKey: futureProcessKeys.channelsKey,
          storeId: 0x01,
          recordId: row['id']! as Uint8List,
          sealed: row['ct']! as Uint8List,
        ),
        throwsA(isA<AeadAuthError>()),
      );
    }
    futureProcessKeys.seal();
  });

  test(
    'per-channel wipe: pre-wipe hook fires first, only that channel dies',
    () async {
      final services = await device.boot();
      final idA = await seedChannel(services, suffix: '_A');
      final idB = await seedChannel(services, suffix: '_B');

      Uint8List? hookedId;
      var channelAliveAtHook = false;
      services.wipe.preChannelWipeHook = (channelId) async {
        hookedId = channelId;
        channelAliveAtHook = services.storage.channels.byId(channelId) != null;
      };

      await services.wipe.wipeChannel(idA);

      expect(hookedId, idA, reason: 'session hang-up seam fires');
      expect(channelAliveAtHook, isTrue, reason: 'hook fires BEFORE the wipe');
      expect(services.storage.channels.byId(idA), isNull);
      expect(services.storage.channels.byId(idB), isNotNull);
      expect(await services.storage.messages.byChannel(idA), isEmpty);
      expect(await services.storage.messages.byChannel(idB), hasLength(1));

      // Raw scan: A's markers gone from every on-disk byte, B's data intact
      // through the API.
      for (final file in allFilesUnder(device.rootDir)) {
        expect(fileContainsMarker(file, '${markerLabel}_A'), isFalse);
        expect(fileContainsMarker(file, '${markerMessage}_A'), isFalse);
        expect(fileContainsMarker(file, '${markerMedia}_A'), isFalse);
      }
      expect(services.storage.channels.byId(idB)!.label, '${markerLabel}_B');
    },
  );
}
