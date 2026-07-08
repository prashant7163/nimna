import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The "zero telemetry SDKs" DONE-WHEN gate (architect Concern 3), turning the
/// non-waivable CLAUDE.md doctrine — "No telemetry/crash/analytics SDKs
/// anywhere, ever — not a CODE decision" — into a mechanical CI assertion.
///
/// The S15 source-import fence (push_dependency_fence_test) is the SECOND belt:
/// it greps `lib/**.dart` imports. It is necessary but NOT sufficient — a
/// telemetry SDK could enter TRANSITIVELY (pulled by a dependency) without any
/// `lib/` import. THIS test walks `pubspec.lock` (direct + transitive, the
/// firebase_messaging subtree included) and the native surfaces (Android
/// gradle, iOS Info.plist / SPM Package.resolved) and asserts NO analytics /
/// crash / telemetry package or plugin appears. `firebase_messaging` is
/// messaging-only and allowed; `firebase_analytics`/`crashlytics`/`performance`
/// are NOT.
void main() {
  // Banned families. A package is banned if its name equals one of these or
  // begins with one followed by `_` (so `sentry` matches `sentry_flutter`,
  // `firebase_analytics` matches `firebase_analytics_platform_interface`).
  const banned = <String>[
    'firebase_analytics',
    'firebase_crashlytics',
    'firebase_performance',
    'firebase_remote_config',
    'firebase_in_app_messaging',
    'firebase_ml',
    'firebase_ml_model_downloader',
    'firebase_installations',
    'sentry',
    'sentry_flutter',
    'mixpanel',
    'mixpanel_flutter',
    'amplitude',
    'amplitude_flutter',
    'segment',
    'analytics',
    'google_analytics',
    'datadog',
    'datadog_flutter_plugin',
    'bugsnag',
    'bugsnag_flutter',
    'onesignal',
    'onesignal_flutter',
    'appcenter',
    'countly_flutter',
    'flutter_local_notifications',
    'posthog',
    'posthog_flutter',
    'instabug',
    'embrace',
    'newrelic_mobile',
  ];

  bool isBanned(String pkg) {
    for (final b in banned) {
      if (pkg == b || pkg.startsWith('${b}_')) {
        return true;
      }
    }
    return false;
  }

  List<String> lockPackageNames() {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue, reason: 'pubspec.lock must exist');
    final names = <String>[];
    var inPackages = false;
    // Package names sit at exactly 2-space indent under the top-level
    // `packages:` map, e.g. `  firebase_messaging:`.
    final entry = RegExp(r'^  ([a-z0-9_]+):\s*$');
    for (final line in lock.readAsLinesSync()) {
      if (line == 'packages:') {
        inPackages = true;
        continue;
      }
      if (inPackages && RegExp(r'^[a-z]').hasMatch(line)) {
        // A new top-level key (e.g. `sdks:`) ends the packages map.
        break;
      }
      final m = entry.firstMatch(line);
      if (inPackages && m != null) {
        names.add(m.group(1)!);
      }
    }
    return names;
  }

  test('pubspec.lock (direct + transitive) contains no telemetry/analytics/'
      'crash SDK', () {
    final names = lockPackageNames();
    final offenders = names.where(isBanned).toList();
    expect(
      offenders,
      isEmpty,
      reason:
          'A telemetry/analytics/crash package is in the dependency tree — the '
          'non-waivable CLAUDE.md gate forbids it (firebase_messaging is '
          'messaging-only; analytics/crashlytics/performance are banned). '
          'Found: $offenders',
    );
  });

  test('the lockfile parser is not vacuous (finds real packages incl. the '
      'firebase_messaging subtree)', () {
    final names = lockPackageNames();
    // Proves the parser reads real names — a broken parser returning nothing
    // would make the ban assertion pass for the wrong reason.
    expect(names, contains('firebase_messaging'));
    expect(names, contains('firebase_core'));
    expect(names.length, greaterThan(50));
    // And the matcher itself turns red on a planted banned name.
    expect(isBanned('firebase_crashlytics'), isTrue);
    expect(isBanned('sentry_flutter'), isTrue);
    expect(isBanned('mixpanel_flutter'), isTrue);
    // ...while messaging-only firebase stays allowed.
    expect(isBanned('firebase_messaging'), isFalse);
    expect(isBanned('firebase_core'), isFalse);
  });

  test(
    'Android gradle carries no firebase analytics/crashlytics/perf plugin',
    () {
      final gradles = Directory('android')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.gradle') || f.path.endsWith('.gradle.kts'),
          )
          .where((f) => !f.path.contains('/.gradle/'))
          .toList();
      expect(gradles, isNotEmpty, reason: 'android gradle files must exist');
      const bannedNative = <String>[
        'firebase-analytics',
        'firebase-crashlytics',
        'com.google.firebase.crashlytics',
        'firebase-perf',
        'com.google.firebase.firebase-perf',
        'play-services-analytics',
        'play-services-measurement',
        'com.google.android.gms.analytics',
      ];
      final offenders = <String>[];
      for (final f in gradles) {
        final src = f.readAsStringSync();
        for (final needle in bannedNative) {
          if (src.contains(needle)) {
            offenders.add('${f.path}: $needle');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Android native carries a firebase analytics/crashlytics/perf plugin '
            '(only APNs/FCM messaging + billing are sanctioned): $offenders',
      );
    },
  );

  test('iOS Info.plist declares no analytics-collection keys; any SPM '
      'Package.resolved carries no analytics framework', () {
    final plist = File('ios/Runner/Info.plist');
    expect(plist.existsSync(), isTrue, reason: 'iOS Info.plist must exist');
    final plistSrc = plist.readAsStringSync();
    const bannedPlistKeys = <String>[
      'FirebaseAppDelegateProxyEnabled',
      'FirebaseAutomaticScreenReportingEnabled',
      'GADApplicationIdentifier',
      'FIREBASE_ANALYTICS_COLLECTION_ENABLED',
      'firebase_crashlytics_collection_enabled',
    ];
    final plistOffenders = bannedPlistKeys.where(plistSrc.contains).toList();
    expect(
      plistOffenders,
      isEmpty,
      reason: 'iOS Info.plist declares an analytics key: $plistOffenders',
    );

    // SPM (no Podfile — plugins via SPM per app-arch §9). If a Runner
    // Package.resolved is committed, it must carry no analytics framework.
    final resolved = Directory('ios')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('Package.resolved'))
        .toList();
    const bannedFrameworks = <String>[
      'firebase-analytics',
      'crashlytics',
      'firebase-perf',
      'appcenter',
      'sentry-cocoa',
      'mixpanel',
      'amplitude',
      'GoogleAppMeasurement',
    ];
    final offenders = <String>[];
    for (final f in resolved) {
      final src = f.readAsStringSync().toLowerCase();
      for (final needle in bannedFrameworks) {
        if (src.contains(needle.toLowerCase())) {
          offenders.add('${f.path}: $needle');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'iOS SPM Package.resolved carries an analytics framework: '
          '$offenders',
    );
  });
}
