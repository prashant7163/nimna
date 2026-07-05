import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Safety-net grep (app-architecture.md §8.6; reviewer remains the
/// authority): no string literal may appear inside a Text-class constructor
/// anywhere under lib/ — every user-facing string comes from the ARB/l10n
/// layer from the first widget.
///
/// The scan runs against WHOLE-FILE contents (review S3): `\s*` crosses
/// newlines, so multi-line `Text(\n  '…'` constructors are caught; the
/// reported line number derives from the match offset.
void main() {
  test('no string literals inside Text(...) constructors under lib/', () {
    final violations = <String>[];
    final pattern = RegExp(
      '(Text|SelectableText|RichText|TextSpan)\\(\\s*[\'"]',
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      // Generated l10n lookup classes legitimately contain the ARB strings.
      if (entity.path.contains('lib/l10n/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      // Strip line comments; newlines survive, so line numbers hold.
      final code = source.replaceAll(RegExp(r'//[^\n]*'), '');

      for (final match in pattern.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        violations.add(
          '${entity.path}:$line: '
          '${match.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Hardcoded user-facing strings found — route them through the '
          'ARB/l10n layer:\n${violations.join('\n')}',
    );
  });
}
