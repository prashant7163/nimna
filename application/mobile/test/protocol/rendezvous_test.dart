import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/pairing_code.dart';
import 'package:nimna/src/protocol/rendezvous.dart';

import '../helpers/test_env.dart';

/// §3.1.2 topic/psk derivation — vector-locked to
/// docs/test-vectors/topic-derivation.json under BOTH parameter sets:
/// the reduced-cost set is the fast default lane; the production-cost set
/// (t=3, m=64 MiB — what real devices produce) runs in the tagged
/// `production-cost` lane (mirrors the Go `-short` split; selectable via
/// `--tags` / excludable via `--exclude-tags`, and it runs in the default
/// suite too).
void main() {
  final vectors =
      jsonDecode(
            File(
              '../../docs/test-vectors/topic-derivation.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final validCases = (vectors['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((c) => c['valid'] as bool)
      .toList();

  test('Argon2id constants match the committed protocol constants', () {
    final prod = vectors['argon2id_production'] as Map<String, dynamic>;
    expect(Argon2Cost.production.opsLimit, prod['time']);
    expect(
      Argon2Cost.production.memLimitBytes,
      (prod['memory_kib'] as int) * 1024,
    );
    expect(prod['parallelism'], 1); // libsodium pwhash p — fixed.
    expect(prod['output_len'], pskBytes);
    final reduced =
        vectors['argon2id_reduced_test_only'] as Map<String, dynamic>;
    expect(Argon2Cost.reducedTestOnly.opsLimit, reduced['time']);
    expect(
      Argon2Cost.reducedTestOnly.memLimitBytes,
      (reduced['memory_kib'] as int) * 1024,
    );
  });

  test('HKDF labels and lengths match the committed vectors', () {
    final hkdf = vectors['hkdf'] as Map<String, dynamic>;
    expect(topicLabel, hkdf['topic_info']);
    expect(pskLabel, hkdf['psk_info']);
    expect(topicBytes, hkdf['topic_len']);
    expect(pskBytes, hkdf['psk_len']);
  });

  group('salt = SHA-256("nimna/topic/v1|" + date)[0:16]', () {
    for (final c in validCases) {
      test(c['name'], () {
        final date = c['creation_date_utc'] as String;
        expect(
          '$topicLabel|$date'.codeUnits,
          ascii.encode(c['salt_preimage_ascii'] as String),
        );
        expect(bytesToHex(rendezvousSalt(date)), c['salt']);
      });
    }
  });

  group('reduced-cost lane (fast default)', () {
    for (final c in validCases) {
      test(c['name'], () async {
        final sodium = await testSodium();
        final expected = c['reduced_test_only'] as Map<String, dynamic>;
        final secrets = deriveRendezvous(
          sodium: sodium,
          code: PairingCode.canonicalize(c['input'] as String)!,
          utcDate: c['creation_date_utc'] as String,
          cost: Argon2Cost.reducedTestOnly,
        );
        addTearDown(secrets.dispose);
        expect(bytesToHex(secrets.topic), expected['topic']);
        expect(
          bytesToHex(secrets.psk.runUnlockedSync(Uint8List.fromList)),
          expected['psk'],
        );
      });
    }
  });

  group('production-cost lane (tagged; the on-device parameters)', () {
    for (final c in validCases) {
      test(c['name'], () async {
        final sodium = await testSodium();
        final expected = c['production'] as Map<String, dynamic>;
        final secrets = deriveRendezvous(
          sodium: sodium,
          code: PairingCode.canonicalize(c['input'] as String)!,
          utcDate: c['creation_date_utc'] as String,
          // Deliberately the DEFAULT cost — proves app code derives the
          // production values without naming a cost.
        );
        addTearDown(secrets.dispose);
        expect(bytesToHex(secrets.topic), expected['topic']);
        expect(
          bytesToHex(secrets.psk.runUnlockedSync(Uint8List.fromList)),
          expected['psk'],
        );
      }, tags: ['production-cost']);
    }
  });

  test('utcDateString formats the spec 10-byte date, locale-independent', () {
    expect(utcDateString(DateTime.utc(2026, 7, 4)), '2026-07-04');
    expect(utcDateString(DateTime.utc(2026, 1, 31, 23, 59)), '2026-01-31');
    // A local-time instant is folded to UTC before formatting.
    expect(
      utcDateString(DateTime.utc(2026, 12, 31, 23).toLocal()),
      '2026-12-31',
    );
  });
}
