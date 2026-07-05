import 'package:flutter/material.dart';

import '../ui/theme/nimna_tokens.dart';
import 'transitions.dart';

/// Builds the two ThemeData (dark/light) from the same token map
/// (designs/handoff/flutter-notes.md — Theme plumbing). Dark-first with a
/// full light theme; `themeMode: ThemeMode.system`, no in-app toggle in v1.
ThemeData nimnaTheme(Brightness brightness) {
  final tokens = brightness == Brightness.dark
      ? NimnaTokens.dark
      : NimnaTokens.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    secondary: tokens.accent,
    onSecondary: tokens.onAccent,
    error: tokens.danger,
    onError: tokens.onDanger,
    surface: tokens.surface1,
    onSurface: tokens.textPrimary,
    outline: tokens.hairline,
  );

  final textTheme = TextTheme(
    displaySmall: NimnaText.display,
    titleLarge: NimnaText.title1,
    titleMedium: NimnaText.title2,
    bodyLarge: NimnaText.bodyLarge,
    bodyMedium: NimnaText.body,
    labelLarge: NimnaText.label,
    bodySmall: NimnaText.caption,
    labelSmall: NimnaText.micro,
  ).apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary);

  // Buttons: height 52, radius 14, Material splash disabled, 6% press
  // overlay (flutter-notes §Per-component).
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(NimnaRadius.medium),
  );
  const buttonSize = Size(64, 52);
  final pressOverlay = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.pressed)
        ? tokens.textPrimary.withValues(alpha: 0.06)
        : null,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.surface0,
    canvasColor: tokens.surface0,
    dividerColor: tokens.hairline,
    splashFactory: NoSplash.splashFactory,
    fontFamily: NimnaText.fontFamily,
    textTheme: textTheme,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: NimnaPageTransitionsBuilder(),
        TargetPlatform.iOS: NimnaPageTransitionsBuilder(),
      },
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.surface3
              : states.contains(WidgetState.pressed)
              ? tokens.accentPressed
              : tokens.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.textDisabled
              : tokens.onAccent,
        ),
        overlayColor: pressOverlay,
        minimumSize: const WidgetStatePropertyAll(buttonSize),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: const WidgetStatePropertyAll(NimnaText.label),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.textDisabled
              : tokens.textPrimary,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.hairline)),
        overlayColor: pressOverlay,
        minimumSize: const WidgetStatePropertyAll(buttonSize),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: const WidgetStatePropertyAll(NimnaText.label),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.textDisabled
              : tokens.accent,
        ),
        overlayColor: pressOverlay,
        minimumSize: const WidgetStatePropertyAll(buttonSize),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: const WidgetStatePropertyAll(NimnaText.label),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    extensions: [tokens],
  );
}
