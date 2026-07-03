# Nimna — Decision Record (append-only)

Format: date · decision · USER/CODE · alternatives · rationale.

---

- **2026-07-03 · Output folder is `/designs`· CODE** · alternatives: `designs/` (as written inside the older design-prompt text) · The work-loop prompt is the governing instruction and explicitly names `/designs` and `/website`; noted here so the discrepancy is never re-litigated.
- **2026-07-03 · Initialized git repo at project root with `.gitignore` (.DS_Store) · CODE** · alternatives: no VCS · The loop requires commits per logical chunk; no repo existed.
- **2026-07-03 · MEMORY.md at project root used as session-resume memory per loop rules · CODE** · alternatives: rely on persistent memory dir only · Loop rules explicitly require it; persistent memory kept as a thin pointer.
- **2026-07-03 · Remote is https://github.com/prashant7163/nimna.git, branch `main`, commits carry no Co-Authored-By trailer · USER** · alternatives: local-only repo, default trailer · User instruction at loop start.
- **2026-07-03 · Wordmark is all-lowercase "nimna" · USER** · alternatives: "Nimna"; decide per logo concept · Embodies the etymology (nimn: low, beneath notice); quiet on home screen and headers.
- **2026-07-03 · App icon is "quietly branded": the symbol, small, on a near-black field · USER** · alternatives: near-anonymous/generic icon · Recognizable if you know it, invisible if you don't; keeps store-listing presence.
- **2026-07-03 · Accent color: each brand direction proposes its own accent world · USER** · alternatives: mandate warm; mandate cool · Judged side-by-side at Checkpoint A1 with full context.
- **2026-07-03 · Typography flavor: each brand direction proposes its own type voice · USER** · alternatives: mandate serif display; mandate strictly sans · Judged at Checkpoint A1.
- **2026-07-03 · Panic wipe = hold-to-wipe (line burns down while held; release cancels; full wipe holds longer than per-channel) · USER** · alternatives: two-tap sheet, type-to-confirm · Fast under stress, impossible by accident — matches spec §6 "fast but unmistakable".
- **2026-07-03 · Paywall = calm full-screen page at second channel creation · USER** · alternatives: bottom sheet · Price as fact, not nag; consistent stillness.
- **2026-07-03 · App-lock = zero-leak lock screen (symbol + PIN/biometric, no content behind) · USER** · alternatives: blurred list · Nothing leaks before unlock; matches discretion posture.
- **2026-07-03 · Disappearing-timer presets: Off / 1 min / 15 min / 1 hr / 24 hr after read · CODE** · alternatives: free-form duration · Five calm choices beat a duration picker; spec §5 format ("read + N minutes") respected.
- **2026-07-03 · Free-choice hi-fi screens: enter-code, chat-waiting (offline outbox), app-lock; light-mode variants: create-code, channel-list, live-chat, paywall · CODE** · alternatives: settings, QR-scan et al. · Covers the three protocol rituals not already mandated; light variants = most-used surfaces.
- **2026-07-03 · App-lock iconography = 3×3 passcode-dot glyph, never a padlock · CODE** · alternatives: padlock, key · Padlocks sit on the brand's Hard Avoids adjacency; passcode dots are honest and ownable.
- **2026-07-03 · CHECKPOINT A2: Logo is Concept 1 — "Two Ends" (●—● symbol, amber i-dot wordmark) · USER** · alternatives: 2 "The Dash", 3 "The Headstroke" · Carries the full positioning sentence in both symbol and wordmark; animates as the session line; survives 48px; degrades gracefully to the dash.
- **2026-07-03 · CHECKPOINT A1: Brand direction is C — "The Line" · USER** · alternatives: A "The Fine Object" (quiet luxury/brass), B "Deep Water" (nimn etymology/ink+gold) · The line motif renders the protocol's own state machine (offline/knock/live/wiped); ownable, discreet at 48px, warm via incandescent amber. Carries: near-black #0B0B0C world, amber #F2A65A accent, Schibsted Grotesk single-family type.
