import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';

/// The content-free invariant, enforced across the bundle (spec §3.2, §3.2.1):
/// the ONLY push body that ships is the two words "New activity" — no channel,
/// sender, count, or content, ever. The relay carries just the loc-key
/// NEW_ACTIVITY; every place that resolves it (Dart ARB + iOS
/// Localizable.strings + Android string resources) must render exactly the
/// canonical body, and nothing near it may leak identity.
void main() {
  const canonical = 'New activity';
  const locales = ['en', 'de', 'fr', 'es', 'it'];

  // The crafted content-free body per launch locale (S16 filled DE/FR/ES/IT).
  // Each is the two-word "New activity" equivalent, verified against the ARBs.
  const bodies = {
    'en': 'New activity',
    'de': 'Neue Aktivität',
    'fr': 'Nouvelle activité',
    'es': 'Actividad nueva',
    'it': 'Nuova attività',
  };

  test('the Dart ARB body is the canonical two words (EN)', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(l10n.push_newActivityBody, canonical);
  });

  test(
    'every launch locale renders ITS OWN content-free body — no EN fallback',
    () async {
      for (final code in locales) {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        final body = l10n.push_newActivityBody;

        // The delegate resolves to THIS locale's crafted body — the loc-key
        // NEW_ACTIVITY renders the translated two words, not the EN template.
        expect(
          body,
          bodies[code],
          reason: '$code push body must render its own crafted two words',
        );
        // Non-EN proves the translation is actually wired (not a fallthrough).
        if (code != 'en') {
          expect(
            body,
            isNot(canonical),
            reason: '$code must render its translation, not the EN fallback',
          );
        }

        // The content-free invariant survives translation: the body stays a
        // short fixed label with no channel, sender, count, or message — so
        // nothing about the line can leak in any locale.
        expect(body.trim(), isNotEmpty);
        expect(
          body.contains(RegExp(r'\d')),
          isFalse,
          reason: '$code body must carry no count/identity digit',
        );
        expect(
          body.trim().split(RegExp(r'\s+')).length,
          lessThanOrEqualTo(2),
          reason: '$code body must stay the two-word content-free label',
        );
      }
    },
  );

  test('iOS Localizable.strings define NEW_ACTIVITY as the two words', () {
    for (final code in locales) {
      final file = File('ios/Runner/$code.lproj/Localizable.strings');
      expect(file.existsSync(), isTrue, reason: 'missing $code Localizable');
      final src = file.readAsStringSync();
      expect(
        RegExp('"NEW_ACTIVITY"\\s*=\\s*"$canonical";').hasMatch(src),
        isTrue,
        reason: '$code NEW_ACTIVITY must be exactly "$canonical"',
      );
    }
  });

  test('Android string resources define NEW_ACTIVITY as the two words', () {
    for (final code in locales) {
      final dir = code == 'en' ? 'values' : 'values-$code';
      final file = File('android/app/src/main/res/$dir/strings.xml');
      expect(file.existsSync(), isTrue, reason: 'missing $dir/strings.xml');
      final src = file.readAsStringSync();
      expect(
        RegExp('<string name="NEW_ACTIVITY">$canonical</string>').hasMatch(src),
        isTrue,
        reason: '$dir NEW_ACTIVITY must be exactly "$canonical"',
      );
    }
  });

  test(
    'NEW_ACTIVITY is the ONLY loc-key the relay ships (no identity keys)',
    () {
      // The relay push bodies are byte-identical constants; extract EVERY
      // loc-key / title_loc_key value and assert the set is exactly
      // {NEW_ACTIVITY} — no channel/sender/name key can ride beside it.
      final push = File('../relay/internal/push/push.go').readAsStringSync();
      // APNs uses "loc-key" (hyphen); FCM uses "title_loc_key" (underscore).
      final keys = RegExp(
        r'(?:title_loc_key|loc-key)"\s*:\s*"([^"]+)"',
      ).allMatches(push).map((m) => m.group(1)).toSet();
      expect(keys, {
        'NEW_ACTIVITY',
      }, reason: 'the only push loc-key is the content-free NEW_ACTIVITY');
    },
  );

  test('the iOS strings carry no per-line/sender key beside NEW_ACTIVITY', () {
    for (final code in locales) {
      final src = File(
        'ios/Runner/$code.lproj/Localizable.strings',
      ).readAsStringSync();
      // Exactly one localization key line (NEW_ACTIVITY); no CHANNEL/FROM/etc.
      final keys = RegExp(
        r'^\s*"([A-Z_]+)"\s*=',
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)).toList();
      expect(keys, ['NEW_ACTIVITY'], reason: '$code must define only the body');
    }
  });
}
