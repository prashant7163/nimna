import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/push/platform_push_source.dart';
import 'package:nimna/src/push/push_service.dart';

import 'fake_push_source.dart';

/// PushService own-token logic — the source-facing half (opt-in gating,
/// caching, rotation), independent of any live session (the wire path is
/// proven end-to-end in push_wire_test.dart). The opt-in lookup is injected
/// so no channel repo is needed here.
void main() {
  TokenPayload apns(String s) => TokenPayload.present(
    platform: PushPlatform.apns,
    token: Uint8List.fromList(utf8.encode(s)),
  );

  // A simple in-memory opt-in lookup; every channel reads [enabled].
  PushOptInLookup lookup(bool enabled) =>
      (_) => enabled;

  test('opted OUT ⇒ absent, and the OS token is never acquired', () async {
    final source = FakePushSource(token: apns('tok'));
    final service = PushService(source: source, isOptedIn: lookup(false));
    addTearDown(service.dispose);

    final token = await service.ownTokenPayload(optedIn: false);

    expect(token.isPresent, isFalse);
    expect(source.acquireCalls, 0, reason: 'off = zero third-party touch');
  });

  test('opted IN ⇒ present token, acquired ONCE then cached', () async {
    final source = FakePushSource(token: apns('tok'));
    final service = PushService(source: source, isOptedIn: lookup(true));
    addTearDown(service.dispose);

    final first = await service.ownTokenPayload(optedIn: true);
    final second = await service.ownTokenPayload(optedIn: true);

    expect(first.isPresent, isTrue);
    expect(first.encode(), apns('tok').encode());
    expect(second.encode(), apns('tok').encode());
    expect(source.acquireCalls, 1, reason: 'the platform round-trip is cached');
  });

  test('an OS rotation replaces the cached own token', () async {
    final source = FakePushSource(token: apns('old'));
    final service = PushService(source: source, isOptedIn: lookup(true))
      ..initialize();
    addTearDown(service.dispose);

    expect(
      (await service.ownTokenPayload(optedIn: true)).encode(),
      apns('old').encode(),
    );

    source.rotate(apns('new'));
    // Let the broadcast rotation land.
    await Future<void>.delayed(Duration.zero);

    expect(
      (await service.ownTokenPayload(optedIn: true)).encode(),
      apns('new').encode(),
    );
  });

  test(
    'opting a line IN eagerly acquires (the honest permission moment)',
    () async {
      final source = FakePushSource(token: apns('tok'));
      final service = PushService(source: source, isOptedIn: lookup(true));
      addTearDown(service.dispose);

      // No bound session — still acquires (this triggers the OS permission
      // prompt at the moment the user opts in).
      await service.onOptInChanged(Uint8List(16), enabled: true);
      expect(source.acquireCalls, 1);

      // Opting OUT is a revoke — it does not acquire a token.
      await service.onOptInChanged(Uint8List(16), enabled: false);
      expect(source.acquireCalls, 1);
    },
  );

  test('InertPushSource never yields a token (pure burner-line)', () async {
    final service = PushService(
      source: const InertPushSource(),
      isOptedIn: lookup(true),
    )..initialize();
    addTearDown(service.dispose);

    expect((await service.ownTokenPayload(optedIn: true)).isPresent, isFalse);
    expect((await service.ownTokenPayload(optedIn: false)).isPresent, isFalse);
  });

  test(
    'notification taps and foreground state pass through the source',
    () async {
      final source = FakePushSource();
      final service = PushService(source: source, isOptedIn: lookup(true));
      addTearDown(service.dispose);

      var taps = 0;
      service.notificationTaps.listen((_) => taps++);
      source.tap();
      await Future<void>.delayed(Duration.zero);
      expect(taps, 1);

      service.setForeground(foreground: false);
      expect(source.lastForeground, isFalse);
    },
  );
}
