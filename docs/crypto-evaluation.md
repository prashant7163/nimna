# Nimna — Session 2 Crypto Evaluation

**Status: LOCKED (USER, 2026-07-04).** All four checkpoint questions (§14
Q1–Q4) answered as recommended at the Session 2 USER checkpoint; the CODE
items (framing, dependencies, test-vector strategy) carry tech-architect
sign-off. Decisions recorded in DECISIONS.md (S2 CHECKPOINT entries,
2026-07-04). This document is the reasoning record; the normative artifact
is `docs/nimna-protocol-spec-v0.2.md`.

Author: tech-architect · Date: 2026-07-04 · Inputs:
`docs/nimna-protocol-spec-v0.1.1.md` (§3, §4, §5, §7 primarily),
`DECISIONS.md` (through 2026-07-04), build plan Session 2 entry,
`designs/screens/03-safety-phrase.html` + voice guide (binding safety-phrase
design), library state verified by web research on 2026-07-04.

---

## 1. Executive summary

The recommended stack is deliberately the most boring one that satisfies
spec §7 — with two hardenings that the boring stack does not give for free
and that this evaluation argues are required for the spec's own claims to
hold:

1. **A hash pre-commitment in the pairing handshake** (ZRTP precedent,
   RFC 6189) — without it, a three-word safety phrase (~31 bits) is
   grindable by a MITM in minutes on GPUs, and the binding three-word
   design would be unsound. With it, three words are sound. It costs
   **zero extra round trips** (the commitment rides in the first pairing
   message, over the joiner's own keys).
2. **Memory-hard topic derivation** (Argon2id, RFC 9106) — without it,
   the relay-visible rendezvous topic ID is a fast-hash image of a 45-bit
   secret, and "the relay never sees the code" (§4) is hollow: one gaming
   GPU inverts SHA-256 over the full code space in under an hour. With it,
   recovering one code costs on the order of a thousand server-years.

Everything else is stock: X25519 + ChaCha20-Poly1305 + SHA-256/HKDF, a
Noise-pattern handshake implemented from the published spec in both stacks
(no Noise library — the Dart Noise ecosystem does not merit sign-off), a
Noise-KK session handshake with per-message rekeying instead of a Double
Ratchet, hand-specified fixed binary framing, and committed, regenerable
test vectors.

### Recommended stack at a glance

| Concern | Recommendation | One-line why |
|---|---|---|
| Key agreement | **X25519** (RFC 7748) | Constant-time by construction, no point-validation footguns, native in Go stdlib and libsodium; NIST curves aren't in libsodium at all. |
| AEAD | **ChaCha20-Poly1305, IETF 96-bit nonce** (RFC 8439) | Constant-time in software on every phone; no AES-NI assumption; first-class in both stacks. |
| Hash / KDF | **SHA-256 + HKDF-SHA-256** (RFC 6234 / RFC 5869) | Go stdlib (`crypto/hkdf` since Go 1.24); universal test vectors; whiteboard-familiar. |
| Slow KDF | **Argon2id** (RFC 9106), t=3, m=64 MiB, p=1 | Topic derivation + code-as-psk stretching; memory-hard kills GPU brute force of the 45-bit space. |
| Pairing handshake | **Noise `XXpsk2` pattern (implemented from the Noise spec) + commitment prologue**; psk = Argon2id-stretched code | Vetted pattern core with third-party vectors; commitment makes the 3-word phrase sound; psk makes a code-less relay MITM impossible in principle. |
| Session handshake | **Noise `KK` pattern** — fresh ephemerals, mutual static auth, 1 RTT | Per-session forward secrecy + post-compromise recovery; fits the synchronous knock/accept flow exactly. |
| In-session FS | **Per-message rekey** (Noise `Rekey`, spec §11.3) | Per-message forward secrecy without Double-Ratchet machinery; TCP ordering makes it trivial. |
| CRID | HKDF-SHA-256 over DH(static,static), 16 bytes | Identical on both ends, reveals nothing, re-derivable, no new persisted state. |
| Safety phrase | 3 words from a 1296-word list (EFF short wordlist 2.0 class), derived like the CRID with a different info string | ~31 bits; sound because of the commitment; re-derivable from the channel store. |
| Topic H(code) | HKDF(Argon2id(code)) with a UTC-date salt component | Slow to brute, precomputation-resistant, still "a hash of the code" per §4. |
| Wire framing | **Hand-specified fixed binary layout** (no CBOR, no protobuf) | Zero deps in both stacks; trivially parseable outer frame; fits the one-whiteboard bar. |
| Go deps | stdlib + `golang.org/x/crypto` (chacha20poly1305, argon2) | Signed off (§11). |
| Dart deps | `sodium` ^4 (libsodium via FFI/build hooks) + `crypto` (dart.dev) for SHA-256/HMAC | Signed off with noted verification items (§11); `cryptography`/`cryptography_flutter` and `noise_protocol_framework` sign-off withheld for core primitives. |

---

## 2. The whiteboard version

### 2.1 Pairing (once per channel, through the rendezvous bridge)

Both sides start from the 9-char Crockford Base32 code `C`
(canonicalized: uppercase, hyphens stripped, `I/L→1`, `O→0`):

```
seed  = Argon2id(C, salt = "nimna/topic/v1|" + UTC-date, t=3, m=64MiB, p=1, 32 bytes)
topic = HKDF(seed, info="topic")[0:16]        ← what the relay sees; never C
psk   = HKDF(seed, info="psk")   [0:32]       ← mixed into the handshake

Creator A registers on topic. Joiner B derives topic for today and, if no
match, yesterday (covers TTL across midnight). Relay bridges first joiner;
B is the Noise initiator, A the responder.

Noise_XXpsk2_25519_ChaChaPoly_SHA256, prologue = M0:

B → A   M0 ‖ M1:   M0 = SHA-256("nimna/commit/v1" ‖ eB.pub ‖ sB.pub)
                   M1 = Noise msg 1: e (empty payload, tagged — psk-pattern
                        rule: `e` also MixKeys, so a key exists; see spec
                        v0.2 §3.1.3 for exact bytes: M1 = 80)
A → B   M2:        Noise msg 2: e, ee, s, es, psk  + payload{ A's push token? }
B → A   M3:        Noise msg 3: s, se              + payload{ B's push token? }

A verifies M0 == SHA-256("nimna/commit/v1" ‖ eB.pub ‖ sB.pub); abort if not.
Any handshake failure kills the topic and the code — regenerate.

ss     = X25519(own static, peer static)          (same value on both ends)
salt2  = SHA-256(min(A.pub,B.pub) ‖ max(A.pub,B.pub))
CRID   = HKDF(ikm=ss, salt=salt2, info="nimna/crid/v1")[0:16]
phrase = 3 words ← HKDF(ikm=ss, salt=salt2, info="nimna/phrase/v1")[0:8]

Persist: own keypair, peer static pub, CRID (spec §6 list — unchanged).
Discard: code, seed, psk, ephemerals, handshake states.
```

Three messages, one commitment hash, one slow-hash call per device.
*(Sketch shorthand: the normative label strings, the 16-byte pre-hashed
Argon2id salt, and the exact byte tables live in spec v0.2 §3.1.2–§3.1.3.)*

### 2.2 Session (every knock → accept)

```
Relay plane (unencrypted routing):  KNOCK{crid, token?} → ACCEPT{crid} → bridged

Noise_KK_25519_ChaChaPoly_SHA256 (both statics known since pairing):

knocker  → S1:  e, es, ss     (no payload)
accepter → S2:  e, ee, se     (no payload)
Split → two cipher states (one per direction)

Each message frame: AEAD(key_dir, nonce = counter, ad = outer header) then
Rekey(key_dir).  Counters strictly increase per direction; receiver enforces.
HANGUP / disconnect → wipe session keys; every session starts from scratch.
```

---

## 3. Primitive set (spec §7 vs. candidates)

### 3.1 Key agreement — X25519 over P-256

| | X25519 | P-256 ECDH |
|---|---|---|
| RFC / pedigree | RFC 7748; ubiquitous (TLS 1.3, Signal, WireGuard, SSH, Noise) | FIPS 186 / SP 800-56A; ubiquitous |
| Misuse resistance | Constant-time by construction; no invalid-curve attacks by design; any 32 bytes is a valid public-key input (all-zero output check is the one rule, and both our libraries enforce it) | Historically a minefield of point-validation and non-constant-time scalar-mult bugs; modern APIs are fine, but the failure modes exist |
| Go | stdlib `crypto/ecdh` (since 1.20; relay pins Go 1.26) | stdlib `crypto/ecdh` |
| Dart | libsodium `crypto_scalarmult` / `crypto_kx` via `sodium` | **absent from libsodium** — would force a different, weaker Dart dependency |
| Noise suites | native DH function | not a standard Noise DH function |

The decisive point is the last row: libsodium — the only Dart-reachable
crypto core with an audited pedigree — has no NIST curves. Choosing P-256
would force the pure-Dart/platform-delegation route for the protocol's core
secret (§11 explains why that is rejected). **Recommend X25519.**

### 3.2 AEAD — ChaCha20-Poly1305 over AES-256-GCM

- AES-GCM is excellent **with hardware AES**. Software fallback AES is
  table-driven and cache-timing-prone; we cannot assert AES hardware across
  every Android device Nimna will ever run on. ChaCha20-Poly1305 is
  constant-time in plain software everywhere — that is why TLS on mobile
  preferred it pre-AES-NI.
- Both are AEADs with 96-bit nonces and equivalent security margins for our
  use (counter nonces, fresh keys per session, per-message rekey).
- Library fit: ChaCha20-Poly1305 is libsodium-first-class and the Noise
  default partner of X25519. RFC 8439, audited implementations everywhere.
- XChaCha20 (192-bit nonce) is unnecessary: we never use random nonces —
  counters under session-unique keys.

**Recommend ChaCha20-Poly1305 (IETF variant, 96-bit nonce).**

### 3.3 Hash / KDF — SHA-256 + HKDF-SHA-256

- SHA-256: RFC 6234, universal, hardware-accelerated on modern ARM,
  no secret-dependent branches or table lookups (relevant for the pure-Dart
  fallback discussed in §11).
- HKDF: RFC 5869, the extract-and-expand standard; in the Go standard
  library as `crypto/hkdf` since Go 1.24 (relay pins Go 1.26 — stdlib-first
  satisfied).
- Alternative BLAKE2b (libsodium-idiomatic, also a Noise hash) was
  considered: faster in software, but SHA-256 wins on Go-stdlib presence,
  ubiquity of third-party vectors, and whiteboard familiarity. Noise's HKDF
  is defined via HMAC for either hash, so the Dart composition work (§11.2)
  is identical either way.

**Recommend SHA-256 + HKDF-SHA-256.**

### 3.4 Slow KDF — Argon2id

RFC 9106; winner of the Password Hashing Competition; in
`golang.org/x/crypto/argon2` and in libsodium (`crypto_pwhash`, which is
Argon2id and hardcodes p=1 — hence our p=1 parameter choice for
cross-stack determinism). Used for exactly one job: stretching the 45-bit
code into the topic ID and the handshake psk (§9). scrypt is the only
comparable boring alternative; Argon2id is the current RFC-blessed choice
and present in both our libraries. **Recommend Argon2id.**

---

## 4. Pairing handshake (spec §3.1)

### 4.1 Noise pattern vs. bespoke composition — honest framing

Composing a documented handshake state machine from audited primitives is
**protocol composition, not primitive hand-rolling** — the standing rule
bans the latter, and either option below respects it. The question is whose
composition analysis we inherit:

- **A published Noise pattern** buys: a vetted composition (the Noise spec,
  revision 34, with formal analyses of the standard patterns via Noise
  Explorer and years of deployment — WireGuard is `IKpsk2`), a precise
  symmetric-state discipline (MixHash/MixKey — every byte of the transcript
  is bound into every key), and **third-party test vectors** (snow,
  cacophony, noise-c vector sets) that catch implementation divergence
  between our Go and Dart engines against a reference neither of us wrote.
- **A bespoke-but-documented X25519+HKDF exchange** buys: fewer moving
  parts (no generic pattern machinery), a shorter document. It costs: the
  composition analysis is entirely ours, and the only test vectors are the
  ones we generate — both implementations could share a bug and the vectors
  would bless it.

The Dart library reality (§11) rules out *Noise-the-library* but not
*Noise-the-spec*: the pattern machinery is a few hundred mechanical lines
per stack, written once, validated against third-party vectors, then reused
for both the pairing pattern and the session pattern (KK). That
amortization plus the external vectors decide it.

**Recommend: implement a minimal Noise engine (two patterns, one cipher
suite) from the Noise specification in both Go and Dart; no Noise library
dependency.**

### 4.2 Mixing the code into the key schedule (psk) — worth it?

Yes. With `psk` mixed into the chaining key, every AEAD operation from
message 2 onward is keyed by material an attacker cannot have without the
code. Consequences:

- **A relay-positioned adversary who never learned the code cannot MITM
  even in principle** — it cannot produce a single valid handshake message.
  Without the psk, relay-position MITM is merely *detected* (by the safety
  phrase); with it, MITM is *impossible* below code compromise. Given the
  relay is explicitly untrusted (§8 non-goals: "the protocol must not
  assume relay trust anywhere"), upgrading the pairing from
  detect-after-the-fact to fail-closed is exactly what the psk is for.
- **What it does NOT buy:** protection against a party who intercepted the
  code out-of-band — the spec's accepted §3.1 failure mode. Against them
  the safety phrase remains the (sufficient) defense, made sound by §5.
- **No offline-dictionary regression:** the psk is blended alongside
  full-entropy DH outputs, so a recorded transcript cannot be used to test
  code guesses offline — testing any candidate requires DH secrets the
  observer doesn't have. (The *topic ID* is the one code-derived value an
  observer can attack offline; §9 hardens it.) An active interposer gets
  exactly one online psk guess per handshake, and a failed handshake kills
  the code (§4.4).
- **Cost: zero.** The Argon2id call already exists for topic derivation;
  psk is a second HKDF expansion of the same seed.

**psk placement — `psk2`, not `psk0/psk1/psk3`:** with `psk0`/`psk1`, the
psk keys an AEAD tag in message 1 *before any DH is mixed* — a recorded
message 1 would become an offline test oracle for the 45-bit code space,
recreating the exact problem §9 exists to solve. With `psk3`, message 2's
payload (the creator's push token) is encrypted under `ee, es` only — an
active code-less interposer could read it before failing at message 3.
`psk2` mixes the psk at the end of message 2: the creator's payload and
everything after requires code knowledge, and no psk-only-keyed ciphertext
ever exists. (Residual nuance, stated honestly: in `XXpsk2` the creator's
static *public key* inside message 2 is encrypted under `ee` alone, so an
active code-less interposer who wins the race to the topic learns one
public key before the handshake fails — of a pairing attempt that then
aborts and regenerates its keypair with a fresh code. No secret, no
completed channel, no MITM. Accepted.)

### 4.3 Push-token payload in the same flight (§3.2.1)

Satisfied without extra messages: the creator's token rides as message 2's
Noise payload, the joiner's as message 3's. Both are under psk-mixed,
DH-fresh keys — to the relay they are indistinguishable ciphertext, as
§3.2.1 requires. Token refresh later travels as an encrypted CONTROL frame
inside sessions (§5 envelope), also already covered.

### 4.4 Failure discipline

Recommend for spec v0.2: **any handshake failure (bad commitment, bad AEAD
tag at any step, malformed message) kills the rendezvous topic and the
code; the creator regenerates code and keypair.** This structurally caps
online psk-guessing and phrase-grinding at one attempt per code, and costs
nothing against the threat model: a code-less prober cannot even find the
topic (§9), so only the relay itself could burn codes — and a malicious
relay can deny service trivially anyway (drop traffic). Joiner-side UX for
every failure is the already-locked generic response (DECISIONS
2026-07-04: expired = used = never-existed).

---

## 5. Safety-phrase soundness — the grinding attack and the commitment

### 5.1 The attack

Three words from a 1296-word list ≈ 2^31 phrases. A MITM bridges two
handshakes (A↔M, M↔B) and wants `phrase(A,M) == phrase(M,B)`. In any
naive DH exchange, whoever moves last can iterate their contribution
offline until the phrases collide before sending. 2^31 X25519+HKDF
evaluations is roughly 2×10^9 scalar mults — at published GPU curve25519
rates (order 10^6/s per device), **minutes to tens of minutes on a small
GPU rig**, comfortably inside the "seconds to minutes" a human waits on the
pairing screen. Three words are *unsound* without a countermeasure. (Going
to 6+ words instead would fight the binding three-word design and still
only buys ~2^62 — better, but the structural fix is cheaper and total.)

### 5.2 The fix — hash pre-commitment (ZRTP precedent, RFC 6189 §4.4.1.1)

The phrase derives from the two static keys (§2.1). The joiner (initiator)
sends `M0 = SHA-256(label ‖ eB.pub ‖ sB.pub)` **before the creator reveals
anything**, and both sides bind M0 into the handshake as the Noise
*prologue* (any disagreement fails the first AEAD). Now:

- The initiator's contribution is fixed at M0, before it has seen the
  responder's keys — it cannot grind.
- The responder reveals its static at message 2, when the initiator's
  static is still hidden behind the commitment — it cannot evaluate the
  phrase as a function of its own choice, so it cannot grind either.
- Both interleavings of a MITM's two handshakes hit one of those two walls
  (M must commit toward A before learning A's keys, and must reveal toward
  B before B opens its commitment).

Result: a MITM gets **one blind lottery ticket per handshake** at 2^-31
(≈ 1 in 2.1 billion), and a failed handshake kills the code (§4.4). Under
that, exactly three words are cryptographically sound.

**Extra flight required: none.** The commitment is over the initiator's own
keys, so it travels in the same flight as Noise message 1. The pairing
stays at three messages. (ZRTP needed a separate commit message because of
its negotiation phase; we don't.)

### 5.3 Phrase derivation and wordlist

- Derivation (§2.1): 8 HKDF output bytes → uint64 big-endian → three
  base-1296 digits → wordlist indices. Deterministic, bias < 10^-9,
  identical on both ends, ~10 lines in each stack.
- Deriving from `(ss, statics)` rather than the handshake transcript keeps
  the phrase **re-derivable from the channel store forever** (nothing new
  persisted; §6 list unchanged) and still detects MITM (a MITM by
  definition leaves different static pairs on the two sides). The
  commitment covers the statics, so grindability is unchanged.
- Wordlist: recommend the **EFF short wordlist 2.0 class** (1296 words,
  unique three-character prefixes, designed for reading aloud — which is
  exactly the "call them and compare" ritual). The mockup's "ember canyon
  plume" is illustrative; the final list is a design/USER item.
- **i18n flag (USER question, §14 Q5):** the phrase must render
  *identically on both devices* or verbal comparison breaks across locales.
  A single locale-independent (English) wordlist extends the "the Nimna
  code renders identically in all locales" doctrine (DECISIONS 2026-07-04)
  to the phrase; per-locale wordlists would localize beautifully and fail
  the moment an EN phone pairs with a DE phone. Recommendation: one global
  list; treat the words as protocol output (like the code), not UI copy.

---

## 6. Session handshake & forward secrecy (spec §3.2/§3.3, §7.3)

### 6.1 Noise KK per session

After pairing, both sides hold each other's statics — the textbook KK
shape: 2 messages, 1 RTT, mutual authentication (`es`/`se`/`ss`), fresh
ephemerals (`ee`) every session. Gives:

- **Per-session forward secrecy:** session keys require the ephemerals,
  which are wiped at hangup. Later compromise of both statics does not
  decrypt recorded past sessions.
- **Post-compromise recovery at session granularity:** an attacker who
  briefly held a device's keys but lost access is locked out again at the
  next session's fresh `ee`.
- A natural fit to the knock→accept flow: KK's two messages are simply the
  first two E2E frames after the relay bridges the CRID.

### 6.2 Per-message forward secrecy — chain, not Double Ratchet

Within a session, apply **Noise `Rekey` after every transport message**
(Noise spec §11.3 — a defined, in-spec operation: the AEAD encrypts a
zero block under the max nonce to produce the next key). Each direction
advances independently; the receiver rekeys after each successful decrypt.
Because a session is one TCP/WebSocket connection, frames per direction
arrive in order — no skipped-key storage, no out-of-order machinery.
Compromise mid-session exposes only messages from the current key forward,
nothing before.

**Why not the Signal Double Ratchet — assessed honestly:** the Double
Ratchet's genuinely hard parts (asynchronous DH ratchet steps, skipped-key
caches, header encryption) exist to heal and reorder across *offline*
gaps under *long-lived* sessions. Nimna is synchronous-only: sessions are
short-lived and a "gap" is a hangup, after which KK's fresh ephemerals
already deliver what a DH-ratchet step would. Async ratcheting buys
nothing here; it would add the protocol's largest state machine to service
a situation the protocol forbids. Library reality seals it: there is no
maintained Dart Double Ratchet implementation with a pedigree worth
sign-off (libsignal has no supported Dart binding; community ports are
stale) — we would be hand-implementing the *hardest* composition option.
KK + per-message rekey delivers §7.3's "per-message forward secrecy
(ratcheting) preferred" at a fraction of the surface.

### 6.3 Panic wipe (§6) — does the proposal deliver?

Yes. Inventory of what decrypts what:

| Material | Lifetime | Wipe effect |
|---|---|---|
| Statics (channel identity) | until wipe | destroyed → no future sessions, CRID/phrase underivable |
| Session ephemerals / handshake states | until Split | already gone at session end |
| Transport keys | one message each (Rekey) | current ones destroyed; older ones already gone |
| code / seed / psk | pairing only | discarded at finalization (spec §3.1.6) |

Past ciphertext (relay- or network-recorded) needs the ephemeral-derived
session keys, which no longer exist anywhere; the statics alone never
suffice (`ee` is mixed into every session). **Destroying keys makes past
ciphertext permanently undecryptable — §6's requirement holds.** (Local
history is separate plaintext-at-rest-encrypted storage and is destroyed by
the same wipe; that's Session 7 territory.)

---

## 7. Replay protection (§7.5)

- **Within a session:** AEAD nonces are per-direction message counters
  (96-bit nonce = 32-bit direction constant ‖ 64-bit counter); the receiver
  enforces strict increment. TCP ordering makes any regression a protocol
  error → hangup. Rekeying does not reset counters. A replayed frame
  cannot decrypt (its key no longer exists after Rekey) and would violate
  the counter discipline anyway.
- **Cross-session:** confirmed killed — every session's keys include fresh
  `ee`; a frame recorded in session N is noise under session N+1's keys.
  Pairing transcripts are equally dead: single-use topic, psk + ephemerals.
- **Relay-plane (KNOCK/ACCEPT/PEER_OFFLINE and teardown)** *[erratum
  2026-07-04: spec v0.2 removed `PEER_OFFLINE` from the knocker-visible
  wire entirely — the USER lapsed-knock decision is enforced at the wire,
  not only in UI; see v0.2 §3.2/§5.4]*: these are
  unencrypted *routing* frames — the relay must read them to route; they
  carry no message content and no secrets except the transient push token
  (§3.2.1, disclosed in the spec). They ride inside TLS, so no on-path
  party below the relay can inject or replay them; the only party who can
  "replay" a KNOCK is the relay itself — which could equally just invent
  one. Consequence of a forged/replayed knock: a push or an in-app knock
  and, if accepted, a bridge on which the impostor cannot complete the KK
  handshake — nothing decrypts, nothing is forged, the bridge dies. Impact
  is bounded to nuisance and is further capped by the §4 rate limits
  (knock 1/10s/CRID, push 1/60s + 6/hr + 20/day per CRID). This matches
  the spec's threat model (§9: relay operator sees/controls routing;
  protection is that there is nothing to steal, not that routing is
  authenticated). Acceptable; documented rather than defended.

---

## 8. CRID derivation (§3.1.6)

```
ss    = X25519(own static priv, peer static pub)        # equal on both ends
salt2 = SHA-256( min(A.pub, B.pub) ‖ max(A.pub, B.pub) ) # lexicographic, order-free
CRID  = HKDF-SHA-256(ikm=ss, salt=salt2, info="nimna/crid/v1", L=16)
```

- **Identical on both ends:** ss is symmetric; the salt sorts the pubs.
- **Reveals nothing:** HKDF output under a secret ikm is a PRF value; the
  relay sees a uniform 16-byte ID it cannot link to keys, codes, or other
  channels. Panic wipe destroys ss's inputs → even the device owner can no
  longer prove a CRID was theirs.
- **Length 16 bytes (128 bits):** collision probability across even
  billions of channels is negligible (birthday bound ~2^-64 at 2^32
  channels), and the CRID prefixes every frame — 16 bytes keeps the outer
  frame lean. 32 bytes buys nothing but overhead.
- **Re-derivable, never persisted-only:** recomputable from the §6 channel
  store at any time; no new persisted state, spec §6's inventory unchanged.

---

## 9. H(code) topic derivation & the 45-bit check

### 9.1 The problem with a plain hash

The relay (and only the relay — topics ride inside TLS) observes topic
IDs. With `topic = SHA-256(code)`, a malicious or compelled relay can
brute the 45-bit code space offline: 2^45 ≈ 3.5×10^13 SHA-256 evaluations
is **under an hour on one consumer GPU** (~2×10^10 H/s). Within the 24 h
TTL it recovers a live code — and under the psk design, the code *is* the
MITM capability (one phrase-lottery attempt, but still). It also makes §4's
"never sees: pairing codes (only their hashes)" claim substantively hollow.
**Plain-hash topics undermine the trade; the fix follows.**

### 9.2 The fix — Argon2id with fixed public parameters

```
seed  = Argon2id(canonical_code,
                 salt = "nimna/topic/v1|" + UTC-date(creation),
                 t=3, m=64 MiB, p=1, out=32)          # RFC 9106 2nd rec., p=1 for libsodium
topic = HKDF-SHA-256(seed, info="nimna/topic/v1")[0:16]
psk   = HKDF-SHA-256(seed, info="nimna/psk/v1")[0:32]
```

- **Phone cost:** one call per pairing per device, ~0.2–0.8 s on current
  hardware (p=1; libsodium's Argon2id is parallelism-1, so p=1 keeps Go
  and Dart outputs identical). Verify on real low-end devices at
  integration; if intolerable, m=32 MiB is the fallback — decide before
  vectors are locked.
- **Attacker cost:** Argon2id at 64 MiB is memory-bandwidth-bound;
  a high-end server sustains order 10^2–10^3 guesses/s (GPUs gain little —
  that is the point of RFC 9106). Full sweep: 3.5×10^13 / 10^3 ≈ 3.5×10^10
  server-seconds ≈ **~1,100 server-years per code**. To cover one code's
  24 h TTL you would need hundreds of thousands of high-end servers for an
  expected hit — against a single burner pairing code. Compare: <1 GPU-hour
  with SHA-256.
- **The date-salt component kills precomputation:** with a fixed salt only,
  a nation-state-class adversary could spend those ~10^3 server-years
  *once*, store code→topic for the whole space (~1 PB), and thereafter
  invert every topic forever. Salting with the code's UTC creation date
  makes any table worthless the next day. Cost: the joiner derives for
  today and, on no-match, yesterday (TTL ≤ 24 h ⇒ two candidates always
  suffice; a device clock wrong by more than a day fails like a typo —
  regenerate). Two topic registrations fit inside the §4 rendezvous
  throttle. If USER judges the two-candidate probe too much protocol
  surface, the fixed-salt variant is still a ~1,100-server-year-per-code
  defense — but the date salt is cheap and recommended.
- **Relay compatibility:** the relay still sees "clients register on an
  opaque 16-byte topic" — statelessly indistinguishable whether a topic is
  expired, used, or never existed, which is precisely the RESOLVED generic
  code response decision (DECISIONS 2026-07-04). Spec v0.2 keeps calling it
  "a hash of the code"; it just stops being a *fast* one.

### 9.3 The verdict on the 45-bit trade

**HOLDS under the recommended design.** The arithmetic, layer by layer:

1. **Online guessing through the relay** (the threat §4's throttling
   addresses): at single-digit attempts/min/IP, even a 10,000-IP botnet
   sustains ~10^8 rendezvous probes/day against a space of 3.5×10^13 —
   ≈ 3×10^-6 probability against any single live code, before the guesser
   still faces the psk-authenticated handshake and the phrase. Lottery no
   one wins — as the spec already claims.
2. **Offline inversion of an observed topic** (the threat throttling does
   NOT address): sealed by Argon2id + date salt as computed above. This
   layer is *required* — with plain SHA-256 the trade would NOT hold
   against a relay-positioned adversary.
3. **Even on full code compromise** (out-of-band interception — accepted
   §3.1 failure mode): the attacker gets one interposition attempt, the
   commitment denies grinding, and the phrase catches it at odds of 2^-31.
   Silence discipline (no failed-attempt notifications, generic code
   responses) leaks nothing back.

45 bits was never asked to resist offline attack by itself; the design's
job is to ensure nothing an attacker can observe is a fast-checkable
function of the code, and that every online path is throttled, one-shot,
or phrase-guarded. With the recommendations above, all three hold.

---

## 10. Wire framing (spec §5 → v0.2 exact bytes)

**Candidates:** hand-specified fixed binary · CBOR (RFC 8949) · protobuf.

- **Protobuf:** codegen toolchains in two stacks, a runtime dep in each,
  schema-evolution machinery we don't need for a protocol whose spec is
  the source of truth. Fails "minimal, boring, justified". Rejected.
- **CBOR:** self-describing and RFC-standardized, but brings a parsing
  dependency into both stacks (fxamacker/cbor in Go — good, but a dep;
  a Dart cbor package of moderate adoption), canonical-encoding pitfalls
  (maps, indefinite lengths) that must be constrained anyway for
  deterministic test vectors, and it papers over exactly the thing the
  spec wants explicit: the bytes. Rejected — runner-up.
- **Hand-specified fixed binary:** zero dependencies in both stacks,
  deterministic by construction (test-vector friendly), and the encoder/
  decoder in each stack is ~100 lines of obvious code. The envelope has
  five message types with fixed headers — this is exactly the case where
  a hand layout is *less* complexity, not more. A leading version byte
  in both planes leaves room to evolve. **Recommended.**

Sketch for v0.2 (exact layout is spec v0.2's deliverable, not this doc's):

```
Outer (relay-visible, trivially parseable):
  [ver:1][frame_type:1][CRID:16][payload…]        # big-endian throughout
  frame_type ∈ relay-plane (REGISTER_TOPIC, KNOCK, ACCEPT, …)
             # erratum: PEER_OFFLINE removed in spec v0.2 (§3.2, §5.4)
             | data-plane (E2E: payload = AEAD ciphertext)

Inner envelope (plaintext of the AEAD, per §5):
  [ver:1][type:1][flags:1][msg_id:16][timestamp:8][body…]
  type ∈ TEXT | ACK | CONTROL | HANGUP | MEDIA_CHUNK
  TEXT: flags bit 0 = expiry present → [expiry_s:4] then UTF-8 body
  MEDIA_CHUNK: manifest frame (chunk_count:4, total_len:8, content_hash:32,
               mime as len-prefixed UTF-8) then indexed chunk frames

AEAD binding: ad = outer header (ver‖frame_type‖CRID); nonce = direction
constant ‖ message counter. Ciphertext is bound to its channel and position.
```

The outer frame stays `[CRID][opaque blob]` in spirit exactly as §5
promises; the relay parses 18 bytes and routes.

---

## 11. Library reality, both stacks (verified 2026-07-04)

### 11.1 Go (relay + Session 3–4 test clients + vector generator)

| Need | Source | Status |
|---|---|---|
| X25519 | stdlib `crypto/ecdh` | in stdlib since Go 1.20; relay pins Go 1.26 ✓ |
| HKDF-SHA-256 | stdlib `crypto/hkdf` | in stdlib since Go 1.24 ✓ |
| SHA-256 | stdlib `crypto/sha256` | ✓ |
| ChaCha20-Poly1305 | `golang.org/x/crypto/chacha20poly1305` | canonical, Go-team-maintained; a stdlib promotion proposal is open but not landed — x/crypto remains the blessed home |
| Argon2id | `golang.org/x/crypto/argon2` | same module ✓ |

**One dependency (`golang.org/x/crypto`), pinned; everything else stdlib.
Nothing further is needed. Tech-architect sign-off: GIVEN.**

### 11.2 Dart/Flutter

**`sodium` ^4.0.2 (skycoder42.de, verified publisher) — RECOMMENDED,
sign-off GIVEN** with the verification notes below.

- libsodium via FFI: the audited, battle-tested C core does the actual
  crypto; Dart is a thin binding. This is the only Dart route where the
  constant-time properties of X25519/ChaCha20-Poly1305 are inherited from
  audited native code rather than reimplemented.
- As of v4 the binaries are built on demand via Dart build hooks — stable
  since Flutter 3.38/Dart 3.10 (Nov 2025); the project pins Flutter 3.44.2,
  well past it. (The old `sodium_libs` companion is explicitly discontinued;
  do not use it — depend on `sodium` directly.)
- `SecureKey` keeps key material in native memory with explicit zeroing —
  directly serves the panic-wipe posture.
- Honest caveats: single-maintainer binding (mitigated by the thinness of
  the layer and the audited core beneath), moderate adoption (~14.5k
  weekly downloads). **Verify at integration (S9):** raw
  `crypto_scalarmult` and `crypto_pwhash` live in the binding's *sumo*
  variant — pin `sodium`'s sumo initialization; confirm the AEAD class
  exposes the IETF ChaCha20-Poly1305 variant.
- **Known gap:** the binding exposes libsodium's default `crypto_auth`
  (HMAC-SHA-512-256) but not HMAC-SHA-256, and no HKDF (libsodium ≥1.0.19
  has `crypto_kdf_hkdf_sha256`, but it is not surfaced in the Dart API
  docs). Plan: take SHA-256/HMAC-SHA-256 from **`crypto` (the dart.dev
  Dart-team package — maximally boring)** and compose HKDF per RFC 5869
  (two HMAC formulas, ~10 lines), validated against RFC 5869 Appendix A
  and RFC 4231 vectors and cross-checked byte-for-byte against Go stdlib
  in the committed vector suite. Hash/HMAC code has no secret-indexed
  lookups or branches, so pure-Dart execution is side-channel-benign here
  — unlike curve or cipher code, which stays in libsodium. This is
  composition-with-published-vectors, the same class as the Noise engine
  itself; flagged for explicit code-reviewer attention.

**`cryptography` 2.9.0 / `cryptography_flutter` 2.3.4 (dint.dev) —
sign-off WITHHELD for core primitives.** Well-liked (310 likes, ~419k
weekly downloads) and it delegates *some* algorithms to platform APIs —
but the delegation matrix is the problem: on Android, X25519 is **not**
delegated (javax.crypto has no X25519), so the protocol's core secret
would run through pure-Dart bignum arithmetic with GC-managed key
material and no constant-time guarantees. For a privacy product, that
side-channel posture is not acceptable for key agreement or AEAD.
Acceptable, if ever needed, strictly for hash/HMAC/HKDF (side-channel-
benign class) — though `crypto` (dart.dev) is preferred even there.

**`noise_protocol_framework` 1.2.0 — sign-off WITHHELD.** Pure Dart,
4 likes, ~62 weekly downloads, niche adoption, and it pulls `pointycastle`
+ `elliptic` (pure-Dart curve arithmetic) for the DH — the same
side-channel objection plus an immature-dependency objection. This is the
concrete reason "Noise via library" loses to "Noise via spec" (§4.1).

**No other Dart crypto dependency is proposed.** Final Dart set:
`sodium` (X25519, ChaCha20-Poly1305, Argon2id, secure memory) +
`crypto` (SHA-256/HMAC) + in-repo HKDF/Noise-engine composition.

---

## 12. Test-vector strategy

Auditors must be able to regenerate everything; a git-ignored script would
defeat that, so the generator is **committed source**.

```
docs/test-vectors/
  README.md                 # what each file proves; how to regenerate
  topic-derivation.json     # codes (incl. canonicalization: case, hyphens,
                            #   I/L→1, O→0) → seed → topic, psk; both salt
                            #   variants; plus reduced-cost params for CI
  pairing-handshake.json    # fixed randomness → full M0..M3 byte
                            #   transcripts, per-step chaining keys, Split
                            #   outputs, CRID, phrase indices+words
  session-handshake.json    # KK transcripts + first N transport frames,
                            #   rekey chain, counter/nonce discipline
  phrase-words.json         # HKDF output → word indices → words
  framing.json              # envelope encode/decode incl. MEDIA_CHUNK
                            #   manifest and edge cases (max sizes, flags)
  generator/                # committed Go module (own go.mod, pins the
                            #   same x/crypto version as the relay);
                            #   `go run ./generator` rewrites all JSON
                            #   deterministically from fixed seeds
```

- JSON with hex-encoded fields: diffable, language-neutral, auditable by
  eye.
- All "randomness" (statics, ephemerals, msg_ids, timestamps) is spelled
  out in each vector — deterministic transcripts per the plan.
- CI check: regenerate and `git diff --exit-code` — the vectors can never
  silently drift from the generator.
- Cross-validation: the Noise engine additionally runs against third-party
  vector sets (snow/cacophony) for `XX`/`KK`/psk patterns, so both our
  stacks are checked against an implementation we didn't write; the Dart
  test suite (S9+) consumes the same committed JSON.
- Argon2id vectors carry production parameters (for auditors) plus a
  reduced-cost parameter set (for fast unit tests) — clearly labeled.

Production vectors are generated once the USER lock lands and are frozen
alongside spec v0.2.

---

## 13. Alternatives considered (summary of the "why nots")

- **P-256 + AES-GCM:** capable primitives, but P-256 is absent from
  libsodium (forcing the weak Dart route), historically footgun-rich, and
  AES-GCM's constant-time story depends on hardware we can't assert on all
  Android devices. No compensating advantage. (§3)
- **Noise via library:** Go-side options exist, but the only Dart Noise
  package is immature and built on pure-Dart curves — sign-off withheld.
  Noise via spec-reimplementation keeps the vetted composition and the
  third-party vectors without the dependency. (§4.1, §11)
- **Plain Noise XX without psk/commitment:** leaves relay-position MITM
  merely detectable and the three-word phrase grindable — unsound against
  the stated attack. Rejected. (§4.2, §5)
- **Bespoke X25519+HKDF handshake:** legitimate and simpler-looking, but
  we would own the composition analysis alone and lose external vectors;
  chosen against, narrowly. (§4.1)
- **Signal Double Ratchet:** solves asynchrony Nimna forbids; largest
  state machine of any option; no sign-off-able Dart implementation.
  KK-per-session + per-message rekey delivers the §7.3 requirement. (§6.2)
- **PAKE on the code (CPace/SPAKE2):** the academically "right" tool for
  low-entropy secrets — it would remove even the one-shot online psk
  guess. Rejected on the boring-tools rule: no audited, maintained
  implementations across *both* Go and Dart, and psk-mixing + Argon2id +
  commitment + phrase reaches the same practical outcome with standard
  parts. Revisit only if the dependency landscape changes.
- **Post-quantum (hybrid X25519+ML-KEM):** no PQ requirement in spec §7;
  hybrid KEMs would double handshake size and pull heavyweight deps into
  Dart today. Noted as a future spec-revision candidate (the Noise-style
  key schedule extends to hybrid inputs cleanly); not v1.

---

## 14. Drafted USER checkpoint questions

*(Tech-architect recommendation marked ►. Nothing below is decided.)*

**Q1 — Primitive suite.** Lock X25519 + ChaCha20-Poly1305(IETF) +
SHA-256/HKDF-SHA-256 + Argon2id as the only protocol primitives?
Options: (a) ► as listed; (b) P-256/AES-GCM suite; (c) BLAKE2b in place of
SHA-256. Recommendation: (a) — §3.

**Q2 — Pairing handshake shape.** Options: (a) ► Noise `XXpsk2`
(implemented from the Noise spec, no library) + commitment prologue +
code-as-psk — 3 messages, relay-MITM impossible without the code, phrase
sound; (b) bespoke documented X25519+HKDF exchange with the same
commitment/psk properties — simpler machinery, no third-party vectors;
(c) plain Noise XX, phrase-only defense — rejected as unsound (§5).
Recommendation: (a).

**Q3 — Topic derivation.** Options: (a) ► Argon2id(t=3, m=64 MiB, p=1)
with UTC-date salt component (joiner probes today/yesterday);
(b) Argon2id with fixed salt only (simpler; accepts the one-time global
precomputation exposure); (c) plain SHA-256 — rejected, breaks the 45-bit
trade (§9). Recommendation: (a); (b) acceptable if the two-candidate probe
is judged too much surface.

**Q4 — Session shape.** Options: (a) ► Noise `KK` per session +
per-message `Rekey`; (b) KK without per-message rekey (session-level FS
only — meets §7.3's minimum, not its preference); (c) Double Ratchet —
rejected (§6.2). Recommendation: (a).

**Q5 — Safety-phrase wordlist & locale policy (genuine USER call:
user-facing + i18n scope).** Options: (a) ► one locale-independent
1296-word list (EFF short wordlist 2.0 class, chosen for read-aloud
distinctiveness) rendered identically in all five launch locales — extends
the "code renders identically" doctrine; (b) per-locale wordlists — native
words, but verbal comparison breaks whenever the two phones' locales
differ; (c) a larger list (e.g., 2048+ words) for more bits — unnecessary
once the commitment makes 2^31 sound, and longer/odder words hurt the
call-and-compare ritual. Recommendation: (a). Follow-up if (a): confirm
the exact list at design time (mockup words are illustrative).

**Q6 — Wire framing.** Options: (a) ► hand-specified fixed binary layout
(version-byte-led, big-endian, zero deps); (b) CBOR (one parsing dep per
stack, canonicalization constraints). Recommendation: (a).

**Q7 — Dart crypto dependencies (formal sign-off confirmation).**
(a) ► `sodium` ^4 (libsodium FFI) + `crypto` (dart.dev) for SHA-256/HMAC,
with HKDF composed per RFC 5869 and vector-locked — sign-off given, S9
verification notes listed in §11.2; (b) `cryptography`/
`cryptography_flutter` as core — sign-off withheld (§11.2);
(c) `noise_protocol_framework` — sign-off withheld. Recommendation: (a).

---

## 15. Spec v0.1.1 conflicts & drift noticed (for the spec v0.2 edit)

None of these block the evaluation; all should be resolved in v0.2:

1. **HANGUP appears in two planes:** §3.3 has HANGUP as a relay-visible
   teardown signal; §5 lists HANGUP as an *encrypted* envelope type.
   Recommend both, explicitly: an authenticated inner HANGUP (so a
   malicious relay cannot forge a graceful "peer ended" — it can only
   produce a "connection lost") plus socket close/relay-plane teardown for
   the routing layer. v0.2 must name them distinctly.
2. **Code canonicalization must be pinned:** four join methods (§3.1.3)
   must all derive the same topic — v0.2 must specify Crockford decode
   rules (case-fold, strip hyphens, I/L→1, O→0) and the QR payload format
   before hashing. Not stated anywhere yet.
3. **§3.1.5's "word/emoji sequence (e.g.)"** vs. the binding three-word
   design (designs/screens/03, voice guide): not a conflict — the design
   is a valid instance — but v0.2 should state "exactly three words" and
   the derivation, ending the "e.g.".
4. **§4 "never sees: pairing codes (only their hashes)"** is only
   substantively true with slow-hash topic derivation (§9); with a fast
   hash it would be true-but-hollow for a 45-bit input. v0.2 should specify
   the Argon2id construction as part of that claim's honesty.
5. **Failure discipline for interrupted pairing** (who retries, does the
   topic survive a failed handshake) is unspecified in §3.1; §4.4
   recommends fail-closed (topic + code die). Interacts with the RESOLVED
   generic-code-response decision — the recommended relay design satisfies
   it structurally (stateless topic tables cannot distinguish expired/
   used/never-existed even internally).
6. **Both 2026-07-04 RESOLVED protocol flags** (generic code response;
   attribution-free lapsed knocks) are compatible with everything here and
   are carried into the v0.2 requirements list — noted so the v0.2 editor
   does not have to rediscover them.
7. **§6 channel-store inventory needs no additions** under the recommended
   design (CRID and phrase re-derivable from statics). If the USER instead
   prefers a transcript-bound phrase at Q5-adjacent discussion, §6 would
   need a persisted `phrase_seed` field — decision-dependent, flagged.
8. **i18n decision (2026-07-04) touches the phrase** (§5.3): the
   locale-independence doctrine currently names the Nimna code; Q5 extends
   it (or not) to the safety phrase. Whichever way Q5 lands, v0.2 should
   state the phrase's locale behavior explicitly.
