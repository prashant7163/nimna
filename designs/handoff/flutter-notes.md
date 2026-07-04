# Nimna — Flutter Implementation Notes (6)

Target: Flutter (iOS + Android), dark-first with full light theme. Tokens: [`../system/tokens.json`](../system/tokens.json) → generate a `NimnaTokens` `ThemeExtension` (one dart file, checked in, hand-synced with tokens.json v1.1.0 — spec v0.1.1 sync: `code` + `media` blocks, `mediaVeil`).

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
| Code entry | 9 `_CodeSegment` boxes in three groups (tokens `code`: 30×52, segment gap 5, group gap 8, drawn 8×2 hyphen dashes) + hidden `TextField` (paste-friendly: accepts with/without hyphens, case-insensitive, Crockford aliases I→1 O→0 normalized); mono style `codeInline`; error shake = 2px `TranslationTransition` ×1, 200ms. Format fixed forever (spec §4): 9 chars Crockford Base32, `XXX-XXX-XXX`. Join methods (spec §3.1): type · paste · `mobile_scanner` live scan · upload QR image/PDF (`image_picker`/`file_picker` + QR decode from still; PDF → first-page raster → decode). |
| QR display | `qr_flutter` on a white `Card` (white in BOTH themes — QR contrast); code string beneath in `codeDisplay`. |
| QR scan | `mobile_scanner`; corner brackets via `CustomPainter` (4 arcs, no full frame); on detect: brackets recolor to accent 200ms, no sound. |
| Chat bubbles | `Container` + `BoxDecoration` radius 16/16/16/4 (author corner); waiting = `dashed` border via CustomPainter or `dotted_border` pkg; list = `ListView` `reverse:true`; disappearing removal = `AnimatedSize`+fade 200ms. |
| Knock banner | `Overlay` entry sliding from top (320ms decelerate), auto-dismiss at knock TTL 60s with countdown `caption`. |
| Sheets | `showModalBottomSheet` with `shape` top-radius 20, `barrierColor` = scrim token, drag handle 32×4. |
| Channel rows | `ListView.separated`, 72px rows, radius 16 cards, gap 12; mini-line = the same line `CustomPainter` at 24px width. |
| Toast | Custom overlay (NOT `SnackBar` — Material styling fights the design); surface3, radius 10, 3s. |
| App lock | `local_auth` (biometric) + custom PIN pad (72px circular keys); route guard: lock on `AppLifecycleState.paused`→resume. Zero-leak: locked route replaces the whole navigator, never stacked above content. |
| Push (opt-in) | Content-free "New activity" only; `firebase_messaging` on Android / APNs direct via relay dispatcher; deep-link straight to knock screen if knock still live, else lapsed message (wireframe F6). Per-channel toggle DEFAULT OFF; device-tokens exchanged peer-to-peer inside the E2E channel and refreshed via CONTROL frames (spec §3.2.1) — the app never registers tokens with any Nimna server. |
| **Media bubbles (v0.1.1, spec §5.1)** | Same bubble geometry, `padding: 0`, `ClipRRect`. Chunked send: MEDIA_CHUNK frames with encrypted manifest; progress = 2px accent line along the bubble's bottom edge (`FractionallySizedBox`), no percentage text. Client-side compression default (`flutter_image_compress`) + original-quality toggle; EXIF strip BEFORE encryption on the sender's device (strip during re-encode; verify no GPS/device tags survive). 5 MB cap client-enforced (string 17 error). Received media → app-private encrypted store only, excluded from gallery and backups; export is an explicit user action (`share_plus`/save with confirm). Disappearing `expiry` applies identically to media. |
| **Sensitive-content check (v0.1.1, spec §5.3)** | iOS: `SensitiveContentAnalysis` framework via platform channel. Android: mechanism is an engineering decision for the build phase (bundled on-device model, or iOS-only at launch) — design is platform-agnostic. Recipient: check after decrypt, before display → blurred (`ImageFilter.blur` σ24 + `mediaVeil` overlay + string 15). Sender: check at attach → whisper card (string 14), non-blocking. HARD BOUNDARY: results never leave the device — nothing blocked, logged, reported, or transmitted; no analytics events, ever. |
| **Screenshot detect-and-notify (v0.1.1, spec §5.2)** | iOS: `UIApplication.userDidTakeScreenshotNotification`. Android: Android 14+ screenshot-detection API / `ContentObserver` fallback. On detect while a session's content is on screen: emit CONTROL screenshot-notice; render peer notices as the in-thread system line (string 12). Honor-system — no blocking. |
| **Paywall (v0.1.1, spec §10)** | `in_app_purchase`: yearly auto-renewing subscription. The CTA price is ALWAYS the store-provided localized string (`ProductDetails.price`) — the `{STORE_PRICE}` placeholder in mockups; never hardcode a number. Entitlement checked only at channel creation, on-device; lapse gates creation only — never touch existing channels (the permanence guarantee is structural: no code path may freeze/degrade a channel). Restore via store identity (`restorePurchases()`); Family Sharing disabled in store config; no trial. |

## Motion & platform hygiene

- Global page transitions: fade + 8px vertical drift (`PageTransitionsTheme`, custom builder, 320ms decelerate). No sideways pushes, no Cupertino back-swipe animation surprise — keep the swipe gesture, restyle the visual.
- All `AnimationController`s honor `MediaQuery.disableAnimations`.
- Secure flags: **RESOLVED by spec v0.1.1 §5.2 — FLAG_SECURE is deliberately NOT used**; the promise is identical on both platforms: screenshots possible, peer always notified (detect-and-notify above). iOS: blur app switcher snapshot via lifecycle overlay (standard, non-controversial — this hides content from the switcher, it does not block capture, so it doesn't contradict the stance).
- Background reality (spec §3.3): hold the socket ~30 s after backgrounding (both platforms, symmetric by policy), then close. No VoIP/background-audio workarounds — review-fatal. Longer gaps: knock → content-free push → tap → reconnect (~1 s). The app never auto-retries knocks (spec §4) — each knock is a deliberate tap.
- Backup exclusion (spec §6): Android `allowBackup=false` + `dataExtractionRules`; iOS `isExcludedFromBackup` on the DB directory.

## Asset wiring

- Fonts bundled via google_fonts at build or vendored .ttf (OFL) — vendor for reproducible builds.
- Logo/icons: prefer `CustomPainter` for the symbol and the 24 UI icons (geometry in `../system/icons/icons.svg` — paths are simple enough to port; `i-doc`/`i-image` added v0.1.1); fall back to `flutter_svg` if painter time is short.
- App icons: from `../brand/app-icon/` per its README (iOS 1024 master; Android adaptive bg/fg/monochrome).
