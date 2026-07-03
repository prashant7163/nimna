# Nimna App Icon (2.3)

**Posture (per decision record): quietly branded.** A near-black field with the symbol — recognizable if you know it, invisible if you don't. No badge, no glow, no border. On both platforms the icon should be one of the *darkest, stillest* objects on the home screen; that stillness is the recognition.

## iOS

- Master: `ios-icon-1024.svg` → export `1024×1024` PNG, **no transparency, no pre-rounded corners** (iOS masks it).
- The symbol spans 62% of the width — inside Apple's comfortable optical zone; the dots survive the superellipse mask at all sizes.
- Also export: 180, 120, 87, 80, 60, 58, 40, 29 px (Xcode asset catalog generates from 1024 in modern tooling — keep the single master authoritative).
- Settings/Spotlight sizes (29–40 px): verified legible (see 48 px test below; 29 px keeps two dots + line distinct because the geometry is only three shapes).

## Android (adaptive)

| Layer | File | Notes |
|---|---|---|
| Background | `android-adaptive-background.svg` | Solid `#0B0B0C`, full 108 dp bleed |
| Foreground | `android-adaptive-foreground.svg` | Symbol, 49 dp wide, centered in the 66 dp safe circle — survives circle, squircle, rounded-square masks and launcher parallax |
| Monochrome | `android-adaptive-monochrome.svg` | Android 13+ themed icons; launcher supplies the tint |

Legacy (API < 26): flatten background + foreground to 48 dp PNG.

## 48 px legibility test

Rendered check (temp/icon-48-test): at 48 px the icon reads as ● — ● on black; at 29 px it still reads because there are only three elements and one contrast decision. Per brand: it looks *unremarkable* at arm's length — a dark tile with a fleck of warm light — and exact up close.

## Store presence note

The same 1024 master serves App Store / Play Store listings. Do not add marketing decoration to the store icon; the listing screenshots carry the story (Task 3 assets).
