# docs/

Protocol truth and build-loop reference material.

- [`nimna-protocol-spec-v0.2.1.md`](nimna-protocol-spec-v0.2.1.md) — **THE
  spec: single source of truth** for all implementation work. Complete and
  self-contained; carries all of v0.2 verbatim (the Session-2 crypto locks,
  exact wire framing, both 2026-07-04 RESOLVED USER protocol flags) and
  adds the 2026-07-05 reconciliation: REACTION envelope, `reply_to`, and
  the restored §3.1 duplicate-channels/self-join doctrines (USER decision,
  DECISIONS.md). Protocol changes from here require a USER decision.
- [`nimna-protocol-spec-v0.2.md`](nimna-protocol-spec-v0.2.md) —
  superseded by v0.2.1; kept in place as history (do not edit). Authored
  at Session 2 from a v0.1.1 snapshot that predated the reaction/reply
  scope additions — the drift v0.2.1 reconciles.
- [`nimna-protocol-spec-v0.1.1.md`](nimna-protocol-spec-v0.1.1.md) —
  superseded by v0.2; kept in place as history (do not edit). It was the
  synced copy of the root user-editable original through Session 1.
- [`crypto-evaluation.md`](crypto-evaluation.md) — Session 2 crypto
  evaluation (tech-architect), **the reasoning record behind spec v0.2**:
  stack comparison, grinding/brute-force arithmetic, library sign-offs,
  alternatives considered. Status LOCKED at the Session 2 USER checkpoint
  (DECISIONS.md, 2026-07-04).
- [`test-vectors/`](test-vectors/README.md) — **committed protocol test
  vectors** authored from spec v0.2: deterministic JSON for
  canonicalization/topic/psk, both handshakes with full transcripts,
  phrase mapping, and framing; the pinned phrase wordlist (SHA-256
  normative); and the committed Go generator that regenerates everything
  byte-identically (CI-enforced, third-party-Noise-vector validated).
  Both stacks must reproduce these byte-for-byte (spec §7).
- [`architecture/`](architecture/README.md) — tech-architect
  **architecture notes**, binding technical shape for implementation
  sessions (relay architecture for Sessions 3–6 lives here; more
  accumulate as phases open).
- [`release/`](release/README.md) — private-side release procedures
  (the relay publish runbook: subtree split, split-tree verification,
  history secret scan, S19 trigger). Monorepo-only, never published.
- [`archive/`](archive/) — superseded documents kept as provenance, never
  synced (see its README).
