# docs/test-vectors/generator/

Committed Go module that deterministically (re)generates every JSON vector
file in [`docs/test-vectors/`](../README.md) from fixed constants — no
randomness, no clock. Auditors regenerate and diff; CI does the same on
every change (`.github/workflows/test-vectors.yml`).

## Commands (run from this directory)

```sh
go run . -dir ..        # rewrite ../[topic-derivation|pairing-handshake|
                        #           session-handshake|phrase-words|framing].json
go test ./...           # engine + RFC + third-party vectors + regeneration guard
go vet ./... && gofmt -l .
```

`go test -short ./...` skips the memory-hard Argon2id vectors and the
full regeneration (both cost seconds, not minutes; `-short` is for tight
inner loops only).

## Package map

- `main.go` — CLI: `go run . -dir <docs/test-vectors>`; requires the pinned
  `wordlist-en-v1.txt` to be present in that directory (its SHA-256 is
  verified before anything is written).
- [`internal/noise/`](internal/noise/README.md) — minimal Noise engine
  (revision 34, suite `25519_ChaChaPoly_SHA256`, fundamental patterns +
  psk modifiers), Nimna's post-Split transport discipline (§5.6 nonces +
  per-message REKEY), RFC 8439/7748 tests, third-party vector runner.
- [`internal/derive/`](internal/derive/README.md) — code
  canonicalization, topic/psk (Argon2id + HKDF), commitment M0, CRID,
  safety phrase; RFC 5869 and Argon2id reference-vector tests.
- [`internal/framing/`](internal/framing/README.md) — outer frame, inner
  envelope, MEDIA_CHUNK manifest/chunk, token_payload; round-trip and
  rejection tests.
- [`internal/vectors/`](internal/vectors/README.md) — the generation of
  the five JSON files, plus the byte-identical-regeneration test.
- [`testdata/`](testdata/README.md) — committed third-party Noise vectors
  (provenance and license notes there).

## Dependencies

Go 1.26 (matching `application/relay/go.mod`) + `golang.org/x/crypto`
v0.53.0 (chacha20poly1305, argon2) — the relay had no x/crypto pin yet, so
the current stable was pinned here first. Everything else is stdlib
(`crypto/ecdh`, `crypto/hkdf`, `crypto/sha256`, `crypto/hmac`). No Noise
library — the engine is implemented from the Noise specification per spec
v0.2 §7, and validated against third-party vectors precisely because of
that.

## Determinism contract

All "randomness" (static/ephemeral keys, msg_ids, tokens, media bytes) is
derived as SHA-256 of readable `nimna/test-vectors/v1/...` labels;
timestamps are fixed constants. JSON is emitted from structs (stable field
order), two-space indent, HTML escaping off, trailing newline —
`internal/vectors/regen_test.go` asserts committed files match a fresh
generation byte-for-byte, and CI enforces it with `git diff --exit-code`.
