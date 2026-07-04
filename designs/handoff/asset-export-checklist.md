# Nimna — Asset Export Checklist (6)

## Logo (from `designs/brand/logo/final/`)
- [ ] lockup / wordmark / symbol × dark / light / mono — SVG masters (done, in repo)
- [ ] PNG exports @1x/2x/3x of lockup-dark + symbol-dark (press kit, store listings)
- [ ] Favicon set from symbol (16/32/48 → dash-only below 24px per usage.md): favicon.ico, icon-192.png, icon-512.png, apple-touch-icon 180px (website Task 3)

## App icons (from `designs/brand/app-icon/`)
- [ ] iOS: 1024 PNG master from `ios-icon-1024.svg` (flatten, no alpha) → Xcode single-size asset
- [ ] Android: `mipmap` adaptive XML + foreground/background/monochrome vectors ported from the three SVG layers
- [ ] Android legacy 48dp flattened PNGs (mdpi→xxxhdpi)
- [ ] Verify at 29px (iOS settings) and themed/monochrome tint (Android 13)

## Fonts
- [ ] Vendor Schibsted Grotesk 400/500/600 + Spline Sans Mono 500 (TTF, SIL OFL, license files alongside)
- [ ] Subset for website (woff2, latin) — Task 3

## Screens → store listings
- [ ] Screenshot the 15 hi-fi HTML screens at 390×844 @3x (headless Chrome, window 438×900, crop `.screen`)
- [ ] Store sets: 6.7" (1290×2796) and 6.1" iOS; Play phone + 7" sets — re-shoot from HTML at scaled windows, don't upscale
- [ ] Store listing copy: NO price number anywhere (spec §10) — the store surfaces its own localized price

## Design-system artifacts
- [ ] tokens.json ↔ `NimnaTokens` dart file sync check (versioned, v1.1.0 — code/media blocks + mediaVeil added for spec v0.1.1)
- [ ] Icon sprite → per-icon SVGs if flutter_svg route chosen
- [ ] Contrast re-verification after ANY palette change: `python3 temp/contrast_final.py` must print ALL PASS
