import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/outer_frame.dart';

import '../helpers/test_env.dart';

/// §5.4 outer-frame codec — vector-locked to docs/test-vectors/framing.json
/// (`outer_frames`: one committed example per frame type), plus strict
/// reject cases (short header, wrong version, unknown type).
void main() {
  final vectors =
      jsonDecode(
            File('../../docs/test-vectors/framing.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final frames = (vectors['outer_frames'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  test('the committed vectors cover the whole frame-type enum', () {
    final covered = frames
        .map((f) => int.parse((f['frame_type'] as String).split(' ').first))
        .toSet();
    expect(covered, FrameType.values.map((t) => t.wire).toSet());
  });

  group('encode/decode per committed vector', () {
    for (final f in frames) {
      test(f['name'], () {
        final wireValue = int.parse(
          (f['frame_type'] as String).split(' ').first,
        );
        final type = FrameType.fromWire(wireValue)!;
        final routingId = hexToBytes(f['routing_id'] as String);
        final payload = hexToBytes(f['payload'] as String);
        final encoded = hexToBytes(f['encoded'] as String);

        expect(
          OuterFrame(
            type: type,
            routingId: routingId,
            payload: payload,
          ).encode(),
          encoded,
        );

        final decoded = OuterFrame.decode(encoded);
        expect(decoded.type, type);
        expect(decoded.routingId, routingId);
        expect(decoded.payload, payload);
      });
    }
  });

  group('strict rejects', () {
    final valid = hexToBytes((frames.first)['encoded'] as String);

    test('short header (every length below 18)', () {
      for (var len = 0; len < outerHeaderBytes; len++) {
        expect(
          () => OuterFrame.decode(Uint8List.sublistView(valid, 0, len)),
          throwsA(isA<OuterFrameError>()),
          reason: 'length $len must reject',
        );
      }
    });

    test('exactly 18 bytes with empty payload decodes', () {
      final decoded = OuterFrame.decode(
        Uint8List.sublistView(valid, 0, outerHeaderBytes),
      );
      expect(decoded.payload, isEmpty);
    });

    test('wrong version rejects', () {
      final bad = Uint8List.fromList(valid);
      bad[0] = 0x02;
      expect(() => OuterFrame.decode(bad), throwsA(isA<OuterFrameError>()));
      bad[0] = 0x00;
      expect(() => OuterFrame.decode(bad), throwsA(isA<OuterFrameError>()));
    });

    test('unknown frame type rejects', () {
      for (final wire in [0x00, 0x06, 0x0F, 0x13, 0x22, 0xFF]) {
        final bad = Uint8List.fromList(valid);
        bad[1] = wire;
        expect(
          () => OuterFrame.decode(bad),
          throwsA(isA<OuterFrameError>()),
          reason: 'frame_type 0x${wire.toRadixString(16)} must reject',
        );
      }
    });

    test('constructor enforces the 16-byte routing id', () {
      expect(
        () =>
            OuterFrame(type: FrameType.registerTopic, routingId: Uint8List(15)),
        throwsArgumentError,
      );
    });
  });
}
