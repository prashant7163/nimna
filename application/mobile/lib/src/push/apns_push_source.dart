/// iOS own-token acquisition over NATIVE APNs — no third-party SDK (USER
/// decision 1, SESSION-15). All Apple: `UNUserNotificationCenter` +
/// `registerForRemoteNotifications` in `AppDelegate.swift`, bridged here
/// through the `app.nimna/push` method channel (the same hand-written
/// platform-glue pattern as `app.nimna/storage`).
///
/// The raw 32-byte APNs device token comes up from native as bytes and is
/// wrapped as a §5.7 present-form [TokenPayload] with platform byte 0x01. The
/// relay hex-encodes those bytes into the `/3/device/<hex>` path (relay
/// `apns.go`), so the RAW binary token is exactly what must travel — never a
/// hex string.
///
/// Locale-independent; no user-facing strings.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../protocol/token_payload.dart';
import 'platform_push_source.dart';

class ApnsPushSource implements PlatformPushSource {
  ApnsPushSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// The hand-written iOS glue channel (mirrors `app.nimna/storage`).
  static const String channelName = 'app.nimna/push';

  final MethodChannel _channel;
  final StreamController<TokenPayload> _rotations =
      StreamController<TokenPayload>.broadcast();
  final StreamController<void> _taps = StreamController<void>.broadcast();

  @override
  PushPlatform get platform => PushPlatform.apns;

  @override
  Future<TokenPayload> acquireOwnToken() async {
    // Native registers with APNs and returns the raw device-token bytes, or
    // null if the OS denied notifications / registration failed — either way
    // the line rides burner mode (absent), never a fabricated token.
    final Uint8List? raw = await _channel.invokeMethod<Uint8List>(
      'registerForToken',
    );
    if (raw == null || raw.isEmpty) {
      return const TokenPayload.absent();
    }
    return TokenPayload.present(platform: PushPlatform.apns, token: raw);
  }

  @override
  Stream<TokenPayload> get onTokenRotated => _rotations.stream;

  @override
  Stream<void> get onNotificationTap => _taps.stream;

  @override
  void setForeground({required bool foreground}) {
    // Fire-and-forget: native uses this to decide whether willPresent shows
    // the OS banner. A dropped call only means a foreground banner may flash
    // — never a privacy leak (the body is always the content-free string).
    unawaited(
      _channel
          .invokeMethod<void>('setForeground', {'foreground': foreground})
          .catchError((_) {}),
    );
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTokenRotated':
        final raw = call.arguments as Uint8List?;
        if (raw != null && raw.isNotEmpty) {
          _rotations.add(
            TokenPayload.present(platform: PushPlatform.apns, token: raw),
          );
        }
      case 'onNotificationTap':
        // Content-free by construction — no arguments are read.
        _taps.add(null);
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _rotations.close();
    await _taps.close();
  }
}
