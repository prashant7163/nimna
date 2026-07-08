import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The push dependency FENCE (S15). It replaces the S12 blanket "no push SDK
/// anywhere" ban now that Android push legitimately requires the one Google
/// SDK (USER decision 1). Two invariants, both mechanical:
///
///  1. **firebase is fenced to `lib/src/push/`** — `firebase_messaging` /
///     `firebase_core` may be imported by EXACTLY ONE file
///     (`fcm_push_source.dart`) and nowhere else under `lib/`. iOS uses
///     native APNs (no SDK); everything above the platform source stays
///     SDK-agnostic.
///  2. **telemetry/analytics/crash SDKs are banned EVERYWHERE** — including
///     inside `lib/src/push/`. `firebase_messaging` is messaging-only; the
///     app must never pull `firebase_analytics`, `firebase_crashlytics`,
///     `firebase_performance`, or any third-party analytics/crash/beacon SDK
///     (CLAUDE.md: not a CODE decision, ever).
void main() {
  final importPattern = RegExp(r'''import\s+['"]package:([a-z0-9_]+)''');

  // firebase pieces the push lane is allowed to use — ONLY inside the fence.
  const fencedFirebase = {'firebase_core', 'firebase_messaging'};

  // The single sanctioned firebase import site.
  const firebaseImportSite = 'lib/src/push/fcm_push_source.dart';

  // Push/notification/analytics/crash SDKs that must NOT appear anywhere,
  // fence included. (Nimna forwards a peer-held token INSIDE the E2E KNOCK
  // and renders no notification content — never a bundled notification UI or
  // any telemetry surface.)
  const bannedEverywhere = [
    'firebase_analytics',
    'firebase_crashlytics',
    'firebase_performance',
    'firebase_remote_config',
    'firebase_in_app_messaging',
    'firebase_ml',
    'flutter_apns',
    'apns',
    'onesignal',
    'flutter_local_notifications',
    'flutter_fcm',
    'fcm',
    'sentry',
    'sentry_flutter',
    'mixpanel_flutter',
    'amplitude_flutter',
    'firebase', // the umbrella meta-package
  ];

  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('firebase is imported ONLY by lib/src/push/fcm_push_source.dart', () {
    final offenders = <String>[];
    for (final file in dartFiles) {
      final path = file.path.replaceAll(r'\', '/');
      for (final match in importPattern.allMatches(file.readAsStringSync())) {
        final pkg = match.group(1)!;
        if (fencedFirebase.contains(pkg) && path != firebaseImportSite) {
          offenders.add('$path: imports package:$pkg');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'firebase must stay fenced to $firebaseImportSite (the sole Google '
          'SDK site, per-channel opt-in, default off):\n${offenders.join('\n')}',
    );
  });

  test('the firebase import site actually exists (fence is not vacuous)', () {
    expect(
      File(firebaseImportSite).existsSync(),
      isTrue,
      reason: '$firebaseImportSite must exist for the fence to mean anything',
    );
    final src = File(firebaseImportSite).readAsStringSync();
    expect(
      fencedFirebase.every((p) => src.contains('package:$p')),
      isTrue,
      reason: 'the fenced site must be the one importing firebase',
    );
  });

  test('no analytics/crash/telemetry/notification SDK anywhere under lib/', () {
    final violations = <String>[];
    for (final file in dartFiles) {
      final path = file.path.replaceAll(r'\', '/');
      for (final match in importPattern.allMatches(file.readAsStringSync())) {
        final pkg = match.group(1)!;
        if (bannedEverywhere.contains(pkg)) {
          violations.add('$path: imports package:$pkg');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'A banned telemetry/analytics/crash/notification SDK is imported — '
          'push stays a peer-held token forwarded inside the E2E KNOCK, and '
          'no analytics/crash SDK exists anywhere (CLAUDE.md):\n'
          '${violations.join('\n')}',
    );
  });
}
