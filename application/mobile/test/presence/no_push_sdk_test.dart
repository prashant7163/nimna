import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Push-off = pure burner-line mode: a channel with push off touches no
/// third-party service. S12 wires opt-in persistence and the token-into-KNOCK
/// payload, but adds NO push SDK — live APNs/FCM own-token acquisition is S15
/// and rides the platform, never a bundled package (spec §3.2.1; CLAUDE.md:
/// no telemetry/crash/analytics/push SDK anywhere). This is the mechanical
/// fence: no source file under lib/ may import a push/notification SDK.
void main() {
  test('no push/notification SDK is imported anywhere under lib/', () {
    // Package prefixes that would mean a third-party push/notification SDK is
    // bundled. (Nimna forwards a peer-held token INSIDE the E2E KNOCK; it
    // never registers with a push service via an SDK.)
    const bannedPackages = [
      'firebase_messaging',
      'firebase_core',
      'firebase',
      'flutter_apns',
      'apns',
      'onesignal',
      'flutter_local_notifications',
      'flutter_fcm',
      'fcm',
    ];
    final importPattern = RegExp(r'''import\s+['"]package:([a-z0-9_]+)''');
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in importPattern.allMatches(source)) {
        final pkg = match.group(1)!;
        if (bannedPackages.contains(pkg)) {
          violations.add('${entity.path}: imports package:$pkg');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'A push/notification SDK is imported — push must stay a peer-held '
          'token forwarded inside the E2E KNOCK, never a bundled SDK:\n'
          '${violations.join('\n')}',
    );
  });
}
