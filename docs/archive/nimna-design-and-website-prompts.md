# Nimna — Design & Website Prompts

> **SUPERSEDED — provenance only (archived 2026-07-04, USER decision).**
> This is the original Task 1–3 prompt set, written against protocol spec v0.1 and the
> pre-subscription pricing model. It is deliberately NOT synced to later spec versions —
> its value is historical. Governing sources today: `nimna-protocol-spec-v0.1.1.md`
> (and successors) at the project root, plus the work-loop prompts. Known stale content
> includes: "first initiated channel free" paywall, one-time-unlock language, and the
> pre-v0.1.1 code-format assumptions.

Two prompts, meant to run as separate Claude Code sessions (or with any design-capable agent). Prompt 1's outputs feed Prompt 2, so run them in order.

---

## Prompt 1 — Design Specs (logo, branding, wireframes, screens)

```
ROLE: You are a senior brand designer and mobile product designer producing a
complete, implementation-ready design specification for Nimna. The Brand
Context above and the attached protocol spec are your source of truth. Where
the spec defines a flow (pairing, knock/accept, sessions, wipe), the design
must follow it exactly — do not invent features that contradict the protocol
(e.g., no "message history sync," no contact lists, no profiles).

DELIVERABLE: A single design-spec package, organized as the following
numbered outputs. Work through them in order; each builds on the previous. store the content in 'designs' folder at the project root.

── 1. BRAND FOUNDATION ──
1.1 Three distinct brand-direction concepts (mood, adjectives, references),
    each honoring the Brand Personality. Recommend one with reasoning.
    Directions to explore (not prescriptive): (a) "quiet luxury / analog
    object," (b) "Sanskrit-rooted minimalism" drawing on the nimn etymology,
    (c) "the line" — literal line/thread/wire as the core motif.
1.2 For the recommended direction: full color system (primary, surface,
    text hierarchy, semantic states incl. the knock/live-session accent),
    specified for BOTH light and dark mode — dark mode is the hero mode for
    this product. WCAG AA contrast verified.
1.3 Typography system: typeface selection (must be available for Flutter/
    Google Fonts or openly licensable), full type scale (display → caption),
    weights, line heights. Should read calm and editorial, not techy.
1.4 Voice & microcopy guide: 10 example strings showing the tone (onboarding
    lines, empty states, the wipe confirmation, the honor-system disclaimer
    for disappearing messages, the offline-peer state).

── 2. LOGO & APP ICON ──
2.1 Three logo concepts as SVG: wordmark + symbol. Symbol ideas must avoid
    the Hard Avoids list. Fertile territory: two elements meeting (two dots,
    two strokes forming a channel), a horizontal "line," negative space,
    Devanagari-inspired geometry (subtle, respectful, abstract).
2.2 Recommend one; refine it: clear-space rules, minimum sizes, mono/inverse
    variants, wordmark-only and symbol-only lockups.
2.3 App icon: adaptations for iOS and Android (incl. Android adaptive icon
    layers). Test at 48px — must stay legible and, per brand, look
    *unremarkable* on a home screen: discreet, not attention-grabbing.

── 3. DESIGN SYSTEM (MOBILE) ──
3.1 Spacing/grid system, corner radii, elevation/shadow rules, motion
    principles (durations, easing; motion should feel like breathing, not
    bouncing).
3.2 Core components with all states (default/pressed/disabled/error):
    buttons, text inputs, the code-entry field, QR display & scanner frame,
    chat bubbles (sent/received/waiting/delivered/disappearing-countdown),
    the knock banner/sheet, session status indicator (offline / knocking /
    live), list rows for channels, modals, toasts.
3.3 Iconography style definition + the ~20 icons the app needs.

── 4. WIREFRAMES (LOW-FI, FLOWS FIRST) ──
Wireframe every screen of these flows as annotated low-fi frames, in order:
    F1 First-run onboarding (3 screens max, explains: what it is / how
       pairing works / what we cannot see).
    F2 Create channel: generate code → share (QR + copy) → waiting → paired
       → safety-phrase comparison → channel ready.
    F3 Join channel: enter/scan code → handshake → safety phrase → ready.
    F4 Channel list (locked and unlocked states; labels are user-edited,
       purely local).
    F5 Chat session: peer offline (compose-to-outbox) → knock sent → peer
       accepts → live session → hangup. Include disappearing-message
       composer control (sender-dictated, per message).
    F6 Receiving a knock (in-app and from the content-free push).
    F7 Channel settings: label edit, notifications opt-in, read-receipt/
       typing toggles, per-channel wipe.
    F8 App settings: app lock setup, full panic wipe (design the confirmation
       to be fast but unmistakable), relay info, licenses.
    F9 Paywall: first initiated channel free; one-time unlock for unlimited.
       No account, no email — design the IAP + restore flow accordingly.
Annotate every wireframe with: purpose, entry/exit points, edge cases
(code expired, peer never accepts, connection drops mid-session, knock
TTL lapses, wrong code, IAP restore on reinstall).

── 5. HIGH-FIDELITY SCREENS ──
5.1 Apply the brand system to the 12 most important screens from the flows
    above (must include: onboarding-1, create-code, safety phrase, channel
    list, live chat, knock received, disappearing composer, panic wipe
    confirm, paywall). Dark mode first; light mode variants for 4 key
    screens.
5.2 Produce each as a clean HTML/CSS mockup (one file per screen, mobile
    viewport 390×844) so they can be screenshotted and iterated. Pixel
    values must follow the design system tokens exactly.
5.3 A tokens file (JSON) capturing colors, type scale, spacing, radii —
    named for direct translation into Flutter ThemeData.

── 6. HANDOFF NOTES ──
Flutter implementation notes per component (suggested widgets, any custom
painting needed, motion specs), asset export checklist, and a one-page
"brand cheat sheet" for future sessions.

WORKING RULES:
- Read the protocol spec fully before starting; flag any design decision
  that has protocol implications instead of silently deciding.
- Present 1.1 and 2.1 (the divergent options) and PAUSE for my selection
  before continuing to refinement. Everything else proceeds without pausing.
- All assets as files in an organized directory tree with a README index.
- Never use placeholder lorem ipsum for microcopy — write real, on-voice
  strings everywhere; copy is part of the design.
```

---

## Prompt 2 — Nimna Website

```
ROLE: You are a senior web designer/developer building the public website for
Nimna. Inputs: the Brand Context, the protocol spec, and the design-spec
package from the previous session (brand system, logo, tokens, screens —
reuse them faithfully; the website must feel like the same object as the app).

GOAL: A modern, creative, informative single-product site whose job is:
(1) make the "nothing stored anywhere, ever" architecture instantly
understood, (2) convert two audiences — the discretion buyer who needs calm
reassurance, and the technical reader who wants to verify claims, (3) drive
App Store / Play Store installs. Domain: nimna.app. Store the content in 'website' folder at the project root.

STRUCTURE (single scrolling page + three sub-pages):

MAIN PAGE, in order:
  1. HERO — the positioning line, one striking visual metaphor for "a private
     line between two people" (consider: an animated line connecting two
     points that vanishes when broken; keep it subtle), two store buttons.
  2. HOW IT WORKS — the pairing ritual in 3 illustrated steps (code → knock →
     live line). This section should feel like explaining a codeword game,
     warm not technical.
  3. THE ARCHITECTURE IS THE PROMISE — the section for skeptics. A creative,
     interactive diagram of the relay: show a message traveling as opaque
     ciphertext through a stateless relay, with plain-language callouts of
     what the relay can and cannot see (mirror spec §4 and §6 honestly,
     including what IS visible: IPs, timing, ciphertext sizes). Include the
     "no accounts / no storage / no logs — verify it yourself" open-source
     relay link (GitHub).
  4. LIVE-ONLY, BY DESIGN — reframe the synchronous constraint as the
     feature it is: "not a worse messenger — not a messenger at all; a text
     call." Short, confident.
  5. DISCRETION FEATURES — app lock, sender-dictated disappearing messages,
     panic wipe, content-free notifications. Present as calm facts.
  6. HONESTY SECTION — a distilled, human-readable version of the threat
     model table (spec §9), including limitations. Title it something like
     "What Nimna does not protect you from." This section is a trust weapon;
     design it prominently, not as fine print.
  7. PRICING — free to join channels forever; one-time unlock to create
     unlimited. No subscription. No account. One payer per pair.
  8. FAQ — 8–10 questions incl.: "Why must we both be online?", "What if I
     lose my phone?", "Can you read my messages?" (answer: architecturally
     no — link the repo), "Why is there no signup?", "Is this legal?"
     (answer plainly and confidently).
  9. FOOTER — GitHub, privacy policy, contact, the nimn etymology as a small
     elegant touch.

SUB-PAGES:
  /privacy — the privacy policy, which is itself a marketing asset: it
     should be shockingly short because there is nothing collected. Write it
     in plain language, legally sensible, with the collected-data table
     visibly near-empty.
  /security — the protocol explained for technical readers: pairing
     handshake, E2E model, forward-secrecy statement, safety phrase, honest
     metadata section, link to spec + repo. Written for the Hacker News
     reader; no marketing tone here at all.
  /press — one-paragraph boilerplate, logo downloads, screenshots, founder
     contact.

DESIGN & BUILD REQUIREMENTS:
  - Use the brand tokens/typography/colors from the design package verbatim.
    Dark, calm, editorial; generous whitespace; the restraint IS the
    creativity. One or two moments of delight maximum (the hero line
    animation, the relay diagram) — everywhere else, stillness.
  - Static site: semantic HTML + modern CSS + minimal vanilla JS. No
    frameworks, no build step, no external requests of any kind — no CDN
    fonts (self-host), no analytics, no cookies. The site must practice
    what the product preaches; state this in the footer ("this site sets no
    cookies and loads nothing from third parties").
  - Fully responsive (360px → desktop), dark/light via prefers-color-scheme
    with dark as default, WCAG AA, all animation honoring prefers-reduced-
    motion, <100KB critical path, real OG/social meta tags, favicon set
    from the app icon.
  - Every claim on the site must be traceable to the spec; where marketing
    shorthand risks overstating (e.g. "impossible to intercept"), soften to
    the accurate claim. I will diff the site copy against the spec.
  - Real copy throughout, in the brand voice: short declarative sentences,
    zero fear-marketing, zero spy imagery.

DELIVERABLE: complete site as static files (index.html, /privacy, /security,
/press, /assets), a README covering local preview and deployment (target:
any static host — Cloudflare Pages / GitHub Pages), and a launch checklist
(meta tags verified, Lighthouse ≥95 across categories, link check).

WORKING RULES:
  - Start by presenting a one-screen content outline + a described visual
    concept for the hero and relay diagram; PAUSE for my approval, then
    build the full site without further pauses.
  - Commit logical chunks; keep PROGRESS.md updated per my repo conventions.
```

---

## Usage notes

- Run Prompt 1 first; its `tokens JSON + brand cheat sheet` become inputs to Prompt 2, so the app and site stay one visual object.
