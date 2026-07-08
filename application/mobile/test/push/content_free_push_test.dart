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

  test('the Dart ARB body is the canonical two words (EN)', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(l10n.push_newActivityBody, canonical);
  });

  test(
    'every launch locale renders the body (non-EN fall back to EN)',
    () async {
      for (final code in locales) {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        expect(
          l10n.push_newActivityBody,
          canonical,
          reason: '$code push body must render the content-free two words',
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
