# Nimna — Design & Website Update Work-Loop (Spec v0.1.1 Sync)

Paste the prompt below into Claude Code from the project root. Attach: `nimna-protocol-spec-v0.1.1.md` (the current single source of truth) and `brand-context.md`.

---

```
PROJECT ROOT: /Users/pacific/Playground/AIManagedProjects/Nimna

You are running an UPDATE work loop. The protocol spec has evolved to v0.1.1
and the existing design artifacts (brand microcopy, design system, wireframes,
hi-fi screens) and the website were produced against an older understanding.
Your job is to bring them into exact alignment with the attached
nimna-protocol-spec-v0.1.1.md.

DO NOT diff the spec against the artifacts bit by bit. The complete set of
changes is enumerated in the CHANGELOG below, each with the artifacts it
touches. Work strictly from the changelog; treat anything not listed as
unchanged. If while working you notice an artifact contradicting the spec in
a way NOT covered by the changelog, do not fix it silently — log it in
PROGRESS.md under "drift found" and ask me.

Follow the established repo conventions: update TASKS.md statuses live,
append to PROGRESS.md after every task and at notable milestones, record
every decision in DECISIONS.md (USER decisions asked, never made; CODE
decisions made and logged; unsure → USER). Front-load all foreseeable user
questions per task before starting it. Commit per logical chunk. Report in
full only when all three tasks are done.

═══════════════════ CHANGELOG: SPEC v0.1.1 DELTAS ═══════════════════

C1. PRICING MODEL REPLACED — most invasive change.
    OLD (in artifacts): one-time unlock; "first channel free" may linger.
    NEW: yearly subscription, priced regionally by the platform stores.
    NO PRICE NUMBER APPEARS ANYWHERE outside the stores — not in mockups,
    not on the website; the paywall screen renders the store-provided
    localized price string (use a {STORE_PRICE} placeholder in designs),
    and the website describes the model without naming a number.
    Initiators pay, receivers NEVER pay and never see a paywall. Creating
    channels requires an active subscription; joining/communicating is
    free forever. THE PERMANENCE GUARANTEE: every channel created while
    subscribed stays fully functional forever, even after lapse — lapse
    gates only NEW channel creation. Nothing is ever frozen or
    repossessed. Restore via store identity only (no accounts); no
    cross-platform carry; no Family Sharing; no trial creation.
    Pricing line to use: "One of you buys the line. The other never pays."
    → Touches: paywall screen + F9 wireframe, onboarding if it mentions
      price, website pricing section (model + permanence only, no
      numbers, store badges as the path to price), website FAQ, any
      microcopy saying "one-time" or "unlock". The permanence guarantee
      must appear wherever pricing is explained — it is a headline trust
      feature, not fine print.

C2. MEDIA & DOCUMENTS ARE IN V1 (spec §5.1).
    Images + PDFs/files, 5 MB cap, client-side compression by default with
    original-quality toggle, EXIF/metadata stripped by default before
    encryption (market as a feature), received media quarantined in Nimna's
    encrypted store (never the gallery; export is deliberate), sender's
    disappearing timer applies to media identically.
    → Touches: chat-session wireframes and hi-fi screens (attach button,
      media bubbles, transfer progress for chunked live transfer, media
      viewer with export-as-deliberate-act), channel settings if media
      options surface there, website features section, website FAQ.

C3. SCREENSHOT POLICY: DETECT-AND-NOTIFY (spec §5.2).
    Symmetric both platforms. "Nimna can't stop a screenshot. It will
    always tell the other person." Disclosed in onboarding as consent.
    Honest limits disclosed: only fires in-app; second camera undetectable.
    → Touches: onboarding flow (disclosure moment), chat screen (the
      screenshot-notice as a system line in the thread), website honesty
      section, microcopy guide.

C4. SENSITIVE-CONTENT HANDLING, ON-DEVICE ONLY (spec §5.3).
    Recipient side: flagged incoming media renders blurred with "sensitive
    content — tap to view." Sender side: soft non-blocking whisper at
    attach time ("This looks like sensitive content — send anyway?").
    Never blocked/logged/reported; sender never learns of recipient flags.
    Android mechanism is delegated to engineering (CODE decision later);
    design both states platform-agnostically.
    → Touches: chat screen states (blurred media bubble), attach flow
      (whisper dialog), website /security page ("even our safety features
      can't phone home — they have nowhere to call").

C5. PAIRING FLOW ENRICHED (spec §3.1).
    Code + QR displayed SIMULTANEOUSLY, independently shareable. User-facing
    name: "Nimna code" (never "pairing code" in UI). Four join methods:
    manual entry, paste, live QR scan, upload QR image/PDF. Share sheet
    carries: "Works once, expires in 24h — share it like a password."
    Safety phrase is the closing ritual of pairing — UX frames it as
    "call them and compare," strongly encouraged, skippable. Failed/stale
    pairing attempts NEVER surface notifications (silence doctrine).
    → Touches: F2/F3 wireframes and their hi-fi screens, share sheet,
      join screen (four input affordances), safety-phrase screen framing,
      microcopy guide, website how-it-works section.

C6. CODE FORMAT FIXED FOREVER (spec §4): 9 characters, Crockford Base32,
    displayed and entered as XXX-XXX-XXX (grouping is part of the format).
    → Touches: every screen showing or accepting a code, QR-adjacent
      displays, website visuals that depict a code.

C7. PUSH MODEL FINALIZED (spec §3.2, §3.2.1).
    Per-channel OPT-IN, DEFAULT OFF. Content-free ("New activity" — no
    channel, sender, or content). Device-tokens are held by PEERS only,
    exchanged inside the encrypted channel, carried inside the knock,
    forwarded statelessly by the relay and immediately discarded — the
    relay stores no token registry. Push-off is the pure "burner-line
    mode" with zero third-party touch.
    → Touches: channel settings (opt-in toggle + honest one-line
      explanation of the trade), notification visuals, website
      architecture/honesty sections, FAQ ("what do Apple/Google see?").

C8. BACKGROUND & SESSION REALITY (spec §3.3).
    30-second background grace on both platforms (symmetric by policy),
    then socket closes; longer gaps bridged by knock → push → tap →
    reconnect (~1s). Knock rate limits exist (1/10s per channel; pushes
    1/min, 6/hr, 20/day) — design the "knocked — waiting" state so the UI
    invites patience, not hammering; the app never auto-retries knocks.
    → Touches: session status indicators, knock UX states, any copy
      implying long-lived background connections.

C9. DEVICE LOSS & REINSTALL DOCTRINE (spec §6.1).
    Channels die with the device — cryptographically, permanently, no
    resurrection, by design. Only the subscription restores (via store).
    Re-pair out-of-band. Permitted UX sugar: stale-knock local hint
    ("no answer in a while — if they lost their device, you'll need to
    pair again").
    → Touches: website FAQ ("what if I lose my phone?" — answer with
      confidence, it's the zero-storage promise keeping itself honest),
      onboarding if it touches permanence, the stale-knock hint state in
      chat/channel UI.

C10. ABUSE POSTURE LANGUAGE (spec §9).
    Three structural facts for public-facing copy: no discovery (pairing
    requires an existing out-of-band relationship), strictly 1:1 (no
    distribution networks), every channel traces to a store-verified paid
    subscription. Residual case (two consenting bad actors) exists in
    every E2E system; Nimna does not claim otherwise.
    → Touches: website /security and honesty sections, press/FAQ copy.

C11. RELAY LICENSING & CREDENTIALS STANCE (spec §4).
    Relay is open source under AGPL-3.0 (Signal-server/SimpleX precedent);
    protocol spec published openly; the APP remains closed. Push
    credentials (APNs/FCM) are deployment configuration, never repository
    content — auditors verify push BEHAVIOR in the open code (content-free
    string, device-token discarded); self-hosted relays bring their own
    credentials or run push-less.
    → Touches: website /security page (license named, the
      code-vs-deployment honesty, "verify it yourself" framing), footer
      GitHub/license mention, FAQ if it covers open source or self-hosting.

═══════════════════ THE THREE TASKS ═══════════════════

TASK 1 — DESIGN SYSTEM & MICROCOPY SYNC
Apply C1, C3, C5, C6 (and any C-item strings) to: the microcopy/voice
guide, design tokens if new components need them (media bubbles, blurred
state, whisper dialog, code-entry XXX-XXX-XXX grouping), and the
component library (new/changed components enumerated from the changelog).
No taste checkpoints — this is surgical execution. Front-load questions.

TASK 2 — WIREFRAMES & HI-FI SCREENS SYNC
Apply every C-item to the affected wireframes (F2, F3, F5, F6, F7, F9 —
plus F1 onboarding for C1/C3/C9 disclosures) and regenerate ONLY the
hi-fi screens whose content changed. Add net-new screens where the
changelog requires them (media viewer, blurred-media state, whisper
dialog, knocked-waiting state) following the existing system. Keep
annotations updated (entry/exit, edge cases from C8 rate limits).

TASK 3 — WEBSITE SYNC
Apply C1, C2, C3, C4, C7, C9, C10, C11 to the site: pricing section
rebuilt around the subscription + permanence guarantee, features updated
for media, honesty section extended (screenshots, push trade, metadata),
/security page updated (on-device sensitive-content stance, push token
design, abuse posture, AGPL-3.0 and the code-vs-deployment honesty), FAQ
updated/extended (lost phone, what Apple/Google see, why no trial,
self-hosting). Re-verify every claim against spec v0.1.1 — the
no-overclaiming rule stands; I will diff copy against spec.
  TASTE CHECKPOINT: if the pricing-section redesign changes the page's
  structure or visual concept (likely), present the revised section
  design and PAUSE before building. Pure copy swaps need no pause.

═══════════════════ START ═══════════════════

Begin: read the spec fully, read TASKS/PROGRESS/DECISIONS to load repo
state, add these three tasks to TASKS.md, then open Task 1 with its
consolidated question list.
```
