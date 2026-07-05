# Nimna — Loop Memory (resume notes)

**What this project is:** Nimna — paid, account-less, synchronous-only, E2E-encrypted 1:1 messaging ("a private line between two people"). The design loop (brand+logo, design system/screens, website) and its v0.1.1 update loop are DONE. Now running: the **IMPLEMENTATION LOOP** — 19 atomic sessions per `nimna-build-plan-v2-sessions.md`, rules in `nimna-implementation-workloop-prompt.md`, spec `docs/nimna-protocol-spec-v0.2.1.md` as single source of truth (v0.2 locked at S2 2026-07-04; v0.2.1 reconciliation 2026-07-05 added REACTION + reply_to + restored §3.1 duplicate-channels/self-join doctrines; v0.2 and v0.1.1 kept as history). S2 locked the crypto: X25519 · ChaCha20-Poly1305 · SHA-256/HKDF · Argon2id; pairing Noise XXpsk2-from-spec + commitment + code-psk (fail-closed); sessions Noise KK + per-message rekey; 3-word EFF-short-2.0 phrase, locale-independent; test vectors + committed generator in `docs/test-vectors/`.

**Implementation loop conventions (opened 2026-07-04):** stack Go relay (`application/relay`, module `nimna.app/relay`, AGPL-3.0 at S6) + Flutter app (`application/mobile`, package `nimna`, IDs `app.nimna`). Agent fleet in `.claude/agents/` (PM, architect, Go dev, Flutter dev, reviewer, QA); per-session pipeline: intake → implement → code-reviewer → senior-qa done-check → wrap (commit + PROGRESS + TASKS + READMEs). Repo-root CLAUDE.md orients fresh sessions. USER checkpoints ahead: S6 relay publish timing, S19 launch execution (S2 crypto lock: done 2026-07-04). One session per sitting; USER triggers the next. **I18N (USER 2026-07-04):** launch EN/DE/FR/ES/IT — app, store listings, website (EN-default + browser-honoring switcher); ARB/l10n from first widget, zero hardcoded strings (reviewer-enforced S7+); protocol/storage locale-independent; crafted PM-reviewed translations (app pass S16; store+website+per-language honesty checks S19).

**Source of truth (read before resuming):**
- `brand-context.md` — personality (quiet luxury, calm, discreet), HARD AVOIDS (no locks/shields/spy/matrix/neon-green/fingerprints/"military-grade"/fear marketing), 6 product rituals.
- `docs/nimna-protocol-spec-v0.2.1.md` — designs must never contradict it (v0.2/v0.1.1 are deprecated history). Key constraints: no accounts/profiles/contact lists, no server storage, no history sync, synchronous-only, relay DOES see IPs/timing/CRIDs/ciphertext sizes (honesty is a brand asset), disappearing messages are honor-system (UX must say so), push is content-free + opt-in + default-off, pairing code single-use w/ TTL, knock TTL ~60s, safety phrase encouraged not enforced.

**Conventions:**
- Outputs: `/designs` (tasks 1–2), `/website` (task 3), each dir README-indexed.
- Real microcopy always, never lorem ipsum. Spec beats visual ambition; flag conflicts in PROGRESS.md.
- Commit every logical chunk + after every task. Update TASKS.md on every status change; append PROGRESS.md at milestones; every decision → DECISIONS.md (USER for taste/brand/money/scope; CODE for routine execution).
- Taste checkpoints: A1 (brand direction), A2 (logo concept), B (website outline + hero/relay-diagram concepts). Pause + set TASKS.md blocked-on-user at each.
- Report in full to user only after all three tasks are done.

**Locked brand (Task 1, do not re-decide):**
- Direction C "The Line": the line motif renders protocol states — dotted grey offline, breathing amber knock, solid amber live, cut on wipe. Amber is rationed (session state, one primary action/screen, i-dot, timer glyph — never decorative). No green anywhere.
- Palette dark (hero): surface #0B0B0C/#141416/#1B1B1E, text #E8E6E1/#A8A6A0/#7C7A75, accent #F2A65A (onAccent #201305), danger #E0655A (fill #8C2F27), lineIdle #6E6E74. Light: paper #F7F5F2, text #1C1B19, single accent "amber-ink" #96581A (onAccent #FFF). Full tokens: designs/brand/color-system.md (all WCAG-verified via temp/contrast_final.py).
- Type: Schibsted Grotesk 400/500/600 only + Spline Sans Mono 500 for codes/safety phrase. Scale in designs/brand/typography.md. No italics, no all-caps except 11px micro overlines.
- Logo: "Two Ends" ●—● + custom monoline lowercase wordmark, amber i-dot. Finals in designs/brand/logo/final/ (usage.md has clear-space/min-size/don'ts). Icons: designs/brand/app-icon/. Sub-12px degradation = the dash.
- Voice: phone-call register (line/knock/pick up/hang up), facts not vows, admits limits plainly. Canonical strings: designs/brand/voice-and-microcopy.md.

**Workflow notes:** run Python via files in git-ignored temp/ (never inline heredocs); qlmanage -t renders SVG→PNG for visual checks; user commits may appear between mine (pull-safe: remote = origin/main).

**Current state:** see TASKS.md (single source of truth for status).
