# Nimna — Loop Memory (resume notes)

**What this project is:** Design work loop for Nimna — paid, account-less, synchronous-only, E2E-encrypted 1:1 messaging ("a private line between two people"). Three tasks: (1) brand+logo, (2) design system/wireframes/hi-fi screens, (3) website.

**Source of truth (read before resuming):**
- `brand-context.md` — personality (quiet luxury, calm, discreet), HARD AVOIDS (no locks/shields/spy/matrix/neon-green/fingerprints/"military-grade"/fear marketing), 6 product rituals.
- `nimna-protocol-spec-v0.1.md` — designs must never contradict it. Key constraints: no accounts/profiles/contact lists, no server storage, no history sync, synchronous-only, relay DOES see IPs/timing/CRIDs/ciphertext sizes (honesty is a brand asset), disappearing messages are honor-system (UX must say so), push is content-free + opt-in + default-off, pairing code single-use w/ TTL, knock TTL ~60s, safety phrase encouraged not enforced.
- `nimna-design-and-website-prompts.md` — task definitions (Prompt 1 = Tasks 1–2, Prompt 2 = Task 3).

**Conventions:**
- Outputs: `/design` (tasks 1–2), `/website` (task 3), each dir README-indexed. Work-loop prompt overrides the `designs/` name in the older prompt text.
- Real microcopy always, never lorem ipsum. Spec beats visual ambition; flag conflicts in PROGRESS.md.
- Commit every logical chunk + after every task. Update TASKS.md on every status change; append PROGRESS.md at milestones; every decision → DECISIONS.md (USER for taste/brand/money/scope; CODE for routine execution).
- Taste checkpoints: A1 (brand direction), A2 (logo concept), B (website outline + hero/relay-diagram concepts). Pause + set TASKS.md blocked-on-user at each.
- Report in full to user only after all three tasks are done.

**Current state:** see TASKS.md (single source of truth for status).
