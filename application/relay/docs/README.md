# docs/ (relay tree)

- `nimna-protocol-spec-v0.2.1.md` — **byte-identical copy** of the
  canonical Nimna protocol specification, vendored so the relay
  repository is auditable offline and self-contained (spec §4: the spec
  is "published openly alongside" the relay). The canonical copy lives in
  the Nimna monorepo at `docs/nimna-protocol-spec-v0.2.1.md`; monorepo CI
  runs a `cmp` step asserting this copy never drifts from it. Never edit
  this file here — spec changes happen at the canonical copy only, then
  are re-copied verbatim. This tree carries only the sole normative spec;
  superseded versions (v0.2, v0.1.1) are monorepo history.

The relay implements spec §3 (protocol phases, relay-visible behavior)
and §4 (the relay doctrine: statelessness, silence, limits); §5.4 defines
the outer frame it routes. Everything else in the spec is client-side
context the relay never parses.
