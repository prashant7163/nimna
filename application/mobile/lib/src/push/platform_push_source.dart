/// The platform-specific push seam (spec §3.2.1, §3.2, §5.7) hidden behind
/// ONE interface so [PushService], its tests, and the dependency fence stay
/// SDK-agnostic. iOS = native APNs (no SDK — [ApnsPushSource] over the
/// `app.nimna/push` method channel); Android = FCM ([FcmPushSource], the SOLE
/// `firebase_messaging` import site, the one justified Google SDK).
///
/// Both yield THIS device's own token as a §5.7 [TokenPayload] present-form,
/// or absent when push is unsupported / OS-denied — a raw platform token
/// string NEVER escapes above this layer. The token rides only inside E2E
/// payloads (the pairing handshake M2/M3 and the token-refresh CONTROL);
/// nothing here sends it anywhere.
///
/// Locale-independent: no user-facing strings live in this lane (the sole
/// push string, "New activity", is rendered by the OS from the app bundle's
/// `NEW_ACTIVITY` resource, never by Dart).
library;

import 'dart:async';

import '../protocol/token_payload.dart';

/// One device's push transport. Implementations are injected into
/// [PushService]; host tests pass [InertPushSource] so no SDK/native channel
/// is ever touched under `flutter test`.
abstract interface class PlatformPushSource {
  /// This device's push platform, or null where push is unsupported (host
  /// tests, desktop). Fixes the §5.7 platform byte (0x01 APNs / 0x02 FCM).
  PushPlatform? get platform;

  /// Acquires — registering with the OS push service if needed — THIS
  /// device's current token, wrapped as a §5.7 present-form [TokenPayload].
  /// Returns [TokenPayload.absent] when push is unsupported here or the OS
  /// denied it (the caller then rides pure burner-line mode). Idempotent.
  Future<TokenPayload> acquireOwnToken();

  /// OS-initiated token rotations, already wrapped as present-form payloads.
  /// [PushService] forwards each to any live session as a token-refresh
  /// CONTROL so the peer's stored address stays current.
  Stream<TokenPayload> get onTokenRotated;

  /// Content-free notification taps that brought the app forward. Emits a
  /// bare event — the OS notification body is only "New activity", so there
  /// is nothing to carry (no channel, sender, or content, ever).
  Stream<void> get onNotificationTap;

  /// Tells the OS layer the app's foreground state so a knock that lands
  /// while foregrounded shows NO OS notification (in-app suppression,
  /// §3.2.1). On Android suppression is structural (a foreground FCM message
  /// is never surfaced as a tray notification by this app); the seam exists
  /// for the iOS `UNUserNotificationCenter` willPresent path.
  void setForeground({required bool foreground});

  Future<void> dispose();
}

/// The no-op source: push unsupported. Every method is silent — no platform,
/// an always-absent own token, no rotations, no taps. This is what host tests
/// and any non-iOS/Android target get, so the fence ("push is opt-in, off =
/// zero third-party touch") holds by construction where no push exists.
class InertPushSource implements PlatformPushSource {
  const InertPushSource();

  @override
  PushPlatform? get platform => null;

  @override
  Future<TokenPayload> acquireOwnToken() async => const TokenPayload.absent();

  @override
  Stream<TokenPayload> get onTokenRotated => const Stream.empty();

  @override
  Stream<void> get onNotificationTap => const Stream.empty();

  @override
  void setForeground({required bool foreground}) {}

  @override
  Future<void> dispose() async {}
}
