# S18 Noise test-oracle harness — design note

Tech-architect architecture note (CODE decision, logged in `DECISIONS.md`
by the orchestrator). Binding technical shape for the Session 18 adversarial
pass. Anything protocol-visible defers to
`docs/nimna-protocol-spec-v0.2.1.md`; this note governs *test tooling only*.

**Status:** design (S18 intake). No production code or tests written yet —
this note tells the S18 implementers what to build and where.

**Scope rails (already USER-settled, not re-opened here):**
- flynn/noise as the oracle, **test-only, never a runtime dependency**
  (DECISIONS 2026-07-05 02:20 "S18 SCOPE ADDITION" + "No-Noise-library").
- HOST-MAX adversarial pass; the 4 genuinely hardware-bound §9 rungs are
  documented accepted limitations carried to PUBLISH_READY device-QA
  (DECISIONS 2026-07-08 S18 intake).

What is a **CODE** decision inside those rails, and what this note settles:
the isolation mechanism, what the oracle cross-verifies (and the honest
fallback where flynn/noise cannot mirror a Nimna deviation), and the
threat-model doc structure. No USER-level concern was found.

**Architect dependency sign-off (given here):** `github.com/flynn/noise`
(BSD-3-Clause, mature, the reference Go Noise implementation) is signed off
as a **test-only dependency of a dedicated, isolated module** — never in the
relay or app graph. Rationale below.

---

## 1. Library + isolation

### 1.1 Recommendation: a separate Go module at `docs/test-vectors/oracle/`

Module path: **`nimna.app/test-vectors/oracle`**, its own `go.mod`/`go.sum`,
outside the relay module tree. This is option (a) in the intake, and it wins
decisively.

Why this location and not `tools/noise-oracle/`: the audit story is
"everything that validates the crypto lives under `docs/test-vectors/`." The
committed vectors, the from-spec generator (`generator/`, module
`nimna.app/test-vectors/generator`), the third-party vector sets, and now the
independent oracle all sit side by side in the audit tree. An auditor reads
one directory. `tools/` would scatter it.

### 1.2 Why a *new* module, not the existing generator module

The generator module could technically host the oracle as `_test.go` files
with flynn/noise as a test dependency. Rejected, for two concrete reasons:

1. **x/crypto pin drift.** The generator's `go.mod` deliberately pins
   `golang.org/x/crypto v0.53.0` to match the relay's pin exactly (DECISIONS
   2026-07-04 13:44: "own go.mod, pins relay's x/crypto version"). flynn/noise
   pulls its own x/crypto (curve25519, chacha20poly1305); adding it to the
   generator module and running `go mod tidy` could bump that pin and silently
   desync the generator from the relay. A separate module quarantines any
   x/crypto version flynn/noise drags in — the generator's go.mod stays
   byte-identical to the relay's pin, and the vector-production path stays
   provably flynn-free.

2. **Independence legibility.** The generator *produces* the canonical
   vectors from the from-spec engine. The oracle's whole value is an
   *independent* implementation agreeing. Keeping them in separate modules /
   separate test binaries makes "the vectors were not produced with the
   oracle library's help" a structural fact an auditor can see, not a claim to
   trust.

### 1.3 Why NOT option (b), the `//go:build oracle` tag inside the relay

Disqualified, exactly as the intake suspected. A build-tagged file inside
`application/relay/` that imports flynn/noise still lists flynn/noise in the
relay module's `go.mod require` block and `go.sum`. The relay is the
AGPL-published artifact; its dependency manifest is part of what auditors and
downstream packagers read. "It's only compiled under a tag" does not remove
it from the manifest, and `go mod tidy` would keep it there. The hard USER
rail is *clean relay go.mod*, and a build tag violates it. Rejected.

### 1.4 How CI proves the relay binary's graph excludes flynn/noise

There is already precedent: `relay.yml` asserts the relay binary does not even
pull `golang.org/x/crypto` into `./cmd/relay`:

```
test "$(go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/')" -eq 0
```

Add the flynn/noise exclusion in the same spirit, layered — a cheap manifest
tripwire plus the semantic graph proof:

- **Manifest tripwire** (relay job): assert flynn/noise appears nowhere in the
  relay module's resolved deps —
  `! grep -q 'flynn/noise' application/relay/go.sum` (and, defensively,
  `go.mod`). Because the relay is a separate module with no path dependency on
  the oracle, flynn/noise cannot enter it unless someone adds a `require`; the
  go.sum grep is the tightest possible tripwire.
- **Graph proof** (relay job): assert the actual build graph is clean —
  `test "$(cd application/relay && go list -deps ./... | grep -c '^github.com/flynn/noise')" -eq 0`.
- **Generator stays flynn-free too** (test-vectors job): assert
  `! grep -q 'flynn/noise' docs/test-vectors/generator/go.sum`, so the
  canonical-vector production path is provably independent of the oracle
  library.
- **Oracle is the one allowed home**: `test-vectors.yml` gains a job that
  `go build`/`go test`s the oracle module; flynn/noise is required there and
  nowhere else. Pin the exact version and run `go mod tidy` in the oracle
  module only.

License note: flynn/noise is BSD-3-Clause. It is test tooling in a dedicated
module, never linked into the AGPL relay binary — no license interaction with
the relay's AGPL-3.0.

---

## 2. What the oracle cross-verifies

The from-spec engines (Dart `application/mobile/lib/src/noise/` and Go
`generator/internal/noise/`) are already byte-locked to the committed vectors
in both stacks. The oracle adds one thing: an **independent** implementation
that reproduces the same committed bytes. So the assertion target is the
**committed vectors**, not a live flynn↔from-spec transcript.

**Why committed-vector equality, not a live transcript.** The vectors are the
single byte-locked source of truth both stacks already pass. An oracle that
regenerates the exact committed handshake messages, handshake hashes, and
Split keys from flynn/noise proves the *vectors themselves* are correct under
an independent impl — that is the added value. A live flynn↔from-spec pairing
would test interop but is more fragile, adds little over "both equal the
committed bytes" (the from-spec engine already round-trips itself in the
generator), and would need the same Nimna-transport shim discussed in §2.3.
The oracle therefore loads `pairing-handshake.json` and
`session-handshake.json` (via relative path from the oracle module) and drives
flynn/noise with each vector's fixed keys/prologue/psk to assert byte-equality.

flynn/noise drives deterministically: fixed ephemerals via a seeded
`Config.Random` reader that returns the vector's ephemeral private key;
prologue via `Config.Prologue`; psk via `Config.PresharedKey` +
`Config.PresharedKeyPlacement`; handshake hash via `ChannelBinding()`; Split
via the two returned `CipherState`s. This is the same technique the existing
`thirdparty_test.go` uses against cacophony/snow vectors.

### 2.1 XXpsk2 pairing handshake (both roles) — FULLY mirrored

flynn/noise expresses the exact construction natively:
- Pattern `HandshakeXX` with `PresharedKeyPlacement = 2` **is** XXpsk2. The
  psk-mode rule (every `e` also MixKeys its public key, Noise rev 34 §9.2 —
  the reason M1 carries a 16-byte tag over an empty payload) is implemented by
  flynn/noise, matching the from-spec engine.
- The **commitment prologue** is a Noise *mechanism* (arbitrary prologue bytes
  MixHashed before message 1) carrying Nimna-specific *content*
  (M0 = SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub), 32 bytes). flynn/noise
  consumes it verbatim as `Config.Prologue`. No deviation in the Noise layer.

Cross-checks, both roles (joiner=initiator, creator=responder):
byte-equal M1/M2/M3 ciphertexts, byte-equal handshake hash after each step and
final, byte-equal Split keys `k_ir`/`k_ri`, all against the committed vector.

**Honest fallback for the two Nimna-external pieces flynn/noise cannot see:**
- The commitment *derivation* M0 — flynn/noise sees only opaque prologue
  bytes. The oracle recomputes M0 with an independent SHA-256 over the
  vector's `eB_pub ‖ sB_pub` and asserts it equals the committed `m0` /
  `prologue`. Independent of any Noise library.
- The creator-side commitment *verification* (spec §3.1.3: check M0 against the
  joiner's revealed static before M4) — also outside Noise. The oracle
  replicates the check independently (constant-time in production; the test
  may use plain compare over public constants, as the generator notes).

### 2.2 Noise_KK session handshake (both roles) — FULLY mirrored

flynn/noise expresses KK natively: `HandshakeKK`, pre-messages = both static
public keys (initiator's first), zero-length prologue, no psk (so `e` tokens
MixHash only). Cross-checks, both transcripts (knocker=joiner and
knocker=creator): byte-equal S1/S2 ciphertexts, byte-equal handshake hash,
byte-equal Split keys, against the committed vector. No deviation in the
handshake layer.

### 2.3 Post-Split transport (M4 PAIR_CONFIRM + session frames) — NOT mirrorable; documented fallback

This is the one genuine deviation flynn/noise **cannot** reproduce, and the
note states it honestly:

- Nimna's transport nonce is `direction(4, big-endian) ‖ counter(8,
  big-endian)` (spec §5.6). flynn/noise's `CipherState` uses the standard
  Noise nonce (a uint64 counter in a 12-byte little-endian-tail nonce). It
  cannot emit Nimna's nonce.
- Nimna **rekeys after every message** (Noise REKEY, spec §3.3.1/§11.3) on
  both encrypt and successful decrypt. flynn/noise's `CipherState` does not
  auto-rekey per message. It cannot reproduce the per-frame key schedule.

Therefore flynn/noise's contribution **ends at Split**. The honest fallback,
which the oracle implements and the threat-model doc documents:

1. Assert flynn/noise's Split keys (`k_ir`, `k_ri`) byte-equal the committed
   vectors' Split keys — this is the cryptographic handoff point, and it is
   fully cross-checked by the independent library.
2. From those keys, independently recompute the Nimna transport wrapping in
   the oracle using **x/crypto's `chacha20poly1305` directly** (audited
   primitive), NOT flynn's `CipherState`:
   - `ciphertext = Seal(k, nonce=dir‖counter, ad=18-byte-outer-header,
     plaintext)`;
   - `REKEY(k) = Seal(k, nonce=0x00000000ffffffffffffffff, ad="",
     32 zero bytes)[:32]`;
   and assert byte-equality against every committed transport frame's
   ciphertext plus `key_before`/`key_after`, and against M4 PAIR_CONFIRM
   (key `k_ri`, direction `0x00000001`, counter 0, AD = outer PAIR_DATA
   header). Honest scope statement in the doc: the AEAD **core** is x/crypto
   in both the from-spec engine and the oracle re-check (there is no
   independent second ChaCha20-Poly1305 worth trusting over the audited one);
   what the oracle re-implements independently is the **Nimna-specific
   wrapping** (nonce layout + per-message REKEY), and the transport
   discipline's ultimate anchor remains (a) the committed vectors and (b) both
   from-spec engines passing them byte-for-byte.

### 2.4 Equivalence-assertion summary

| Layer | flynn/noise mirrors it? | Oracle assertion |
|---|---|---|
| XXpsk2 M1–M3 (both roles) | Yes, byte-for-byte (pattern+psk2+prologue) | Byte-equal msgs, handshake hash, Split vs committed |
| XXpsk2 commitment M0 derive/verify | No (Nimna-external) | Independent SHA-256 recompute + verify vs committed |
| KK S1–S2 (both roles) | Yes, byte-for-byte | Byte-equal msgs, handshake hash, Split vs committed |
| Split → transport keys | Yes (Split output) | Byte-equal `k_ir`/`k_ri` vs committed |
| Transport nonce ‖ per-msg REKEY (M4 + frames) | No (non-standard nonce, no per-msg rekey) | Independent x/crypto re-wrap vs committed; documented |

---

## 3. Threat-model doc structure

**Deliverable:** `docs/architecture/threat-model.md` (S18). One table, every
row closed with a coverage cell. Row set = every spec §9 row **plus** every
plan-§18 new row. Columns:

| Column | Content |
|---|---|
| Adversary / threat | The §9 row label or the new-row name |
| Spec / plan ref | §9, §3.x, §4, §5.x, or plan-§18 |
| Protection (as claimed) | The honest claim from §9 / the spec |
| Coverage | Test file/name that exercises it, **or** "accepted limitation" |
| Status | PASS (host test) / ACCEPTED-LIMIT (+ PUBLISH_READY pointer) |

Every row must resolve to a passing host-level test **or** an explicitly
documented accepted limitation — the plan's done-check.

**§9 rows** (verbatim from the spec table): relay operator (incl. compelled);
relay code-from-topic offline brute force; network observer; pairing-time
MITM; relay-plane replay/forgery (KNOCK/ACCEPT/TEARDOWN); peer's device
seized; your own device seized; counterpart captures content
(screenshot/second camera); metadata correlation. Plus the structural-abuse
posture paragraph.

**Plan-§18 new rows** and their target test homes (developers own the tests;
these are the intended homes, not authored yet):
- **Replay** (session frames) → transport counter/AEAD rejection tests, both
  stacks (from-spec engine: a replayed/out-of-sequence frame fails AEAD and
  kills the session, §3.3.1).
- **MITM** → pairing without psk fails (XXpsk2 psk2); commitment/phrase
  cross-check tests (oracle §2.1 + engine tests).
- **Malformed frames + fuzzing (relay)** → `go test -fuzz` on the outer-frame
  decoder in `application/relay/internal/wire`.
- **Malformed frames + fuzzing (app)** → Dart fuzz over the envelope codec
  (mobile).
- **Storage/backup inspection** → host forensic-scan test opening the REAL
  encrypted DB/blob files produced by mobile host tests and asserting no
  plaintext / no key material leaks.
- **Screenshot-notice suppression honesty** → test proving the CONTROL
  screenshot notice (§5.2) is emitted; the *inability* to force a peer to
  honor it is documented as an honest limitation (honor-system, disclosed).
- **Push-bombing vs rate limits** → relay rate-limit tests (§4).
- **EXIF-strip** → mobile media-pipeline test running a real image through the
  real strip path, asserting EXIF/XMP/ICC removed.
- **Wipe forensics** → panic-wipe test asserting keys/records are
  unrecoverable after wipe.

**The 4 hardware-bound accepted limitations** (DECISIONS 2026-07-08),
each a row with Status = ACCEPTED-LIMIT and a PUBLISH_READY §2 device-QA
hand-step pointer:
1. Real-camera EXIF capture (host strips synthetic EXIF; a physical camera's
   real metadata is device-QA).
2. OS screenshot keystroke event (the actual platform screenshot signal on a
   physical device).
3. Push delivery to a **locked physical device** (real APNs/FCM to a locked
   handset).
4. Cold-boot disk forensics on a seized handset (physical-media recovery).

M3 "honest product" = host-max evidence for every row that a host can drive +
an explicit, honest device-QA checklist for this hardware-bound residue.

---

## 4. Flags

No USER-level concern. The library and the test-only rail are USER-settled;
the isolation mechanism, cross-check scope, and doc structure decided here are
CODE within that rail, with the architect dependency sign-off recorded in §1.
The one item for the orchestrator to log in `DECISIONS.md` at S18 wrap is this
note's CODE decision: separate `nimna.app/test-vectors/oracle` module +
the three-layer CI dep-graph exclusion.
