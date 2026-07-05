import 'package:flutter/material.dart';

/// Nimna design tokens — hand-synced with `designs/system/tokens.json`
/// v1.1.0 (Direction C — The Line). THE ONLY FILE ALLOWED TO CONTAIN COLOR
/// LITERALS; everything else consumes semantic names via
/// `Theme.of(context).extension<NimnaTokens>()`. A drift-guard test
/// (test/ui/tokens_drift_test.dart) reads the JSON and asserts every value
/// here matches — tokens cannot silently diverge from design.
class NimnaTokens extends ThemeExtension<NimnaTokens> {
  const NimnaTokens({
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentPressed,
    required this.accentGlow,
    required this.onAccent,
    required this.lineIdle,
    required this.lineLive,
    required this.danger,
    required this.dangerFill,
    required this.onDanger,
    required this.warning,
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.scrim,
    required this.mediaVeil,
  });

  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color accent;
  final Color accentPressed;
  final Color accentGlow;
  final Color onAccent;
  final Color lineIdle;
  final Color lineLive;
  final Color danger;
  final Color dangerFill;
  final Color onDanger;
  final Color warning;
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color scrim;
  final Color mediaVeil;

  static const NimnaTokens dark = NimnaTokens(
    surface0: Color(0xFF0B0B0C),
    surface1: Color(0xFF141416),
    surface2: Color(0xFF1B1B1E),
    surface3: Color(0xFF232327),
    hairline: Color(0xFF26262A),
    textPrimary: Color(0xFFE8E6E1),
    textSecondary: Color(0xFFA8A6A0),
    textTertiary: Color(0xFF7C7A75),
    textDisabled: Color(0xFF55534F),
    accent: Color(0xFFF2A65A),
    accentPressed: Color(0xFFDE8F3E),
    accentGlow: Color(0x24F2A65A),
    onAccent: Color(0xFF201305),
    lineIdle: Color(0xFF6E6E74),
    lineLive: Color(0xFFF2A65A),
    danger: Color(0xFFE0655A),
    dangerFill: Color(0xFF8C2F27),
    onDanger: Color(0xFFFFF6F5),
    warning: Color(0xFFCBA35C),
    bubbleSent: Color(0xFF26201A),
    bubbleReceived: Color(0xFF1D1D20),
    scrim: Color(0x99000000),
    mediaVeil: Color(0xB30B0B0C),
  );

  static const NimnaTokens light = NimnaTokens(
    surface0: Color(0xFFF7F5F2),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFFFFFFF),
    hairline: Color(0xFFE5E2DC),
    textPrimary: Color(0xFF1C1B19),
    textSecondary: Color(0xFF57544E),
    textTertiary: Color(0xFF6F6B62),
    textDisabled: Color(0xFFB0ACA4),
    accent: Color(0xFF96581A),
    accentPressed: Color(0xFF7C4813),
    accentGlow: Color(0x1A96581A),
    onAccent: Color(0xFFFFFFFF),
    lineIdle: Color(0xFF827F78),
    lineLive: Color(0xFF96581A),
    danger: Color(0xFFA6362C),
    dangerFill: Color(0xFFA6362C),
    onDanger: Color(0xFFFFFFFF),
    warning: Color(0xFF8A6B3A),
    bubbleSent: Color(0xFFF3E8DA),
    bubbleReceived: Color(0xFFFFFFFF),
    scrim: Color(0x59000000),
    mediaVeil: Color(0xB3F7F5F2),
  );

  /// Semantic-name → color map (drift-guard test surface; keys match
  /// tokens.json `color.dark`/`color.light` keys exactly).
  Map<String, Color> toColorMap() => {
    'surface0': surface0,
    'surface1': surface1,
    'surface2': surface2,
    'surface3': surface3,
    'hairline': hairline,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textTertiary': textTertiary,
    'textDisabled': textDisabled,
    'accent': accent,
    'accentPressed': accentPressed,
    'accentGlow': accentGlow,
    'onAccent': onAccent,
    'lineIdle': lineIdle,
    'lineLive': lineLive,
    'danger': danger,
    'dangerFill': dangerFill,
    'onDanger': onDanger,
    'warning': warning,
    'bubbleSent': bubbleSent,
    'bubbleReceived': bubbleReceived,
    'scrim': scrim,
    'mediaVeil': mediaVeil,
  };

  @override
  NimnaTokens copyWith() => this;

  @override
  NimnaTokens lerp(NimnaTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NimnaTokens(
      surface0: mix(surface0, other.surface0),
      surface1: mix(surface1, other.surface1),
      surface2: mix(surface2, other.surface2),
      surface3: mix(surface3, other.surface3),
      hairline: mix(hairline, other.hairline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      accent: mix(accent, other.accent),
      accentPressed: mix(accentPressed, other.accentPressed),
      accentGlow: mix(accentGlow, other.accentGlow),
      onAccent: mix(onAccent, other.onAccent),
      lineIdle: mix(lineIdle, other.lineIdle),
      lineLive: mix(lineLive, other.lineLive),
      danger: mix(danger, other.danger),
      dangerFill: mix(dangerFill, other.dangerFill),
      onDanger: mix(onDanger, other.onDanger),
      warning: mix(warning, other.warning),
      bubbleSent: mix(bubbleSent, other.bubbleSent),
      bubbleReceived: mix(bubbleReceived, other.bubbleReceived),
      scrim: mix(scrim, other.scrim),
      mediaVeil: mix(mediaVeil, other.mediaVeil),
    );
  }
}

/// Typography (tokens.json `typography.styles`; designs/brand/typography.md).
/// Metrics only — color is applied by the theme/text theme. Weights select
/// the `wght` axis of the vendored variable fonts.
abstract final class NimnaText {
  static const String fontFamily = 'Schibsted Grotesk';
  static const String fontFamilyMono = 'Spline Sans Mono';

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: -0.4,
  );

  static const TextStyle title1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 31 / 24,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: -0.2,
  );

  static const TextStyle title2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: -0.1,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 25 / 17,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: 0,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: 0,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: 0.1,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: 0.1,
  );

  /// Uppercase is applied at call sites (TextStyle cannot transform case);
  /// micro never carries essential standalone meaning.
  static const TextStyle micro = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 15 / 11,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: 0.6,
  );

  static const TextStyle codeDisplay = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: 6,
  );

  static const TextStyle codeInline = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: 2,
  );

  /// Style-name → style map (drift-guard test surface; keys match
  /// tokens.json `typography.styles` keys exactly).
  static const Map<String, TextStyle> styles = {
    'display': display,
    'title1': title1,
    'title2': title2,
    'bodyLarge': bodyLarge,
    'body': body,
    'label': label,
    'caption': caption,
    'micro': micro,
    'codeDisplay': codeDisplay,
    'codeInline': codeInline,
  };
}

/// tokens.json `spacing`.
abstract final class NimnaSpacing {
  static const double base = 4;
  static const List<double> scale = [4, 8, 12, 16, 20, 24, 32, 40, 48, 64];
  static const double screenMargin = 20;
  static const double listRowChannel = 72;
  static const double listRowSettings = 56;
  static const double touchTargetMin = 44;
}

/// tokens.json `radius`.
abstract final class NimnaRadius {
  static const double small = 10;
  static const double medium = 14;
  static const double large = 16;
  static const double sheet = 20;
  static const double full = 999;
  static const double bubbleTail = 4;
}

/// tokens.json `motion`. Springs are forbidden by the design system.
abstract final class NimnaMotion {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration enter = Duration(milliseconds: 320);
  static const Duration breath = Duration(milliseconds: 2800);
  static const Duration wipeCut = Duration(milliseconds: 480);
  static const Cubic easeStandard = Cubic(0.4, 0, 0.2, 1);
  static const Cubic easeDecelerate = Cubic(0.2, 0, 0, 1);
}

/// tokens.json `line` (the session-indicator motif).
abstract final class NimnaLine {
  static const double thickness = 2;
  static const List<double> dotGapIdle = [2, 7];
  static const double endpointRadius = 3;
  static const int holdToWipeChannelMs = 1500;
  static const int holdToWipeFullMs = 2500;
}

/// tokens.json `code` — fixed permanently by spec §4.
abstract final class NimnaCode {
  static const int length = 9;
  static const List<int> grouping = [3, 3, 3];
  static const String separator = '-';
  static const double entrySegmentWidth = 30;
  static const double entrySegmentHeight = 52;
  static const double entrySegmentGap = 5;
  static const double entryGroupGap = 8;
}

/// tokens.json `media`.
abstract final class NimnaMedia {
  static const int attachmentCapMB = 5;
  static const double thumbRadiusInner = 0;
  static const double docRowHeight = 64;
  static const double transferProgressThickness = 2;
  static const double blurSigma = 24;
}
