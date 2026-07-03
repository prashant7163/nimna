# Nimna — Flutter Implementation Notes (6)

Target: Flutter (iOS + Android), dark-first with full light theme. Tokens: [`../system/tokens.json`](../system/tokens.json) → generate a `NimnaTokens` `ThemeExtension` (one dart file, checked in, hand-synced with tokens.json v1.0.0).

## Theme plumbing

- `ThemeData(brightness: …)` twice from the same token map; expose semantic names (`surface0`, `textSecondary`, `accent`…) via `ThemeExtension<NimnaTokens>` — do NOT scatter `Color(0xFF…)` literals.
- Typography: `google_fonts` package — `GoogleFonts.schibstedGrotesk()` (400/500/600) and `GoogleFonts.splineSansMono()` (500). Map the 10 styles in tokens to a `NimnaText` class; chat body = `bodyLarge` 17/25.
- Light/dark follows system (`themeMode: ThemeMode.system`); no in-app toggle in v1 (fewer settings = calmer).

## Per-component notes

| Component | Widget approach |
|---|---|
| **The line (session indicator)** | `CustomPainter` — one painter, five states (idle dotted / knock breathing / live / reconnecting / cut). Dot pattern: 2px dots, 7px gaps, round caps (`PathMetrics` dashing). Breathing: `AnimationController` 2800ms, opacity 0.25→1.0, `Curves.easeInOut`, `repeat(reverse:true)`. Connect moment: animate two dots from ends to center meeting, 320ms decelerate. Respect `MediaQuery.disableAnimations` → freeze solid. |
| Buttons | `FilledButton`/`OutlinedButton`/`TextButton` with `ButtonStyle` from tokens; **disable Material splash** (`splashFactory: NoSplash.splashFactory`, use `overlayColor` 6% for press). Height 52, radius 14. |
| Hold-to-wipe | `GestureDetector` `onTapDown/Up/Cancel` + `AnimationController` (1500ms channel / 2500ms full). Burn bar = `FractionallySizedBox` clipping a darker overlay right→left. Fire only on completion; release = reverse animation. Haptic: `HapticFeedback.heavyImpact()` on completion only. |
| Code entry | 8 `_CodeSegment` boxes + hidden `TextField` (autofill/paste-friendly); mono style `codeInline`; error shake = 2px `TranslationTransition` ×1, 200ms. Alphabet: unambiguous set per spec §3.1 (no 0/O/1/I/L). |
| QR display | `qr_flutter` on a white `Card` (white in BOTH themes — QR contrast); code string beneath in `codeDisplay`. |
| QR scan | `mobile_scanner`; corner brackets via `CustomPainter` (4 arcs, no full frame); on detect: brackets recolor to accent 200ms, no sound. |
| Chat bubbles | `Container` + `BoxDecoration` radius 16/16/16/4 (author corner); waiting = `dashed` border via CustomPainter or `dotted_border` pkg; list = `ListView` `reverse:true`; disappearing removal = `AnimatedSize`+fade 200ms. |
| Knock banner | `Overlay` entry sliding from top (320ms decelerate), auto-dismiss at knock TTL 60s with countdown `caption`. |
| Sheets | `showModalBottomSheet` with `shape` top-radius 20, `barrierColor` = scrim token, drag handle 32×4. |
| Channel rows | `ListView.separated`, 72px rows, radius 16 cards, gap 12; mini-line = the same line `CustomPainter` at 24px width. |
| Toast | Custom overlay (NOT `SnackBar` — Material styling fights the design); surface3, radius 10, 3s. |
| App lock | `local_auth` (biometric) + custom PIN pad (72px circular keys); route guard: lock on `AppLifecycleState.paused`→resume. Zero-leak: locked route replaces the whole navigator, never stacked above content. |
| Push (opt-in) | Content-free "New activity" only; `firebase_messaging` on Android / APNs direct via relay dispatcher; deep-link straight to knock screen if knock still live, else lapsed message (wireframe F6). |

## Motion & platform hygiene

- Global page transitions: fade + 8px vertical drift (`PageTransitionsTheme`, custom builder, 320ms decelerate). No sideways pushes, no Cupertino back-swipe animation surprise — keep the swipe gesture, restyle the visual.
- All `AnimationController`s honor `MediaQuery.disableAnimations`.
- Secure flags: `FLAG_SECURE` on Android (no screenshots of app content? — **decision needed**: blocking screenshots contradicts the honest honor-system stance; recommend NOT setting FLAG_SECURE, matching the "a screenshot is still a screenshot" copy. Flag for user.). iOS: blur app switcher snapshot via lifecycle overlay (standard, non-controversial).
- Backup exclusion (spec §6): Android `allowBackup=false` + `dataExtractionRules`; iOS `isExcludedFromBackup` on the DB directory.

## Asset wiring

- Fonts bundled via google_fonts at build or vendored .ttf (OFL) — vendor for reproducible builds.
- Logo/icons: prefer `CustomPainter` for the symbol and the 22 UI icons (geometry in `../system/icons/icons.svg` — paths are simple enough to port); fall back to `flutter_svg` if painter time is short.
- App icons: from `../brand/app-icon/` per its README (iOS 1024 master; Android adaptive bg/fg/monochrome).
