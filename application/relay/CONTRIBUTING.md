# Contributing to the nimna relay

Thanks for reading the code — that is the point of publishing it.

## What is welcome

Small, focused fixes: bugs, portability problems, documentation
corrections, test gaps, build/deploy-kit improvements. Open an issue
first for anything larger than a screenful so effort isn't wasted.

## What is not changeable by pull request

**Protocol behavior is spec-governed.** Wire formats, frame semantics,
limits, TTLs, and the silence doctrine (the relay never explains itself
on the wire) are defined by the Nimna protocol specification
(`docs/nimna-protocol-spec-v0.2.md`, vendored byte-identical in this
repo) — they change only via the spec, never via a relay PR. The same
holds for the repository's standing invariants:

- zero storage (in-memory tables only; no database, no disk writes, no
  queues),
- identifier-free logging (the `internal/ident` unloggable types, the
  log-scrub test),
- `cmd/relay`'s x/crypto-free import graph (the anchored CI step),
- no new dependencies without a very good reason (stdlib-first; the
  current tree carries exactly two direct dependencies —
  `github.com/coder/websocket` for the transport, `golang.org/x/crypto`
  for `cmd/testclient`'s Argon2id only; see the README's Dependencies
  section).

PRs that weaken an invariant or add a response surface will be declined
regardless of code quality.

## Mechanics

- **DCO sign-off required, no CLA.** Add `Signed-off-by: Your Name
  <you@example.com>` to each commit (`git commit -s`), certifying the
  [Developer Certificate of Origin](https://developercertificate.org/).
- Checks that must pass locally (CI runs the same):
  `go build ./... && go vet ./... && go test ./...` and `gofmt -l .`
  prints nothing.
- Tests accompany behavior changes in the same PR.

## Security

Security contact: *to be published at launch* — a dedicated mailbox on
the project domain lands with the public release checklist. Until then,
open a private security advisory on the repository rather than a public
issue.

## License

AGPL-3.0 (see `LICENSE`). By contributing you agree your contribution is
licensed under the same terms.
