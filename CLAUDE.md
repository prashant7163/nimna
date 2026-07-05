# Nimna — project context

Paid, account-less, synchronous-only, E2E-encrypted 1:1 messaging — "a
private line between two people." A **stateless Go relay** routes ciphertext
between two live **Flutter** clients and never stores anything.

## Source of truth (in conflict, higher wins; flag conflicts in PROGRESS.md)
1. `docs/nimna-protocol-spec-v0.2.1.md` — THE spec (supersedes v0.2 and
   v0.1.1, kept as history). Wire formats, limits, TTLs, doctrines
   verbatim; no silent protocol "improvements."
2. `nimna-build-plan-v3-sessions.md` — 19 atomic sessions; one session =
   one sitting = one done-check; dependency graph + parallel groups
   (v2 deprecated, kept as history). Governed by
   `nimna-implementation-workloop-prompt.md`.
3. `designs/` — tokens, components, wireframes, hi-fi screens, voice guide.
   BINDING for all UI: implement, don't reinterpret. Canonical microcopy
   only, never lorem ipsum.

## Layout
`application/relay/` Go relay (AGPL-3.0, public at S6) · `application/mobile/`
Flutter app (closed) · `designs/` + `website/` design-loop outputs · `docs/`
spec, test vectors, architecture notes · `temp/` git-ignored scratch.

## Tracking files (the loop's memory — keep them current)
- `TASKS.md` session statuses · `PROGRESS.md` append-only log (+ QA
  sign-off per session) · `DECISIONS.md` append-only, USER vs CODE —
  settled matters are never re-opened. Unsure which kind → USER (ask).
- Stamps are full datetime `YYYY-MM-DD HH:MM +tz` (USER, 2026-07-04) —
  never date-only; local time with UTC offset.

## Standing rules
- **Crypto:** only Session-2-locked primitives; no hand-rolled crypto, ever.
- **Relay statelessness:** at-rest inventory is memory tables + TLS certs +
  push-credential config. Any persistence beyond that = USER decision.
- **Logging:** relay = aggregate metrics, identifier-free; CRIDs/IPs/
  tokens/code-hashes are unloggable wrapper types (CI-asserted). App =
  encrypted local ring-buffer log, events/error-codes only. **No telemetry/
  crash/analytics SDKs anywhere, ever** — not a CODE decision.
- **Dependencies:** minimal, boring, pinned, justified; stdlib-first;
  crypto/network deps need tech-architect sign-off.
- **i18n (USER, 2026-07-04):** launch languages EN/DE/FR/ES/IT — app, store
  listings, website (site EN-default + browser-honoring switcher, zero
  external resources). Every user-facing string via ARB/l10n from the first
  widget — zero hardcoded strings (reviewer-enforced from S7); locale-aware
  dates/times/plurals; layouts survive German-length strings; left/right
  never hardcoded. Protocol/storage code locale-independent — the Nimna
  code renders identically in all locales. Translations are crafted vs the
  voice guide (claim-accuracy exact), PM-reviewed, disputes → USER; app
  pass S16, store+website S19 with per-language copy-honesty checks.
- **Agents:** six roles in `.claude/agents/` (PM, architect, Go dev,
  Flutter dev, reviewer, QA). Pipeline per session: intake → implement →
  code-reviewer (always) → senior-qa done-check (always) → wrap.
- **Parallel sessions (USER, 2026-07-05):** up to 3 concurrent where the
  v3 plan's dependency graph allows — a ceiling, never a quota. Each runs in its own worktree/branch
  (`session-N-<slug>`); merge to main only after that session's
  code-review + QA done-check pass. No cross-branch dependencies — if X
  needs Y's output, they were never parallel. Two parallel sessions never
  write the same directory/module; protocol-envelope work serializes
  until the v0.2.1 codec layer's tests pass in both stacks (checkpoint:
  S10); shared foundations (l10n scaffolding, storage, codec) are
  prerequisites, never peers. TASKS/PROGRESS/DECISIONS are merge
  hotspots: parallel sessions append to `progress/SESSION-N.md`; the
  orchestrator folds into the canonical files serially at merge (same
  fold treatment for ARB keys — namespaced per session — pubspec unions,
  route registrations). Full agent pipeline still applies per session
  before merge; QA also runs the full cross-stack suite on main after
  every merge. USER questions stay consolidated per session; conflicting
  needs across parallel sessions are serialized to USER once by the
  orchestrator. Merge conflicts twice in a row on the same files → drop
  that track to serial, note it in PROGRESS.md — throughput never
  outranks correctness.

## Conventions
- Commits: clear scoped messages, **no Co-Authored-By trailer**. Remote:
  github.com/prashant7163/nimna, branch `main` (user commits may interleave
  — pull-safe).
- Scripts: write to git-ignored `temp/`, never inline heredocs.
- Every hand-authored folder carries a README.md; update it when contents
  change. Exempt: generated trees (mobile `android/`/`ios/` internals,
  build outputs), git-ignored dirs, and `.claude/agents/` (every .md there
  is an agent definition). Leaf asset folders may be covered by a parent
  README index.
- Checks: relay `go build/test/vet ./...` + `gofmt -l .` clean; mobile
  `flutter analyze` + `flutter test` +
  `dart format --output=none --set-exit-if-changed lib test` clean.
