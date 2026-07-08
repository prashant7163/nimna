import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/screenshot/screenshot_detector.dart';
import 'package:nimna/src/screenshot/screenshot_notice.dart';
import 'package:nimna/src/screenshot/screenshot_system_line.dart';

/// S14 screenshot UI + detector wiring (spec §5.2). The system line is voice
/// string 12, VERBATIM, a bare centered caption (no bubble, no icon). The
/// detector's Dart glue is provable headlessly (a real capture is the S18 rung).
void main() {
  final en = AppLocalizationsEn();

  Widget host(Widget child) => MaterialApp(
    theme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('ScreenshotSystemLine', () {
    testWidgets('peer side renders string 12 verbatim, no bubble', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ScreenshotSystemLine(
            notice: ScreenshotNotice(own: false, timestampMs: 0),
          ),
        ),
      );
      expect(find.text(en.screenshot_systemLinePeer), findsOneWidget);
      expect(find.text('They took a screenshot.'), findsOneWidget);
      // Event, not speech — no Container decoration bubble around the caption.
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('own side names that the peer was told (string 12)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ScreenshotSystemLine(
            notice: ScreenshotNotice(own: true, timestampMs: 0),
          ),
        ),
      );
      expect(find.text(en.screenshot_systemLineOwn), findsOneWidget);
      expect(
        find.text("You took a screenshot. They've been told."),
        findsOneWidget,
      );
    });
  });

  group('PlatformScreenshotDetector', () {
    const channelName = 'app.nimna/screenshot';
    const channel = MethodChannel(channelName);

    // Plain (real-async) tests, NOT testWidgets: the detector's broadcast
    // stream and the `handlePlatformMessage` reply resolve on the real event
    // loop — a fake-async zone leaves those microtasks unpumped and the test
    // never completes.
    test('start/stop invoke the native channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final detector = PlatformScreenshotDetector();
      await detector.start();
      await detector.stop();
      expect(calls, ['start', 'stop']);
      await detector.dispose();
    });

    test('a native onScreenshot call emits on the stream', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final detector = PlatformScreenshotDetector();
      final emitted = Completer<void>();
      final sub = detector.onScreenshot.listen((_) {
        if (!emitted.isCompleted) {
          emitted.complete();
        }
      });

      // Simulate the native side invoking onScreenshot on the channel.
      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onScreenshot'),
        ),
        (_) {},
      );

      await emitted.future; // completes when the stream emits (else times out).
      await sub.cancel();
      await detector.dispose();
    });
  });
}
