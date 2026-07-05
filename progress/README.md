# progress/

Per-session progress files for **parallel sessions** (USER, 2026-07-05 —
see CLAUDE.md "Parallel sessions" and `nimna-build-plan-v3-sessions.md`).

`TASKS.md`, `PROGRESS.md`, and `DECISIONS.md` are merge hotspots: a session
running in its own worktree never edits them directly. Instead it appends
everything it would have written — status changes, progress entries,
decision candidates, plus its one-line app-shell route registrations and
declared pubspec additions — to `SESSION-N.md` in this folder, in the same
formats the canonical files use (full `YYYY-MM-DD HH:MM +tz` stamps).

At merge time (only after that session's code-review + senior-qa done-check
pass), the orchestrator folds each `SESSION-N.md` into the canonical
tracking files **serially**, wires route registrations, union-merges
pubspec, resolves namespaced ARB keys, and deletes the folded file. An
empty folder means no parallel session is currently mid-flight.
