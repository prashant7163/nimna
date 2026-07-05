import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/storage/keys/key_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_env.dart';

/// The done-check core, at the storage layer: persists encrypted records
/// across kill-and-relaunch; plaintext provably absent from every on-disk
/// byte; schema reset, seal, and both wipe primitives behave.
void main() {
  const markerLabel = 'NIMNA_TEST_MARKER_LABEL_ZQXJKVBWP';
  const markerMessage = 'NIMNA_TEST_MARKER_MSGBODY_ZQXJKVBWP';
  const markerMedia = 'NIMNA_TEST_MARKER_MEDIA_ZQXJKVBWP';
  const markerCrid = 'NIMNA_MARKER_CRID';
  const markerToken = 'NIMNA_TEST_MARKER_TOKEN';

  late TestDevice device;

  setUp(() {
    device = TestDevice.create();
  });

  tearDown(() async {
    await device.dispose();
  });

  /// Creates one marker-laden channel with [suffix] appended to every
  /// marker. Returns the id plus PRE-CREATE COPIES of the key material —
  /// create() takes ownership and zeroizes the passed buffers (review S1).
  Future<({Uint8List id, Uint8List cdk, Uint8List ownPriv})>
  createMarkerChannel(dynamic services, {String suffix = ''}) async {
    final storage = services.storage;
    final cipher = storage.cipher;
    final cdk = cipher.randomBytes(32);
    final ownPriv = cipher.randomBytes(32);
    final cdkCopy = Uint8List.fromList(cdk);
    final ownPrivCopy = Uint8List.fromList(ownPriv);
    final record = ChannelRecord(
      id: cipher.newRecordId(),
      ownStaticPrivate: ownPriv,
      ownStaticPublic: cipher.randomBytes(32),
      peerStaticPublic: cipher.randomBytes(32),
      crid: asciiBytes(markerCrid + suffix),
      label: markerLabel + suffix,
      cdk: cdk,
      createdAtMs: DateTime.utc(2026, 7, 5).millisecondsSinceEpoch,
      peerDeviceToken: asciiBytes(markerToken + suffix),
    );
    await storage.channels.create(record);
    return (id: record.id, cdk: cdkCopy, ownPriv: ownPrivCopy);
  }

  test('persists encrypted records across storage-layer relaunch', () async {
    var services = await device.boot();
    final created = await createMarkerChannel(services);
    final channelId = created.id;

    for (var i = 0; i < 3; i++) {
      await services.storage.messages.append(
        channelId,
        MessageRecord(
          id: services.storage.cipher.newRecordId(),
          direction: i.isEven
              ? MessageDirection.sent
              : MessageDirection.received,
          timestampMs: 1751700000000 + i,
          type: MessageType.text,
          text: '$markerMessage #$i',
          deliveryState: DeliveryState.sent,
        ),
        purgeAt: i == 2 ? 1751800000000 : null,
      );
    }
    final mediaBytes = asciiBytes(markerMedia * 40);
    final media = await services.storage.media.add(
      channelId: channelId,
      mime: 'image/jpeg',
      bytes: mediaBytes,
    );

    // Kill and relaunch at the storage layer.
    await device.shutdown();
    services = await device.boot();

    final channels = services.storage.channels.all;
    expect(channels, hasLength(1));
    expect(channels.single.label, markerLabel);
    expect(
      services.storage.channels.byCrid(asciiBytes(markerCrid)),
      isNotNull,
      reason: 'CRID index rebuilt at unlock',
    );
    expect(channels.single.peerDeviceToken, asciiBytes(markerToken));

    // Review S1: the cached record's key fields are zeroized — live key
    // material exists only in SecureKey native memory.
    expect(channels.single.cdk.every((b) => b == 0), isTrue);
    expect(channels.single.ownStaticPrivate.every((b) => b == 0), isTrue);

    final messages = await services.storage.messages.byChannel(channelId);
    expect(messages, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(messages[i].text, '$markerMessage #$i');
    }

    final index = await services.storage.media.indexByChannel(channelId);
    expect(index, hasLength(1));
    expect(index.single.byteLength, mediaBytes.length);
    expect(
      index.single.contentHash,
      Uint8List.fromList(hash.sha256.convert(mediaBytes).bytes),
    );
    final blob = await services.storage.media.readBlob(
      channelId: channelId,
      id: media.id,
    );
    expect(blob, mediaBytes);
  });

  test('no plaintext marker or key material in any on-disk byte', () async {
    final services = await device.boot();
    final created = await createMarkerChannel(services);
    final channelId = created.id;
    await services.storage.messages.append(
      channelId,
      MessageRecord(
        id: services.storage.cipher.newRecordId(),
        direction: MessageDirection.sent,
        timestampMs: 1751700000000,
        type: MessageType.text,
        text: markerMessage,
      ),
    );
    await services.storage.media.add(
      channelId: channelId,
      mime: 'application/pdf',
      bytes: asciiBytes(markerMedia * 40),
    );
    services.diag.log(DiagEvent.storeOpened); // diag file exists too

    // Key-material needles from the PRE-CREATE copies (the cached record's
    // fields are zeroized — review S1); scanned both as raw bytes and as
    // their hex-ASCII rendering (review N1).
    final mkRaw = Uint8List.fromList(device.keyStore.stored!);
    final byteNeedles = <String, List<int>>{
      'mk-raw': mkRaw,
      'cdk-raw': created.cdk,
      'ownpriv-raw': created.ownPriv,
    };
    final mkHex = bytesToHex(mkRaw);
    final cdkHex = bytesToHex(created.cdk);
    final ownPrivHex = bytesToHex(created.ownPriv);

    // Scanner sanity: a plaintext file WOULD be caught.
    final canary = File('${device.rootDir.path}/canary.txt')
      ..writeAsStringSync(markerLabel);
    expect(fileContainsMarker(canary, markerLabel), isTrue);
    canary.deleteSync();

    // Scan every byte the app persisted: DB + WAL/SHM sidecars + media
    // blobs + diag day files (WAL exists while the connection is live).
    final files = allFilesUnder(device.rootDir);
    expect(files, isNotEmpty);
    expect(
      files.any((f) => f.path.endsWith('nimna.db')),
      isTrue,
      reason: 'db file must be under the store root',
    );
    for (final file in files) {
      for (final marker in [
        markerLabel,
        markerMessage,
        markerMedia,
        markerCrid,
        markerToken,
        mkHex,
        cdkHex,
        ownPrivHex,
      ]) {
        expect(
          fileContainsMarker(file, marker),
          isFalse,
          reason: 'marker "$marker" leaked into ${file.path}',
        );
      }
      for (final entry in byteNeedles.entries) {
        expect(
          fileContainsBytes(file, entry.value),
          isFalse,
          reason: '${entry.key} bytes leaked into ${file.path}',
        );
      }
    }

    // Control: the same markers ARE recoverable through the API.
    expect(services.storage.channels.all.single.label, markerLabel);
    final messages = await services.storage.messages.byChannel(channelId);
    expect(messages.single.text, markerMessage);
  });

  test('sealing closes the decryption path structurally', () async {
    final services = await device.boot();
    await createMarkerChannel(services);
    final channelsRepo = services.storage.channels;

    await services.storage.seal();

    expect(services.keyService.sealed, isTrue);
    expect(() => services.storage.channels, throwsStateError);
    expect(() => channelsRepo.all, throwsStateError);
    expect(
      () => services.keyService.channelsKey,
      throwsA(isA<StorageSealedError>()),
    );
  });

  test('schema-version mismatch triggers destructive reset', () async {
    var services = await device.boot();
    await createMarkerChannel(services);
    await device.shutdown();

    // Tamper the schema epoch out from under the app.
    final db = await databaseFactoryFfi.openDatabase(device.storeRoot.dbPath);
    await db.update('meta', {
      'v': Uint8List.fromList('99'.codeUnits),
    }, where: "k = 'schema_version'");
    await db.close();

    services = await device.boot();
    expect(
      services.storage.channels.all,
      isEmpty,
      reason: 'reset store starts empty',
    );
    final events = services.diag.readAll().map((r) => r.event).toList();
    expect(events, contains(DiagEvent.schemaReset));
  });

  test('full wipe: fresh empty store, new master key, no trace', () async {
    var services = await device.boot();
    await createMarkerChannel(services);
    final mkBefore = bytesToHex(device.keyStore.stored!);

    await services.storage.fullWipe();

    expect(device.keyStore.stored, isNull, reason: 'keystore entry destroyed');
    expect(services.keyService.sealed, isTrue);
    expect(
      allFilesUnder(device.rootDir),
      isEmpty,
      reason: 'store root recreated empty',
    );

    // Relaunch: indistinguishable from a fresh install.
    services = await device.boot();
    expect(bytesToHex(device.keyStore.stored!), isNot(mkBefore));
    expect(services.storage.channels.all, isEmpty);
    final events = services.diag.readAll().map((r) => r.event).toSet();
    expect(events, isNot(contains(DiagEvent.channelWiped)));
    expect(events, contains(DiagEvent.masterKeyGenerated));
  });

  test('per-channel wipe kills rows and files; others intact', () async {
    final services = await device.boot();
    final idA = (await createMarkerChannel(services, suffix: '_A')).id;
    final idB = (await createMarkerChannel(services, suffix: '_B')).id;

    Future<void> addContent(Uint8List channelId, String tag) async {
      await services.storage.messages.append(
        channelId,
        MessageRecord(
          id: services.storage.cipher.newRecordId(),
          direction: MessageDirection.sent,
          timestampMs: 1751700000000,
          type: MessageType.text,
          text: 'msg $tag',
        ),
      );
      await services.storage.media.add(
        channelId: channelId,
        mime: 'image/png',
        bytes: asciiBytes('blob $tag' * 10),
      );
    }

    await addContent(idA, 'A');
    await addContent(idB, 'B');
    final mediaFilesBefore = allFilesUnder(device.storeRoot.mediaDir);
    expect(mediaFilesBefore, hasLength(2));

    await services.storage.wipeChannel(idA);

    expect(services.storage.channels.all, hasLength(1));
    expect(services.storage.channels.byId(idB), isNotNull);
    expect(await services.storage.messages.byChannel(idA), isEmpty);
    expect(await services.storage.messages.byChannel(idB), hasLength(1));
    expect(
      allFilesUnder(device.storeRoot.mediaDir),
      hasLength(1),
      reason: "A's blob file deleted, B's kept",
    );
    final events = services.diag.readAll().map((r) => r.event).toList();
    expect(events, contains(DiagEvent.channelWiped));
  });

  test('store root layout: one root, explicit db path, subdirs', () async {
    await device.boot();
    expect(device.storeRoot.dbFile.existsSync(), isTrue);
    expect(device.storeRoot.mediaDir.existsSync(), isTrue);
    expect(device.storeRoot.diagDir.existsSync(), isTrue);
    expect(device.storeRoot.dbPath, contains('nimna.db'));
  });
}
