# cmd/testclient/testdata/

Vendored protocol test vectors — **read-only conformance fixtures, never
edited or regenerated here**.

- `topic-derivation.json` — byte-identical copy of the Nimna monorepo's
  `docs/test-vectors/topic-derivation.json` (produced by the committed
  vector generator there): §3.1.2 code canonicalization, date salt, and
  Argon2id/HKDF topic derivation cases, at both production and clearly
  labeled reduced-cost test parameters. Vendored so `go test ./...` is
  self-contained in the public relay repository; the previous
  repo-escaping relative path would break outside the monorepo.

Provenance and drift control: the monorepo copy is canonical; monorepo CI
runs a `cmp` step asserting this copy stays byte-identical to its source
on every change to either file. To update: regenerate the canonical
vectors in the monorepo, then re-copy the file verbatim.
