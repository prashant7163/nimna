# Nimna — Low-Fi Wireframes (Design Spec §4)

Annotated low-fi wireframes for all nine flows. Open any `f*.html` in a browser; each page is a **horizontally scrollable strip** of 390 px frames, with an annotation card (Purpose · Entry points · Exit points · Edge cases) under every frame. Shared styles live in `wf.css`.

## Reading conventions

- **Solid frame border** = happy-path screen · **dashed frame border** = EDGE frame.
- **The session line** (the one brand convention carried into low-fi): thin black line, **dotted = idle/offline**, **solid = knocking/live**, always with a text label. Breathing/connect/burn animations are annotated in `[bracketed italic notes]`, never animated.
- All microcopy is real and on-voice (phone-call register: line / knock / pick up / hang up). Voice-guide strings 1–10 appear verbatim where they apply.
- Grey boxes (`#DDD`) are placeholders (QR, camera, keyboard, system IAP sheet). No color, no brand fonts — hierarchy and annotation are the deliverable.

## Index

| File | Flow | Frames | Key edge cases covered |
|---|---|---|---|
| `f1-onboarding.html` | F1 First-run onboarding (what it is · how pairing works · what we cannot see) | 3 | Kill-and-relaunch mid-onboarding; honesty guard on "cannot see" claims |
| `f2-create-channel.html` | F2 Create channel (generate → share → wait → paired → safety phrase → ready) | 8 | **Code expires unused** ("nothing was created"); **safety-phrase mismatch** (MITM defense, calm); handshake failure mid-exchange; intercepted code |
| `f3-join-channel.html` | F3 Join channel (enter/scan → handshake → safety phrase → ready) | 7 | **Wrong code** (canonical error string); **expired code** (+ honesty note below); camera permission denied; one side declines the phrase |
| `f4-channel-list.html` | F4 Channel list (unlocked · locked zero-leak · label edit · empty) | 4 | Empty list (voice string 4); wiped channel leaves no ghost; forgotten PIN has no recovery |
| `f5-chat-session.html` | F5 Chat session (offline outbox → knock → accept → live → timer → hangup) | 8 | **Knock TTL lapses**; **connection drops mid-session** (voice string 10); **peer never accepts** (messages wait calmly, forever); pending ACKs resend on next bridge |
| `f6-receiving-knock.html` | F6 Receiving a knock (in-app banner · content-free push · knock screen) | 4 | **Knock already lapsed on open** ("knock back?"); push says only "New activity"; simultaneous knocks queue |
| `f7-channel-settings.html` | F7 Channel settings (label · notification opt-in · receipts · per-channel wipe) | 3 | **Early release cancels wipe — nothing happens**; push-token honesty; honor-system receipts |
| `f8-app-settings.html` | F8 App settings (app lock · panic wipe 2.5 s · relay info · licenses) | 4 | **Wipe canceled by release**; keys destroyed → past ciphertext undecryptable (spec §6); unlock survives wipe via store |
| `f9-paywall.html` | F9 Paywall (every created line until unlocked · one-time unlock · restore) | 5 | **IAP restore on reinstall** (store-mediated, no account/email anywhere); purchase fails/cancelled → calm return, no nagging; joining never gated |

Total: 46 frames. The six edge cases the design-spec §4 mandates (code expired · peer never accepts · connection drops mid-session · knock TTL lapses · wrong code · IAP restore on reinstall) live in F2.7 · F5.1/F5.7 · F5.8 · F5.7/F6.4 · F3.6 · F9.5 respectively.

## Decisions taken at wireframe level (no protocol impact)

- **Safety phrase has no skip.** Spec §3.1.5 says verification is "strongly encouraged, not enforced"; these wireframes always show the screen and offer only *They match / They don't match*. Adding a quiet skip is an open product question — flagged, not decided.
- **No free initiation exists** — every created line requires the one-time unlock (F9.1); joining stays free forever, with full two-way messaging. The only billing state is store-held unlocked-or-not, so wipe can't become a paywall-evasion loop. *(USER decision 2026-07-04 — supersedes the earlier "first initiated line free / free slot counts ever-initiated" model.)*
- **Disappearing-timer preset is sticky per channel** after being set, but rides each message individually (spec §5 `expiry` is per-message).
- **Simultaneous knock banners queue** one at a time, oldest first (F6.1).
- **PIN length** shown as 6 digits, accepts 4–8 (F8.2).
- **Empty channel labels allowed**; row renders "—" plus the line (F4.3).

## Protocol-honesty notes surfaced in the frames

- **"Expired code" vs "wrong code" on the joiner's side (F3.7):** the relay is stateless and sees only code hashes, so it cannot distinguish *expired* from *never existed*. The distinct dimmed "expired" state renders only when the app can know locally (e.g., a QR payload carrying an expiry hint — a small spec addition, **flagged, not assumed**). The default failure is the wrong-code state, whose copy already covers expiry.
- **Lapsed-knock attribution (F6.4):** the named "Marlowe knocked" variant requires the app to have *seen* the knock while it lived. From a cold open after expiry, the push named no channel and the relay remembers nothing — the app honestly cannot know who knocked, and shows nothing.
