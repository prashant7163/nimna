# docs/test-vectors/oracle/

**Test-only, independent cross-verification of the committed Noise vectors.**
Module `nimna.app/test-vectors/oracle` — its own `go.mod`/`go.sum`, separate
from the relay and from the vector `generator/`. Built for the Session 18
adversarial pass (§18-I); binding shape in
[`../../architecture/s18-noise-oracle-design.md`](../../architecture/s18-noise-oracle-design.md).

## What it does

The from-spec engines (Go `generator/internal/noise/`, Dart
`application/mobile/lib/src/noise/`) are already byte-locked to the committed
vectors. This module adds one thing an auditor can check for themselves: an
**independent** Noise implementation — [`github.com/flynn/noise`](https://github.com/flynn/noise),
the reference Go library — reproducing the same committed bytes.

Driven with each vector's fixed keys, prologue and psk (deterministic
ephemerals via a seeded `Config.Random`), the oracle asserts byte-equality
against [`../pairing-handshake.json`](../pairing-handshake.json) and
[`../session-handshake.json`](../session-handshake.json):

| Test | Layer | Assertion |
|---|---|---|
| `TestOracleXXpsk2BothRoles` | XXpsk2 M1–M3, both roles | `HandshakeXX` + `PresharedKeyPlacement=2`; byte-equal messages, per-step handshake hash, Split keys |
| `TestOracleCommitmentM0` | commitment M0 | independent SHA-256 of `"nimna/commit/v1" ‖ eB ‖ sB` equals the committed prologue (Nimna-external; flynn sees only opaque prologue bytes) |
| `TestOraclePairingTransport` | M4 PAIR_CONFIRM | independent x/crypto re-wrap under `k_ri` equals the committed frame |
| `TestOracleKKBothRoles` | KK S1–S2, both roles | `HandshakeKK`, statics as pre-messages, zero prologue, no psk; byte-equal messages, handshake hash, Split keys |
| `TestOracleSessionTransport` | transport frames | independent x/crypto re-wrap (nonce `dir‖counter`, per-message REKEY) equals every committed ciphertext + `key_before`/`key_after` |

## The honest fallback (transport)

flynn/noise **cannot** mirror Nimna's post-Split transport: it uses the
standard Noise nonce and does not rekey per message. So flynn's contribution
ends at Split — where its keys are cross-checked byte-for-byte. The transport
frames are then re-derived from those same committed keys using
`golang.org/x/crypto/chacha20poly1305` **directly** (pinned to the relay's
`v0.53.0`). The AEAD *core* is x/crypto on both sides; what is independently
re-implemented here is the Nimna-specific **wrapping** — the
`direction(4,BE)‖counter(8,BE)` nonce and the `REKEY` schedule. The ultimate
anchor for transport remains the committed vectors and both from-spec engines
passing them. This is documented verbatim in `oracle_test.go`.

## Dependency isolation (audited)

`github.com/flynn/noise` (BSD-3-Clause) is **test tooling in this module
only** — never linked into the AGPL relay or any shipped artifact, and never
in the vector-production path. Three CI guards in `.github/workflows/` enforce
it (design note §1.4):

- **relay.yml, layer a** — `! grep -q 'flynn/noise' go.mod go.sum` (manifest tripwire)
- **relay.yml, layer b** — `go list -deps ./...` carries zero flynn/noise packages (semantic graph proof)
- **test-vectors.yml, layer c** — the `generator/` go.sum stays flynn-free (vectors produced independently)
- **test-vectors.yml, layer d** — this module is gofmt/vet/build/test-checked

## Running

```sh
cd docs/test-vectors/oracle
go test ./...        # the whole point: an independent library agrees
```
