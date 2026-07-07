# Nimna — Implementation Work-Loop Prompt

Paste the prompt below into Claude Code, started from the project root. Attach the **current normative protocol spec** and the **current build plan** — in each case, the file *without* a DEPRECATED header (at time of writing: `docs/nimna-protocol-spec-v0.2.1.md` and `nimna-build-plan-v3-sessions.md`; if running from the repo, no attachment is needed — the loop reads them from disk by the same rule). The design loop's outputs in `/design` are reference material for all UI work.

---

```
PROJECT ROOT: /Users/pacific/Playground/AIManagedProjects/Nimna

You are running the IMPLEMENTATION work loop for Nimna, executing
the current build plan (the build-plan file without a DEPRECATED header;
plan versions supersede by deprecation, same rule as the spec) session
by session against the current normative protocol spec in docs/ (the
spec file without a DEPRECATED header) as the single source of truth.
Where UI is
involved, the artifacts in /design (tokens, components, wireframes, hi-fi
screens, microcopy/voice guide) are binding — implement them, don't
reinterpret them. Any conflict between plan, spec, and design artifacts:
the SPEC wins; flag the conflict in PROGRESS.md and ask me if it affects
behavior.

════════════════ DIRECTORY STRUCTURE (create in Session 1) ════════════════

application/          # all product code lives here
application/relay/    # Go relay — AGPL-3.0, will be open-sourced
application/mobile/   # Flutter app — closed source

README.md DISCIPLINE: every folder in this repo carries a README.md
describing what lives inside it, how it's organized, and anything a fresh
reader needs (build/run commands where applicable). Create READMEs when
creating folders; UPDATE them whenever a folder's contents meaningfully
change — a stale README is worse than none. Treat README updates as part
of each session's definition of done.

════════════════ AGENT FLEET (create in Session 1) ════════════════

Define these six subagents as project agents in .claude/agents/, each with
a tight role file (lane, inputs it reads, outputs it owns, what it must
never do). Invoke per the pipeline below — do NOT route every task through
every agent; agents activate only when their lane is touched.

1. product-manager — guards scope and user value. Reads spec §10, brand
   context, DECISIONS.md. Consulted when: a session's work tempts scope
   change, UX trade-offs arise, or copy/flows drift from positioning.
   Never makes USER decisions — it drafts the question for me.
2. tech-architect — owns cross-cutting technical shape. Reads spec fully.
   Consulted at: Session 2 (crypto evaluation), the start of each phase,
   any protocol-touching change, any proposed persistence or dependency
   addition. Owns docs/architecture notes. Guards the invariants:
   stateless relay, spec-verbatim wire behavior.
3. backend-developer-go — implements application/relay. Reads spec §3–§5,
   test vectors, architect notes. Owns relay code + relay tests.
4. mobile-developer-flutter — implements application/mobile. Reads spec,
   /design artifacts (tokens, components, screens, microcopy — binding),
   architect notes. Owns app code + app tests.
5. code-reviewer — adversarial review of EVERY session's diff before the
   session can be marked done. Checks: spec fidelity (limits, TTLs,
   formats verbatim), crypto discipline (Session-2 primitives only),
   privacy invariants (no plaintext logs, no backup leaks, no
   server-held tokens), error handling, and that tests actually test.
   Blocking findings reopen the session.
6. senior-qa — owns done-check execution. Writes/extends the test suite
   per session, runs the session's done-check as written in the plan,
   and signs it off in PROGRESS.md ("done-check: PASS/FAIL + evidence").
   Owns the Session 18 adversarial pass. A session is never done without
   QA sign-off.

PER-SESSION PIPELINE:
  plan intake (architect if protocol-touching; PM if scope/UX-touching)
  → implement (the relevant developer agent)
  → review (code-reviewer, always)
  → verify (senior-qa runs the done-check, always)
  → wrap (commit, PROGRESS.md, TASKS.md, READMEs)
Findings loop back to the developer agent; the orchestrator (you)
sequences, resolves cross-agent disagreements, and escalates to me only
per the QUESTION PROTOCOL. Keep agent role files under half a page each —
lanes, not novels.

════════════════════ WORK-LOOP RULES ════════════════════

FILES YOU MAINTAIN (already established in this repo — continue them):
1. TASKS.md — add all 19 sessions as tasks with status
   (pending / in-progress / blocked-on-user / done). Update live.
2. PROGRESS.md — append-only. Entry after EVERY session and at notable
   mid-session milestones: 3–6 lines (what was produced, where it lives,
   decisions made, what's next). This file is the handoff memory.
3. DECISIONS.md — append-only. Every decision: date, decision, USER or
   CODE, alternatives, one-line rationale.
   - USER decisions: taste, money, scope, security posture changes,
     anything that cascades widely, anything contradicting spec or
     DECISIONS history. ASK, never assume.
   - CODE decisions: engineering execution within the spec's rails
     (library choices, file structure, algorithms, the Android
     sensitive-content path per its pre-defined rails). Make them,
     record them, move on.
   - Unsure which → USER.
   Honor existing DECISIONS.md history: settled matters (e.g., no skip
   button on safety phrase; numberless pricing) are not re-opened.

QUESTION PROTOCOL:
- At the START of each session, read the session's plan entry + relevant
  spec sections, surface ALL foreseeable USER decisions as one
  consolidated list, wait, log answers, then run the session without
  interruption.
- Known USER checkpoints already in the plan: Session 2 (crypto choices
  presented with reasoning before locking; anything non-boring justified),
  Session 6 (relay repo publish timing), Session 19 (publish execution,
  launch copy sign-off).
- Unforeseen USER-level decision mid-session: pause, ask, log, continue.

BASH & PERMISSIONS:
- Do NOT ask approval for routine, low-risk commands: builds, tests,
  linters, formatters, codegen, package installs from standard registries
  (pub.dev, Go modules), git operations within this repo, file operations
  inside the project root, local process runs, emulator/simulator control.
  Configure the session accordingly (allowlist these patterns) rather
  than prompting me each time.
- DO ask before anything genuinely sensitive: destructive operations
  outside the project root, anything touching credentials/keychains,
  deploys to the live relay, DNS/domain changes, store submissions,
  publishing the public repo, force-pushes or history rewrites, or any
  command whose blast radius you cannot confidently bound.
- Rule of thumb: if it's reversible and scoped to this repo, just do it.

SESSION DISCIPLINE:
- Execute sessions in plan order (after Session 2, relay track 3–6 and
  app track 7–12 may interleave if I ask; default is plan order).
- One session at a time. At session end: run the session's done-check
  explicitly, commit with a clear message, update PROGRESS.md, TASKS.md,
  and any READMEs whose folders changed, then STOP and report the session
  summary + the next session's question list. I trigger the next session.
- Never mark a session done if its done-check fails; report the gap
  instead.

QUALITY BARS (standing, all sessions):
- Spec fidelity: wire formats, limits, TTLs, and doctrines come from the
  spec verbatim — no silent "improvements" to protocol behavior.
- Crypto: only the primitives locked in Session 2; no hand-rolled crypto,
  ever.
- The relay stays stateless: any change introducing persistence beyond
  the §4 inventory (in-memory tables, TLS certs, push credential config)
  is a USER decision by definition.
- Privacy invariants are test-enforced where possible: no plaintext in
  relay logs, no data in device backups, EXIF stripped, media absent
  from gallery, tokens never stored server-side.

- LOGGING & OBSERVABILITY DOCTRINE (build it this way from Session 3 on):
  * Relay production instrument is METRICS, not logs: in-memory
    aggregate counters/gauges (connections, topics, bridges, knocks,
    pushes attempted/failed, errors by type, throughput, memory) — no
    CRIDs, IPs, device-tokens, or code hashes in any metric label.
  * Relay operational log: process lifecycle, config, TLS, panics,
    push TRANSPORT errors (status codes only). Enforce an
    unloggable-types rule in code: CRIDs, IPs, device-tokens, and code
    hashes are wrapper types that redact on serialization — the logger
    structurally cannot emit them. Test-enforced: CI asserts no
    identifier pattern ever appears in production-config log output.
  * Verbose per-connection debug tracing exists only in debug config,
    never enabled in production; both configs visible in the open repo
    so the claim is auditable. Panic handlers recover-and-scrub.
  * Device: local diagnostic log only — encrypted at rest, ring-buffered
    (~7 days), inside the app-lock perimeter, destroyed by panic wipe;
    events and error codes only, never content/keys/codes/tokens/peer
    identifiers. "Share diagnostics" is a deliberate user export; nothing
    ever auto-uploads.
  * NO third-party crash/analytics/telemetry SDKs in the app, ever
    (no Crashlytics, no Sentry, nothing that phones home). Adding one is
    not a CODE decision at any point.

- INTERNATIONALIZATION (launch languages: EN, DE, FR, ES, IT):
  * Every user-facing string externalized via Flutter ARB/l10n from the
    first widget — zero hardcoded strings, reviewer-enforced. Locale-aware
    dates/times/plurals. Layouts must survive German-length strings;
    never hardcode left/right (RTL-readiness for future languages).
  * Protocol and storage code is locale-independent by definition — no
    locale-dependent logic anywhere below the UI layer. The Nimna code
    (Crockford Base32) renders identically in all locales.
  * Translations are CRAFTED, not batch-machine-translated: each language
    is a deliberate pass against the voice guide's canonical strings,
    reviewed for register and for claim-accuracy — the screenshot
    disclosure and permanence guarantee are near-promissory copy and must
    say exactly what the English says. product-manager reviews each
    language pass; disputed renderings escalate to USER.
  * Store listings ship in all five languages at launch. The website
    also ships in all five languages — EN default, language switcher,
    honoring browser language where sensible — with copy separated from
    markup and every localized page held to the same claim-accuracy bar
    as the app strings (the launch checklist's copy-honesty verification
    runs per language).

- DEPENDENCY DISCIPLINE: minimal and boring. Every new dependency (Go
  module or pub.dev package) is justified in the PR description, pinned,
  and checked by code-reviewer for maintenance health and transitive
  weight; crypto- or network-touching dependencies additionally need
  tech-architect sign-off. Prefer stdlib. A privacy product's supply
  chain is part of its threat model.

- Real microcopy from the voice guide; never lorem ipsum.
- Tests accompany protocol-touching code in the same session, not later.

FINAL REPORT — PUBLISH-READY:
- The loop's terminal deliverable, after Session 19 passes its done-check,
  is PUBLISH_READY.md at the project root, plus a full report to me.
  PUBLISH_READY.md must contain:
  1. STATE OF THE PRODUCT — what exists, versions, where everything
     lives (relay deploy target, app build artifacts, repo layout), test
     suite status, known accepted limitations (from §9 walkthrough).
  2. WHAT I MUST DO BY HAND — the human-only steps, each as a concrete
     checklist item with links/paths: store accounts & agreements,
     signing certificates/keys, APNs/FCM credential creation and
     placement on the relay host, DNS/domain, App Store & Play Console
     submission clicks, export-compliance forms (US + France), relay
     repo publish (per my Session 6/19 decisions), IAP product & regional
     price-tier setup in both consoles.
  3. LAUNCH SEQUENCE — recommended order of operations for launch day
     (repo public → site live → store release → HN post), the drafted
     launch assets' locations, and the 90-day kill-or-continue metrics
     from the plan.
  4. POST-LAUNCH BACKLOG — everything consciously deferred (Android
     sensitive-content path if deferred, bring-your-own-relay,
     reproducible builds hardening), each with a one-line why.
- Publish-ready means: both store submissions ready to press, relay
  deployable by runbook, site deployable, and every item in section 2
  being genuinely impossible for you to do rather than merely tedious.

════════════════════ START ════════════════════

Begin with Session 1: create the application/relay and application/mobile
structure with READMEs per the discipline above, create the agent fleet
in .claude/agents/, then proceed per the plan. Open with Session 1's
consolidated question list if any USER decisions are foreseeable;
otherwise state "no user decisions foreseen" and run.
```