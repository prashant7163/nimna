# Nimna — Design Work Loop Task Board

Single source of truth for loop status. Statuses: pending / in-progress / blocked-on-user / done.

---

## Task 1 — Brand Foundation & Logo
**Status:** done (2026-07-03)

Spec sections: design prompt §1 (Brand Foundation), §2 (Logo & App Icon).
Taste Checkpoint A — two pauses: A1 brand direction (after 1.1), A2 logo concept (after 2.1).

Deliverables:
- [x] 1.1 Three brand-direction concepts + recommendation → `/designs/brand/brand-directions.md` (2026-07-03)
- [x] **CHECKPOINT A1** — Direction C "The Line" selected (2026-07-03)
- [x] 1.2 Color system, dark + light, WCAG AA verified (33/33 pass) → `/designs/brand/color-system.md` (2026-07-03)
- [x] 1.3 Typography system (Schibsted Grotesk + Spline Sans Mono) → `/designs/brand/typography.md` (2026-07-03)
- [x] 1.4 Voice & microcopy guide (10 strings + honesty checklist) → `/designs/brand/voice-and-microcopy.md` (2026-07-03)
- [x] 2.1 Three logo concepts as SVG (wordmark + symbol) → `/designs/brand/logo/concepts/` (2026-07-03)
- [x] **CHECKPOINT A2** — Concept 1 "Two Ends" selected (2026-07-03)
- [x] 2.2 Refined final logo: 9 SVG variants + usage.md (clear-space, min sizes, mono/inverse, lockups) → `/designs/brand/logo/final/` (2026-07-03)
- [x] 2.3 App icons: iOS 1024 master + Android adaptive (bg/fg/monochrome), 48px render-verified → `/designs/brand/app-icon/` (2026-07-03)
- [x] `/designs/README.md` + `/designs/brand/README.md` indexes updated (2026-07-03)

Completed: 2026-07-03

---

## Task 2 — Design System, Wireframes & Hi-Fi Screens
**Status:** done (2026-07-03)

Spec sections: design prompt §3 (Design System), §4 (Wireframes F1–F9), §5 (Hi-Fi Screens), §6 (Handoff Notes).

Deliverables:
- [x] 3.1 Spacing/grid, radii, elevation, motion principles → `/designs/system/foundations.md` (2026-07-03)
- [x] 3.2 Core components, all states → `/designs/system/components.md` (2026-07-03)
- [x] 3.3 Iconography style + 22 icons → `/designs/system/icons/` (2026-07-03)
- [x] 4 Annotated wireframes F1–F9, 46 frames, all six mandated edge cases → `/designs/wireframes/` (2026-07-03)
- [x] 5.1–5.2 12 hi-fi screens 390×844 dark + 4 light variants, render-verified → `/designs/screens/` (2026-07-03)
- [x] 5.3 Design tokens JSON (Flutter ThemeData-ready) → `/designs/system/tokens.json` (2026-07-03)
- [x] 6 Flutter handoff notes + asset checklist + brand cheat sheet → `/designs/handoff/` (2026-07-03)
- [x] README indexes for system / wireframes / screens / handoff (2026-07-03)

Completed: 2026-07-03
Open items: paywall price (USER, pending) · FLAG_SECURE stance (build phase)

---

## Task 3 — Website
**Status:** done (2026-07-03)

Spec: design prompt "Prompt 2" in full; reuse Task 1–2 tokens/logo/screens verbatim.
Taste Checkpoint B: content outline + hero & relay-diagram visual concepts → pause → build.

Deliverables:
- [x] **CHECKPOINT B** — outline approved; hero H1 "Line Draws Itself"; relay R1 "Glass Relay" (2026-07-03)
- [x] index.html — all nine sections, hero H1 animation, R1 glass-relay diagram (2026-07-03)
- [x] /privacy, /security, /press sub-pages (2026-07-03)
- [x] /assets — self-hosted woff2 fonts (OFL notice), favicon set, OG image, press kit (logos + 3 screenshots) (2026-07-03)
- [x] Deployment README + launch checklist (2026-07-03)
- [x] Copy self-checked against protocol spec (checklist "Copy honesty" section); link check ALL OK, zero external resources; responsive verified at 390/360px (2026-07-03)

Completed: 2026-07-03
Open items: store URLs, repo public, hello@nimna.app mailbox, Lighthouse on deployed URL (see website/launch-checklist.md)

---

# UPDATE LOOP — Spec v0.1.1 Sync (opened 2026-07-04)

Source of truth: `nimna-protocol-spec-v0.1.1.md` + the C1–C11 changelog in the update prompt.
Rule: work strictly from the changelog; uncovered drift → log in PROGRESS.md ("drift found") and ask, never fix silently.

## Task U1 — Design System & Microcopy Sync
**Status:** done (2026-07-04)

Applies C1, C3, C5, C6 (+ all C-item canonical strings).

Deliverables:
- [x] Voice & microcopy guide: strings now 18 — string 9 rebuilt (subscription + permanence, {STORE_PRICE}, no numbers), 11–18 added (screenshot disclosure/notice, share briefing, whisper, blur, stale knock, media, push trade), "Nimna code" naming locked, honesty checklist grown to 10 nevers → `/designs/brand/voice-and-microcopy.md` (2026-07-04)
- [x] Tokens v1.1.0: `code` block (9-char, 3-3-3, Crockford), `media` block (5 MB cap, progress line, blurSigma), `mediaVeil` dark+light → `/designs/system/tokens.json` (2026-07-04)
- [x] Components: code entry fixed to XXX-XXX-XXX + four join methods + silence doctrine; QR+code simultaneous display; media bubbles (5 states); whisper card; media viewer; screenshot system line; push toggle; knock patience (C8 limits, no counters) → `/designs/system/components.md` (2026-07-04)
- [x] Icons 22→24 (`i-doc`, `i-image`, render-verified); color-system + typography + READMEs synced; handoff cheat sheet verified clean (2026-07-04)

Completed: 2026-07-04

## Task U2 — Wireframes & Hi-Fi Screens Sync
**Status:** done (2026-07-04) — F2.4 drift resolved with USER-authored copy (see DECISIONS.md); F3 joiner side checked clean

Deliverables:
- [x] Wireframes 46 → 57 frames (subagent, reviewed + render-verified): F1 +screenshot-consent pane · F2 9 frames (share sheet, call-and-compare, silence doctrine) · F3 four join methods · F5 15 frames (+attach/whisper/media-send/blur/viewer/system-line/stale-knock) · F6/F7 push honesty + string 18 · F9 7 frames (subscription, {STORE_PRICE}, lapsed edge) · F4/F8 C1 sweeps · README synced (2026-07-04)
- [x] Hi-fi: 02/03/05/09/10/11 + light variants regenerated; net-new 13-media-viewer, 14-sensitive-blur, 15-whisper-attach; 01 dots 3→4; all screenshot-verified at 390×844 (2026-07-04)
- [x] Handoff synced: flutter-notes (media/sensitive/screenshot/paywall/push rows, FLAG_SECURE resolved, background reality), asset checklist, cheat sheet (2026-07-04)

## Task U3 — Website Sync
**Status:** done (2026-07-04)

Deliverables:
- [x] CHECKPOINT — pricing section: two cards + permanence band + store badges (USER, 2026-07-04); built + render-verified desktop/mobile (2026-07-04)
- [x] index: How-it-works (Nimna code, KR7-FM2-XQ4), relay sees-list + transient wake-token, 2 media facts, honesty (screenshot notice + push-trade card), FAQ (lost phone rewritten; +media, +Apple/Google, +no-trial, +self-host), footer AGPL-3.0 (2026-07-04)
- [x] /security: v0.1.1 sections (code format, silence doctrine, background/rate limits, media, screenshots, sensitive-content, push forwarder-not-registry, device loss, abuse posture, AGPL + code-vs-deployment) (2026-07-04)
- [x] /privacy (push rewrite, content-scanning row) + /press (facts rebuilt) (2026-07-04)
- [x] Launch checklist: price item retired, copy-honesty section re-verified against v0.1.1 (2026-07-04)
- [x] Link check ALL OK, zero external resources; stale-term sweep clean (2026-07-04)

---

# IMPLEMENTATION LOOP — Build Plan v2 (opened 2026-07-04)

Plan: `nimna-build-plan-v2-sessions.md` · Rules: `nimna-implementation-workloop-prompt.md` · Spec: `docs/nimna-protocol-spec-v0.1.1.md` (v0.2 supersedes at S2).
One session = one sitting = one done-check; code-reviewer + senior-qa sign-off required before done. Statuses: pending / in-progress / blocked-on-user / done.

## Phase 0 — Foundations
- **Session 1 — Scaffolding & conventions: done** (2026-07-04) — skeletons (Go relay + Flutter app, all checks clean) · agent fleet ×6 · CI ×2 · CLAUDE.md · spec copied to docs/ · reviewer blockers fixed · QA done-check PASS · i18n scope addition (USER) logged & propagated
- Session 2 — Crypto selection & spec v0.2: pending · USER checkpoint: crypto choices presented before locking
## Phase 1 — Relay (Go)
- Session 3 — Connections & rendezvous: pending
- Session 4 — Channels, knock, sessions, push forwarding: pending
- Session 5 — Hardening, rate limits & observability: pending
- Session 6 — Deploy & open-source release: pending · USER checkpoint: repo publish timing
## Phase 2 — App core (Flutter)
- Session 7 — Skeleton & encrypted local storage: pending · i18n: ARB/l10n wiring from the first widget — zero hardcoded user-facing strings (reviewer-enforced S7 onward)
- Session 8 — Pairing: initiator side: pending
- Session 9 — Pairing: joiner side & handshake: pending
- Session 10 — Live text messaging: pending
- Session 11 — Media & documents: pending
- Session 12 — Knock, presence, offline-compose, reconnect: pending
## Phase 3 — Discretion features
- Session 13 — App lock & panic wipe: pending
- Session 14 — Screenshot policy & sensitive-content handling: pending · CODE-within-rails: Android sensitive-content path
- Session 15 — Notifications end-to-end: pending
## Phase 4 — Ship
- Session 16 — Polish & first-run: pending · i18n: crafted DE/FR/ES/IT app translation pass vs voice guide (PM-reviewed; disputed renderings → USER)
- Session 17 — Subscription & paywall: pending
- Session 18 — Adversarial pass & test suite: pending
- Session 19 — Store prep & launch assets: pending · USER checkpoints: publish execution, launch copy sign-off · i18n: store listings ×5 languages, localized text-bearing screenshots, website in all five (EN default + language switcher), launch-checklist copy-honesty verification run per language

Milestones: M1 relay live (post-S6) · M2 two phones talking (post-S12) · M3 honest product (post-S18) · M4 launch-ready (post-S19). Terminal deliverable: `PUBLISH_READY.md`.
