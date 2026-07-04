# Nimna Iconography (3.3)

## Style definition

- **24 px grid**, 2 px optical padding; stroke **1.75 px**, round caps and joins, `currentColor`.
- Monoline, geometric, rounded — the same DNA as the logo: every icon is *drawn with the brand's line*. Filled shapes only for dots (keypad, knock source, QR modules).
- No filled solids, no duotone, no outlines-with-fills, no perspective, no 3D-anything.
- Color: icons render in `textSecondary` at rest, `textPrimary` when their row/action is active. Amber only when the icon *is* the session state (knock, timer countdown). Danger color only on `line-cut` inside wipe contexts.
- Per Hard Avoids + decision record: **no padlocks, no shields, no keys, no fingerprints, no eyes-as-surveillance.** App lock is represented by the passcode keypad glyph; "what we can't see" uses `eye-off` (a crossed-out eye is an anti-surveillance statement, not spy imagery).

## The set (24)

| id | Meaning / where used |
|---|---|
| `i-plus` | Create channel (channel list) |
| `i-keypad` | App lock (settings, lock screen affordance) |
| `i-qr` | Show my code as QR (create flow) |
| `i-scan` | Scan their code (join flow) |
| `i-copy` | Copy code (create flow) |
| `i-share` | Share code via… (create flow) |
| `i-sliders` | Settings (app + channel) |
| `i-chevron-right` | Row navigation |
| `i-arrow-left` | Back |
| `i-close` | Dismiss sheets/modals |
| `i-check` | Delivered tick (bubbles); success rows |
| `i-timer-fade` | Disappearing messages (composer control, bubble countdown, channel setting) |
| `i-bell` | Notifications opt-in (per-channel, default off — spec §3.2) |
| `i-bell-off` | Notifications off state |
| `i-line-cut` | Wipe (per-channel and full) — the line, cut |
| `i-hang-up` | End session |
| `i-knock` | Knock (chat action bar; knock banner) |
| `i-pencil` | Edit local label |
| `i-info` | Relay info, licenses (settings) |
| `i-restore` | Restore purchase (paywall) |
| `i-eye-off` | "What we can't see" (onboarding-3, settings honesty section) |
| `i-external` | Outbound links (GitHub/relay repo); **Export from media viewer** (the deliberate act — spec §5.1) |
| `i-doc` | Document attachments: doc bubble, file picker, upload-QR-PDF join method (spec §5.1, §3.1 — added v0.1.1) |
| `i-image` | Image attachments: photo picker, attach preview (spec §5.1 — added v0.1.1) |

Sprite: [`icons.svg`](icons.svg) (SVG `<symbol>`-style defs, `currentColor`). Preview: [`preview.html`](preview.html).
Usage in HTML mockups: `<svg class="ic"><use href="icons.svg#i-knock"/></svg>` with `stroke-width:1.75; fill:none; stroke:currentColor` on the `.ic` class (dot-groups override internally).
Flutter: re-draw as `CustomPainter`s or export per-icon SVGs via the asset checklist (handoff notes).
