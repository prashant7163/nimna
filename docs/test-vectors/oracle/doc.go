// Package oracle is a TEST-ONLY, independent cross-verification of Nimna's
// committed Noise test vectors, built for the Session 18 adversarial pass.
//
// It exists in its own Go module (nimna.app/test-vectors/oracle) for one
// reason: it depends on github.com/flynn/noise — the reference Go Noise
// implementation — as an INDEPENDENT second engine, and that dependency
// must never touch the AGPL relay's or the vector generator's module graph
// (see docs/architecture/s18-noise-oracle-design.md §1, and the CI
// dep-graph guards in .github/workflows/). flynn/noise (BSD-3-Clause) is
// test tooling only; it is never linked into any shipped artifact.
//
// The oracle asserts that flynn/noise, driven with each committed vector's
// fixed keys / prologue / psk, reproduces the exact committed handshake
// messages, handshake hashes and Split keys — proving the vectors are
// correct under a second, independent implementation. Where flynn/noise
// cannot mirror a Nimna-specific deviation (the §5.6 transport nonce and
// the per-message REKEY), the oracle re-implements only that wrapping using
// the audited golang.org/x/crypto/chacha20poly1305 primitive directly; see
// the honest-scope comment in session_test.go.
//
// The package intentionally ships no non-test code: everything lives in
// *_test.go files, run with `go test ./...` inside this module.
package oracle
