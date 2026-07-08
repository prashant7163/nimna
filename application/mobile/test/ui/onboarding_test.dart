import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/ui/screens/onboarding/onboarding_screen.dart';

/// F1 first-run onboarding (USER 2026-07-08): four screens, shown once per
/// install. This exercises the four-screen flow and the CONDITIONAL Android
/// screenshot caveat (F1.4) via the injected probe seam — the load-bearing new
/// behaviour. The first-run GATE (initialRoute) is covered by
/// `test/app/first_run_store_test.dart` (the marker) plus `app.dart`'s ternary;
/// a full NimnaApp mount is avoided here because the route builds
/// `const OnboardingScreen()` whose production caveat probe hits the native
/// screenshot channel (not injectable through the route).
///
/// Uses `pump()`, never `pumpAndSettle()`.
void main() {
  final en = AppLocalizationsEn();

  Widget harness(OnboardingScreen screen) => MaterialApp(
    theme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  );

  Future<void> toLastPage(WidgetTester tester) async {
    // Bare OnboardingScreen has no continuous animation, so pumpAndSettle is
    // safe here (it settles the caveat probe future + each page transition).
    await tester.pumpAndSettle();
    // F1.1 — what it is (voice string 1), and Skip present on the first three.
    expect(find.text(en.onboarding_whatItIsHeadline), findsOneWidget);
    expect(find.text(en.onboarding_skip), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(en.onboarding_next));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('F1.4: the Android caveat renders only when the probe says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(OnboardingScreen(androidCaveatProbe: () async => true)),
    );
    await toLastPage(tester);

    // Last screen: no Skip (consent), Start is the single action.
    expect(find.text(en.onboarding_start), findsOneWidget);
    expect(find.text(en.onboarding_skip), findsNothing);
    expect(
      find.text(en.screenshot_onboardingDisclosure),
      findsOneWidget,
      reason: 'F1.4 always renders the voice-string-11 disclosure',
    );
    expect(
      find.text(en.screenshot_onboardingAndroidCaveat),
      findsOneWidget,
      reason: 'Android 13 and older sees the honest sub-14 caveat',
    );
  });

  testWidgets('F1.4: iPhone / Android 14+ sees the clean copy, no caveat', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(OnboardingScreen(androidCaveatProbe: () async => false)),
    );
    await toLastPage(tester);

    expect(find.text(en.screenshot_onboardingDisclosure), findsOneWidget);
    expect(find.text(en.screenshot_onboardingAndroidCaveat), findsNothing);
  });
}
