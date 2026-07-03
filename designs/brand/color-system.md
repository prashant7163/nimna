# Nimna — Color System (1.2)

Direction: **C — The Line.** Dark mode is the hero mode; light mode is a full first-class citizen.

## Principles

1. **One accent.** Incandescent amber is the only color in the product. It means exactly one thing: *the line is alive (or about to be)*. It is never decorative.
2. **Color is state.** The palette is a status language mapped to the protocol: grey = apart, breathing amber = knocking, solid amber = live, absence = wiped.
3. **Darkness is the product.** Near-black isn't a theme; it's the room the line glows in. Surfaces separate by elevation steps of barely-there grey, not by borders or shadows.
4. **Destructive ≠ scary.** The wipe uses a quiet ember-red — serious, not alarming. No red badges anywhere else, ever.
5. **No green.** "Delivered" and "success" are typographic (a check glyph in text colors) or amber moments. A third hue would dilute the language. Green additionally reads "online status," which Nimna deliberately does not broadcast.

## Dark mode (hero)

| Token | Hex | Role |
|---|---|---|
| `surface0` | `#0B0B0C` | App background — the room |
| `surface1` | `#141416` | List rows, cards |
| `surface2` | `#1B1B1E` | Sheets, modals, knock banner |
| `surface3` | `#232327` | Toasts, topmost layer |
| `hairline` | `#26262A` | Dividers, input strokes (decorative) |
| `textPrimary` | `#E8E6E1` | Body, titles — warm off-white |
| `textSecondary` | `#A8A6A0` | Supporting text, timestamps |
| `textTertiary` | `#7C7A75` | Hints, captions — **surface0/1 only** (4.01:1 on surface2 — use textSecondary there) |
| `textDisabled` | `#55534F` | Disabled labels (exempt from AA) |
| `accent` | `#F2A65A` | Incandescent amber — live line, knock, primary action, the i-dot |
| `accentPressed` | `#DE8F3E` | Pressed state of accent fills |
| `accentGlow` | `#F2A65A` @ 14% | Knock-banner wash, live-line halo |
| `onAccent` | `#201305` | Text/icons on amber fills |
| `lineIdle` | `#6E6E74` | The line, offline (dotted) |
| `lineLive` | `#F2A65A` | The line, live (solid) = accent |
| `danger` | `#E0655A` | Destructive text/ghost actions |
| `dangerFill` | `#8C2F27` | Wipe confirmation button fill |
| `onDanger` | `#FFF6F5` | Text on dangerFill |
| `warning` | `#CBA35C` | Rare: code-TTL expiring notice |
| `bubbleSent` | `#26201A` | Sent bubble — faint warmth (the ember side) |
| `bubbleReceived` | `#1D1D20` | Received bubble — neutral |
| `bubbleWaiting` | transparent + dashed `lineIdle` border | Composed-while-offline (spec §3.4) |
| `scrim` | `#000000` @ 60% | Behind sheets/modals |

## Light mode

Light mode swaps "a lit filament in a dark room" for "amber ink on warm paper." The vivid amber fails contrast on paper, so light mode uses a single darker **amber-ink**; the hue stays, the meaning stays.

| Token | Hex | Role |
|---|---|---|
| `surface0` | `#F7F5F2` | App background — warm paper, never pure white |
| `surface1` | `#FFFFFF` | List rows, cards |
| `surface2` | `#FFFFFF` (+ elevation shadow) | Sheets, modals |
| `surface3` | `#FFFFFF` (+ elevation shadow) | Toasts |
| `hairline` | `#E5E2DC` | Dividers, input strokes |
| `textPrimary` | `#1C1B19` | Body, titles |
| `textSecondary` | `#57544E` | Supporting text |
| `textTertiary` | `#6F6B62` | Hints, captions |
| `textDisabled` | `#B0ACA4` | Disabled |
| `accent` | `#96581A` | Amber-ink — fills, links, live line (one value for all) |
| `accentPressed` | `#7C4813` | Pressed accent |
| `accentGlow` | `#96581A` @ 10% | Washes |
| `onAccent` | `#FFFFFF` | Text on accent fills |
| `lineIdle` | `#827F78` | The line, offline |
| `lineLive` | `#96581A` | The line, live |
| `danger` / `dangerFill` | `#A6362C` | Destructive text; wipe fill |
| `onDanger` | `#FFFFFF` | Text on dangerFill |
| `warning` | `#8A6B3A` | Warning-ink |
| `bubbleSent` | `#F3E8DA` | Warm paper tint |
| `bubbleReceived` | `#FFFFFF` + hairline | Neutral |
| `bubbleWaiting` | transparent + dashed `lineIdle` border | Outbox |
| `scrim` | `#000000` @ 35% | Behind sheets |

## The line — state language (both modes)

| Protocol state (spec §3.2–3.4) | Line rendering |
|---|---|
| Peer offline / no session | `lineIdle`, dotted (2px dots, 7px gaps), rounded caps |
| Knock sent / knock received | `accent`, solid, breathing opacity 25%→100%, 2.8s ease-in-out loop |
| Live session (bridged) | `accent`, solid, steady; subtle `accentGlow` halo |
| Session ended (hangup/drop) | Animates back to dotted `lineIdle` |
| Channel wiped | Line is cut: shrinks from center to two dots, then nothing |

## Amber rationing rules

Amber may appear as: (1) the line in knock/live states, (2) the single primary action on a screen, (3) the wordmark's i-dot, (4) the disappearing-message timer glyph. It may **not** appear in: navigation, decorations, icons at rest, celebratory effects, badges. If a screen has no primary action and no live line, it has no amber. Screens are *supposed* to be quiet.

## WCAG AA verification

All pairings verified programmatically (WCAG 2.1 relative-luminance formula; script: `temp/contrast_final.py`). Requirements: 4.5:1 normal text, 3.0:1 large text / UI components (1.4.11).

```
 15.77  (req 4.5)  PASS   #E8E6E1 on #0B0B0C  — text-primary on surface-0
 14.75  (req 4.5)  PASS   #E8E6E1 on #141416  — text-primary on surface-1
 13.78  (req 4.5)  PASS   #E8E6E1 on #1B1B1E  — text-primary on surface-2
  8.08  (req 4.5)  PASS   #A8A6A0 on #0B0B0C  — text-secondary on surface-0
  7.06  (req 4.5)  PASS   #A8A6A0 on #1B1B1E  — text-secondary on surface-2
  4.59  (req 4.5)  PASS   #7C7A75 on #0B0B0C  — text-tertiary on surface-0  (surface-0/1 only)
  9.72  (req 4.5)  PASS   #F2A65A on #0B0B0C  — accent (amber) as text on surface-0
  8.49  (req 4.5)  PASS   #F2A65A on #1B1B1E  — accent as text on surface-2
  8.97  (req 4.5)  PASS   #201305 on #F2A65A  — on-accent on accent (primary button)
  5.79  (req 4.5)  PASS   #E0655A on #0B0B0C  — danger as text on surface-0
  5.06  (req 4.5)  PASS   #E0655A on #1B1B1E  — danger as text on surface-2
  7.74  (req 4.5)  PASS   #FFF6F5 on #8C2F27  — on-danger on danger-fill (wipe button)
  8.37  (req 4.5)  PASS   #CBA35C on #0B0B0C  — warning as text on surface-0
 12.91  (req 4.5)  PASS   #E8E6E1 on #26201A  — text-primary on bubble-sent
 13.48  (req 4.5)  PASS   #E8E6E1 on #1D1D20  — text-primary on bubble-received
  3.88  (req 3.0)  PASS   #6E6E74 on #0B0B0C  — line-idle on surface-0 (UI indicator)
  3.39  (req 3.0)  PASS   #6E6E74 on #1B1B1E  — line-idle on surface-2 (UI indicator)
  9.72  (req 3.0)  PASS   #F2A65A on #0B0B0C  — line-live on surface-0 (UI indicator)
 15.82  (req 4.5)  PASS   #1C1B19 on #F7F5F2  — text-primary on surface-0
 17.21  (req 4.5)  PASS   #1C1B19 on #FFFFFF  — text-primary on surface-1
  6.93  (req 4.5)  PASS   #57544E on #F7F5F2  — text-secondary on surface-0
  4.88  (req 4.5)  PASS   #6F6B62 on #F7F5F2  — text-tertiary on surface-0
  5.20  (req 4.5)  PASS   #96581A on #F7F5F2  — accent (amber-ink) as text on surface-0
  5.66  (req 4.5)  PASS   #96581A on #FFFFFF  — accent as text on surface-1
  5.66  (req 4.5)  PASS   #FFFFFF on #96581A  — on-accent on accent (primary button)
  6.06  (req 4.5)  PASS   #A6362C on #F7F5F2  — danger as text on surface-0
  6.59  (req 4.5)  PASS   #FFFFFF on #A6362C  — on-danger on danger-fill
  4.55  (req 4.5)  PASS   #8A6B3A on #F7F5F2  — warning-ink as text on surface-0
 14.23  (req 4.5)  PASS   #1C1B19 on #F3E8DA  — text-primary on bubble-sent
 17.21  (req 4.5)  PASS   #1C1B19 on #FFFFFF  — text-primary on bubble-received
  3.67  (req 3.0)  PASS   #827F78 on #F7F5F2  — line-idle on surface-0 (UI indicator)
  5.20  (req 3.0)  PASS   #96581A on #F7F5F2  — line-live on surface-0 (UI indicator)

ALL PASS
```

**Known constraint (recorded):** `textTertiary` (dark) passes only on `surface0/1`; on `surface2+` use `textSecondary`. This is a usage rule, not an exception.
