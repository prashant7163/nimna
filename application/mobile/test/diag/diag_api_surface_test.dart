import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan enforcement of the diag package's structural no-content
/// discipline (app-architecture.md §6): the PUBLIC API of lib/src/diag/
/// must accept no String, Object, or dynamic parameter anywhere — free
/// text must be unrepresentable, not merely discouraged.
void main() {
  test('no public method/function in src/diag takes text-capable params', () {
    final dir = Directory('lib/src/diag');
    expect(dir.existsSync(), isTrue);

    final violations = <String>[];
    // Matches declarations of public functions/methods/constructors and
    // captures their parameter list. Declaration terminators after the
    // closing paren (review S4): `=>` (expression body), `{` (block body,
    // same line or not), `;` (const enum ctors), with an optional
    // constructor initializer list in between — so inline and
    // expression-bodied methods cannot slip past the scan.
    final decl = RegExp(
      r'^\s*(?:static\s+)?(?:const\s+)?(?:[A-Za-z_<>?,\s]+\s)?'
      r'([A-Za-z][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*'
      r'(?::[^{;]*)?(?:async\s*)?(?:=>|\{|;)',
      multiLine: true,
    );
    final banned = RegExp(r'\b(String|Object|dynamic)\b');

    for (final entity in dir.listSync().whereType<File>()) {
      if (!entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      // Strip comments so doc text cannot trip or mask the scan.
      final code = source
          .replaceAll(RegExp(r'///.*'), '')
          .replaceAll(RegExp(r'//.*'), '');

      for (final match in decl.allMatches(code)) {
        final name = match.group(1)!;
        final params = match.group(2)!;
        if (name.startsWith('_')) {
          continue; // private — not API surface
        }
        // Skip control-flow keywords the regex may catch.
        if (const {
          'if',
          'for',
          'while',
          'switch',
          'catch',
          'return',
          'assert',
          'super',
        }.contains(name)) {
          continue;
        }
        if (banned.hasMatch(params)) {
          violations.add('${entity.path}: $name($params)');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Public diag API must be enums+ints only. '
          'Offending declarations:\n${violations.join('\n')}',
    );
  });

  test('the log entrypoint signature is enums and ints only', () {
    final source = File('lib/src/diag/diag.dart').readAsStringSync();
    // The whole public logging surface, verbatim.
    expect(
      source,
      contains(
        'void log(\n'
        '    DiagEvent event, {\n'
        '    DiagCode code = DiagCode.none,\n'
        '    List<int> args = const [],\n'
        '  })',
      ),
      reason: 'Diag.log signature drifted — this is a review event',
    );
  });
}
