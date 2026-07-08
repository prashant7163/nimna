import 'dart:async';

import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/push/platform_push_source.dart';

/// Scriptable [PlatformPushSource] for push unit tests — never touches a
/// native channel or SDK. [token] is what `acquireOwnToken` yields;
/// [acquireCalls] proves the caching contract; [rotate]/[tap] drive the OS
/// event streams; [lastForeground] records the suppression seam.
class FakePushSource implements PlatformPushSource {
  FakePushSource({this.platform = PushPlatform.fcm, TokenPayload? token})
    : _token = token ?? const TokenPayload.absent();

  @override
  PushPlatform? platform;

  TokenPayload _token;
  int acquireCalls = 0;
  bool? lastForeground;

  final StreamController<TokenPayload> _rotations =
      StreamController<TokenPayload>.broadcast();
  final StreamController<void> _taps = StreamController<void>.broadcast();

  void setToken(TokenPayload token) => _token = token;

  void rotate(TokenPayload token) => _rotations.add(token);

  void tap() => _taps.add(null);

  @override
  Future<TokenPayload> acquireOwnToken() async {
    acquireCalls++;
    return _token;
  }

  @override
  Stream<TokenPayload> get onTokenRotated => _rotations.stream;

  @override
  Stream<void> get onNotificationTap => _taps.stream;

  @override
  void setForeground({required bool foreground}) => lastForeground = foreground;

  @override
  Future<void> dispose() async {
    await _rotations.close();
    await _taps.close();
  }
}
