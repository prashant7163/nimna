# docs/

Protocol truth and build-loop reference material.

- [`nimna-protocol-spec-v0.2.md`](nimna-protocol-spec-v0.2.md) — **THE
  spec: single source of truth** for all implementation work. Complete and
  self-contained; locks the Session-2 crypto decisions (primitives,
  handshakes, derivations, exact wire framing) and carries both 2026-07-04
  RESOLVED USER protocol flags normatively. Protocol changes from here
  require a USER decision.
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
- Tech-architect **architecture notes** accumulate here from Session 2 on.
- [`archive/`](archive/) — superseded documents kept as provenance, never
  synced (see its README).
