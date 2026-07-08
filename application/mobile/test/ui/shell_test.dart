import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/lock_gate.dart';
import 'package:nimna/src/ui/screens/channel_list_screen.dart';
import 'package:nimna/src/ui/theme/nimna_tokens.dart';

import '../helpers/test_env.dart';

/// Widget-layer done-check slices: boots to the shell in all five locales
/// (canonical string 4 from the ARB; DE/FR/ES/IT fall back to EN pre-S16),
/// both themes expose NimnaTokens, and LockGate swaps the whole subtree
/// while sealed (zero-leak).
void main() {
  final en = AppLocalizationsEn();
  late TestDevice device;
  late NimnaServices services;

  setUp(() async {
    device = TestDevice.create();
    services = await device.boot();
  });

  tearDown(() async {
    await device.dispose();
  });

  for (final locale in const [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
  ]) {
    testWidgets('boots to the empty channel list in $locale', (tester) async {
      await tester.pumpWidget(NimnaApp(services: services, locale: locale));
      await tester.pumpAndSettle();

      // String 4 verbatim from the ARB, in THIS locale's crafted copy
      // (S16 filled DE/FR/ES/IT — the shell renders its own translation,
      // not the EN template).
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.channelListEmptyHeadline), findsOneWidget);
      expect(find.text(l10n.channelListEmptyBody), findsOneWidget);
      expect(find.text(l10n.appTitle), findsOneWidget);

      // "Create a code" is live (the G2 single entry point, S8); "Enter a
      // code" is now live too (the S9 joiner flow, never paywalled).
      final create = tester.widget<FilledButton>(find.byType(FilledButton));
      final enter = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(create.onPressed, isNotNull);
      expect(enter.onPressed, isNotNull);
      expect(find.text(l10n.actionCreateCode), findsOneWidget);
      expect(find.text(l10n.actionEnterCode), findsOneWidget);
    });
  }

  testWidgets('dark theme exposes the dark token set', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ChannelListScreen));
    final tokens = Theme.of(context).extension<NimnaTokens>();
    expect(tokens, NimnaTokens.dark);
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      NimnaTokens.dark.surface0,
    );
  });

  testWidgets('light theme exposes the light token set', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ChannelListScreen));
    expect(Theme.of(context).extension<NimnaTokens>(), NimnaTokens.light);
  });

  testWidgets('LockGate replaces the whole subtree while sealed', (
    tester,
  ) async {
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelListScreen), findsOneWidget);

    services.keyService.seal();
    await tester.pumpAndSettle();

    // Zero-leak: no channel-list widget, no navigator content, no copy.
    expect(find.byType(ChannelListScreen), findsNothing);
    expect(find.byType(Navigator), findsNothing);
    expect(find.text(en.channelListEmptyHeadline), findsNothing);
    expect(find.byType(LockGate), findsOneWidget);

    // Reopen: the shell returns.
    await tester.runAsync(() => services.keyService.open());
    await tester.pumpAndSettle();
    expect(find.byType(ChannelListScreen), findsOneWidget);
  });
}
