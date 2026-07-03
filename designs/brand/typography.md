# Nimna — Typography System (1.3)

## Typefaces

**Primary — Schibsted Grotesk.** One family for everything, display to caption. SIL Open Font License; on Google Fonts; available in Flutter via the `google_fonts` package (`GoogleFonts.schibstedGrotesk`). A calm, contemporary grotesk with slightly warm terminals — modern without being techy, editorial without a serif. Single-family restraint is itself the Direction-C statement: one voice, one line weight of speech.

Weights used: **400** (Regular), **500** (Medium), **600** (SemiBold). Nothing heavier — bold shouting is off-brand.

**Code companion — Spline Sans Mono.** SIL OFL; Google Fonts; `GoogleFonts.splineSansMono`. Used *only* for machine-shaped strings: the pairing code, the safety phrase, relay address in settings. A humanist mono (not a terminal font) — it disambiguates characters (the spec's "unambiguous alphabet") without importing hacker aesthetics. Weight 500 only.

**Fallback stacks (web/handoff):**
`"Schibsted Grotesk", -apple-system, "Segoe UI", Roboto, sans-serif` · `"Spline Sans Mono", ui-monospace, "SF Mono", monospace`

## Type scale

Sizes in logical px (Flutter dp/sp; 1:1 with CSS px in the mockups). Line heights are fixed values, not ratios, for pixel-exact handoff.

| Style | Size / Line | Weight | Letter-spacing | Use |
|---|---|---|---|---|
| `display` | 32 / 40 | 500 | −0.4 | Onboarding headlines, paywall headline |
| `title1` | 24 / 31 | 500 | −0.2 | Screen titles |
| `title2` | 20 / 26 | 500 | −0.1 | Section heads, channel name in session header |
| `bodyLarge` | 17 / 25 | 400 | 0 | **Chat messages** — the product's reading size; generous by intent |
| `body` | 15 / 22 | 400 | 0 | Default UI text, settings rows, dialogs |
| `label` | 15 / 20 | 500 | +0.1 | Buttons, tabs, list-row actions |
| `caption` | 13 / 18 | 400 | +0.1 | Timestamps, hints, helper text |
| `micro` | 11 / 15 | 500 | +0.6, uppercase | Overlines: "WAITING", "LIVE", section labels |
| `codeDisplay` | 28 / 36 (mono) | 500 | +6 | The pairing code, shown big |
| `codeInline` | 17 / 24 (mono) | 500 | +2 | Code entry field, safety phrase words |

## Rules

1. **Two weights per screen, maximum.** Usually 400 + 500. 600 is reserved for the single most important word in a destructive confirmation ("Wipe **everything**?").
2. **Hierarchy by spacing and color, not size jumps.** Adjacent styles differ subtly; the quietness is the luxury. Never skip from `caption` to `display` on one surface.
3. **No italics.** Emphasis is `textPrimary` vs `textSecondary`, or 500 vs 400.
4. **No all-caps except `micro`** — and `micro` is a whisper (status overlines), not a shout.
5. **Numbers in codes are always mono.** Never render a pairing code or safety phrase in the UI face; the mono shift signals "this is exact — read it carefully."
6. **Minimum text size 11px**; `micro` never carries essential standalone meaning (always paired with a visual state).
7. **Dynamic type:** all styles scale with platform text-size settings; the line motif and layout must tolerate up to 1.3× without truncating chat text (chat may wrap freely; codes may scroll horizontally, never shrink).

## Why not…

- **Inter / Roboto:** default-app feel; Nimna should feel like an object, not a template.
- **Space Grotesk / mono-first identity:** drifts toward the crypto/hacker aesthetic on the Hard Avoids list.
- **A serif display:** beautiful but imports "editorial brand" where Direction C wants "drawn with one line." The website may set pull-quotes in the same grotesk at display size — restraint holds there too.
