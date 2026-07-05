# Nimna Build Plan v3 — Atomic Sessions with Parallel Groups (normative spec: v0.2.1)

**Supersedes** `nimna-build-plan-v2-sessions.md` (kept as history with a
deprecation header). **v3 changes ONLY structure, not scope** (USER,
2026-07-05): same 19 sessions, same deliverables, same done-checks. What v3
adds:

- Normative source updated to `docs/nimna-protocol-spec-v0.2.1.md`
  (supersedes v0.2 and v0.1.1; § numbering identical, so all section
  references below remain valid).
- Sessions already completed are marked **DONE** with their commit refs.
- A **dependency graph** for every not-yet-done session: prerequisites +
  the directories/modules it owns.
- **Parallel groups**: up to 3 sessions may run concurrently where the
  graph allows, under the standing parallel-execution rules in CLAUDE.md
  (USER, 2026-07-05). Governed, as before, by
  `nimna-implementation-workloop-prompt.md`; per-session pipeline
  (intake → implement → code-reviewer → senior-qa done-check → wrap) is
  unchanged and applies to every parallel session before merge.

**Structure:** one session = one atomic sitting = one clear deliverable +
done-check. `/clear` between sessions. Sessions sized context-friendly.

**Stack (locked):** Relay in **Go** (single static binary). App in
**Flutter/Dart** (iOS + Android). Single small VPS instance. Monorepo layout:

```
Nimna/
├── application/
│   ├── relay/      # Go relay (AGPL-3.0, publish executes at Session 19)
│   └── mobile/     # Flutter app (closed source)
├── designs/        # produced by the design loop
├── website/        # produced by the design loop
├── docs/           # spec + protocol test vectors + architecture notes
├── progress/       # per-session progress files for parallel sessions
├── TASKS.md  PROGRESS.md  DECISIONS.md  CLAUDE.md
```

Every folder carries a README.md describing its contents — maintained as
content evolves, not written once and forgotten.

---

## Status snapshot (2026-07-05 02:43 +0200)

| Session | Status | Commit refs |
|---|---|---|
| S1 Scaffolding & conventions | **DONE** | `b61b779` |
| S2 Crypto selection & spec v0.2 | **DONE** | `545d10f` |
| S3 Connections & rendezvous | **DONE** | `f89a853` (intake `5b81e25`, B1 adjudication `895215a`) |
| S4 Channels, knock, sessions, push | **DONE** | `832eedf` |
| S5 Hardening, rate limits, observability | **DONE** | `dc56ba2` |
| S6 Deploy & open-source release | **DONE** | `9254c7d` (wrap `39bfc59`) |
| — Spec v0.2.1 reconciliation (mini-session) | **DONE** | `3720d59` |
| S7 Skeleton & encrypted local storage | **in-progress** | (uncommitted; runs in the main tree — the last session to do so, predating the worktree rule) |
| DS Design-sync — reply/reaction UI, canonical strings + ARB stubs, self-join F3 (USER, 2026-07-05) | **in-progress** | (worktree `design-sync-reply-reactions`; S7-independent; hard prereq for S10, self-join surface for S9) |
| S8–S19 | pending | — |

---

## Phase 0 — Foundations

### Session 1 — Scaffolding & conventions — **DONE** (`b61b779`, 2026-07-04)
- Create the `application/relay` and `application/mobile` skeletons (Go module; Flutter project), READMEs in every folder, repo-root CLAUDE.md (<1 page: project context, conventions, spec pointer), CI lint/test skeleton for both stacks.
- Create the agent fleet in `.claude/agents/` per the work-loop prompt: product-manager, tech-architect, backend-developer-go, mobile-developer-flutter, code-reviewer, senior-qa — half-page role files each.
- Copy the spec and (later) protocol test vectors into `docs/`.
- **Done when:** both projects build empty; every folder has a README; agent fleet exists; CLAUDE.md orients a fresh session in one read.

### Session 2 — Crypto selection & spec v0.2 — **DONE** (`545d10f`, 2026-07-04)
- Evaluate primitives against spec §7 (authenticated agreement, AEAD, forward secrecy/ratchet, safety phrase, replay protection; Dart + Go library maturity; audit pedigree). Expected territory: X25519, ChaCha20-Poly1305, HKDF, possibly Noise framework. Anything exotic requires explicit justification to USER.
- Verify the 9-char/45-bit code space + relay throttling trade holds under the chosen handshake; flag to USER if not.
- Lock choices → spec v0.2 with concrete handshake sequence and exact wire framing (byte layout). Write protocol test vectors into `docs/`.
- **Done when:** spec v0.2 committed; test vectors exist; handshake explainable on one whiteboard.
- *As-built notes:* primitives USER-locked (X25519 · ChaCha20-Poly1305 · SHA-256/HKDF · Argon2id · Noise XXpsk2-from-spec · KK + per-message rekey · 3-word EFF phrase); PEER_OFFLINE removed from the knocker-visible wire (USER); spec since superseded by **v0.2.1** (`3720d59` — REACTION `0x06`, `reply_to` flag bit 2, restored §3.1 doctrines).

## Phase 1 — Relay (Go)

### Session 3 — Connections & rendezvous — **DONE** (`f89a853`, 2026-07-04)
- WebSocket server, connection lifecycle, in-memory registries, `H(code)` rendezvous topics with 24h TTL, first-come-wins bridging, topic death on completion.
- **Done when:** two CLI test clients rendezvous via a code hash and exchange raw frames.

### Session 4 — Channels, knock, sessions, push forwarding — **DONE** (`832eedf`, 2026-07-04)
- CRID registration; knock/accept/hangup lifecycle per spec v0.2.1 (KNOCK/ACCEPT/TEARDOWN; lapsed-knock enforcement is structural — PEER_OFFLINE was removed from the knocker-visible wire at S2, USER); knock TTL (60s); bridge teardown; keepalive pings; 30s background-grace expiry semantics.
- Stateless push forwarding per §3.2.1: offline peer + device-token in knock → one APNs/FCM call ("New activity", content-free) → token discarded. Credentials via config slots only (env/mounted files), never in repo.
- **Done when:** CLI clients pair, disconnect, knock (with and without token), accept, chat, hang up — relay memory empty after; a mock push sink receives exactly one content-free call per eligible knock.

### Session 5 — Hardening, rate limits & observability — **DONE** (`dc56ba2`, 2026-07-04)
- Spec §4 limits as config with defaults: per-IP connection caps, frame-rate caps, max frame size (must accommodate MEDIA_CHUNK), rendezvous throttling (single-digit/min/IP), knock 1/10s/CRID, push 1/min + 6/hr + 20/day per CRID (in-memory counters, reset on restart). Structured errors, graceful shutdown, soak-test script.
- Observability per the work-loop doctrine: aggregate metrics endpoint (no identifiers in labels), sanitized operational log with **unloggable wrapper types** for CRIDs/IPs/device-tokens/code-hashes (redact on serialization, CI-asserted), debug-only tracing config, recover-and-scrub panic handlers.
- **Done when:** abuse scripts bounce off every limit; overnight soak shows flat memory; CI log-scrub assertion passes; metrics answer "is the relay healthy" without touching a single identifier.

### Session 6 — Deploy & open-source release — **DONE** (`9254c7d` + wrap `39bfc59`, 2026-07-05)
- Single-binary deploy + TLS to the VPS (relay.nimna.app), health endpoint, minimal ops runbook.
- Public-repo readiness: AGPL-3.0 LICENSE, README leading with the zero-storage claim and how to audit it (§4 inventory: routing tables in memory, TLS certs, push credentials as deployment config), config.example with empty push slots, .gitignore guard, contribution note. Publish timing = USER decision.
- **Done when:** relay live on domain; repo publishable as-is.
- *As-built notes (USER deferrals, logged):* "live on relay.nimna.app" deferred until a VPS exists — substituted local production-shaped TLS deploy; live APNs/FCM platform verification deferred to S15; publish click executes at S19.

## Phase 2 — App core (Flutter)

### Session 7 — Skeleton & encrypted local storage — **in-progress**
- App scaffold, navigation shell, encrypted local DB (channel store, message store, media store per §6), platform keystore integration, cloud-backup exclusion flags verified on both platforms.
- Local diagnostic log per the work-loop doctrine: encrypted, ring-buffered (~7 days), app-lock perimeter, wiped by panic wipe, events/error-codes only.
- **Done when:** app boots, persists encrypted records across restart, data provably absent from device backups; diagnostic log demonstrably contains no content/keys/codes/tokens.
- *Standing i18n rule applies from here:* ARB/l10n from the first widget, zero hardcoded user-facing strings (reviewer-enforced S7 onward).
- *v0.2.1 coordination (PROGRESS 2026-07-05):* message-store schema anticipates `reply_to` (msg_id column) and a reactions adjunct table; app-architecture note's spec pointer fixed to v0.2.1 at wrap.

### Session 8 — Pairing: initiator side
- Keypair + 9-char Crockford Base32 code generation, XXX-XXX-XXX display, simultaneous QR render, share sheet with the §3.1 one-liner ("Works once, expires in 24h — share it like a password"), rendezvous registration, waiting state, TTL expiry handling.
- **Done when:** app creates a Nimna code and holds rendezvous against a CLI peer.

### Session 9 — Pairing: joiner side & handshake
- All four join methods: manual XXX-XXX-XXX entry, paste, live QR scan, QR upload (image/PDF). Key exchange per spec (device-token included in encrypted payload when push enabled), safety-phrase derivation + comparison screen (two buttons only — match / don't match; no skip button, per DECISIONS), channel finalization, code discard, silence doctrine (no failed-attempt surfacing). Self-join blocked client-side with the §3.1 canonical copy (v0.2.1).
- **Done when:** two devices pair end-to-end via each join method; MITM test vector rejected; phrase screen matches the design-loop artifacts.
- *Prereq (USER, 2026-07-05):* design-sync DS supplies the self-join guard surface (F3 error state + canonical copy) before this session starts.

### Session 10 — Live text messaging
- Session UI, encrypt/frame/send TEXT (5,000-char soft cap, transparent chunking), receive/decrypt/ACK, delivery states (waiting → sent → delivered), typing indicators, HANGUP, per-message expiry (sender-dictated) honored on both ends with the honest honor-system copy. REACTION + `reply_to` per spec v0.2.1 §5.5/§5.8 (inherit-expiry, silent-drop, quoted previews, neutral tombstone) — these are v0.2.1 envelope surface, not scope growth.
- **Codec obligation (deferred from the v0.2.1 reconciliation, PROGRESS 2026-07-05):** this is the first envelope-codec session — extend the vector generator codec to v0.2.1 (REACTION/`reply_to` encode/decode + invalid cases in `framing.json`, a `session-handshake.json` transport case, generator `SpecRef` → v0.2.1). **This session completes the CODEC CHECKPOINT** (see Parallel groups).
- **Done when:** two paired devices exchange E2E text live; debug relay logs show ciphertext only; expiry round-trips.
- **Done-check ADDITION (USER, 2026-07-05):** `lib/src/session` ships decomposed per-concern — composer/bubbles and connection-state in separate files with no shared mutable surface — as the testable condition gating S11 ∥ S12. Senior-qa passes/fails this clause explicitly; a FAIL means S10 is not done (standard no-partial-credit rule).
- *Prereq (USER, 2026-07-05):* design-sync DS supplies the reply/reaction UI artifacts (components, F5 frames, canonical strings) before this session starts.

### Session 11 — Media & documents
- Attach flow: images + PDFs/files, 5 MB cap, client-side compression default with original-quality toggle, EXIF/metadata strip before encryption, MEDIA_CHUNK chunking with encrypted manifest (count + content hash), reassembly + integrity check + ACK, transfer progress UI, media viewer, encrypted-store quarantine (never gallery; export = deliberate act), expiry applies to media.
- **Done when:** photo and PDF round-trip between devices; EXIF verifiably stripped; media absent from gallery/photo backups; expired media vanishes on both ends.

### Session 12 — Knock, presence, offline-compose, reconnect
- Knock/accept UX with the rate-limit-aware "knocked — waiting" state (no auto-retry, ever); lapsed-knock handling (attribution-free "No answer.", per DECISIONS); local waiting-outbox auto-flush on bridge; 30s background grace; reconnect logic; device-token refresh via CONTROL frames in live sessions; per-channel push opt-in (default off) with honest one-line trade explanation; stale-knock local hint (§6.1 sugar).
- **Done when:** compose-offline → knock (+push when enabled) → accept → backlog delivers in order; token rotation survives; push-off channels function as pure burner-line mode.

## Phase 3 — Discretion features

### Session 13 — App lock & panic wipe
- PIN/biometric gate, lock-on-background, per-channel wipe and full wipe (keys + history + media, irrecoverable), fast-but-unmistakable confirmation per design artifacts.
- **Done when:** wipe leaves no recoverable trace under device inspection; lock engages reliably.

### Session 14 — Screenshot policy & sensitive-content handling
- Detect-and-notify on both platforms (no FLAG_SECURE blocking — symmetric promise): screenshot → CONTROL notice → system line in peer's thread. Onboarding disclosure copy per design artifacts.
- Sensitive content per §5.3: iOS SensitiveContentAnalysis for recipient-side blur ("sensitive content — tap to view") + sender-side non-blocking whisper at attach. Android path = CODE decision within rails (on-device only, zero network calls, local-blur-only consequences; iOS-only-at-launch is the pre-approved fallback) — decide, record in DECISIONS.md.
- **Done when:** screenshot notice round-trips; flagged media blurs on iOS; sender whisper fires; Android decision recorded and implemented or explicitly deferred.

### Session 15 — Notifications end-to-end
- FCM/APNs client integration, device-token lifecycle (obtain, include in pairing payload, refresh via CONTROL), content-free "New activity" rendering, tap → open → reconnect flow, in-app suppression when foregrounded, verified default-off.
- Absorbs the S6 USER deferral: live APNs/FCM platform verification (relay transports were mock-verified at S6).
- **Done when:** locked phone receives contentless nudge on knock; disabling push per-channel results in zero third-party touch for that channel.

## Phase 4 — Ship

### Session 16 — Polish & first-run
- Onboarding (3 screens max, incl. screenshot-policy and permanence disclosures per design), empty/error states, app icon + name, dark mode, accessibility pass, microcopy sweep against the voice guide.
- "Share diagnostics" in settings: deliberate user export of the scrubbed local log — nothing ever auto-uploads; no third-party SDKs anywhere (verify the dependency tree).
- i18n (USER, 2026-07-04): crafted DE/FR/ES/IT app translation pass vs the voice guide (claim-accuracy exact), PM-reviewed, disputes → USER.
- **Done when:** a stranger goes install → paired chat unaided; dependency tree contains zero telemetry/analytics/crash SDKs.

### Session 17 — Subscription & paywall
- Yearly auto-renewing subscription via StoreKit 2 / Play Billing, priced by regional store tiers — the app NEVER hardcodes a price; paywall renders the store-provided localized string ({STORE_PRICE} in designs). Creation gated on active entitlement, checked on-device only (accepted §10 limitation: no server-side receipt validation — the relay learns nothing). Receivers never see a paywall. Permanence guarantee honored structurally: lapse gates creation only, existing channels untouched. Restore as a first-class flow (reinstall + new-device-same-store-account tested). Family Sharing disabled.
- **Done when:** sandbox subscribe/lapse/restore all behave per §10 on both platforms; a lapsed account's existing channels work forever.

### Session 18 — Adversarial pass & test suite
- Threat-model walkthrough vs §9 incl. new rows: replay, MITM, malformed frames + fuzzing (relay and app), storage/backup inspection, screenshot-notice suppression honesty, push-bombing vs rate limits, EXIF-strip verification, wipe forensics.
- USER scope addition (2026-07-05): the hand-implemented Noise engine cross-verified against an established Go Noise library (flynn/noise class) as a TEST ORACLE — test-only, never a runtime dependency, in addition to the committed vector sets.
- **Done when:** every §9 row has a passing test or a documented accepted limitation.

### Session 19 — Store prep & launch assets
- Store listings (positioning per brand: "a private line between two people — nothing stored anywhere, ever"; model described without price numbers — stores display price), privacy questionnaires ("data collected: none"), proactive review notes (E2E media precedent, §9 structural abuse posture, why zero storage), export-compliance declarations (US + France form), screenshots from design artifacts, launch checklist, HN launch draft ("the ~300-line relay" post), relay repo publish decision executed per USER call.
- i18n (USER, 2026-07-04): store listings ×5 languages, localized text-bearing screenshots, website in all five (EN default + browser-honoring switcher, zero external resources), launch-checklist copy-honesty verification run per language.
- **Done when:** both store submissions ready to press; launch post drafted.

---

## Dependency graph (not-yet-done sessions)

Prerequisite = must be **merged to main** (review + QA passed) before the
session starts. "Owns" = the only places that session writes, besides the
shared hotspots listed under Merge hotspots (which are orchestrator-folded,
never a reason to parallelize into the same module). All `lib/…` paths are
under `application/mobile/`.

| Session | Prerequisites | Owns (directories / modules) | Protocol-envelope-touching? |
|---|---|---|---|
| **S7** (in-progress) | S1, S2 | Mobile foundations: `lib/src/app` (shell/nav), `lib/src/crypto` (at-rest), `lib/src/storage`, `lib/src/domain`, `lib/src/diag`, `lib/l10n` scaffolding, `pubspec.*`, `assets/`, `test/` foundations | No |
| **DS** design-sync (USER, 2026-07-05) | — (works from spec v0.2.1 + existing design system only; S7-independent) | `designs/` (voice-guide strings, components, wireframe frames F3/F5, hi-fi where materially changed) + ARB stub handoff in `designs/handoff/` — the live `lib/l10n` files stay S7's; stub keys are folded at merge per the hotspot rules | No |
| **S8** | S7 · S2 vectors · S3 relay (done) | `lib/src/transport` (WS client, §5.4 outer frame), `lib/src/protocol` (topic derivation §3.1.2, rendezvous, PAIR_DATA slice), `lib/src/pairing/initiator` (initiator flow + screens; the create-line action = a single call site in an initiator-side/shell file — see G2 opening condition) | **Yes** (outer frame + pairing plane) |
| **S9** | S8 · **DS** (self-join guard F3 surface) | `lib/src/noise` (XXpsk2 engine, commitment, code-psk), `lib/src/pairing/joiner` (4 join methods + safety-phrase screen; initiator tree untouched), codec slices in `lib/src/protocol` (S8 merged by then) | **Yes** (handshake messages) |
| **S10** | S9 · S4 relay (done) · **DS** (reply/reaction UI) | `lib/src/protocol` (complete v0.2.1 §5.5–§5.8 envelope codec incl. TEXT/ACK/CONTROL/REACTION/`reply_to`), `lib/src/session` (chat UI, delivery states) + `docs/test-vectors/` generator extension (Go) | **Yes — builds the codec (CODEC CHECKPOINT)** |
| **S11** | S10 | `lib/src/media` (attach, compression, EXIF strip, MEDIA_CHUNK, viewer, quarantine) + composer/bubble files inside `lib/src/session` | Consumes codec only |
| **S12** | S10 | `lib/src/presence` (knock UX, outbox, reconnect, background grace, token-refresh CONTROL usage, push opt-in) + connection-state files inside `lib/src/session` | Consumes codec only |
| **S13** | S7 | `lib/src/lock` (PIN/biometric, lock-on-background), `lib/src/wipe`, settings lock/wipe screens | No |
| **S14** | S10, S11 | `lib/src/screenshot` (detect + CONTROL notice + system line), `lib/src/sensitive` (blur, whisper), platform-channel shims | Consumes codec only |
| **S15** | S9 (token in pairing payload), S12 (refresh + knock→push flow) | `lib/src/push` (FCM/APNs client, token lifecycle), platform push config; live APNs/FCM verification (S6 deferral) | Consumes codec only |
| **S16** | S8–S15 (all merged) | Cross-cutting: whole `lib/` (onboarding, states, dark mode, a11y, microcopy, DE/FR/ES/IT translation pass) | No |
| **S17** | S7, S8 (creation flow to gate) | `lib/src/billing` (StoreKit 2 / Play Billing, entitlement), paywall screen, creation-gate wiring confined to the initiator entry call site (S8's merged files — untouched by S9's joiner lane) | No |
| **S18** | S7–S17 (all merged) | Test suites both stacks, fuzz harnesses, Noise test-oracle harness (test-only), threat-model docs | Tests everything — frozen surface |
| **S19** | S18 · USER checkpoints (publish, launch copy) | `website/` ×5 languages, store-listing docs, launch checklist, publish execution | No |

```
S7 ──┬── S8 ──┬── S9 ──── S10 ──┬── S11 ──┬── S14 ──┐
     │        └── S17 ─────────┐│         │          │
     │                         ││         │          ├─ S16 ── S18 ── S19
     │                         │└── S12 ──┼── S15 ──┤
     └── S13 ──────────────────┴──────────┴──────────┘
     (S13 and S17 are floating non-protocol sessions: S13 slots anywhere
      after S7, S17 anywhere after S8 — wherever a concurrency slot is free.
      S16 requires S8–S15; S17 must also be merged before S16 so the polish
      sweep covers the paywall.
      DS design-sync (USER, 2026-07-05) is G1's third lane: S7-independent,
      so it starts immediately; it feeds S9 (self-join guard surface) and
      S10 (reply/reaction UI) as a hard prerequisite edge.)
```

### CODEC CHECKPOINT (hard serialization rule)

Protocol-envelope-touching work serializes until the v0.2.1 parser/codec
layer is built and its tests pass in **both stacks**:

- **Go stack:** the test-vector generator codec extended to v0.2.1
  (REACTION + `reply_to` + invalid cases; regenerated `framing.json`;
  CI byte-sync guards green). The relay itself never parses inner
  envelopes (§5.4 outer frame only — done and tested at S3–S5).
- **Dart stack:** `lib/src/protocol` implements the complete v0.2.1 §5
  envelope surface and passes against the committed vectors.

The checkpoint completes at **S10's done-check**. Until then, at most ONE
protocol-envelope-touching session runs at any moment — which the chain
S8 → S9 → S10 enforces naturally, since each is the other's prerequisite.
The rule's real bite: no OTHER session may touch envelope encode/decode
while the chain runs, and after the checkpoint the codec is **frozen** —
later sessions (S11/S12/S14/S15) only consume it. Any post-checkpoint codec
change re-serializes all protocol-touching work until vectors pass again in
both stacks.

---

## Parallel groups (max 3 concurrent; derived earliest-start schedule)

Groups are concurrency sets, not lockstep phases: sessions run at
different speeds, and a still-running session simply keeps occupying one
of the 3 slots when the next group opens. **Three is a ceiling, never a
quota (USER, 2026-07-05):** a group is as wide as the graph safely allows,
no wider — a slot is filled by a legitimate lane or left empty. Every session runs in its own
worktree/branch and merges to main only after code-review + QA pass
(CLAUDE.md parallel rules). QA runs the full cross-stack suite on main
after every merge.

| Group | Sessions (≤3) | Why safe / why not wider |
|---|---|---|
| **G0** (active) | S7 solo | Shared foundation (storage, at-rest crypto, l10n scaffolding, app shell) — prerequisite to every mobile session, never a parallel peer. |
| **G1** | S8 ∥ S13 ∥ **DS** | Disjoint ownership: S8 = transport/protocol/pairing-initiator; S13 = lock/wipe/settings (consumes S7's merged storage API read-only); DS = `designs/` + ARB stub handoff — zero code-tree overlap (USER, 2026-07-05: the legitimate third lane). DS is S7-independent and starts immediately, ahead of G1 formally opening. No fourth candidate exists and none is owed — ceiling, not quota. S9–S12/S14/S15 stay blocked by the S8→S9→S10 chain, S17 by S8 (creation gate), S16/S18/S19 by nearly everything. |
| **G2** | S9 ∥ S17 (∥ S13 if still running) | **Ownership proof:** S9 writes `lib/src/pairing/joiner` + `lib/src/noise` + codec slices in `lib/src/protocol` (protocol; solo-in-class under the checkpoint). S17 writes `lib/src/billing` + the paywall screen + gate wiring at the initiator entry call site — inside S8's **merged** initiator files, which S9's joiner lane never touches. File-disjoint by construction; receivers-never-see-a-paywall (§10) means the gate has no joiner-side surface at all. **Opening condition, verified at S8 wrap:** (a) the pairing tree is actually split `initiator/` vs `joiner/` with no shared mutable pairing scaffolding both sessions would edit; (b) the create-line action is a single call site in an initiator-side/shell file. If either fails: split the scaffolding first, else serialize S17 behind S9 (USER, 2026-07-05: "if shared, split or serialize"). |
| **G3** | S10 (∥ S13/S17 stragglers) | S10 builds the codec — no other protocol-touching work beside it; non-protocol stragglers may finish alongside. |
| **G4** | S11 ∥ S12 — **CONDITIONAL** | Both consume the frozen codec, but both add files inside `lib/src/session`. The split is now a TESTABLE S10 done-check clause (USER, 2026-07-05): composer/bubbles and connection-state in separate files, no shared mutable surface — senior-qa passes/fails it explicitly, so G4's condition is decided at S10's done-check, not by judgment at wrap. S11 owns composer+bubbles, S12 owns connection-state. On the first same-file conflict anyway, serialize S11 → S12. Churn rule applies. |
| **G5** | S14 ∥ S15 (∥ S17 if not yet run) | S14 = screenshot/sensitive; S15 = push client — disjoint modules, both codec consumers only. |
| **G6** | S16 solo | Cross-cutting polish + translation sweep writes across the whole app — no disjointness possible. |
| **G7** | S18 solo | Adversarial pass needs a frozen full surface; its findings can reopen anything. |
| **G8** | S19 solo | Gated on S18 honesty results + USER checkpoints (publish execution, launch copy sign-off). |

### Sessions judged UNSAFE to parallelize (with anything), and why

- **S7** — it IS the shared foundation (storage layer, at-rest crypto,
  l10n scaffolding, app shell). Prerequisite, not a peer, by rule.
- **S8, S9, S10 with each other or any protocol work** — chain-dependent
  by definition, plus the codec checkpoint serializes the envelope layer
  until S10's vectors pass in both stacks.
- **S16** — a polish/microcopy/a11y/translation sweep touches every
  screen; there is no directory it doesn't write.
- **S18** — must observe a frozen product; anything running beside it
  invalidates the pass as it happens, and its findings may reopen any
  session.
- **S19** — serial behind S18 (copy-honesty checks must reflect the final
  adversarial results) and behind two USER checkpoints.
- **S11 ∥ S12** — allowed only under the G4 file-split condition, which is
  now S10's explicit done-check clause (USER, 2026-07-05): unsafe by
  default until senior-qa PASSES that clause at S10.

### Merge hotspots (orchestrator-folded, serially, at merge time)

Shared-write surfaces that would otherwise break directory disjointness.
Parallel sessions never edit the canonical copies directly:

- **`TASKS.md` / `PROGRESS.md` / `DECISIONS.md`** — each parallel session
  appends to `progress/SESSION-N.md`; the orchestrator folds into the
  canonical files at merge time. (USER, 2026-07-05.)
- **`lib/l10n/*.arb`** — every UI session adds strings to all five files.
  Sessions namespace their keys (`pairing_…`, `lock_…`, `billing_…`, …);
  the orchestrator resolves ARB merges at fold-in. Key collisions are a
  blocker, not a merge.
- **`pubspec.yaml` / `pubspec.lock`** — dependency additions are declared
  at session intake (architect sign-off, per standing rules); orchestrator
  union-merges the yaml and regenerates the lock on main after merge.
- **App-shell route registry (`lib/src/app`)** — sessions add screens as
  new files in their own module and list the one-line route registration
  in their progress file; the orchestrator wires registrations at merge.
- **Parent READMEs** (`lib/src/README.md` etc.) — folded at merge like
  the tracking files.

**Churn rule (USER):** merge conflicts twice in a row on the same files →
drop the affected track to serial and note it in PROGRESS.md. Throughput
never outranks correctness.

---

## Session hygiene
- One session = one sitting = one `/clear`. CLAUDE.md stays under a page; link the spec, never paste it.
- Parallel sessions: own worktree/branch named `session-N-<slug>`; append to `progress/SESSION-N.md` during the session; the orchestrator folds tracking files, ARB keys, pubspec, and route registrations at merge, serially. End state per session is unchanged: commit + PROGRESS.md entry (done / decisions / next, via fold-in) + TASKS.md status + README updates for any folder whose contents changed.
- USER question protocol unchanged: consolidate questions per session; conflicting needs across parallel sessions are serialized to USER once by the orchestrator, not twice.

## Milestones
- **M1 (after S6):** relay live and auditable. *(Reached 2026-07-05 in production-shaped form; "live on relay.nimna.app" rides the VPS deferral, USER.)*
- **M2 (after S12):** two real phones talking privately — the demo-to-a-friend moment.
- **M3 (after S18):** honest product.
- **M4 (after S19):** launch-ready. Kill-or-continue checkpoint: 90 days post-launch.
