# Nimna — Progress Log (append-only)

## 2026-07-03 — Loop initialized
- Read all three source docs in full (brand-context, protocol spec v0.1, design & website prompts) plus the build-plan for context.
- Created TASKS.md / PROGRESS.md / DECISIONS.md / MEMORY.md; git initialized.
- Task 1 opened; consolidated question list issued to user (wordmark casing, icon discretion level, accent-color leanings, typography flavor).
- Next: answers → 1.1 three brand directions → Checkpoint A1.

## 2026-07-03 — 1.1 Brand directions produced; Checkpoint A1 reached
- Front-loaded Task 1 answers logged: lowercase wordmark, quietly-branded icon, accent + type proposed per direction.
- Produced three directions: A "The Fine Object" (quiet luxury, brass/ember, Fraunces+Instrument Sans), B "Deep Water" (nimn etymology, ink indigo/lamp gold, Martel+Mukta), C "The Line" (protocol-as-motif, near-black/incandescent amber, Schibsted Grotesk). Recommended C.
- Lives in designs/brand/brand-directions.md + direction-previews.html (browser side-by-side).
- Next: user selects direction → 1.2 color, 1.3 type, 1.4 voice → 2.1 logo concepts → Checkpoint A2.

## 2026-07-03 — A1: Direction C locked; 1.2–1.4 done; 2.1 logo concepts; Checkpoint A2 reached
- USER selected Direction C "The Line" at A1.
- 1.2 color system (dark hero + light "amber ink on paper"), all 33 WCAG pairings verified programmatically (temp/contrast_final.py). 1.3 type: Schibsted Grotesk + Spline Sans Mono for codes. 1.4 voice guide: 10 strings + protocol-honesty checklist. All in designs/brand/.
- 2.1: three logo concepts, custom monoline wordmark (drawn, not typeset): "Two Ends" (recommended), "The Dash", "The Headstroke". SVGs + logo-previews.html in designs/brand/logo/concepts/. Concept-3 first draft (stems touching headstroke) killed for legibility — read "hlmhd".
- Next: A2 selection → 2.2 refine logo → 2.3 app icons → Task 1 done.

## 2026-07-03 — TASK 1 COMPLETE
- A2: USER selected Concept 1 "Two Ends". 2.2: nine final SVGs (lockup/wordmark/symbol × dark/light/mono) + usage.md in designs/brand/logo/final/. 2.3: iOS 1024 master + Android adaptive bg/fg/monochrome layers + app-icon.md in designs/brand/app-icon/; 48px legibility render-verified.
- Full brand foundation now in designs/brand/ (directions, color, type, voice, logo, icons), all READMEs current.
- Next: Task 2 (design system → wireframes F1–F9 → 12 hi-fi screens → handoff). Front-loading user questions (wipe style, paywall presentation, lock-screen posture) before starting.

## 2026-07-03 — TASK 2 COMPLETE
- USER front-loads: hold-to-wipe, full-screen paywall, zero-leak lock. System: foundations + components + 22 icons + tokens.json (designs/system/). Screens: 12 dark + 4 light hi-fi HTML at 390×844, token-exact, Chrome-render-verified (designs/screens/). Handoff: flutter-notes, asset checklist, brand cheat sheet (designs/handoff/). Wireframes (subagent, reviewed): 46 annotated frames F1–F9, all six mandated edge cases (designs/wireframes/).
- Mid-task USER decisions: safety-phrase has no skip; free slot = ever-initiated (wipe doesn't reset).
- PROTOCOL FLAGS (from wireframe review, for spec v0.2): (1) joiner-side "expired vs never-existed" code states are indistinguishable to a stateless relay — a distinct expired UI needs a QR-carried expiry hint or stays folded into the wrong-code error, as wireframed; (2) after a lapsed knock from a cold open, the app cannot attribute the knocker (content-free push) — named strings only apply to knocks seen while connected, as wireframed.
- Open items: paywall price (USER), FLAG_SECURE (build phase).
- Next: Task 3 website — Checkpoint B (outline + hero/relay concepts).
