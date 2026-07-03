# Nimna — Design Work Loop Task Board

Single source of truth for loop status. Statuses: pending / in-progress / blocked-on-user / done.

---

## Task 1 — Brand Foundation & Logo
**Status:** in-progress (opened 2026-07-03; consolidated question list issued)

Spec sections: design prompt §1 (Brand Foundation), §2 (Logo & App Icon).
Taste Checkpoint A — two pauses: A1 brand direction (after 1.1), A2 logo concept (after 2.1).

Deliverables:
- [ ] 1.1 Three brand-direction concepts + recommendation → `/design/brand/brand-directions.md`
- [ ] **CHECKPOINT A1** — user selects direction
- [ ] 1.2 Color system, dark + light, WCAG AA verified → `/design/brand/color-system.md`
- [ ] 1.3 Typography system (Flutter/Google Fonts-compatible) → `/design/brand/typography.md`
- [ ] 1.4 Voice & microcopy guide (10 real strings) → `/design/brand/voice-and-microcopy.md`
- [ ] 2.1 Three logo concepts as SVG (wordmark + symbol) → `/design/brand/logo/concepts/`
- [ ] **CHECKPOINT A2** — user selects logo concept
- [ ] 2.2 Refined final logo: clear-space, min sizes, mono/inverse, lockups → `/design/brand/logo/final/`
- [ ] 2.3 App icons: iOS + Android adaptive layers, 48px legibility check → `/design/brand/app-icon/`
- [ ] `/design/README.md` + `/design/brand/README.md` indexes updated

Completed: —

---

## Task 2 — Design System, Wireframes & Hi-Fi Screens
**Status:** pending

Spec sections: design prompt §3 (Design System), §4 (Wireframes F1–F9), §5 (Hi-Fi Screens), §6 (Handoff Notes).
No taste checkpoints; front-load user questions before starting.

Deliverables:
- [ ] 3.1 Spacing/grid, radii, elevation, motion principles → `/design/system/`
- [ ] 3.2 Core components, all states → `/design/system/components.md`
- [ ] 3.3 Iconography style + ~20 icons → `/design/system/icons/`
- [ ] 4 Annotated wireframes F1–F9 → `/design/wireframes/`
- [ ] 5.1–5.2 12 hi-fi screens, HTML/CSS 390×844, dark-first + 4 light variants → `/design/screens/`
- [ ] 5.3 Design tokens JSON (Flutter ThemeData-ready) → `/design/system/tokens.json`
- [ ] 6 Flutter handoff notes + asset checklist + brand cheat sheet → `/design/handoff/`
- [ ] README indexes for system / wireframes / screens / handoff

Completed: —

---

## Task 3 — Website
**Status:** pending

Spec: design prompt "Prompt 2" in full; reuse Task 1–2 tokens/logo/screens verbatim.
Taste Checkpoint B: content outline + hero & relay-diagram visual concepts → pause → build.

Deliverables:
- [ ] **CHECKPOINT B** — content outline + hero/relay-diagram concepts approved
- [ ] index.html (hero, how-it-works, architecture, live-only, discretion, honesty, pricing, FAQ, footer)
- [ ] /privacy, /security, /press sub-pages
- [ ] /assets (self-hosted fonts, logo, screenshots, favicons, OG image)
- [ ] Deployment README + launch checklist (Lighthouse ≥95, link check, meta tags)
- [ ] Copy self-checked against protocol spec for overclaiming

Completed: —
