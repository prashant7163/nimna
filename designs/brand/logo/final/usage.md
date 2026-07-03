# Nimna Logo — Usage Rules (2.2)

Final mark: **"Two Ends"** — two dots joined by one lit line, beside a custom monoline wordmark whose i-dot carries the same amber as the line.

## Files

| File | Use |
|---|---|
| `lockup-dark.svg` | Primary. Dark surfaces (app, website hero, store dark assets) |
| `lockup-light.svg` | Light surfaces (documents, light-mode web) |
| `lockup-mono.svg` | Single-color contexts (engraving, watermark, favicon fallback); inherits `currentColor` |
| `wordmark-dark/light/mono.svg` | Headers where the symbol would repeat (e.g., website nav next to the favicon) |
| `symbol-dark/light/mono.svg` | Avatars, favicons, watermarks, anywhere the name is already present |

## Construction

Everything is built from one stroke unit **u** (the wordmark stroke = 10 SVG units). Letterforms: monoline, round caps, x-height 42u/10, geometric single-storey `a`. Symbol: dots r = 0.65u, line weight 0.7u, line length 5.2u. The symbol's line and the wordmark's i-dot are the only amber elements — never add more.

## Clear space

Minimum clear space around any variant = **the height of the wordmark's x-height** (≈ 40% of lockup height) on all four sides. Nothing enters it: no text, no rules, no edges.

## Minimum sizes

| Variant | Minimum height |
|---|---|
| Full lockup | 24 px |
| Wordmark only | 16 px |
| Symbol only | 12 px |

Below these, use the symbol; below 12 px (e.g., 16 px favicon) the symbol simplifies to **the dash** (line without dots) — the sanctioned degradation, per the concept review.

## Color rules

- Dark surfaces: strokes/dots `#E8E6E1`, amber `#F2A65A`.
- Light surfaces: strokes/dots `#1C1B19`, amber-ink `#96581A`.
- Mono: one color, any color — but if the context allows only one *brand* color, that color is the surface-appropriate amber.
- Never: gradients, shadows, outlines, glows (the *app's* live-line glow is a UI behavior, not a logo treatment).

## Don'ts

- Don't typeset "nimna" in Schibsted Grotesk as a substitute wordmark — the wordmark is drawn, not typed.
- Don't capitalize. It is `nimna`, always.
- Don't rotate the symbol vertical, don't extend the line's length, don't add a third dot.
- Don't place the dark lockup on photography or colored fields; the brand lives on its own near-black or paper.
- Don't animate the logo except: the symbol's line may breathe/connect using the session-state language (color-system.md) in the app splash and website hero only.
