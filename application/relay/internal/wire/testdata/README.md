# internal/wire/testdata/

Vendored protocol test vectors — **read-only conformance fixtures, never
edited or regenerated here**.

- `framing.json` — byte-identical copy of the Nimna monorepo's
  `docs/test-vectors/framing.json` (produced by the committed vector
  generator there). Vendored so `go test ./...` is self-contained in the
  public relay repository; the previous repo-escaping relative path would
  break outside the monorepo.

Provenance and drift control: the monorepo copy is canonical; monorepo CI
runs a `cmp` step asserting this copy stays byte-identical to its source
on every change to either file. To update: regenerate the canonical
vectors in the monorepo, then re-copy the file verbatim.
