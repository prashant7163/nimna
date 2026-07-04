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
**Status:** in-progress (2026-07-04)

Applies C1, C3, C5, C6 (+ all C-item canonical strings).

Deliverables:
- [ ] Voice & microcopy guide: string 9 rebuilt (subscription + permanence guarantee), screenshot-policy string (C3), "Nimna code" naming sweep (C5), share-sheet briefing line, new-string additions → `/designs/brand/voice-and-microcopy.md`
- [ ] Tokens: media bubble / blurred-state / whisper-dialog / code-entry 3-3-3 grouping additions as needed → `/designs/system/tokens.json`
- [ ] Components: code-entry fixed to 9-char XXX-XXX-XXX (C6), media bubble + transfer progress (C2 strings), blurred sensitive-media state (C4), whisper dialog (C4), screenshot system-line (C3), knock-waiting patience state notes (C8) → `/designs/system/components.md`
- [ ] Brand cheat sheet / color-system / typography touched only where C-item strings or code format appear

## Task U2 — Wireframes & Hi-Fi Screens Sync
**Status:** pending

All C-items → F1 (C1/C3/C9 disclosures), F2/F3 (C5/C6), F5/F6/F7 (C2/C3/C4/C8), F9 (C1); regenerate only changed hi-fi screens; net-new screens: media viewer, blurred-media state, whisper dialog, knocked-waiting; annotations updated with C8 rate-limit edge cases.

## Task U3 — Website Sync
**Status:** pending

Applies C1, C2, C3, C4, C7, C9, C10, C11. Pricing section rebuilt (subscription + permanence guarantee — TASTE CHECKPOINT if structure/visual concept changes), features + media, honesty section extended, /security updated (on-device sensitive content, push token design, abuse posture, AGPL-3.0, code-vs-deployment honesty), FAQ extended (lost phone, Apple/Google visibility, no trial, self-hosting). Full copy re-verification against spec v0.1.1.
