import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';

import '../helpers/test_env.dart';

/// The planted-marker audit (app-architecture.md §6 test layer 3 — mirror
/// of the relay logscrub test): drive real storage flows carrying known
/// sensitive markers — a fake Nimna-code string, fake token bytes, key hex
/// — then prove the markers appear neither in the decrypted diagnostic log
/// dump nor anywhere in the raw on-disk log bytes.
void main() {
  // A fake code in canonical XXX-XXX-XXX display form, plus its bare form.
  const fakeCodeDisplay = 'ZQX-JKV-BWP';
  const fakeCodeBare = 'ZQXJKVBWP';
  const fakeLabel = 'AUDIT_MARKER_LABEL_$fakeCodeBare';
  const fakeMessage = 'AUDIT_MARKER_BODY_$fakeCodeBare';
  const fakeTokenText = 'AUDIT_MARKER_TOKEN_$fakeCodeBare';

  test('diag log contains no content, keys, codes, or tokens', () async {
    final device = TestDevice.create();
    addTearDown(device.dispose);
    final services = await device.boot();
    final cipher = services.storage.cipher;

    // Drive flows that touch every diag-logging path with markers in play.
    // create() takes ownership of key material and zeroizes the passed
    // buffers (review S1) — snapshot the needles first.
    final cdk = cipher.randomBytes(32);
    final cdkCopy = Uint8List.fromList(cdk);
    final channel = ChannelRecord(
      id: cipher.newRecordId(),
      ownStaticPrivate: cipher.randomBytes(32),
      ownStaticPublic: cipher.randomBytes(32),
      peerStaticPublic: cipher.randomBytes(32),
      crid: asciiBytes(fakeCodeBare),
      label: fakeLabel,
      cdk: cdk,
      createdAtMs: 1751700000000,
      peerDeviceToken: asciiBytes(fakeTokenText),
    );
    await services.storage.channels.create(channel);
    await services.storage.messages.append(
      channel.id,
      MessageRecord(
        id: cipher.newRecordId(),
        direction: MessageDirection.received,
        timestampMs: 1751700000001,
        type: MessageType.text,
        text: fakeMessage,
      ),
    );
    await services.storage.media.add(
      channelId: channel.id,
      mime: 'image/jpeg',
      bytes: asciiBytes(fakeMessage * 20),
    );
    await services.storage.wipeChannel(channel.id);
    // Error path with a code arg (ints only — the API admits nothing else).
    services.diag.log(
      DiagEvent.storageError,
      code: DiagCode.ioError,
      args: [42],
    );

    final mkRaw = Uint8List.fromList(device.keyStore.stored!);
    final markers = [
      fakeCodeDisplay,
      fakeCodeBare,
      fakeLabel,
      fakeMessage,
      fakeTokenText,
      bytesToHex(cdkCopy),
      bytesToHex(mkRaw),
    ];
    // Raw byte needles for key material (review N1).
    final byteNeedles = <String, List<int>>{
      'cdk-raw': cdkCopy,
      'mk-raw': mkRaw,
    };

    // 1. The decrypted dump: every record decodes to closed-enum ids and
    //    int args — there is structurally nowhere for a marker to hide;
    //    render each record's full content and assert markers absent.
    final records = services.diag.readAll();
    expect(records, isNotEmpty);
    for (final record in records) {
      expect(DiagEvent.values, contains(record.event));
      expect(DiagCode.values, contains(record.code));
      final rendered =
          '${record.event.name} ${record.code.name} '
          '${record.timestampMs} ${record.args.join(' ')}';
      for (final marker in markers) {
        expect(
          rendered.contains(marker),
          isFalse,
          reason: 'marker "$marker" surfaced in decoded diag record',
        );
      }
    }

    // 2. The raw on-disk log bytes.
    final diagFiles = allFilesUnder(device.storeRoot.diagDir);
    expect(diagFiles, isNotEmpty, reason: 'diag day file must exist');
    for (final file in diagFiles) {
      for (final marker in markers) {
        expect(
          fileContainsMarker(file, marker),
          isFalse,
          reason: 'marker "$marker" leaked into raw ${file.path}',
        );
      }
      for (final entry in byteNeedles.entries) {
        expect(
          fileContainsBytes(file, entry.value),
          isFalse,
          reason: '${entry.key} bytes leaked into raw ${file.path}',
        );
      }
    }
  });
}
