# Nimna — Design Work-Loop Prompt (3 Tasks)

Paste the prompt below into Claude Code, started from the project root.
Attach alongside it: `brand-context.md` (the Shared Brand Context), `nimna-protocol-spec-v0.1.md`, and `nimna-design-and-website-prompts.md` (the detailed task specs it will execute).

---

```
PROJECT ROOT: /Users/pacific/Playground/AIManagedProjects/Nimna

You are running a three-task design work loop for Nimna. Theese files at the PROJECT ROOT
are your source of truth:
- brand-context.md — brand identity, personality, avoids, product rituals
- nimna-protocol-spec-v0.1.md — the protocol; designs must never contradict it
- nimna-design-and-website-prompts.md — the detailed specification for the
  work; Task definitions below reference its sections

════════════════════════ WORK-LOOP RULES ════════════════════════

FILES YOU MAINTAIN (create on first run, at project root):

1. TASKS.md — the task board. Each task listed with status
   (pending / in-progress / blocked-on-user / done), its deliverables as
   checkboxes, and completion timestamp. Update immediately on every status
   change. This file is the single source of truth for where the loop stands.

2. PROGRESS.md — append-only log. After EVERY task completion AND at any
   milestone worth recording mid-task (a system finalized, a flow fully
   wireframed, a page built), append a dated entry: 3–6 lines covering what
   was produced, where it lives, and what comes next. Keep entries terse —
   this file is the handoff memory between sessions.

3. DECISIONS.md — append-only decision record. Every decision gets an entry:
   date, decision, who made it (USER or CODE), alternatives considered,
   one-line rationale. Two kinds:
   - USER decisions: anything about taste, brand direction, money, scope,
     or anything that cascades widely. These are YOURS TO ASK, never to make.
   - CODE decisions: routine execution choices (a spacing value, an icon
     grid, file organization). Make them, record them, move on. When unsure
     which kind it is, treat it as USER.

QUESTION PROTOCOL:
- At the START of each task, before producing anything, read the relevant
  spec sections and surface ALL foreseeable user decisions for that task as
  one consolidated question list. Wait for answers, log them in
  DECISIONS.md, then run the task without interruption.
- Exception — the three TASTE CHECKPOINTS defined in the task list below.
  These cannot be front-loaded because the options don't exist yet. At each
  checkpoint: present the options, PAUSE, set TASKS.md status to
  blocked-on-user, and wait. Log my selection in DECISIONS.md, then continue.
- If an unforeseen user-level decision appears mid-task, do not guess:
  pause, ask, log, continue.

REPORTING:
- Report back to me in full ONLY when all three tasks are done: a summary of
  everything produced, the directory tree of outputs, all decisions made,
  and any open items or recommendations. Between tasks, a one-line "Task N
  done, starting Task N+1" plus the PROGRESS.md entry is enough.

GENERAL:
- Commit at each logical chunk with clear messages; commit after every task.
- All output files organized under /design (tasks 1–2) and /website (task 3),
  each with a README index.
- Real microcopy everywhere, never lorem ipsum — copy is part of the design.
- Any conflict between visual ambition and the protocol spec: the spec wins;
  flag the conflict in PROGRESS.md.

════════════════════════ THE THREE TASKS ════════════════════════

TASK 1 — BRAND FOUNDATION & LOGO
Execute sections 1 (Brand Foundation) and 2 (Logo & App Icon) of the design
prompt in nimna-design-and-website-prompts.md, in full.
  TASTE CHECKPOINT A: after presenting the three brand-direction concepts
  (1.1) AND the three logo concepts (2.1) — present both sets together in
  one pause if feasible, or as two pauses if logo concepts depend on the
  chosen direction (they do; use two pauses: direction first, then logos).
  Deliverables: brand direction doc, color system (dark+light), typography
  system, voice & microcopy guide, final logo SVGs with usage rules, app
  icons (iOS + Android adaptive).
  Done when: every deliverable exists under /design/brand and PROGRESS.md
  records the outcome.

TASK 2 — DESIGN SYSTEM, WIREFRAMES & HI-FI SCREENS
Execute sections 3 (Design System), 4 (Wireframes F1–F9), 5 (Hi-Fi Screens),
and 6 (Handoff Notes) of the design prompt, in full, applying the Task 1
brand decisions.
  No taste checkpoints — this is execution. Front-load any user questions
  (e.g., preferences on paywall presentation, wipe-confirmation style)
  before starting.
  Deliverables: design tokens JSON (Flutter ThemeData-ready), component
  specs, annotated wireframes for all nine flows, 12 hi-fi screens as
  HTML/CSS mockups (390×844, dark-first), Flutter handoff notes, brand
  cheat sheet.
  Done when: /design/system, /design/wireframes, /design/screens,
  /design/handoff are complete with README indexes.

TASK 3 — WEBSITE
Execute Prompt 2 (the website) from nimna-design-and-website-prompts.md in
full, reusing Task 1–2 tokens, logo, and screens verbatim.
  TASTE CHECKPOINT B: the content outline + hero & relay-diagram visual
  concepts (as defined in that prompt's working rules). Present, pause,
  log selection, then build without further pauses.
  Deliverables: complete static site (index, /privacy, /security, /press,
  /assets), deployment README, launch checklist (Lighthouse ≥95, link
  check, meta tags).
  Done when: /website is complete, previews locally, and the copy has been
  self-checked against the protocol spec for overclaiming.

════════════════════════ START ════════════════════════

Begin now: create TASKS.md, PROGRESS.md, and DECISIONS.md, read all three
attached documents fully, then open Task 1 with its consolidated question
list.
```
