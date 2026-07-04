# Nimna — Low-Fi Wireframes (Design Spec §4)

*Synced to protocol spec v0.1.1 (2026-07-04): media & documents, screenshot policy, sensitive-content handling, four join methods, push/token honesty, 30 s background grace, device-loss hint, yearly-subscription paywall with the permanence guarantee.*

Annotated low-fi wireframes for all nine flows. Open any `f*.html` in a browser; each page is a **horizontally scrollable strip** of 390 px frames, with an annotation card (Purpose · Entry points · Exit points · Edge cases) under every frame. Shared styles live in `wf.css`.

## Reading conventions

- **Solid frame border** = happy-path screen · **dashed frame border** = EDGE frame.
- **The session line** (the one brand convention carried into low-fi): thin black line, **dotted = idle/offline**, **solid = knocking/live**, always with a text label. Breathing/connect/burn animations are annotated in `[bracketed italic notes]`, never animated.
- All microcopy is real and on-voice (phone-call register: line / knock / pick up / hang up). Voice-guide strings 1–18 appear verbatim where they apply.
- The Nimna code renders as `XXX-XXX-XXX` — hyphens, three groups of three — everywhere it appears (spec §4: the grouping is part of the format, fixed permanently).
- Grey boxes (`#DDD`) are placeholders (QR, camera, keyboard, photos, system store sheet). No color, no brand fonts — hierarchy and annotation are the deliverable.

## Index

| File | Flow | Frames | Key edge cases covered |
|---|---|---|---|
| `f1-onboarding.html` | F1 First-run onboarding (what it is · how pairing works · what we cannot see · the screenshot terms) | 4 | Kill-and-relaunch mid-onboarding; honesty guard on "cannot see" claims; screenshot policy as informed consent (F1.4, string 11) |
| `f2-create-channel.html` | F2 Create channel (generate → share sheet → wait → key exchange → safety phrase → ready) | 9 | **Code expires unused** ("nothing was created" + silence doctrine); **safety-phrase mismatch** (MITM defense, calm); handshake failure mid-exchange; intercepted code |
| `f3-join-channel.html` | F3 Join channel (type / paste / scan / upload → handshake → safety phrase → ready) | 7 | **Wrong code** (canonical error string); **expired code** (+ honesty note below); camera permission denied; one side declines the phrase |
| `f4-channel-list.html` | F4 Channel list (unlocked · locked zero-leak · label edit · empty) | 4 | Empty list (voice string 4); wiped channel leaves no ghost; forgotten PIN has no recovery |
| `f5-chat-session.html` | F5 Chat session (offline outbox → knock → live → attach/media → viewer → screenshot line → timer → hangup) | 15 | **Knock TTL lapses**; **connection drops mid-session** (voice string 10); **peer never accepts** (messages wait calmly, forever); sensitive-content whisper at attach; blurred received media; stale-knock hint (device-loss sugar, string 16) |
| `f6-receiving-knock.html` | F6 Receiving a knock (in-app banner · content-free push · knock screen) | 4 | **Knock already lapsed on open** ("knock back?"); push says only "New activity"; simultaneous knocks queue |
| `f7-channel-settings.html` | F7 Channel settings (label · push toggle · receipts · per-channel wipe) | 3 | **Early release cancels wipe — nothing happens**; push trade disclosed in-place (string 18, always visible); honor-system receipts |
| `f8-app-settings.html` | F8 App settings (app lock · panic wipe 2.5 s · relay info · licenses) | 4 | **Wipe canceled by release**; keys destroyed → past ciphertext undecryptable (spec §6); the subscription survives wipe via the store |
| `f9-paywall.html` | F9 Paywall (yearly subscription · permanence guarantee · store-mediated restore) | 7 | **Restore on reinstall** (store-mediated, no account/email anywhere); purchase cancelled → calm return; **lapsed subscription** — every existing line keeps working, only Create is gated |

Total: 57 frames. The six edge cases the design-spec §4 mandates (code expired · peer never accepts · connection drops mid-session · knock TTL lapses · wrong code · IAP restore on reinstall) live in F2.8 · F5.1/F5.13 · F5.15 · F5.13/F6.4 · F3.6 · F9.5 respectively.

## Decisions taken at wireframe level (no protocol impact)

- **Safety phrase has no skip — confirmed USER decision (2026-07-04), no longer an open question.** Only *They match / They don't match*, and the screen is framed as the closing ritual of pairing ("Call them and compare", F2.6/F3.4). The spec's "strongly encouraged, not enforced" is honored by the soft skip of tapping *They match* — never by a skip button.
- **Creation requires an active yearly subscription; the permanence guarantee rides at headline height** (spec §10, USER 2026-07-04 — supersedes both the earlier "first initiated line free" and the "one-time unlock" models). Every line created while subscribed works forever; a lapse gates only new creation (F9.7). Joining stays free forever, with full two-way messaging, and never surfaces a paywall. No price appears anywhere in designs or copy — the CTA carries the literal `{STORE_PRICE}` placeholder, rendered by StoreKit / Play Billing at runtime.
- **The whisper card sits inline above the attach preview — never a modal** (F5.6); composer and preview stay live behind it, and editing or removing the attachment dismisses it. At most once per attachment.
- **Attach sheet contents: Photo · File** (F5.5), with the original-quality toggle (default off) and the string-17 metadata caption living in the attach preview itself.
- **Received-media blur renders in-thread and reveals in place on tap** (F5.8); the media viewer (F5.9) is where Export — the single deliberate act — lives, with the confirm wording from components.md.
- **The screenshot system-line frame (F5.10) shows both string-12 variants in one thread** for economy; in reality each renders at its own moment.
- **Disappearing-timer preset is sticky per channel** after being set, but rides each message individually (spec §5 `expiry` is per-message) — and governs media identically (spec §5.1).
- **Simultaneous knock banners queue** one at a time, oldest first (F6.1).
- **PIN length** shown as 6 digits, accepts 4–8 (F8.2).
- **Empty channel labels allowed**; row renders "—" plus the line (F4.3).

## Protocol-honesty notes surfaced in the frames

- **"Expired code" vs "wrong code" on the joiner's side (F3.7):** the relay is stateless and sees only code hashes, so it cannot distinguish *expired* from *never existed*. The distinct dimmed "expired" state renders only when the app can know locally (e.g., a QR payload carrying an expiry hint — a small spec addition, **flagged, not assumed**). The default failure is the wrong-code state, whose copy already covers expiry. No failed pairing attempt ever notifies anyone, on either side (spec §3.1 silence doctrine).
- **Lapsed-knock attribution (F6.4):** the named "Marlowe knocked" variant requires the app to have *seen* the knock while it lived. From a cold open after expiry, the push named no channel and the relay remembers nothing — the app honestly cannot know who knocked, and shows nothing.
