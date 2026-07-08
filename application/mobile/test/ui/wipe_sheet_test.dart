import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/ui/theme/nimna_tokens.dart';
import 'package:nimna/src/ui/widgets/destructive_hold_button.dart';
import 'package:nimna/src/ui/widgets/wipe_sheet.dart';

/// Hold semantics (intake §7): release at 99% ⇒ no service call and the
/// track resets; completion ⇒ exactly one call; durations pinned to the
/// USER decision (1.5 s channel / 2.5 s full); strings render from the ARB
/// in all five locales.
void main() {
  final en = AppLocalizationsEn();

  Widget host({
    required bool full,
    required Future<void> Function() onWipe,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      theme: nimnaTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WipeSheetBody(full: full, onWipe: onWipe),
      ),
    );
  }

  testWidgets('release at 99% cancels — no call, ever partially', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        full: false,
        onWipe: () async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(DestructiveHoldButton);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(); // ticker start reference
    // 99% of the 1.5 s channel hold.
    await tester.pump(const Duration(milliseconds: 1485));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, 0);
    // Track reset: the controller snapped back to zero (button still
    // armed — holding again from zero works).
    final gesture2 = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await gesture2.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('completion fires exactly one call and closes the sheet', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        full: false,
        onWipe: () async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(DestructiveHoldButton);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(); // ticker start reference
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, 1);
    // The wipe was awaited, then the sheet dismissed itself.
    expect(find.byType(WipeSheetBody), findsNothing);
  });

  testWidgets('the hold button is dead after firing — never a second call', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: nimnaTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: DestructiveHoldButton(
              label: 'hold',
              holdDuration: const Duration(milliseconds: 1500),
              onComplete: () => calls++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(DestructiveHoldButton);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);

    final gesture2 = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture2.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('durations are pinned to the USER decision: 1.5 s channel, '
      '2.5 s full', (tester) async {
    // The token values themselves are drift-guarded against tokens.json;
    // here we pin that the sheets pass exactly those tokens.
    expect(NimnaLine.holdToWipeChannelMs, 1500);
    expect(NimnaLine.holdToWipeFullMs, 2500);

    await tester.pumpWidget(host(full: false, onWipe: () async {}));
    await tester.pumpAndSettle();
    var button = tester.widget<DestructiveHoldButton>(
      find.byType(DestructiveHoldButton),
    );
    expect(button.holdDuration, const Duration(milliseconds: 1500));

    await tester.pumpWidget(host(full: true, onWipe: () async {}));
    await tester.pumpAndSettle();
    button = tester.widget<DestructiveHoldButton>(
      find.byType(DestructiveHoldButton),
    );
    expect(button.holdDuration, const Duration(milliseconds: 2500));
  });

  for (final locale in const [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
  ]) {
    testWidgets('full-wipe sheet strings render from the ARB in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(full: true, onWipe: () async {}, locale: locale),
      );
      await tester.pumpAndSettle();

      // String 8 verbatim in THIS locale's crafted copy (S16 filled
      // DE/FR/ES/IT — the sheet renders its own translation, not EN).
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.wipe_fullBody), findsOneWidget);
      expect(find.text(l10n.wipe_holdToWipe), findsOneWidget);
      expect(find.text(l10n.wipe_fullHoldCaption), findsOneWidget);
      expect(find.text(l10n.wipe_actionKeep), findsOneWidget);
      // The emphasized title renders as a rich text containing string 8's
      // first line, in this locale's copy.
      expect(
        find.textContaining(l10n.wipe_fullTitleEmphasis, findRichText: true),
        findsWidgets,
      );
    });
  }

  testWidgets('channel sheet carries the F7.2 strings verbatim', (
    tester,
  ) async {
    await tester.pumpWidget(host(full: false, onWipe: () async {}));
    await tester.pumpAndSettle();

    expect(find.text(en.wipe_channelTitle), findsOneWidget);
    expect(find.text(en.wipe_channelBody), findsOneWidget);
    expect(find.text(en.wipe_channelPeerNote), findsOneWidget);
    expect(find.text(en.wipe_channelHoldCaption), findsOneWidget);
    expect(find.text(en.wipe_actionKeep), findsOneWidget);
  });
}
