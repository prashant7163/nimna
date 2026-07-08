import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:nimna/src/push/apns_push_source.dart';

/// ApnsPushSource wraps the native `app.nimna/push` channel: it turns the raw
/// device-token bytes into a §5.7 present-form payload (platform 0x01), maps a
/// null/denied registration to absent (burner mode), and surfaces native
/// rotation/tap callbacks as Dart streams. Native is mocked — no real APNs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.nimna/push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a raw device token becomes a present-form APNs payload', () async {
    final raw = Uint8List.fromList(List<int>.generate(32, (i) => i));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'registerForToken');
      return raw;
    });
    final source = ApnsPushSource();
    addTearDown(source.dispose);

    final token = await source.acquireOwnToken();

    expect(token.isPresent, isTrue);
    expect(token.platform, PushPlatform.apns);
    expect(token.token, raw, reason: 'the RAW 32 bytes travel (relay hexes)');
  });

  test('a null/denied registration ⇒ absent (burner mode)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final source = ApnsPushSource();
    addTearDown(source.dispose);

    expect((await source.acquireOwnToken()).isPresent, isFalse);
  });

  test('a native token rotation surfaces as a present-form payload', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final source = ApnsPushSource();
    addTearDown(source.dispose);

    final seen = <TokenPayload>[];
    source.onTokenRotated.listen(seen.add);

    final rotated = Uint8List.fromList(utf8.encode('rotated'));
    await _invokeFromNative(messenger, channel.name, 'onTokenRotated', rotated);
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(1));
    expect(seen.single.platform, PushPlatform.apns);
    expect(seen.single.token, rotated);
  });

  test('a native tap surfaces as a content-free open event', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final source = ApnsPushSource();
    addTearDown(source.dispose);

    var taps = 0;
    source.onNotificationTap.listen((_) => taps++);

    await _invokeFromNative(messenger, channel.name, 'onNotificationTap', null);
    await Future<void>.delayed(Duration.zero);

    expect(taps, 1);
  });

  test('setForeground reaches native', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final source = ApnsPushSource();
    addTearDown(source.dispose);

    source.setForeground(foreground: false);
    await Future<void>.delayed(Duration.zero);

    final fg = calls.singleWhere((c) => c.method == 'setForeground');
    expect((fg.arguments as Map)['foreground'], isFalse);
  });
}

/// Delivers a native→Dart method call to the channel's Dart handler, carrying
/// [arguments] under [method].
Future<void> _invokeFromNative(
  BinaryMessenger messenger,
  String channelName,
  String method,
  Object? arguments,
) async {
  const codec = StandardMethodCodec();
  final encoded = codec.encodeMethodCall(MethodCall(method, arguments));
  // The sanctioned test path for a native→Dart method call on this channel.
  // ignore: deprecated_member_use
  await messenger.handlePlatformMessage(channelName, encoded, (_) {});
}
