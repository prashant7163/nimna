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

## 2026-07-03 — TASK 3 COMPLETE · ALL THREE TASKS DONE
- Checkpoint B: USER approved outline as proposed, hero H1 "Line Draws Itself", relay R1 "Glass Relay".
- Built website/: index (9 sections) + /privacy + /security + /press, tokens verbatim from designs/system, fonts self-hosted (latin woff2 + OFL notice), zero external requests, dark default + light via prefers-color-scheme, reduced-motion honored throughout.
- Assets: favicon set + og.png generated from brand; press kit (3 logo SVGs, 512px icon, 3 screen PNGs cropped from hi-fi mockups).
- Verified: link check ALL OK / zero external resources (temp/check_links.py); responsive at true 390px & 360px via iframe test (fixed a real relay-diagram overflow found in testing); copy honesty self-check vs spec recorded in website/launch-checklist.md.
- Launch blockers intentionally left as placeholders: store URLs, repo must go public, hello@nimna.app mailbox, Lighthouse run on the deployed URL.

## 2026-07-04 — Paywall model corrected (USER)
- USER clarification: there is NO free created line — creating any channel requires the one-time unlock; free users join and talk both ways, forever. Supersedes the 2026-07-03 "first line free / paywall at second create / free-slot counting" model (see DECISIONS.md 2026-07-04).
- New voice string 9 headline: "Creating a line is the only thing that costs. Pay once for as many as you like."
- Propagated: voice-and-microcopy.md string 9 · screens 09-paywall dark+light · wireframes F2.1/F4.1/F4.4/F9 (header, trigger, annotations, 3× headline) · wireframes README · website pricing cards + FAQ · press fact sheet.
- NOT edited (user-authored prompt doc, per decision-log precedent): nimna-design-and-website-prompts.md still says "F9 Paywall: first initiated channel free" — flagged to USER to amend or leave.
- Open item unchanged: paywall price (USER, pending).

## 2026-07-04 — UPDATE LOOP opened: spec v0.1.1 sync (C1–C11)
- Read nimna-protocol-spec-v0.1.1.md in full + C1–C11 changelog; loaded TASKS/PROGRESS/DECISIONS state.
- Three sync tasks registered in TASKS.md (U1 system+microcopy · U2 wireframes+screens · U3 website).
- Spec v0.1.1 closes two open items from the first loop: FLAG_SECURE is deliberately NOT used (spec §5.2, matching our 2026-07-03 recommendation), and the paywall-price question is retired — spec §10 mandates regional store pricing with NO number published anywhere (paywall renders the store's localized string; designs carry {STORE_PRICE}). C1 also supersedes the 2026-07-04 one-time-unlock correction — model is now a yearly subscription with the permanence guarantee.
- Task U1 opened; front-loaded two USER questions: safety-phrase skip (answer: keep no-skip) and price display (answer: numberless — independently confirmed by the updated spec).
- Mid-open, USER updated nimna-protocol-spec-v0.1.1.md and nimna-design-update-workloop-prompt.md on disk (C1 refined to the no-number doctrine); both re-read in full before any artifact edits. Root MEMORY.md source-of-truth pointer now names v0.1.1 (user edit).

## 2026-07-04 — TASK U1 COMPLETE (system & microcopy sync)
- Voice guide: 10 → 18 strings. String 9 rebuilt around "One of you buys the line. The other never pays." + permanence guarantee as headline + {STORE_PRICE}; new canonical strings for screenshot disclosure/in-thread notice (C3), share-sheet briefing (C5, verbatim), sensitive-content whisper + blur (C4, verbatim), stale-knock hint (C9), media/metadata/cap (C2), push trade (C7), knock patience (C8). "Nimna code" locked as the only UI name; words-we-avoid extended (pairing code, one-time/unlock/pay once, any price number). Honesty checklist 4 → 10 nevers.
- Components: code entry rewritten for the permanent 9-char XXX-XXX-XXX format (drawn hyphens, Crockford normalization, four join methods, silence doctrine in the error state); QR display = one simultaneous surface; NEW media bubbles (sending/receiving/waiting/blurred/disappearing — progress is a 2px line, no percentages), whisper card (explicitly not a modal), media viewer (export as the deliberate act), screenshot system line, push toggle (caption IS the disclosure); knock-waiting rebuilt to invite patience (no Knock affordance during the 60s window; rate limits never surfaced as counters).
- Tokens v1.1.0: code + media blocks, mediaVeil both modes (verified by mechanism, not ratio — noted in color-system.md). No price token exists by doctrine.
- Icons 22 → 24: i-doc, i-image drawn in the monoline DNA, qlmanage render-verified.
- Process slip, self-caught: one inline `python3 -c` used for a preview.html edit despite the temp/-scripts rule; noted, not repeated.
- Next: Task U2 (wireframes + hi-fi screens). No foreseeable USER questions — all taste was settled at loop open; will pause only if real drift surfaces.

## 2026-07-04 — TASK U2 COMPLETE (wireframes via subagent + hi-fi screens) · TASK U3 COMPLETE (website)
- U2 hi-fi: 02/03/05/09/10/11 regenerated (+ light variants via sed) — 9-char hyphenated code, four join affordances on 10, "Call them and compare" on 03, media bubble + "They took a screenshot." system line in 05, paywall rebuilt around string 9 with literal {STORE_PRICE}, patience caption on 11; net-new 13-media-viewer / 14-sensitive-blur / 15-whisper-attach. All 13 changed/new files screenshot-verified at 390×844. Code-entry geometry corrected mid-build (32→30px segments; 348px row fits 350px content width) — tokens/components/CSS kept in lockstep.
- U2 wireframes (subagent, reviewed against its report + renders of F5/F9): 46 → 57 frames; every C-item applied; README index/decisions/edge-map resynced. Notably good: F9.5 restore edge annotates store-receipt-as-only-memory; F5.6 whisper card annotates the §5.3 hard boundary verbatim.
- U2 handoff: flutter-notes gained media/sensitive-content/screenshot/paywall rows; FLAG_SECURE marked RESOLVED per §5.2; background-grace + no-auto-retry noted; icons 24.
- U3 (checkpoint answered mid-U2 wait: two cards + permanence band + store badges): index/security/privacy/press/launch-checklist all synced to v0.1.1 (details in TASKS.md). Verified: link check ALL OK · zero external resources · stale-term sweep clean ("pairing code" survives only in /security's technical register, deliberate) · pricing section render-checked desktop + 500px (standalone-section harness in temp/, since the 88vh hero defeats tall-window full-page shots and old headless ignores fragment scroll) · one brand fix: italic <em> removed from marketing copy (no-italics rule).
- **DRIFT FOUND (wireframes F2.4, awaiting USER):** caption "You can put the phone away — we'll be here." + annotation claiming rendezvous listening survives OS connection kills. Spec v0.1.1 §3.3 closes the socket ~30 s after backgrounding, and no push path exists during pairing (tokens exchange only inside an established channel) — the caption overpromises background presence. Not fixed silently, per loop rules; question issued.
- Commits: b076b0b (screens+handoff), 353632a (website); wireframes commit follows the drift answer.

## 2026-07-04 — Drift resolved (USER) · update loop closed
- F2.4 rewritten with USER-authored copy: "Waiting for them to join…" / "Your code works for 24 hours — come back anytime. Pairing completes when you're both here." Annotation now records the ~30 s grace, H(code) re-registration on reopen, and the deliberate absence of push during pairing. The adjacent F2.3 "never stopped listening" annotation softened to the same standard (grace-window honest).
- Per USER instruction, F3's joiner side checked for the same overpromise: **none found** — F3.3 is a sub-second bridge frame; "Found them." renders only at match; its drop-mid-handshake edge already states codes are spent on failure. Logged as drift-checked-clean.
- Decision recorded as USER entry in DECISIONS.md (binding pattern for app copy at build time: pairing copy promises the code's lifetime, never background presence).
- Note for spec v0.2 consideration: hi-fi screen 02's on-surface caption still says "Waiting for them to join…" only (no background promise — already clean).

## 2026-07-04 — Both protocol flags RESOLVED (USER) · prompts doc archived
- Flag 1 (expired vs never-existed): USER decides expired = used = never-existed to the joiner — ONE generic response for all three; differing responses would let a prober confirm a code once existed (silence doctrine extended); carry into spec v0.2. Propagated: F3.7 reworked from "special-case expired state" to a decision-documentation frame rendering identically to F3.6 (QR-expiry-hint idea withdrawn); components.md code-entry error state; voice-guide register note; wireframes README index row + honesty note marked RESOLVED.
- Flag 2 (lapsed-knock attribution): USER decides lapsed knocks carry NO attribution — knocker sees exactly "No answer.", never offline vs saw-and-ignored (receiver's plausible deniability outranks knocker's closure); carry into spec v0.2. Propagated: F5.13 caption corrected from "They didn't pick up." (a real leak — it implied the knock reached them); attribution-neutral rule pinned in voice guide + components session-indicator; README honesty note marked RESOLVED covering both directions. Scope note: string 5's "They're not on the line right now" (compose-time offline state, spec §3.4) is untouched — the decision governs lapsed knocks, and the outbox UX is spec-sanctioned presence.
- nimna-design-and-website-prompts.md → docs/archive/ via git mv, with a superseded-provenance header (USER); never synced again, per decision.
- Process note: USER acknowledged the logged temp/-rule slips as the system working; rule unchanged.
