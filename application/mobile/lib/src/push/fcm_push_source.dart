/// Android own-token acquisition via FCM — THE one Google SDK (USER decision
/// 1, SESSION-15), justified because Android push is impossible without Google
/// FCM. This is the SOLE `firebase_messaging` / `firebase_core` import site in
/// the entire app; `push_dependency_fence_test` asserts nothing else under
/// `lib/` imports them.
///
/// Privacy posture (spec §3.2.1, voice string 18):
///  - Firebase is initialised LAZILY — only inside [acquireOwnToken], which
///    [PushService] calls ONLY for a channel the user opted into. Until a
///    line opts in, `Firebase.initializeApp()` is never called and NOTHING
///    about the device touches Google (string 18, "Off").
///  - Auto-init is force-disabled so firebase_messaging never generates a
///    token or phones home on app start on its own.
///  - The relay sends a `notification`-type FCM message, so a backgrounded
///    device shows the OS tray banner (localised from the app's NEW_ACTIVITY
///    string resource) with no Dart running; a foreground message is dropped
///    (in-app suppression, §3.2.1). No background isolate handler exists.
///
/// The FCM registration token is a string; the relay sends it verbatim as
/// `message.token` (relay `fcm.go`), so it travels as its UTF-8 bytes inside
/// the §5.7 present-form [TokenPayload] with platform byte 0x02.
///
/// Locale-independent; no user-facing strings.
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../protocol/token_payload.dart';
import 'platform_push_source.dart';

class FcmPushSource implements PlatformPushSource {
  FcmPushSource();

  bool _initialised = false;
  final StreamController<TokenPayload> _rotations =
      StreamController<TokenPayload>.broadcast();
  final StreamController<void> _taps = StreamController<void>.broadcast();
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  @override
  PushPlatform get platform => PushPlatform.fcm;

  @override
  Future<TokenPayload> acquireOwnToken() async {
    try {
      await _ensureInitialised();
      final messaging = FirebaseMessaging.instance;
      // Android 13+ POST_NOTIFICATIONS runtime grant; older APIs return
      // authorized without a prompt. A denial → burner mode (absent).
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return const TokenPayload.absent();
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        return const TokenPayload.absent();
      }
      return TokenPayload.present(
        platform: PushPlatform.fcm,
        token: utf8.encode(token),
      );
    } on Object {
      // No Firebase project / google-services.json wired yet (the live-push
      // hand-step is deferred to PUBLISH_READY, USER decision 2) — or any
      // transient FCM failure. Degrade silently to burner mode; a push that
      // silently fails IS spec §3.2.1's contract.
      return const TokenPayload.absent();
    }
  }

  Future<void> _ensureInitialised() async {
    if (_initialised) {
      return;
    }
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    // Belt-and-suspenders: never let firebase_messaging auto-generate a
    // token or collect on its own — token flow is user-driven only.
    await messaging.setAutoInitEnabled(false);
    _refreshSub = messaging.onTokenRefresh.listen((token) {
      if (token.isNotEmpty) {
        _rotations.add(
          TokenPayload.present(
            platform: PushPlatform.fcm,
            token: utf8.encode(token),
          ),
        );
      }
    });
    // Background/terminated taps → content-free open events. The RemoteMessage
    // body is never read (it carries only the loc-key).
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => _taps.add(null),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _taps.add(null);
    }
    _initialised = true;
  }

  @override
  Stream<TokenPayload> get onTokenRotated => _rotations.stream;

  @override
  Stream<void> get onNotificationTap => _taps.stream;

  @override
  void setForeground({required bool foreground}) {
    // No-op on Android: suppression is structural. A foreground FCM message
    // fires onMessage — which this app never listens to display — so no OS
    // banner appears while foregrounded; a backgrounded message is shown by
    // the OS tray with no app involvement.
  }

  @override
  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    await _rotations.close();
    await _taps.close();
  }
}
