# Nimna Design System — Components (3.2)

All values reference `tokens.json` and `foundations.md`. States listed per component. Dark-mode values shown; light mode swaps tokens per color-system.md (accent → amber-ink, elevation → shadows).

---

## Buttons

Height 52, radius `rMedium` 14, `label` type (15/20 · 500), full-width minus margins. One primary per screen, maximum.

| Variant | Default | Pressed | Disabled | Notes |
|---|---|---|---|---|
| **Primary** | fill `accent`, text `onAccent` | fill `accentPressed`, scale 0.99 | fill `surface2`, text `textDisabled` | The screen's single amber action |
| **Secondary** | 1 px `hairline` stroke, text `textPrimary` | stroke `textTertiary`, bg `surface1` | stroke+text at `textDisabled` | |
| **Ghost** | text `textSecondary`, no chrome | text `textPrimary` | `textDisabled` | "Keep", "Not now" |
| **Destructive-hold** | fill `dangerFill`, text `onDanger`, hold-progress bar burns right→left | (is the hold) | n/a | Wipe only; 1.5 s per-channel, 2.5 s full; release cancels |

Press feedback: `durMicro` opacity/scale; no ripples (Material ripple disabled — too playful).

## Text input

Height 52, radius 14, bg `surface1`, 1 px `hairline`; label above at `caption`.
States: default · **focused** (stroke `textSecondary` — not amber; focus is not a session event) · **error** (stroke `danger` + `caption` message below in `danger`, factual: "That code didn't match anything.") · disabled (bg `surface0`, text `textDisabled`).

## Code-entry field

For pairing codes (spec §3.1: 8–10 chars, unambiguous alphabet, shown grouped `XXX·XXX·XX`).
Segmented boxes 44×52, radius `rSmall`, `codeInline` mono type, auto-advance; paste fills all.
States: empty (hairline) · filling (active segment stroke `textSecondary`) · **complete** (all strokes `textSecondary`, Join enables) · **error/wrong code** (segments stroke `danger`, gentle 2 px horizontal shake ×1 — the one permitted shake in the product, `durStandard`) · **expired** (segments dim to `textDisabled`, message: "This code has expired. Ask them to make a new one.").

## QR display & scanner frame

**Display:** QR on a `#FFFFFF` card (QR needs true white even in dark mode), radius `rLarge`, 24 padding, code string beneath in `codeDisplay` mono, share/copy actions below. Never amber-tint the QR.
**Scanner:** full-bleed camera, corner brackets only (4 arcs, `textPrimary`, 2 px, radius 16 — no full box, no crosshair), `body` prompt above, ghost button "Enter it instead" below. On detect: brackets → solid amber momentarily (`durStandard`), then navigate. No beep.

## Chat bubbles

Radius 16/16/16/4 (4 toward author), padding 12×14, `bodyLarge` 17/25, max-width 75%, timestamp `caption` `textTertiary` outside bubble on last of group.

| State | Rendering |
|---|---|
| **Sent** | bg `bubbleSent`, right-aligned |
| **Received** | bg `bubbleReceived`, left-aligned |
| **Waiting** (peer offline, local-only — spec §3.4) | transparent bg, 1 px **dashed** `lineIdle` border; header above outbox group: `micro` "WAITING — ON YOUR PHONE ONLY"; sends in order on bridge |
| **Delivered** (client ACK — spec §3.3) | sent bubble + 12 px check glyph `textTertiary` beside timestamp; no double-ticks, no read receipts unless channel opts in (then "Seen" `caption` under last bubble) |
| **Disappearing (countdown)** | timer glyph + remaining time `caption` `accent` beside timestamp; at T-10 s text dims to `textTertiary`; removal = fade + collapse `durStandard`, no shredding theatrics |

## Knock banner / sheet

**In-app banner** (peer knocked while app open): slides from top `durEnter`, bg `surface2`, radius 16, the channel's label + "is knocking." + the mini-line breathing amber beneath; actions **Pick up** (primary, compact 40 px) / **Ignore** (ghost). Auto-dismiss at knock TTL (60 s) with no trace.
**Knock screen** (from content-free push → app opened → knock present): full-screen: label `title1`, breathing line across the frame, Pick up / Ignore. Never shows message content — there is none anywhere until bridged.

## Session status indicator — the line

The defining component. A 2 px line spanning the chat header, under the channel label.
States (canonical choreography in foundations.md): **offline** dotted `lineIdle` + `caption` "Not on the line" · **knocking (outgoing)** breathing amber + "Knocked — waiting…" + countdown from 60 s ("Knock again" appears on lapse) · **knocking (incoming)** breathing + Pick up inline · **live** solid amber, faint `accentGlow`, + "On the line" `micro` · **reconnecting** (drop mid-session, spec §3.3 keepalive) dotted amber + "The line dropped. Trying to reconnect…" · **hangup** plays cut animation → offline.
The line is never absent in a chat screen — its state IS the screen's truth.

## Channel list row

Height 72, bg `surface1` on `surface0`, radius 16, 12 gap between rows (cards, not a table).
Contents: user-chosen local label (`body` 500) — labels are local only, never transmitted (spec §6); beneath, state `caption`: "Quiet" (default), "Knocking…" (amber, breathing dot prefix), "On the line" (amber), "Waiting: N" (outbox count). Right edge: mini-line 24 px wide in the channel's current state.
States: default · pressed (`surface2`, `durMicro`) · **wiped/none** — a wiped channel simply isn't there.
No avatars, no photos, no initials-circles: a channel is a label and a line, not a person-record (spec: no identity).

## Modal

Center card, bg `surface2`, radius 16, padding 24, scrim 60%, `title2` + `body` `textSecondary` + actions right-aligned (ghost + primary). Reserved for blocking decisions only (wipe uses its own sheet — see wireframe F8).

## Toast

Bottom, above safe-area, bg `surface3`, radius `rSmall` 10, `body`, max 2 lines, auto-dismiss 3 s, one at a time, no icons, no colors: "Code copied." · "Purchase restored." · "Channel wiped." Never used for errors that need action.

## Sheet

Bottom sheet, bg `surface2`, top radius `rSheet` 20, grab-handle 32×4 `hairline`, slide+fade `durEnter`. Used by: disappearing-timer picker, share options, wipe confirmation.
