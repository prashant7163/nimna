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

For the Nimna code (spec §4, fixed permanently: **9 characters, Crockford Base32, displayed and entered as `XXX-XXX-XXX`** — the grouping is part of the format).
Nine segmented boxes 32×52 in three groups of three, radius `rSmall`, `codeInline` mono type; group gap 12 with a 6×2 hairline dash centered in each gap (the hyphen, drawn not typed). Auto-advance across groups; paste fills all (accepts with or without hyphens, case-insensitive, Crockford aliases I→1, O→0 normalized silently).
**Four ways in** (spec §3.1 join methods — the join screen offers all four): type it · paste it · scan the QR live · upload a QR image or PDF.
States: empty (hairline) · filling (active segment stroke `textSecondary`) · **complete** (all strokes `textSecondary`, Join enables) · **error/wrong code** (segments stroke `danger`, gentle 2 px horizontal shake ×1 — the one permitted shake in the product, `durStandard`; message: "That code didn't match anything. Codes expire — ask them to make a new one." Expired and never-existed are indistinguishable by design, and no failed attempt ever notifies anyone — spec §3.1 silence doctrine).

## QR display & scanner frame

**Display:** code and QR are **one surface, shown simultaneously** (spec §3.1) — each independently shareable through different channels. QR on a `#FFFFFF` card (QR needs true white even in dark mode), radius `rLarge`, 24 padding; the code beneath in `codeDisplay` mono as `XXX-XXX-XXX`; share/copy actions below act on either form. Every share path carries the briefing line (string 13): "Works once, expires in 24h — share it like a password." Never amber-tint the QR.
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

## Media bubbles — images & documents (spec §5.1, new in v0.1.1)

Same geometry family as text bubbles: radius 16/16/16/4, max-width 75%. Images fill the bubble edge-to-edge (no inner padding); documents render as a row — doc glyph 24, filename `body` 500 (middle-truncated), size + kind `caption` `textTertiary`.

| State | Rendering |
|---|---|
| **Sending (chunked live transfer)** | image at 60% opacity; a 2 px `accent` progress line along the bubble's bottom edge fills left→right — the line motif carries the transfer; no percentage text. A live session moves 5 MB in seconds; the progress line is reassurance, not a meter |
| **Receiving** | placeholder bubble at intrinsic aspect, `surface2`, same bottom progress line |
| **Waiting** (peer offline) | thumbnail dimmed inside the dashed `lineIdle` border, under the same "WAITING — ON YOUR PHONE ONLY" header as text |
| **Blurred — sensitive (spec §5.3)** | thumbnail blurred (sigma per `media.blurSigma`), `mediaVeil` overlay, centered `caption` `textPrimary`: "Sensitive content — tap to view." Tap reveals in place, `durStandard` cross-fade. Nothing is reported to anyone, including the sender — the state is purely local |
| **Disappearing** | identical timer chrome to text bubbles — one timer, one rule, media included |

Attach affordance: a plus glyph left of the composer (icon set already carries `plus`); opens photo/file pickers. At attach: over-cap error (string 17: "That's over 5 MB…"); metadata-strip notice surfaces as `caption` under the preview the first time ("Photos are cleaned before they're sealed…" — string 17); original-quality toggle lives in the attach preview, off by default.

## Whisper card — sensitive-content check at attach (spec §5.3)

**Not a modal** — the check must whisper, not block. An inline card that rises above the attach preview: bg `surface2`, radius 16, padding 16, `body` text "This looks like sensitive content — send anyway?", actions right-aligned: ghost **Go back** · secondary-compact **Send anyway**. The composer and preview stay live behind it; editing or removing the attachment dismisses it. Never amber (this is caution, not a session event), never `danger` (nothing is wrong). Appears `durEnter` slide+fade, at most once per attachment.

## Media viewer

Full-bleed on `surface0`, chrome fades after 2 s (tap restores). Top: local label + received time `caption`. Bottom bar: **Export** (secondary) — the single deliberate act that moves a file out of Nimna's encrypted store (spec §5.1: never auto-saved, never in the gallery); confirm sheet states it plainly: "This copies it out of Nimna — into your phone's own storage." Disappearing media shows its countdown in the top bar; export of disappearing media is allowed (honor-system honesty — a screenshot is still a screenshot) but the timer chrome stays visible.

## System line — screenshot notice (spec §5.2)

A bare centered `caption` `textTertiary` line in the thread flow — an event, not speech: no bubble, no icon, 16 vertical padding. Strings (12): "They took a screenshot." / own side: "You took a screenshot. They've been told." Arrives via CONTROL frame; honor-system like expiry. Also used for future channel events; never for errors.

## Toggle (channel settings — push opt-in, spec §3.2)

Track 44×26 radius `rFull`, thumb 22. Off: track `surface3`, 1 px `hairline`, thumb `textTertiary`. On: track `accent`, thumb `onAccent`. `durMicro` slide, no bounce. **Push is per-line, default OFF**; the row carries string 18's honest trade beneath the label as `caption` `textSecondary`, and turning it on re-states it in a confirm-free toast-less way — the caption is the disclosure, always visible, not a one-time dialog.

## Knock banner / sheet

**In-app banner** (peer knocked while app open): slides from top `durEnter`, bg `surface2`, radius 16, the channel's label + "is knocking." + the mini-line breathing amber beneath; actions **Pick up** (primary, compact 40 px) / **Ignore** (ghost). Auto-dismiss at knock TTL (60 s) with no trace.
**Knock screen** (from content-free push → app opened → knock present): full-screen: label `title1`, breathing line across the frame, Pick up / Ignore. Never shows message content — there is none anywhere until bridged.

## Session status indicator — the line

The defining component. A 2 px line spanning the chat header, under the channel label.
States (canonical choreography in foundations.md): **offline** dotted `lineIdle` + `caption` "Not on the line" · **knocking (outgoing)** breathing amber + "Knocked — waiting…" + countdown from 60 s · **knocking (incoming)** breathing + Pick up inline · **live** solid amber, faint `accentGlow`, + "On the line" `micro` · **reconnecting** (drop mid-session, spec §3.3 keepalive) dotted amber + "The line dropped. Trying to reconnect…" · **hangup** plays cut animation → offline.
**The waiting state invites patience, never hammering** (spec §4: the app never auto-retries; the relay collapses duplicate knocks inside 10 s silently, and pushes are capped 1/min · 6/hr · 20/day — limits the UI never surfaces as counters, it simply doesn't tempt them): while the 60 s countdown runs, the Knock affordance is absent — the breathing line IS the feedback, with string 6's "One knock is enough — it won't repeat on its own" as its `caption`. Only on lapse does a quiet ghost **Knock again** appear. After an extended unanswered stretch, the stale-knock hint may surface locally (string 16, spec §6.1): "No answer in a while. If they lost their phone, this line can't come back — you'd pair again with a new code."
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

Bottom sheet, bg `surface2`, top radius `rSheet` 20, grab-handle 32×4 `hairline`, slide+fade `durEnter`. Used by: disappearing-timer picker, share options, wipe confirmation, attach picker (photo / file), media-export confirm. The code share sheet always carries the briefing line (string 13) as its `caption` header: "Works once, expires in 24h — share it like a password."
