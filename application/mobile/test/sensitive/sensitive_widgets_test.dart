import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/media/ui/attach_sheet.dart';
import 'package:nimna/src/sensitive/sensitive_content_analyzer.dart';
import 'package:nimna/src/sensitive/sensitive_image_veil.dart';
import 'package:nimna/src/sensitive/sensitive_whisper_card.dart';

/// S14 sensitive-content UI + analyzer (spec §5.3, iOS-only). Recipient blur is
/// voice string 15; the sender whisper is voice string 14 — VERBATIM. Fail-open
/// by contract; a real analysis is the S18 device rung, so every test here
/// injects a fake analyzer.
void main() {
  final en = AppLocalizationsEn();

  Widget host(Widget child) => MaterialApp(
    theme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Uint8List tinyJpeg() {
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(120, 120, 120));
    return Uint8List.fromList(img.encodeJpg(image));
  }

  group('SensitiveImageVeil', () {
    testWidgets('flagged image blurs + shows string 15, tap reveals', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SensitiveImageVeil(
            imageBytes: Uint8List(0),
            analyzer: _FakeAnalyzer(true),
            child: const SizedBox(
              key: ValueKey('img'),
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Blurred, with the string 15 caption over it.
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.text(en.sensitive_veilCaption), findsOneWidget);
      expect(find.text('Sensitive content — tap to view.'), findsOneWidget);

      // Tap reveals in place — the veil + caption go, the child stays.
      await tester.tap(find.byType(SensitiveImageVeil));
      await tester.pumpAndSettle();
      expect(find.text(en.sensitive_veilCaption), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byKey(const ValueKey('img')), findsOneWidget);
    });

    testWidgets('a clear image is never blurred (fail-open)', (tester) async {
      await tester.pumpWidget(
        host(
          SensitiveImageVeil(
            imageBytes: Uint8List(0),
            analyzer: _FakeAnalyzer(false),
            child: const SizedBox(
              key: ValueKey('img'),
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text(en.sensitive_veilCaption), findsNothing);
      expect(find.byKey(const ValueKey('img')), findsOneWidget);
    });
  });

  group('SensitiveWhisperCard', () {
    testWidgets('renders string 14 verbatim with both actions', (tester) async {
      await tester.pumpWidget(
        host(SensitiveWhisperCard(onSendAnyway: () {}, onGoBack: () {})),
      );
      expect(find.text(en.sensitive_whisperQuestion), findsOneWidget);
      expect(
        find.text('This looks like sensitive content — send anyway?'),
        findsOneWidget,
      );
      expect(find.text(en.sensitive_whisperSendAnyway), findsOneWidget);
      expect(find.text(en.sensitive_whisperGoBack), findsOneWidget);
    });

    testWidgets('actions fire their callbacks', (tester) async {
      var sent = false;
      var back = false;
      await tester.pumpWidget(
        host(
          SensitiveWhisperCard(
            onSendAnyway: () => sent = true,
            onGoBack: () => back = true,
          ),
        ),
      );
      await tester.tap(find.text(en.sensitive_whisperSendAnyway));
      expect(sent, isTrue);
      await tester.tap(find.text(en.sensitive_whisperGoBack));
      expect(back, isTrue);
    });
  });

  group('AttachImagePreview whisper wiring', () {
    testWidgets('a flagged attachment raises the whisper (string 14)', (
      tester,
    ) async {
      final jpeg = tinyJpeg();
      await tester.runAsync(() async {
        // The real widget lives in a scroll-controlled bottom sheet; host it in
        // a scroll view so the natural-height preview never overflows the test
        // viewport (a layout-only concern, not the whisper logic).
        await tester.pumpWidget(
          host(
            SingleChildScrollView(
              child: AttachImagePreview(
                rawBytes: jpeg,
                analyzer: _FakeAnalyzer(true),
              ),
            ),
          ),
        );
        // Wait out the processing isolate + the analysis, then the whisper.
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (find.text(en.sensitive_whisperQuestion).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      expect(find.text(en.sensitive_whisperQuestion), findsOneWidget);
    });
  });

  group('analyzers', () {
    test('NoOp is always false', () async {
      expect(
        await const NoOpSensitiveContentAnalyzer().isSensitive(Uint8List(0)),
        isFalse,
      );
    });

    test('platform analyzer never touches the channel off iOS', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.nimna/sensitive');
      var touched = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            touched = true;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final analyzer = PlatformSensitiveContentAnalyzer(isIOS: false);
      expect(await analyzer.isSensitive(Uint8List(0)), isFalse);
      expect(touched, isFalse, reason: 'iOS-only: Android never analyses');
    });

    test('platform analyzer relays the iOS flag; errors fail open', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.nimna/sensitive');
      var flag = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (flag) {
              return true;
            }
            throw PlatformException(code: 'analysis_disabled');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final analyzer = PlatformSensitiveContentAnalyzer(isIOS: true);
      expect(await analyzer.isSensitive(Uint8List(0)), isTrue);
      flag = false; // native throws → fail open to false (§5.3 display sugar).
      expect(await analyzer.isSensitive(Uint8List(0)), isFalse);
    });
  });
}

class _FakeAnalyzer implements SensitiveContentAnalyzer {
  _FakeAnalyzer(this.flag);

  final bool flag;

  @override
  Future<bool> isSensitive(Uint8List imageBytes) async => flag;
}
