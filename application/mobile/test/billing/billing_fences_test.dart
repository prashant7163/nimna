import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural invariants for S17 billing (same class as the S8 source-scan
/// pins; reviewer remains the authority):
///
/// 1. **in_app_purchase fence:** `package:in_app_purchase` is imported by
///    exactly ONE module — `lib/src/billing/store_entitlement_source.dart`.
///    Everything else talks to the pure-Dart [EntitlementSource] seam, so the
///    store SDK can never leak into the app.
/// 2. **Permanence — no billing on the session/storage path:** the
///    protocol, transport, and storage trees (the send/receive/session path)
///    NEVER reference billing. Permanence is structural (spec §10): a lapse
///    can only be discovered at creation intent, never on an existing
///    channel, because nothing on that path can consult the subscription.
void main() {
  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String stripComments(String source) =>
      source.replaceAll(RegExp(r'//[^\n]*'), '');

  test('package:in_app_purchase is imported only by the store source', () {
    const storeModule = 'lib/src/billing/store_entitlement_source.dart';
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.path == storeModule || file.path.contains('lib/l10n/')) {
        continue;
      }
      final code = stripComments(file.readAsStringSync());
      if (code.contains('package:in_app_purchase')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'in_app_purchase is fenced to $storeModule (SESSION-17). The store '
          'SDK must never leak past the EntitlementSource seam. Offenders: '
          '$offenders',
    );
  });

  test('no PROVISIONAL placeholder survives in the billing ARB namespace', () {
    // The paywall disclosure was USER-approved 2026-07-07 12:39; the
    // pre-merge-blocker placeholder must be fully gone from every billing_*
    // key and its metadata. Scoped to the billing namespace on purpose —
    // other sessions legitimately carry their own PROVISIONAL design-loop
    // flags (e.g. S13), which are out of this lane.
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final offenders = <String>[];
    arb.forEach((key, value) {
      if (!key.toLowerCase().contains('billing')) {
        return;
      }
      if (jsonEncode(value).contains('PROVISIONAL')) {
        offenders.add(key);
      }
    });
    expect(
      offenders,
      isEmpty,
      reason:
          'PROVISIONAL text still present in a billing_* ARB entry (S17 '
          'pre-merge blocker was cleared 2026-07-07 12:39). Offenders: '
          '$offenders',
    );
  });

  test('the session/storage path never references billing (permanence)', () {
    // The send/receive/session path + at-rest storage. If any of these ever
    // consulted the subscription, permanence would stop being structural.
    const guardedTrees = [
      'lib/src/protocol',
      'lib/src/transport',
      'lib/src/storage',
      'lib/src/crypto',
    ];
    final offenders = <String>[];
    final pattern = RegExp(r'\b(BillingService|EntitlementSource|\.billing)\b');
    for (final tree in guardedTrees) {
      if (!Directory(tree).existsSync()) {
        continue;
      }
      for (final file in dartFilesUnder(tree)) {
        final code = stripComments(file.readAsStringSync());
        if (pattern.hasMatch(code)) {
          offenders.add(file.path);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A session/storage-path file references billing — the send/receive '
          'path and at-rest store must NEVER consult the subscription '
          '(permanence is structural, spec §10). Offenders: $offenders',
    );
  });
}
