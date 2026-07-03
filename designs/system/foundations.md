# Nimna Design System — Foundations (3.1)

Everything inherits from one idea: **a warm line in a dark room.** Layouts are still; the only thing that moves meaningfully is the line, and the only thing that glows is amber.

## Spacing & grid

- Base unit: **4 px**. Scale: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`.
- Screen margins: **20 px** (mobile, 390 pt reference frame).
- Vertical rhythm: sections separate by 32; related elements by 12; label→field by 8.
- List rows: **72 px** (channel rows), 56 px (settings rows). Touch targets ≥ 44×44.
- Chat: bubble max-width 75% of frame; inter-bubble gap 4 (same author) / 16 (turn change).
- One column, always. Nimna never needs a grid heavier than a single measured column.

## Corner radii

| Token | Value | Applies to |
|---|---|---|
| `rSmall` | 10 | Toasts, small chips, code segments |
| `rMedium` | 14 | Buttons, inputs |
| `rLarge` | 16 | Cards, list containers, chat bubbles¹ |
| `rSheet` | 20 | Bottom sheets (top corners) |
| `rFull` | 999 | The session line's endpoints, dots, pills |

¹ Chat bubbles: 16 on three corners, **4** on the corner pointing to its author — a quiet tail without drawing one.

## Elevation

- **Dark mode: elevation is surface, not shadow.** Layers step `surface0 → 1 → 2 → 3`; shadows are invisible on near-black and therefore banned. A hairline (`#26262A`) separates only where surfaces would otherwise merge (e.g., sheet over surface2 content).
- **Light mode: real shadows, small ones.** `shadowSm` 0 1 2 rgba(0,0,0,.06) (rows/cards) · `shadowMd` 0 4 12 rgba(0,0,0,.08) (sheets) · `shadowLg` 0 12 32 rgba(0,0,0,.12) (modals). Never colored shadows, never glows — the amber glow belongs to the line alone.

## Motion — "breathing, not bouncing"

| Token | Value | Use |
|---|---|---|
| `durMicro` | 120 ms | Press feedback, toggles |
| `durStandard` | 200 ms | State changes, fades |
| `durEnter` | 320 ms | Sheets, screens entering/leaving |
| `durBreath` | 2 800 ms | The knock breath loop (opacity 25→100→25%) |
| `easeStandard` | cubic-bezier(0.4, 0, 0.2, 1) | Everything by default |
| `easeDecelerate` | cubic-bezier(0.2, 0, 0, 1) | Entrances only |

Rules: **no spring, no overshoot, no bounce — ever.** Nothing autoplays except the line's state animations. Sheets slide + fade; screens crossfade with 8 px vertical drift, never push sideways. `prefers-reduced-motion` / platform setting: all loops freeze at their most legible frame (knock = solid amber), transitions drop to fades of `durMicro`.

**The line's choreography** (canonical, from color-system.md): offline = dotted, still · knock = solid, breathing at `durBreath` · connect moment = dots travel from both ends and meet in the middle (once, 320 ms, decelerate) · live = solid, still, faint glow · hangup = reverse of connect, then dotted · wipe = the line shrinks from center outward to two dots, which fade (once, 480 ms).

## Layout posture

- Headlines start at the **top third**, never vertically centered (calm ≠ empty).
- One primary action per screen, bottom-anchored, full-width minus margins.
- Destructive actions never sit adjacent to primary ones.
- Empty states are two lines of copy, no illustrations — the voice does the work.
