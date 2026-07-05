import 'dart:convert';
import 'dart:io';

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/ui/theme/nimna_tokens.dart';

/// The drift guard (app-architecture.md §8.4): reads the design system's
/// tokens.json (monorepo-relative — the app tree is closed-source and never
/// split) and asserts every constant in nimna_tokens.dart matches. Tokens
/// cannot silently diverge from design.
void main() {
  late Map<String, dynamic> tokens;

  setUpAll(() {
    final file = File('../../designs/system/tokens.json');
    expect(file.existsSync(), isTrue, reason: 'tokens.json must exist');
    tokens = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    expect((tokens[r'$meta'] as Map<String, dynamic>)['version'], '1.1.0');
  });

  /// tokens.json colors are #RRGGBB or #RRGGBBAA.
  Color parseColor(String hex) {
    final h = hex.substring(1);
    final rgb = int.parse(h.substring(0, 6), radix: 16);
    final alpha = h.length == 8 ? int.parse(h.substring(6), radix: 16) : 0xFF;
    return Color((alpha << 24) | rgb);
  }

  void expectColorsMatch(String themeName, NimnaTokens theme) {
    final colors =
        (tokens['color'] as Map<String, dynamic>)[themeName]
            as Map<String, dynamic>;
    final dartColors = theme.toColorMap();
    expect(
      dartColors.keys.toSet(),
      colors.keys.toSet(),
      reason: '$themeName color keys must match tokens.json exactly',
    );
    for (final entry in colors.entries) {
      expect(
        dartColors[entry.key]!.toARGB32(),
        parseColor(entry.value as String).toARGB32(),
        reason: '$themeName.${entry.key} drifted from tokens.json',
      );
    }
  }

  test('dark colors match tokens.json', () {
    expectColorsMatch('dark', NimnaTokens.dark);
  });

  test('light colors match tokens.json', () {
    expectColorsMatch('light', NimnaTokens.light);
  });

  test('typography matches tokens.json', () {
    final typography = tokens['typography'] as Map<String, dynamic>;
    expect(NimnaText.fontFamily, typography['fontFamily']);
    expect(NimnaText.fontFamilyMono, typography['fontFamilyMono']);

    final styles = typography['styles'] as Map<String, dynamic>;
    expect(NimnaText.styles.keys.toSet(), styles.keys.toSet());
    for (final entry in styles.entries) {
      final spec = entry.value as Map<String, dynamic>;
      final style = NimnaText.styles[entry.key]!;
      expect(
        style.fontSize,
        (spec['size'] as num).toDouble(),
        reason: '${entry.key}.size',
      );
      expect(
        style.height! * style.fontSize!,
        closeTo((spec['lineHeight'] as num).toDouble(), 0.001),
        reason: '${entry.key}.lineHeight',
      );
      expect(
        style.letterSpacing,
        (spec['letterSpacing'] as num).toDouble(),
        reason: '${entry.key}.letterSpacing',
      );
      final weight = spec['weight'] as int;
      expect(
        style.fontWeight,
        FontWeight.values[(weight ~/ 100) - 1],
        reason: '${entry.key}.weight',
      );
      expect(
        style.fontVariations,
        contains(FontVariation('wght', weight.toDouble())),
        reason: '${entry.key} variable-font wght axis',
      );
      final mono = spec['mono'] == true;
      expect(
        style.fontFamily,
        mono ? NimnaText.fontFamilyMono : NimnaText.fontFamily,
        reason: '${entry.key}.mono',
      );
    }
  });

  test('spacing matches tokens.json', () {
    final spacing = tokens['spacing'] as Map<String, dynamic>;
    expect(NimnaSpacing.base, (spacing['base'] as num).toDouble());
    expect(
      NimnaSpacing.scale,
      (spacing['scale'] as List).map((v) => (v as num).toDouble()).toList(),
    );
    expect(
      NimnaSpacing.screenMargin,
      (spacing['screenMargin'] as num).toDouble(),
    );
    expect(
      NimnaSpacing.listRowChannel,
      (spacing['listRowChannel'] as num).toDouble(),
    );
    expect(
      NimnaSpacing.listRowSettings,
      (spacing['listRowSettings'] as num).toDouble(),
    );
    expect(
      NimnaSpacing.touchTargetMin,
      (spacing['touchTargetMin'] as num).toDouble(),
    );
  });

  test('radius matches tokens.json', () {
    final radius = tokens['radius'] as Map<String, dynamic>;
    expect(NimnaRadius.small, (radius['small'] as num).toDouble());
    expect(NimnaRadius.medium, (radius['medium'] as num).toDouble());
    expect(NimnaRadius.large, (radius['large'] as num).toDouble());
    expect(NimnaRadius.sheet, (radius['sheet'] as num).toDouble());
    expect(NimnaRadius.full, (radius['full'] as num).toDouble());
    expect(NimnaRadius.bubbleTail, (radius['bubbleTail'] as num).toDouble());
  });

  test('motion matches tokens.json (and springs stay forbidden)', () {
    final motion = tokens['motion'] as Map<String, dynamic>;
    expect(NimnaMotion.micro.inMilliseconds, motion['durMicroMs']);
    expect(NimnaMotion.standard.inMilliseconds, motion['durStandardMs']);
    expect(NimnaMotion.enter.inMilliseconds, motion['durEnterMs']);
    expect(NimnaMotion.breath.inMilliseconds, motion['durBreathMs']);
    expect(NimnaMotion.wipeCut.inMilliseconds, motion['durWipeCutMs']);

    List<double> cubic(Cubic c) => [c.a, c.b, c.c, c.d];
    expect(
      cubic(NimnaMotion.easeStandard),
      (motion['easeStandard'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
    );
    expect(
      cubic(NimnaMotion.easeDecelerate),
      (motion['easeDecelerate'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
    );
    expect(motion['springs'], 'forbidden');
  });

  test('line matches tokens.json', () {
    final line = tokens['line'] as Map<String, dynamic>;
    expect(NimnaLine.thickness, (line['thickness'] as num).toDouble());
    expect(
      NimnaLine.dotGapIdle,
      (line['dotGapIdle'] as List).map((v) => (v as num).toDouble()).toList(),
    );
    expect(
      NimnaLine.endpointRadius,
      (line['endpointRadius'] as num).toDouble(),
    );
    expect(NimnaLine.holdToWipeChannelMs, line['holdToWipeChannelMs']);
    expect(NimnaLine.holdToWipeFullMs, line['holdToWipeFullMs']);
  });

  test('code block matches tokens.json (fixed forever by spec §4)', () {
    final code = tokens['code'] as Map<String, dynamic>;
    expect(NimnaCode.length, code['length']);
    expect(NimnaCode.grouping, code['grouping']);
    expect(NimnaCode.separator, code['separator']);
    expect(
      NimnaCode.entrySegmentWidth,
      (code['entrySegmentWidth'] as num).toDouble(),
    );
    expect(
      NimnaCode.entrySegmentHeight,
      (code['entrySegmentHeight'] as num).toDouble(),
    );
    expect(
      NimnaCode.entrySegmentGap,
      (code['entrySegmentGap'] as num).toDouble(),
    );
    expect(NimnaCode.entryGroupGap, (code['entryGroupGap'] as num).toDouble());
  });

  test('media block matches tokens.json', () {
    final media = tokens['media'] as Map<String, dynamic>;
    expect(NimnaMedia.attachmentCapMB, media['attachmentCapMB']);
    expect(
      NimnaMedia.thumbRadiusInner,
      (media['thumbRadiusInner'] as num).toDouble(),
    );
    expect(NimnaMedia.docRowHeight, (media['docRowHeight'] as num).toDouble());
    expect(
      NimnaMedia.transferProgressThickness,
      (media['transferProgressThickness'] as num).toDouble(),
    );
    expect(NimnaMedia.blurSigma, (media['blurSigma'] as num).toDouble());
  });
}
