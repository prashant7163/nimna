# Nimna — Design Work Loop Task Board

Single source of truth for loop status. Statuses: pending / in-progress / blocked-on-user / done.
Stamps are full datetime (`YYYY-MM-DD HH:MM +tz`); times before 2026-07-04 15:29 +0200 were backfilled from git history (a line's stamp = its last status-changing commit).

---

## Task 1 — Brand Foundation & Logo
**Status:** done (2026-07-03 21:25 +0200)

Spec sections: design prompt §1 (Brand Foundation), §2 (Logo & App Icon).
Taste Checkpoint A — two pauses: A1 brand direction (after 1.1), A2 logo concept (after 2.1).

Deliverables:
- [x] 1.1 Three brand-direction concepts + recommendation → `/designs/brand/brand-directions.md` (2026-07-03 20:50 +0200)
- [x] **CHECKPOINT A1** — Direction C "The Line" selected (2026-07-03 21:08 +0200)
- [x] 1.2 Color system, dark + light, WCAG AA verified (33/33 pass) → `/designs/brand/color-system.md` (2026-07-03 21:08 +0200)
- [x] 1.3 Typography system (Schibsted Grotesk + Spline Sans Mono) → `/designs/brand/typography.md` (2026-07-03 21:08 +0200)
- [x] 1.4 Voice & microcopy guide (10 strings + honesty checklist) → `/designs/brand/voice-and-microcopy.md` (2026-07-03 21:08 +0200)
- [x] 2.1 Three logo concepts as SVG (wordmark + symbol) → `/designs/brand/logo/concepts/` (2026-07-03 21:17 +0200)
- [x] **CHECKPOINT A2** — Concept 1 "Two Ends" selected (2026-07-03 21:25 +0200)
- [x] 2.2 Refined final logo: 9 SVG variants + usage.md (clear-space, min sizes, mono/inverse, lockups) → `/designs/brand/logo/final/` (2026-07-03 21:25 +0200)
- [x] 2.3 App icons: iOS 1024 master + Android adaptive (bg/fg/monochrome), 48px render-verified → `/designs/brand/app-icon/` (2026-07-03 21:25 +0200)
- [x] `/designs/README.md` + `/designs/brand/README.md` indexes updated (2026-07-03 21:25 +0200)

Completed: 2026-07-03 21:25 +0200

---

## Task 2 — Design System, Wireframes & Hi-Fi Screens
**Status:** done (2026-07-03 21:55 +0200)

Spec sections: design prompt §3 (Design System), §4 (Wireframes F1–F9), §5 (Hi-Fi Screens), §6 (Handoff Notes).

Deliverables:
- [x] 3.1 Spacing/grid, radii, elevation, motion principles → `/designs/system/foundations.md` (2026-07-03 21:55 +0200)
- [x] 3.2 Core components, all states → `/designs/system/components.md` (2026-07-03 21:55 +0200)
- [x] 3.3 Iconography style + 22 icons → `/designs/system/icons/` (2026-07-03 21:55 +0200)
- [x] 4 Annotated wireframes F1–F9, 46 frames, all six mandated edge cases → `/designs/wireframes/` (2026-07-03 21:55 +0200)
- [x] 5.1–5.2 12 hi-fi screens 390×844 dark + 4 light variants, render-verified → `/designs/screens/` (2026-07-03 21:55 +0200)
- [x] 5.3 Design tokens JSON (Flutter ThemeData-ready) → `/designs/system/tokens.json` (2026-07-03 21:55 +0200)
- [x] 6 Flutter handoff notes + asset checklist + brand cheat sheet → `/designs/handoff/` (2026-07-03 21:55 +0200)
- [x] README indexes for system / wireframes / screens / handoff (2026-07-03 21:55 +0200)

Completed: 2026-07-03 21:55 +0200
Open items: paywall price (USER, pending) · FLAG_SECURE stance (build phase)

---

## Task 3 — Website
**Status:** done (2026-07-03 22:23 +0200)

Spec: design prompt "Prompt 2" in full; reuse Task 1–2 tokens/logo/screens verbatim.
Taste Checkpoint B: content outline + hero & relay-diagram visual concepts → pause → build.

Deliverables:
- [x] **CHECKPOINT B** — outline approved; hero H1 "Line Draws Itself"; relay R1 "Glass Relay" (2026-07-03 22:23 +0200)
- [x] index.html — all nine sections, hero H1 animation, R1 glass-relay diagram (2026-07-03 22:23 +0200)
- [x] /privacy, /security, /press sub-pages (2026-07-03 22:23 +0200)
- [x] /assets — self-hosted woff2 fonts (OFL notice), favicon set, OG image, press kit (logos + 3 screenshots) (2026-07-03 22:23 +0200)
- [x] Deployment README + launch checklist (2026-07-03 22:23 +0200)
- [x] Copy self-checked against protocol spec (checklist "Copy honesty" section); link check ALL OK, zero external resources; responsive verified at 390/360px (2026-07-03 22:23 +0200)

Completed: 2026-07-03 22:23 +0200
Open items: store URLs, repo public, hello@nimna.app mailbox, Lighthouse on deployed URL (see website/launch-checklist.md)

---

# UPDATE LOOP — Spec v0.1.1 Sync (opened 2026-07-04 04:30 +0200)

Source of truth: `nimna-protocol-spec-v0.1.1.md` + the C1–C11 changelog in the update prompt.
Rule: work strictly from the changelog; uncovered drift → log in PROGRESS.md ("drift found") and ask, never fix silently.

## Task U1 — Design System & Microcopy Sync
**Status:** done (2026-07-04 04:36 +0200)

Applies C1, C3, C5, C6 (+ all C-item canonical strings).

Deliverables:
- [x] Voice & microcopy guide: strings now 18 — string 9 rebuilt (subscription + permanence, {STORE_PRICE}, no numbers), 11–18 added (screenshot disclosure/notice, share briefing, whisper, blur, stale knock, media, push trade), "Nimna code" naming locked, honesty checklist grown to 10 nevers → `/designs/brand/voice-and-microcopy.md` (2026-07-04 04:36 +0200)
- [x] Tokens v1.1.0: `code` block (9-char, 3-3-3, Crockford), `media` block (5 MB cap, progress line, blurSigma), `mediaVeil` dark+light → `/designs/system/tokens.json` (2026-07-04 04:36 +0200)
- [x] Components: code entry fixed to XXX-XXX-XXX + four join methods + silence doctrine; QR+code simultaneous display; media bubbles (5 states); whisper card; media viewer; screenshot system line; push toggle; knock patience (C8 limits, no counters) → `/designs/system/components.md` (2026-07-04 04:36 +0200)
- [x] Icons 22→24 (`i-doc`, `i-image`, render-verified); color-system + typography + READMEs synced; handoff cheat sheet verified clean (2026-07-04 04:36 +0200)

Completed: 2026-07-04 04:36 +0200

## Task U2 — Wireframes & Hi-Fi Screens Sync
**Status:** done (2026-07-04 05:20 +0200) — F2.4 drift resolved with USER-authored copy (see DECISIONS.md); F3 joiner side checked clean

Deliverables:
- [x] Wireframes 46 → 57 frames (subagent, reviewed + render-verified): F1 +screenshot-consent pane · F2 9 frames (share sheet, call-and-compare, silence doctrine) · F3 four join methods · F5 15 frames (+attach/whisper/media-send/blur/viewer/system-line/stale-knock) · F6/F7 push honesty + string 18 · F9 7 frames (subscription, {STORE_PRICE}, lapsed edge) · F4/F8 C1 sweeps · README synced (2026-07-04 05:20 +0200)
- [x] Hi-fi: 02/03/05/09/10/11 + light variants regenerated; net-new 13-media-viewer, 14-sensitive-blur, 15-whisper-attach; 01 dots 3→4; all screenshot-verified at 390×844 (2026-07-04 05:20 +0200)
- [x] Handoff synced: flutter-notes (media/sensitive/screenshot/paywall/push rows, FLAG_SECURE resolved, background reality), asset checklist, cheat sheet (2026-07-04 05:20 +0200)

## Task U3 — Website Sync
**Status:** done (2026-07-04 05:20 +0200)

Deliverables:
- [x] CHECKPOINT — pricing section: two cards + permanence band + store badges (USER, 2026-07-04 05:20 +0200); built + render-verified desktop/mobile (2026-07-04 05:20 +0200)
- [x] index: How-it-works (Nimna code, KR7-FM2-XQ4), relay sees-list + transient wake-token, 2 media facts, honesty (screenshot notice + push-trade card), FAQ (lost phone rewritten; +media, +Apple/Google, +no-trial, +self-host), footer AGPL-3.0 (2026-07-04 05:20 +0200)
- [x] /security: v0.1.1 sections (code format, silence doctrine, background/rate limits, media, screenshots, sensitive-content, push forwarder-not-registry, device loss, abuse posture, AGPL + code-vs-deployment) (2026-07-04 05:20 +0200)
- [x] /privacy (push rewrite, content-scanning row) + /press (facts rebuilt) (2026-07-04 05:20 +0200)
- [x] Launch checklist: price item retired, copy-honesty section re-verified against v0.1.1 (2026-07-04 05:20 +0200)
- [x] Link check ALL OK, zero external resources; stale-term sweep clean (2026-07-04 05:20 +0200)

---

# IMPLEMENTATION LOOP — Build Plan v2 (opened 2026-07-04 06:03 +0200)

Plan: `nimna-build-plan-v3-sessions.md` (v3 2026-07-05 02:43 +0200 — structure only, USER: dependency graph + parallel groups, normative source v0.2.1, DONE commit refs; v2 deprecated as history) · Rules: `nimna-implementation-workloop-prompt.md` + CLAUDE.md "Parallel sessions" (USER, 2026-07-05) · Spec: `docs/nimna-protocol-spec-v0.2.1.md` (v0.2 locked at S2, 2026-07-04; v0.2.1 reconciliation 2026-07-05 02:20 +0200 — REACTION, reply_to, restored §3.1 doctrines; v0.2 and v0.1.1 kept as history).
One session = one sitting = one done-check; code-reviewer + senior-qa sign-off required before done; up to 3 sessions concurrent per the v3 parallel groups (worktree per session, fold-in at merge). Statuses: pending / in-progress / blocked-on-user / done.

## Phase 0 — Foundations
- **Session 1 — Scaffolding & conventions: done** (2026-07-04 06:03 +0200) — skeletons (Go relay + Flutter app, all checks clean) · agent fleet ×6 · CI ×2 · CLAUDE.md · spec copied to docs/ · reviewer blockers fixed · QA done-check PASS · i18n scope addition (USER) logged & propagated
- **Session 2 — Crypto selection & spec v0.2: done** (2026-07-04 13:44 +0200) — USER checkpoint held, all four choices locked as recommended (X25519/ChaCha20-Poly1305/SHA-256+HKDF/Argon2id · Noise XXpsk2-from-spec + commitment + code-psk, fail-closed · KK + per-message rekey · 3-word global EFF wordlist) · 45-bit check HOLDS (Argon2id date-salted topics required) · spec v0.2 committed, supersedes v0.1.1 · docs/test-vectors: 5 JSON suites + pinned wordlist + committed Go generator (third-party Noise 64/64, RFC vectors, byte-identical regeneration) + CI drift guard · reviewer REOPEN→PASS · QA done-check PASS · flagged: PEER_OFFLINE wire removal (USER veto window), screen-03 wordlist design-sync
## Phase 1 — Relay (Go)
- **Session 3 — Connections & rendezvous: done** (2026-07-04 15:27 +0200) — WebSocket relay (coder/websocket v1.8.15) with 18-byte §5.4 outer frame, silent topic registry (first-two-bridge, no tombstones, 24h janitor), verbatim PAIR_DATA forwarding, unloggable ident types, cmd/testclient with real §3.1.2 Argon2id derivation · architecture note docs/architecture/relay-architecture.md (binding S3–S6) · reviewer REOPEN→PASS (B1 transport-close carve-out adjudicated by architect, §5.1) · QA done-check PASS (live rendezvous, relay silence, -race suite)
- **Session 4 — Channels, knock, sessions, push forwarding: done** (2026-07-04 17:05 +0200) — CRID registry + KNOCK/ACCEPT/TEARDOWN/SESSION_DATA bridging (23-row edge table, state-dependent rejections all silent), 60 s pending knocks with deliver-on-register, structurally content-free push forwarding (Sender has no content parameter; bounded dispatcher; config-gated HTTP sink — real APNs/FCM deferred to S6, stdlib-only design signed off), testclient knock/answer roles · reviewer PASS zero blockers (S1 comment + N1 note fixes applied) · QA done-check PASS (exactly one push per eligible knock, relay silent at 3 lifecycle lines, memory provably empty)
- **Session 5 — Hardening, rate limits & observability: done** (2026-07-04 21:28 +0200) — spec §4 limits as config with spec-verbatim defaults (per-IP conns 64, frame 50/s burst 100, max frame 128 KiB, rendezvous 6/min/IP, knock 10 s collapse, push 60 s/6 hr/20 day per CRID in a bounded evicting table, reg cap 256/plane, idle 90 s), silence-preserving enforcement (over-cap connect = zero-byte refusal, new class beside §5.1, empty-vs-loaded covering test; all shared-state limits silent), liveness via last-inbound-byte listener wrapper (pings count structurally), identifier-free Prometheus-text metrics on 127.0.0.1:9441 ops listener, recover-and-scrub, CI log-scrub + x/crypto-free assertions, cmd/soak · reviewer PASS zero blockers (5 mutations caught; 4 nits applied) · QA done-check PASS (accelerated 20-min soak: heap ratio 0.992, post-drain gauges zero; overnight deviation reported per note §21)
- **Session 6 — Deploy & open-source release: done** (2026-07-05 01:05 +0200) — USER checkpoint: prepare now, publish at S19 · TLS on the public listener (stdlib, TLS 1.3, hot cert reload, TCP→limits→TLS→HTTP), /healthz + version, real APNs/FCM transports (stdlib ES256/RS256 JWTs, mock-verified; live check deferred to S15, USER), deploy kit (systemd unit, relay.env.example, build.sh, certbot hook, RUNBOOK — "live on relay.nimna.app" deferred until a VPS exists, USER, logged), public-repo readiness (AGPL-3.0 "The Nimna Authors", audit-map README, CONTRIBUTING, spec copy + vendored vectors w/ CI byte-sync, public ci.yml, publish runbook) · reviewer PASS zero blockers (6 mutations, 5 caught → 7 findings applied, padding test now deterministic) · QA done-check PASS (local production-shaped TLS deploy, 9/9 boot-fatal matrix pre-bind, split-sim standalone green, silence audit clean)
## Phase 2 — App core (Flutter)
- **Session 7 — Skeleton & encrypted local storage: in-progress** (2026-07-05 01:18 +0200) · i18n: ARB/l10n wiring from the first widget — zero hardcoded user-facing strings (reviewer-enforced S7 onward)
- **Design-sync DS — reply/reaction UI, canonical strings + ARB stubs, self-join F3: done** (2026-07-05 04:03 +0200) — G1 third lane (USER 2026-07-05 02:58); designs/ synced to v0.2.1: voice strings 19–21 (canonical strings byte-locked), 4 new components (reaction chip w/ hostile-UTF-8 clamp, message-actions card, quoted-reply preview, self-join own-code state), frames 57→62 (F5.16–19, F3.8 EDGE), hi-fi 05+16, 12 namespaced ARB keys in designs/handoff/ · emoji presets confirmed (USER 03:30) · reviewer PASS zero blockers (S1/S2 + 6 nits applied; self-join distinctness adjudicated spec-mandated) · QA done-check PASS 9/9 own-evidence · merged --no-ff · **ARB key fold into lib/l10n executes at S7 merge (in-flight)** · S9/S10 design prereqs satisfied
- Session 8 — Pairing: initiator side: pending
- Session 9 — Pairing: joiner side & handshake: pending · needs DS (self-join guard surface; USER 2026-07-05)
- Session 10 — Live text messaging: pending · needs DS (reply/reaction UI) · USER done-check addition (2026-07-05 02:58 +0200): lib/src/session decomposed per-concern (composer/bubbles vs connection-state, separate files, no shared mutable surface) — senior-qa passes/fails explicitly; gates S11 ∥ S12
- Session 11 — Media & documents: pending
- Session 12 — Knock, presence, offline-compose, reconnect: pending
## Phase 3 — Discretion features
- Session 13 — App lock & panic wipe: pending
- Session 14 — Screenshot policy & sensitive-content handling: pending · CODE-within-rails: Android sensitive-content path
- Session 15 — Notifications end-to-end: pending
## Phase 4 — Ship
- Session 16 — Polish & first-run: pending · i18n: crafted DE/FR/ES/IT app translation pass vs voice guide (PM-reviewed; disputed renderings → USER)
- Session 17 — Subscription & paywall: pending
- Session 18 — Adversarial pass & test suite: pending · USER scope addition (2026-07-05 02:20 +0200): hand-implemented Noise engine cross-verified against an established Go Noise library (e.g. flynn/noise) as a TEST ORACLE — test-only, never a runtime dependency, in addition to the committed vector sets
- Session 19 — Store prep & launch assets: pending · USER checkpoints: publish execution, launch copy sign-off · i18n: store listings ×5 languages, localized text-bearing screenshots, website in all five (EN default + language switcher), launch-checklist copy-honesty verification run per language

Milestones: M1 relay live (post-S6) · M2 two phones talking (post-S12) · M3 honest product (post-S18) · M4 launch-ready (post-S19). Terminal deliverable: `PUBLISH_READY.md`.
