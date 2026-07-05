> **DEPRECATED — historical record only. The active plan is
> [`nimna-build-plan-v3-sessions.md`](nimna-build-plan-v3-sessions.md).**

# Nimna Build Plan v2 — Atomic Claude Code Sessions (synced to spec v0.1.1)

**Supersedes** the original session plan. Deltas absorbed: Go relay (decided), media & docs in v1 (§5.1), screenshot detect-and-notify (§5.2), sensitive-content handling (§5.3), token-in-knock push design (§3.2.1), 30s background grace (§3.3), 9-char XXX-XXX-XXX Nimna code (§4), knock/push rate limits (§4), device-loss doctrine (§6.1), regional subscription pricing via store tiers with the permanence guarantee (§10), AGPL-3.0 relay licensing with credentials-as-config (§4).

**Structure:** one session = one atomic sitting = one clear deliverable + done-check. `/clear` between sessions. Sessions sized context-friendly.

**Stack (locked):** Relay in **Go** (single static binary). App in **Flutter/Dart** (iOS + Android). Single small VPS/Fly.io instance. Monorepo layout:

```
Nimna/
├── application/
│   ├── relay/      # Go relay (AGPL-3.0, open-sourced at Session 6)
│   └── mobile/     # Flutter app (closed source)
├── designs/         # produced by the design loop
├── website/        # produced by the design loop
├── docs/           # spec + protocol test vectors
├── TASKS.md  PROGRESS.md  DECISIONS.md  CLAUDE.md
```

Every folder carries a README.md describing its contents — maintained as content evolves, not written once and forgotten.

---

## Phase 0 — Foundations

### Session 1 — Scaffolding & conventions
- Create the `application/relay` and `application/mobile` skeletons (Go module; Flutter project), READMEs in every folder, repo-root CLAUDE.md (<1 page: project context, conventions, spec pointer), CI lint/test skeleton for both stacks.
- Create the agent fleet in `.claude/agents/` per the work-loop prompt: product-manager, tech-architect, backend-developer-go, mobile-developer-flutter, code-reviewer, senior-qa — half-page role files each.
- Copy spec v0.1.1 and (later) protocol test vectors into `docs/`.
- **Done when:** both projects build empty; every folder has a README; agent fleet exists; CLAUDE.md orients a fresh session in one read.

### Session 2 — Crypto selection & spec v0.2
- Evaluate primitives against spec §7 (authenticated agreement, AEAD, forward secrecy/ratchet, safety phrase, replay protection; Dart + Go library maturity; audit pedigree). Expected territory: X25519, ChaCha20-Poly1305, HKDF, possibly Noise framework. Anything exotic requires explicit justification to USER.
- Verify the 9-char/45-bit code space + relay throttling trade holds under the chosen handshake; flag to USER if not.
- Lock choices → spec v0.2 with concrete handshake sequence and exact wire framing (byte layout). Write protocol test vectors into `docs/`.
- **Done when:** spec v0.2 committed; test vectors exist; handshake explainable on one whiteboard.

## Phase 1 — Relay (Go)

### Session 3 — Connections & rendezvous
- WebSocket server, connection lifecycle, in-memory registries, `H(code)` rendezvous topics with 24h TTL, first-come-wins bridging, topic death on completion.
- **Done when:** two CLI test clients rendezvous via a code hash and exchange raw frames.

### Session 4 — Channels, knock, sessions, push forwarding
- CRID registration; `KNOCK {crid, peer_device_token?}` / `ACCEPT` / `PEER_OFFLINE` / `HANGUP`; knock TTL (60s); bridge teardown; keepalive pings; 30s background-grace expiry semantics.
- Stateless push forwarding per §3.2.1: offline peer + device-token in knock → one APNs/FCM call ("New activity", content-free) → token discarded. Credentials via config slots only (env/mounted files), never in repo.
- **Done when:** CLI clients pair, disconnect, knock (with and without token), accept, chat, hang up — relay memory empty after; a mock push sink receives exactly one content-free call per eligible knock.

### Session 5 — Hardening, rate limits & observability
- Spec §4 limits as config with defaults: per-IP connection caps, frame-rate caps, max frame size (must accommodate MEDIA_CHUNK), rendezvous throttling (single-digit/min/IP), knock 1/10s/CRID, push 1/min + 6/hr + 20/day per CRID (in-memory counters, reset on restart). Structured errors, graceful shutdown, soak-test script.
- Observability per the work-loop doctrine: aggregate metrics endpoint (no identifiers in labels), sanitized operational log with **unloggable wrapper types** for CRIDs/IPs/device-tokens/code-hashes (redact on serialization, CI-asserted), debug-only tracing config, recover-and-scrub panic handlers.
- **Done when:** abuse scripts bounce off every limit; overnight soak shows flat memory; CI log-scrub assertion passes; metrics answer "is the relay healthy" without touching a single identifier.

### Session 6 — Deploy & open-source release
- Single-binary deploy + TLS to the VPS (relay.nimna.app), health endpoint, minimal ops runbook.
- Public-repo readiness: AGPL-3.0 LICENSE, README leading with the zero-storage claim and how to audit it (§4 inventory: routing tables in memory, TLS certs, push credentials as deployment config), config.example with empty push slots, .gitignore guard, contribution note. Publish timing = USER decision.
- **Done when:** relay live on domain; repo publishable as-is.

## Phase 2 — App core (Flutter)

### Session 7 — Skeleton & encrypted local storage
- App scaffold, navigation shell, encrypted local DB (channel store, message store, media store per §6), platform keystore integration, cloud-backup exclusion flags verified on both platforms.
- Local diagnostic log per the work-loop doctrine: encrypted, ring-buffered (~7 days), app-lock perimeter, wiped by panic wipe, events/error-codes only.
- **Done when:** app boots, persists encrypted records across restart, data provably absent from device backups; diagnostic log demonstrably contains no content/keys/codes/tokens.

### Session 8 — Pairing: initiator side
- Keypair + 9-char Crockford Base32 code generation, XXX-XXX-XXX display, simultaneous QR render, share sheet with the §3.1 one-liner ("Works once, expires in 24h — share it like a password"), rendezvous registration, waiting state, TTL expiry handling.
- **Done when:** app creates a Nimna code and holds rendezvous against a CLI peer.

### Session 9 — Pairing: joiner side & handshake
- All four join methods: manual XXX-XXX-XXX entry, paste, live QR scan, QR upload (image/PDF). Key exchange per spec (device-token included in encrypted payload when push enabled), safety-phrase derivation + comparison screen (two buttons only — match / don't match; no skip button, per DECISIONS), channel finalization, code discard, silence doctrine (no failed-attempt surfacing).
- **Done when:** two devices pair end-to-end via each join method; MITM test vector rejected; phrase screen matches the design-loop artifacts.

### Session 10 — Live text messaging
- Session UI, encrypt/frame/send TEXT (5,000-char soft cap, transparent chunking), receive/decrypt/ACK, delivery states (waiting → sent → delivered), typing indicators, HANGUP, per-message expiry (sender-dictated) honored on both ends with the honest honor-system copy.
- **Done when:** two paired devices exchange E2E text live; debug relay logs show ciphertext only; expiry round-trips.

### Session 11 — Media & documents
- Attach flow: images + PDFs/files, 5 MB cap, client-side compression default with original-quality toggle, EXIF/metadata strip before encryption, MEDIA_CHUNK chunking with encrypted manifest (count + content hash), reassembly + integrity check + ACK, transfer progress UI, media viewer, encrypted-store quarantine (never gallery; export = deliberate act), expiry applies to media.
- **Done when:** photo and PDF round-trip between devices; EXIF verifiably stripped; media absent from gallery/photo backups; expired media vanishes on both ends.

### Session 12 — Knock, presence, offline-compose, reconnect
- Knock/accept UX with the rate-limit-aware "knocked — waiting" state (no auto-retry, ever); PEER_OFFLINE handling; local waiting-outbox auto-flush on bridge; 30s background grace; reconnect logic; device-token refresh via CONTROL frames in live sessions; per-channel push opt-in (default off) with honest one-line trade explanation; stale-knock local hint (§6.1 sugar).
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
- **Done when:** locked phone receives contentless nudge on knock; disabling push per-channel results in zero third-party touch for that channel.

## Phase 4 — Ship

### Session 16 — Polish & first-run
- Onboarding (3 screens max, incl. screenshot-policy and permanence disclosures per design), empty/error states, app icon + name, dark mode, accessibility pass, microcopy sweep against the voice guide.
- "Share diagnostics" in settings: deliberate user export of the scrubbed local log — nothing ever auto-uploads; no third-party SDKs anywhere (verify the dependency tree).
- **Done when:** a stranger goes install → paired chat unaided; dependency tree contains zero telemetry/analytics/crash SDKs.

### Session 17 — Subscription & paywall
- Yearly auto-renewing subscription via StoreKit 2 / Play Billing, priced by regional store tiers — the app NEVER hardcodes a price; paywall renders the store-provided localized string ({STORE_PRICE} in designs). Creation gated on active entitlement, checked on-device only (accepted §10 limitation: no server-side receipt validation — the relay learns nothing). Receivers never see a paywall. Permanence guarantee honored structurally: lapse gates creation only, existing channels untouched. Restore as a first-class flow (reinstall + new-device-same-store-account tested). Family Sharing disabled.
- **Done when:** sandbox subscribe/lapse/restore all behave per §10 on both platforms; a lapsed account's existing channels work forever.

### Session 18 — Adversarial pass & test suite
- Threat-model walkthrough vs §9 incl. new rows: replay, MITM, malformed frames + fuzzing (relay and app), storage/backup inspection, screenshot-notice suppression honesty, push-bombing vs rate limits, EXIF-strip verification, wipe forensics.
- **Done when:** every §9 row has a passing test or a documented accepted limitation.

### Session 19 — Store prep & launch assets
- Store listings (positioning per brand: "a private line between two people — nothing stored anywhere, ever"; model described without price numbers — stores display price), privacy questionnaires ("data collected: none"), proactive review notes (E2E media precedent, §9 structural abuse posture, why zero storage), export-compliance declarations (US + France form), screenshots from design artifacts, launch checklist, HN launch draft ("the ~300-line relay" post), relay repo publish decision executed per USER call.
- **Done when:** both store submissions ready to press; launch post drafted.

---

## Session hygiene
- One session = one sitting = one `/clear`. CLAUDE.md stays under a page; link the spec, never paste it.
- End every session: commit + PROGRESS.md entry (done / decisions / next) + TASKS.md status + README updates for any folder whose contents changed.
- After Session 2, the relay track (3–6) and app track (7–12) are parallelizable if desired.

## Milestones
- **M1 (after S6):** relay live and auditable.
- **M2 (after S12):** two real phones talking privately — the demo-to-a-friend moment.
- **M3 (after S18):** honest product.
- **M4 (after S19):** launch-ready. Kill-or-continue checkpoint: 90 days post-launch.
