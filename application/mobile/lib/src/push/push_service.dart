/// The push orchestrator (spec §3.2.1, §3.2, §5.5, §5.7) — the single seam
/// between the platform push source and the session/opt-in machinery. It
/// owns:
///
///  - **Own-token acquisition** — THIS device's APNs/FCM token as a §5.7
///    present-form [TokenPayload], acquired ONLY for an opted-in line
///    (default off ⇒ absent ⇒ zero third-party touch, string 18).
///  - **Token-refresh wiring** — at a bound session going live, and on OS
///    token rotation, it drives [SessionController.sendTokenRefresh] with the
///    device's own token so the peer's stored address stays current (§5.5
///    control 0x04). Opting a line out sends the absent-form REVOKE.
///  - **Tap routing** — a content-free [notificationTaps] stream the app root
///    listens to (tap → open → reconnect/knock-answer).
///  - **Foreground suppression** — [setForeground] so a knock landing while
///    foregrounded shows no OS banner.
///
/// Pure Dart, Flutter-free, locale-independent. No push SDK is imported here
/// — the SDK lives ONLY in [FcmPushSource] behind [PlatformPushSource].
library;

import 'dart:async';
import 'dart:typed_data';

import '../protocol/token_payload.dart';
import '../session/connection/session_controller.dart';
import '../session/model/chat_event.dart';
import 'platform_push_source.dart';

/// Lazy per-channel opt-in lookup. Injected (not a captured [PushOptIn]) so
/// the orchestrator never holds a stale [ChannelRepository] across a
/// seal/unseal cycle — it resolves the current repo at read time, and reads
/// false while the perimeter is sealed. Locale-independent, pure.
typedef PushOptInLookup = bool Function(Uint8List channelId);

class PushService {
  PushService({
    required PlatformPushSource source,
    required PushOptInLookup isOptedIn,
  }) : _source = source,
       _isOptedIn = isOptedIn;

  // ignore_for_file: prefer_initializing_formals — the public constructor
  // keeps typed, named parameters (source/isOptedIn) for call sites.

  final PlatformPushSource _source;
  final PushOptInLookup _isOptedIn;

  final List<_BoundSession> _bound = [];
  Future<TokenPayload>? _ownToken;
  StreamSubscription<TokenPayload>? _rotationSub;
  TokenPayload? _rotated;
  bool _initialised = false;

  /// Subscribes to OS token rotations so a fresh token is re-announced to
  /// every live opted-in session. Idempotent; safe to skip in tests that do
  /// not exercise rotation.
  void initialize() {
    if (_initialised) {
      return;
    }
    _initialised = true;
    _rotationSub = _source.onTokenRotated.listen((token) {
      // A rotated token replaces the cache and is pushed to live opted-in
      // sessions so the peer never wakes a stale address.
      _rotated = token;
      _ownToken = Future.value(token);
      for (final b in _bound) {
        if (b.live && _isOptedIn(b.channelId) && token.isPresent) {
          b.controller.sendTokenRefresh(token);
        }
      }
    });
  }

  /// This device's own token for a line, honouring its opt-in: present-form
  /// when [optedIn] and the OS yielded a token, else absent (burner mode).
  /// Cached — the platform round-trip runs once per app run (until a
  /// rotation), never per call.
  Future<TokenPayload> ownTokenPayload({required bool optedIn}) async {
    if (!optedIn) {
      return const TokenPayload.absent();
    }
    if (_rotated != null) {
      return _rotated!;
    }
    return _ownToken ??= _source.acquireOwnToken();
  }

  /// Binds a launched [controller] so that, once its line goes live, this
  /// device's own token is announced to the peer (only if the channel is
  /// opted in and a token exists). Also re-announces on OS rotation and
  /// unbinds when the session ends.
  void bindSession(SessionController controller, Uint8List channelId) {
    final bound = _BoundSession(controller, Uint8List.fromList(channelId));
    _bound.add(bound);
    bound.sub = controller.events.listen((event) {
      if (event is LineStateChanged && event.state == SessionLineState.live) {
        bound.live = true;
        unawaited(_announce(bound));
      } else if (event is SessionEnded) {
        _unbind(bound);
      }
    });
    // A controller already live at bind time (rare, but possible) still gets
    // its announce.
    if (controller.isLive) {
      bound.live = true;
      unawaited(_announce(bound));
    }
  }

  /// Reacts to a per-line opt-in toggle. On a LIVE bound session it takes
  /// effect immediately: opting IN announces the own token (present); opting
  /// OUT sends the absent-form REVOKE so the peer deletes our address and can
  /// never wake us again (unilateral, permanent — spec §4). Off the line, the
  /// change simply rides the next session start.
  Future<void> onOptInChanged(
    Uint8List channelId, {
    required bool enabled,
  }) async {
    final live = _bound
        .where((b) => b.live && _sameChannel(b.channelId, channelId))
        .toList();
    if (enabled) {
      // Acquire eagerly: this is the honest moment to trigger the OS
      // notification-permission prompt (string 18 is the always-visible
      // disclosure). Announce to any live session so the peer's stored
      // address updates immediately.
      final token = await ownTokenPayload(optedIn: true);
      if (token.isPresent) {
        for (final b in live) {
          b.controller.sendTokenRefresh(token);
        }
      }
    } else {
      // Opting out is a unilateral, permanent REVOKE (spec §4): tell any live
      // session to send absent so the peer deletes our address.
      for (final b in live) {
        b.controller.sendTokenRefresh(const TokenPayload.absent());
      }
    }
  }

  /// Content-free notification taps (tap → open → reconnect). The app root
  /// listens; the payload is always null (only "New activity" ever ships).
  Stream<void> get notificationTaps => _source.onNotificationTap;

  /// Foreground state → OS suppression seam (no banner while foregrounded).
  void setForeground({required bool foreground}) =>
      _source.setForeground(foreground: foreground);

  Future<void> _announce(_BoundSession bound) async {
    if (!bound.live || !_isOptedIn(bound.channelId)) {
      return;
    }
    final token = await ownTokenPayload(optedIn: true);
    // Only announce a real token; a missing token is NOT a revoke (that would
    // wrongly delete a good address the peer already holds).
    if (token.isPresent && bound.live) {
      bound.controller.sendTokenRefresh(token);
    }
  }

  void _unbind(_BoundSession bound) {
    unawaited(bound.sub?.cancel());
    _bound.remove(bound);
  }

  Future<void> dispose() async {
    await _rotationSub?.cancel();
    for (final b in List<_BoundSession>.from(_bound)) {
      await b.sub?.cancel();
    }
    _bound.clear();
    await _source.dispose();
  }

  static bool _sameChannel(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _BoundSession {
  _BoundSession(this.controller, this.channelId);

  final SessionController controller;
  final Uint8List channelId;
  StreamSubscription<ChatEvent>? sub;
  bool live = false;
}
