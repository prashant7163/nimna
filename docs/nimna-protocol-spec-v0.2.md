# Nimna Protocol Specification — v0.2

**Status:** Locked, normative. **This document supersedes v0.1.1** and is
the single source of truth for all implementation work. It is complete and
self-contained — v0.1.1 remains in the repository as history only. The
cryptographic design was evaluated in `docs/crypto-evaluation.md` (the
reasoning record) and locked by USER decision on 2026-07-04 (DECISIONS.md,
seven Session-2 entries). Protocol changes from here require a USER
decision.

**One-line summary:** Nimna is a synchronous, end-to-end encrypted,
account-less 1:1 messaging protocol in which a stateless relay routes
ciphertext between two live device connections and never stores anything.

**Changelog — what v0.2 adds over v0.1.1** (nothing doctrinal was removed):

- **Primitives locked (§7):** X25519 · ChaCha20-Poly1305 (IETF) ·
  SHA-256 / HKDF-SHA-256 · Argon2id. No other cryptography exists in the
  protocol.
- **Pairing handshake made concrete (§3.1.3):**
  `Noise_XXpsk2_25519_ChaChaPoly_SHA256` with a commitment prologue
  (grind-proof safety phrase) and the pairing code mixed in as psk
  (a relay that never learned the code cannot MITM even in principle).
  Push tokens ride in the handshake payloads, as §3.2.1 always required.
- **Session handshake made concrete (§3.3.1):**
  `Noise_KK_25519_ChaChaPoly_SHA256` per session — fresh ephemerals, mutual
  authentication, per-session forward secrecy — plus per-message rekeying
  for per-message forward secrecy.
- **Exact derivations (§3.1.1–§3.1.5):** code canonicalization and QR
  payload; rendezvous topic and psk via Argon2id with a UTC-creation-date
  salt; CRID (16 bytes) and safety phrase (exactly three words, one global
  wordlist) from the channel's static key material.
- **Exact wire framing (§5):** fixed binary layouts for the relay-visible
  outer frame, the relay-plane message set, and the encrypted inner
  envelope including MEDIA_CHUNK.
- **Failure discipline (§3.1.6):** pairing is fail-closed — any handshake
  failure kills the topic and the code.
- **Relay max frame size concretized (§4, §5.1):** default 128 KiB
  (v0.1.1 named no number); sized to carry a full 65,536-byte MEDIA_CHUNK
  transport frame.
- **Knock hold & relay inventory made exact (§4):** pending knocks are held
  in relay memory for a fixed **60 s** (v0.1.1 said "e.g., 60s"); the
  relay's transient in-memory inventory is enumerated in full — topic
  registrations (capped at 24 h per connection), CRID registrations,
  bridges, pending knocks, rate/push counters — all the same
  dies-with-the-process class as before.
- **Non-goals extended (§8):** post-quantum key exchange and traffic
  padding/length hiding are now explicit v1 non-goals.
- **Two USER protocol decisions of 2026-07-04 stated normatively:**
  expired, used, and never-existed codes are indistinguishable to a joiner
  (one generic response surface, §3.1.6); lapsed knocks carry no
  attribution — the knocker-visible surface never distinguishes offline
  from seen-and-ignored, and `PEER_OFFLINE` is therefore no longer a
  knocker-visible wire message (§3.2).
- **HANGUP split into two named things (§3.3, §5):** the encrypted,
  authenticated `HANGUP` envelope (end-of-session, unforgeable by the
  relay) and the relay-plane `TEARDOWN` frame (routing housekeeping).
- **Threat model updated (§9):** pairing-time MITM row rewritten for the
  locked handshake; offline topic-brute row added; relay-plane replay
  stated honestly.

---

## 1. Design principles

1. **Zero server storage.** The relay never writes message content,
   metadata records, or queues to disk. All routing state lives in memory
   for the lifetime of active connections only.
2. **No identity.** No accounts, phone numbers, emails, or usernames. A
   channel is defined solely by two device-held keypairs.
3. **Synchronous only.** Messages flow only when both peers hold live
   connections to the relay. There is no store-and-forward.
4. **E2E encryption.** The relay routes opaque ciphertext. Plaintext exists
   only on the two paired devices.
5. **Code is ephemeral.** The pairing code exists only to rendezvous during
   first pairing. After key exchange, it is discarded and never reused.
6. **Minimal metadata.** The relay necessarily observes: channel routing
   IDs, connection times, IP addresses, and ciphertext sizes/timing. It
   observes nothing else. The relay is open source so this claim is
   auditable.

## 2. Entities and terms

| Term | Meaning |
|---|---|
| **Device** | A phone running the Nimna app. One device per person per channel. |
| **Relay** | The stateless WebSocket router. Open source. |
| **Channel** | A paired 1:1 connection between exactly two devices, identified by their two static public keys. Permanent once paired, until either side deletes it. |
| **Pairing code** | Short, human-shareable, single-use code used only for rendezvous during pairing. User-facing name: **"Nimna code."** |
| **Rendezvous topic** | The 16-byte identifier both devices derive from the code (§3.1.2). The relay matches pairing peers on it and never sees the code itself. |
| **psk** | A 32-byte secret both devices derive from the code (§3.1.2), mixed into the pairing handshake so code knowledge is required to complete it. |
| **Static keypair** | The fresh X25519 keypair each device generates for a channel at pairing. The channel *is* these two keypairs. |
| **Channel routing ID (CRID)** | An opaque 16-byte identifier derived from the channel's key material (§3.1.5), used by the relay to match the two peers. Reveals nothing about the devices. |
| **Safety phrase** | Exactly three words both devices derive from the channel's key material (§3.1.4), compared out-of-band by the two humans. |
| **Knock** | A request from one peer to open a live session on a channel. |
| **Session** | A live window during which both peers are connected and messages flow, keyed by a fresh handshake (§3.3.1). |

## 3. Protocol phases

### 3.1 Pairing (one-time per channel)

1. **Initiation.** Device A generates a fresh X25519 static keypair
   (A_pub, A_priv) and a pairing code `C` (format: **9 characters,
   Crockford Base32, displayed as XXX-XXX-XXX** — fixed permanently, see
   §3.1.1 and §4). The app displays **both the text code and its QR
   encoding simultaneously**, each independently shareable through
   different channels. A derives the rendezvous topic and psk from the
   code (§3.1.2), opens a WebSocket to the relay, and registers interest
   in the topic — a slow hash of the code, so the relay never sees the
   code itself.
2. **Out-of-band share.** A shares `C` with B outside Nimna (verbally, QR
   in person, any channel). The code has a TTL (default: 24h, configurable
   at generation; shorter = safer). The share sheet carries a one-line
   briefing: *"Works once, expires in 24h — share it like a password."*
   Beyond that nudge, the sharing channel is the user's domain and its
   risks are theirs; Nimna does not pretend to control it.
3. **Join.** Device B generates its own fresh X25519 static keypair
   (B_pub, B_priv), canonicalizes the code (§3.1.1), derives the topic
   candidates and psk (§3.1.2), connects to the relay, and registers on
   the topic. B may supply the code by any of four methods: (i) manual
   entry, (ii) paste from clipboard, (iii) live QR scan, (iv) upload of a
   QR image or PDF. All four canonicalize to the same bytes and therefore
   the same topic.
4. **Key exchange.** When both are present on the topic, the relay bridges
   them. **First-come-wins:** the topic bridges its first two registrants
   and closes to further joiners; it dies when either bridged connection
   drops. Across the bridge, A and B run the pairing handshake (§3.1.3):
   an authenticated key agreement bound to the code, carrying each side's
   push device-token E2E-encrypted (§3.2.1). All handshake and payload
   bytes are opaque to the relay.
5. **Verification (recommended).** Both apps derive the **safety phrase**
   — exactly three lowercase words (§3.1.4) — from the channel key
   material and display it. The phrases on the two legitimately paired
   devices always match; the check works only when compared
   **out-of-band with the intended human** (a call, or in person — the
   same trusted channel the code traveled). If a MITM interposed, the two
   victims' phrases derive from different keys and won't match; if an
   interceptor paired in B's place, the real B has no phrase at all. UX:
   designed as the natural closing ritual of pairing ("call them and
   compare"), strongly encouraged, not enforced. The phrase is rendered
   from one global wordlist, identically in every locale (§3.1.4).
6. **Finalization.** Both devices derive the **CRID** from the shared key
   material (§3.1.5), persist the channel locally (peer static public key,
   own static keypair, CRID, user-chosen local label), and **discard the
   pairing code, seed, and psk permanently**. The rendezvous topic dies at
   the relay; codes are single-use and cannot be replayed.

**Failure modes:** code expires unused → nothing was created, A simply
regenerates. A third party who intercepts `C` before B uses it can pair
with A in B's place — mitigated by the safety-phrase check and code TTL; a
misplaced code is abusable at most once, within its window. Once a channel
is finalized, the code is structurally dead: later attempts hit a
rendezvous topic that no longer exists and receive silence. Any failure
*during* the handshake kills the topic and the code (§3.1.6). **No
failed-attempt notifications** are ever surfaced to the user — there is
nothing actionable to report, and a discretion product does not manufacture
anxiety.

### 3.1.1 Code format, canonicalization & QR payload

- **Generation:** 9 characters sampled uniformly at random from the
  32-character Crockford Base32 alphabet
  (`0123456789ABCDEFGHJKMNPQRSTVWXYZ` — no I, L, O, U), giving a space of
  2^45 ≈ 35 trillion codes. Displayed and entered as `XXX-XXX-XXX`. This
  format never changes.
- **Canonical form:** the 9 characters, uppercase, without hyphens —
  exactly 9 ASCII bytes. This byte string is the only form ever hashed.
- **Canonicalization of input** (applies identically to all four join
  methods): strip whitespace (exactly: ASCII space, tab, CR, LF) and
  hyphens; fold to uppercase; map `I → 1`,
  `L → 1`, `O → 0` (Crockford decode rules). `U` is not in the alphabet
  and is invalid — reject, don't map. Anything that does not canonicalize
  to exactly 9 alphabet characters is invalid input (client-side error;
  nothing is sent).
- **QR payload:** the ASCII string `nimna:XXX-XXX-XXX` (canonical
  characters, display hyphenation, `nimna:` prefix lowercase). Scanners
  accept the payload with or without the prefix and hyphens — the
  canonicalization above makes all forms converge. A QR carries nothing
  else: no expiry hint, no version, no metadata (a code is a code;
  distinct payloads per case would create distinguishable codes, see
  §3.1.6).

### 3.1.2 Rendezvous derivation: topic and psk

Both devices derive, from the canonical code bytes:

```
date  = UTC date of code creation, "YYYY-MM-DD" (10 ASCII bytes)
salt  = SHA-256("nimna/topic/v1|" + date)[0:16]          # 16 bytes
seed  = Argon2id(password = canonical_code_bytes,        # 9 bytes
                 salt     = salt,
                 t = 3, m = 64 MiB, p = 1,               # Argon2 v1.3
                 out = 32 bytes)
topic = HKDF-SHA-256(ikm = seed, salt = empty, info = "nimna/topic/v1")[0:16]
psk   = HKDF-SHA-256(ikm = seed, salt = empty, info = "nimna/psk/v1")[0:32]
```

- All label strings are ASCII, no terminators. HKDF salt is zero-length
  (RFC 5869 default). Argon2id parameters are fixed protocol constants
  (p = 1 matches libsodium's `crypto_pwhash`, keeping both stacks
  byte-identical). The salt is pre-hashed to 16 bytes because libsodium's
  API takes exactly 16 salt bytes.
- **The creator** uses its code-creation date. **The joiner** derives the
  topic for today (its own UTC date) and registers; if no bridge forms, it
  also derives and registers yesterday's — two candidates always cover a
  TTL ≤ 24h. A device clock wrong by more than a day fails like a typo:
  regenerate the code. The joiner computes at most two Argon2id calls
  (~0.2–0.8 s each on current phones), once per pairing — never in any
  other flow.
- **Why a slow, date-salted hash (honesty note):** the relay observes
  topic IDs. A fast hash of a 45-bit secret would let anyone holding a
  topic ID recover the live code offline in under an hour on one consumer
  GPU — making "the relay never sees the code" true only on a
  technicality. Argon2id at these parameters is memory-hard: a full-space
  sweep costs on the order of a thousand server-years per code, and the
  date salt makes any precomputed table worthless the next day. The claim
  in §4 is honest because of this construction.

### 3.1.3 Pairing handshake

`Noise_XXpsk2_25519_ChaChaPoly_SHA256` per the Noise Protocol Framework
(revision 34), implemented from the specification in both stacks — there
is no Noise library dependency. The **joiner is the Noise initiator**; the
creator is the responder. The relay is role-blind: it bridges the topic's
first two registrants and forwards opaque `PAIR_DATA` frames (§5.4).

**Commitment prologue.** Before its first Noise message, the joiner
computes over its own fresh keys:

```
M0 = SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub)        # 15 + 32 + 32 bytes in
```

Both sides use `M0` (32 bytes) as the Noise **prologue** (mixed into the
handshake hash after protocol-name initialization; any disagreement fails
the first AEAD). The commitment fixes the joiner's contributions before
the creator reveals anything, and the creator's are revealed before the
commitment opens — neither side, nor a bridging MITM, can grind key
material against the safety phrase (§9). It costs no extra round trip:
M0 travels in the same frame as Noise message 1.

**Message sequence** (message pattern `→ e` · `← e, ee, s, es, psk` ·
`→ s, se`; per Noise rules for psk patterns, `e` tokens also MixKey the
ephemeral public key):

| # | Dir | PAIR_DATA payload (exact bytes) | Size |
|---|---|---|---|
| M1 | joiner → creator | `M0 (32) ‖ eB_pub (32) ‖ tag over empty payload (16)` — psk-pattern rule: `e` also MixKeys its public key, so message 1's empty payload is tagged | 80 |
| M2 | creator → joiner | `eA_pub (32) ‖ enc(sA_pub) (48) ‖ enc(token_payload_A) (n+16)` — Noise msg 2; psk mixed before the payload | 96 + n |
| M3 | joiner → creator | `enc(sB_pub) (48) ‖ enc(token_payload_B) (n+16)` — Noise msg 3 | 64 + n |
| M4 | creator → joiner | `PAIR_CONFIRM`: ChaCha20-Poly1305(key = Split's responder→initiator key, nonce = `0x00000001 ‖ counter 0` (§5.6), ad = outer frame header, plaintext = empty) | 16 |

- **M1's tag is integrity, not authentication** (honesty note): its key
  derives only from public material — the protocol name and eB_pub (the
  psk-pattern `e`/MixKey rule) — and the prologue M0 binds through the
  AEAD's associated data (the handshake hash), so the tag proves nothing
  about the sender and hides nothing; it exists to hard-fail transcript or
  prologue disagreement at the earliest possible byte. It is not a code oracle: the
  psk is not mixed until `psk2`, so no recorded message is testable
  against code guesses (§9).
- On receiving M3, the creator decrypts `sB_pub` and **verifies
  `M0 == SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub)`**. Mismatch =
  handshake failure (§3.1.6). Only after this check does the creator send
  M4 and finalize.
- The joiner finalizes on receiving a valid M4. M4 is the creator's
  key-confirmation and commitment-check acknowledgment; without it the
  joiner discards everything (no half-open channels on the joiner side).
- **Payloads** (`token_payload`, §5.7): each side's current push
  device-token, or the one-byte "absent" form if push is off. These are
  Noise handshake payloads — AEAD-bound to the full transcript and, from
  M2 onward, to the psk: a relay-positioned party that never learned the
  code cannot read them, and cannot produce a single valid message from
  M2 onward. Without the psk mixed in, MITM would merely be *detectable*
  (by the phrase); with it, MITM below code compromise is *impossible*.
- **psk placement is deliberate** (`psk2`, end of message 2): earlier
  placements (`psk0`/`psk1`) would key an AEAD tag with code-derived
  material *before any DH is mixed*, turning a recorded message into an
  offline test oracle for the 45-bit code space; a later placement
  (`psk3`) would let an active code-less interposer read the creator's
  token payload before failing. One accepted nuance, stated honestly: in
  `XXpsk2` the creator's static *public key* in M2 is encrypted under the
  ephemeral-ephemeral key alone, so an active code-less interposer that
  wins the race to the topic learns one public key of a pairing attempt
  that then fail-closes — the keypair is discarded with the code, no
  channel forms, nothing else leaks.
- After M4 both sides destroy the handshake states, ephemerals, Split
  keys, seed and psk. Pairing establishes *identity* (the two statics);
  message traffic always runs in sessions (§3.3), including the first one.

### 3.1.4 Safety phrase — derivation and rendering

```
ss     = X25519(own static private, peer static public)   # identical on both ends
salt2  = SHA-256( min(A_pub, B_pub) ‖ max(A_pub, B_pub) ) # lexicographic byte order
out    = HKDF-SHA-256(ikm = ss, salt = salt2, info = "nimna/phrase/v1")[0:8]
n      = uint64 big-endian from out
word0  = (n ÷ 1296²) mod 1296        # most-significant digit first
word1  = (n ÷ 1296)  mod 1296
word2  =  n          mod 1296
```

- **Exactly three words**, indices into the **EFF short wordlist 2.0**
  (1296 words, chosen for read-aloud distinctiveness — unique
  three-character prefixes). The wordlist is pinned: its canonical file is
  committed at `docs/test-vectors/wordlist-en-v1.txt` and its SHA-256,
  recorded alongside the protocol test vectors, is normative. ~2^31
  possible phrases; sound at that size because of the commitment prologue
  (§9).
- Rendered lowercase, mono-spaced, in derivation order (word0 word1
  word2). **The phrase is protocol output, not UI copy: one global
  wordlist, rendered identically in all locales** — like the Nimna code
  itself (i18n decision, 2026-07-04). Localized wordlists would break the
  verbal comparison the moment the two phones' locales differ.
- Because it derives from the statics alone, the phrase is re-derivable
  from the channel store at any time; nothing extra is persisted.

### 3.1.5 CRID — derivation and finalization

```
CRID = HKDF-SHA-256(ikm = ss, salt = salt2, info = "nimna/crid/v1")[0:16]
```

with `ss` and `salt2` exactly as in §3.1.4. Properties: identical on both
ends (ss is symmetric; the salt sorts the public keys), a uniform 16-byte
PRF output the relay cannot link to keys, codes, or other channels;
re-derivable from the channel store forever; collisions negligible
(birthday bound ≈ 2^-64 at 2^32 channels). 16 bytes keeps the outer frame
lean — the CRID prefixes every session frame.

### 3.1.6 Failure discipline (fail-closed) & the one generic response

- **Any pairing-handshake failure — commitment mismatch, AEAD failure at
  any step, malformed or out-of-order message, bridge lost mid-handshake —
  kills the attempt completely:** both sides wipe all handshake state, the
  creator marks the code dead (it is never re-registered) and generates a
  fresh code *and* a fresh static keypair for the next attempt. This caps
  online code-guessing and phrase-grinding at **one attempt per code**,
  structurally.
- **Expired, used, and never-existed codes are indistinguishable to a
  joiner** (USER decision, 2026-07-04). The relay makes this structural:
  topic registration always succeeds silently; a topic with no counterpart
  simply never bridges, and the relay — stateless — cannot itself
  distinguish expired from used from never-existed. The joiner client
  shows one canonical rendering for every non-bridging outcome, after its
  own timeout: *"That code didn't match anything. Codes expire — ask them
  to make a new one."* No distinct wire response, error code, or timing
  behavior may differentiate the cases.

### 3.2 Knock (session initiation)

1. Peer A (either side may knock) connects to the relay, registers its
   CRIDs (`REGISTER_CRID`, §5.4), and sends `KNOCK` on the channel's CRID,
   optionally carrying B's push device-token (§5.4) — which A holds
   locally (exchanged during pairing and refreshed in sessions, §3.2.1);
   it is included only if the channel has push enabled.
2. The relay checks for a live connection registered on the same CRID.
   - **Peer online (app open/connected or within background grace):** the
     relay forwards the knock (`KNOCK_FWD` — any device-token stripped,
     never forwarded); B's app surfaces it in-app.
   - **Peer not connected:** if the knock carried a device-token, the
     relay makes one outbound call to APNs/FCM using Nimna's server-side
     push credentials, delivering a content-free notification to that
     device-token: *"New activity"* — no channel, no sender, no content —
     then **discards the device-token immediately**. The relay stores no
     token registry, no CRID→device mapping, nothing. It is a stateless
     push *forwarder*, never a token *registry*.
   - **In both cases the knocker receives nothing back at knock time.**
     There is no `PEER_OFFLINE` response and no lapse notification: the
     knocker-visible surface is `ACCEPT` (bridge opens) or silence (the
     knocker's client times out and renders *"No answer."*). **Lapsed
     knocks carry no attribution** (USER decision, 2026-07-04): neither
     the wire nor the UI ever distinguishes "offline" from
     "saw-and-ignored" — the receiver's plausible deniability outranks the
     knocker's closure. The relay's offline check exists only to drive the
     push call and is never reported.
3. B opens the app, connects, registers its CRIDs, and sends `ACCEPT` on
   the CRID (or ignores; pending knocks expire after **60 s** at the
   relay, silently).
4. On accept, the relay marks the CRID as **bridged** — both connections
   are now paired in memory, signals both ends (`SESSION_BRIDGED`), and
   the session handshake begins (§3.3.1).

**Push is per-channel opt-in, default-off.** With push off, knocks reach
only online/grace-window peers, and coordination happens out-of-band — the
pure burner-line mode, with zero third-party touch.

### 3.2.1 Device-token exchange (peer-held, never server-held)

- During pairing, each side's handshake payload includes its current push
  device-token **inside the E2E-encrypted exchange** (M2/M3, §3.1.3;
  omitted via the "absent" form if the user hasn't enabled push). Each
  device stores its *peer's* device-token locally, encrypted at rest like
  all channel data. To the relay, tokens at this stage are
  indistinguishable ciphertext.
- Platforms rotate device-tokens; peers refresh each other via an
  encrypted CONTROL frame (token-refresh, §5.5) whenever a live session
  occurs. The same frame with the "absent" form revokes: the peer deletes
  its stored token (push opt-out propagates unilaterally). A stale
  device-token means a push silently fails — the fallback is out-of-band
  coordination, identical to push-off behavior.
- **Disclosure (honest edition):** at knock time, the relay transiently
  observes "wake device-token Y for CRID X" — a momentary in-memory
  linkage of a channel to a device, unlogged and unstored. Apple/Google
  observe that their infrastructure delivered a content-free push from
  Nimna's credentials to that device at that time; they never see channel,
  counterpart, or content. This transient linkage and the platform's
  delivery knowledge are the full price of push, which is why it remains
  opt-in.
- Nimna's APNs/FCM credentials live on the relay server only (never in the
  app binary) and identify *Nimna the sender*, not any user. Consequence
  for future self-hosted relays: operators need their own push credentials
  or run push-less.

### 3.3 Live session

- **Session handshake (§3.3.1) first:** on `SESSION_BRIDGED`, the
  **knocker (initiator)** and accepter (responder) run `Noise_KK` — two
  frames, one round trip — then messages flow. Messages are
  client-encrypted, framed (§5), and sent as WebSocket binary frames
  tagged with the CRID. The relay forwards frames verbatim to the bridged
  peer and retains nothing; handshake and transport frames are equally
  opaque to it.
- **Delivery semantics:** fire-and-forward at the relay. End-to-end
  acknowledgment happens between clients: the recipient returns an
  encrypted `ACK {msg_id}`; the sender marks the message delivered.
  Messages not acked remain local-only in "pending" state (see §6).
- **Typing/presence indicators (optional):** encrypted CONTROL frames,
  indistinguishable from messages to the relay.
- **Keepalive:** clients ping every N seconds (e.g., 30s) at the WebSocket
  layer. A connection is considered dropped after a missed-ping window.
- **Session end:** the ending side sends the encrypted **`HANGUP`
  envelope** (§5.5) — authenticated end-of-session, which a relay cannot
  forge — then the relay-plane **`TEARDOWN`** frame (or simply
  disconnects; a dropped connection is an implicit teardown). The relay
  tears down the bridge, notifies the peer (`TEARDOWN`), and forgets the
  CRID immediately. Client rendering distinguishes honestly: a session
  that ended with an authenticated HANGUP is "ended"; a bridge that died
  without one is "connection lost" — the relay can produce the second,
  never the first. Both sides destroy all session keys at teardown; every
  session starts from a fresh handshake.
- **Background grace:** after the app is backgrounded, the socket is held
  alive for **~30 seconds** on both platforms (this matches the iOS
  background execution grace; Android is kept symmetric by policy so the
  promise is identical everywhere). Within the grace window, an incoming
  knock or message reaches the app as if foregrounded. After the grace
  window the socket closes; longer gaps are bridged by the knock →
  content-free push → tap → reconnect path (§3.2), which resumes a session
  in about a second. No VoIP/background-audio workarounds are ever used to
  extend socket life — they are review-fatal for a non-call app.

### 3.3.1 Session handshake, transport keys & rekeying

`Noise_KK_25519_ChaChaPoly_SHA256` (revision 34), implemented from the
specification. Pre-messages: both static public keys, known since pairing
(initiator's first, per Noise pre-message rules). Prologue: zero-length.
The **knocker is the initiator**. Message pattern
`→ e, es, ss` · `← e, ee, se`; payloads are zero-length:

| # | Dir | SESSION_DATA payload (exact bytes) | Size |
|---|---|---|---|
| S1 | knocker → accepter | `eI_pub (32) ‖ tag over empty payload (16)` | 48 |
| S2 | accepter → knocker | `eR_pub (32) ‖ tag over empty payload (16)` | 48 |

The first two `SESSION_DATA` frames on a fresh bridge are, by definition,
S1 and S2; anything malformed there is a protocol error (below). After S2,
`Split()` yields two 32-byte transport keys: `k_ir` (initiator→responder)
and `k_ri` (responder→initiator). Handshake states and ephemerals are then
destroyed.

**Transport phase (per direction, independently):**

- **Nonce (12 bytes):** 32-bit big-endian direction constant ‖ 64-bit
  big-endian message counter. Direction constants: **initiator→responder
  `0x00000000`**, **responder→initiator `0x00000001`**. The counter starts
  at 0 and increments by 1 per message sent in that direction; it never
  resets within a session. Counter value `2^64-1` is forbidden (reserved;
  it collides with the rekey nonce — unreachable in practice under §4
  frame-rate limits).
- **AEAD:** ChaCha20-Poly1305 (IETF) with
  `ad = the frame's outer header` (§5.4: `ver ‖ frame_type ‖ CRID`,
  18 bytes) — every ciphertext is bound to its channel and its position.
- **Per-message rekey (per-message forward secrecy):** after *each*
  message is encrypted (sender side) or successfully decrypted (receiver
  side), that direction's key is replaced:
  `k ← first 32 bytes of ChaCha20-Poly1305-Encrypt(k, nonce = twelve bytes
  0x00000000‖0xFFFFFFFFFFFFFFFF, ad = empty, plaintext = 32 zero bytes)`
  (the Noise `REKEY` function, spec §11.3; the all-ones counter block is
  endian-agnostic). The old key is zeroized immediately. Compromise
  mid-session exposes only traffic from the captured key forward.
- **Receiver enforcement:** frames in each direction must arrive with
  counters exactly 0, 1, 2, … (the WebSocket/TCP stream guarantees order;
  any gap, repeat, or regression is an attack or a bug). Any counter
  violation, AEAD failure, or malformed frame is a **protocol error**: the
  receiver destroys all session keys, sends `TEARDOWN`, and the session is
  over. No partial tolerance.

### 3.4 Sending while peer is offline

There is no server queueing. A message composed while the peer is offline
is stored **locally on the sender's device only**, marked "waiting."
Sending it triggers a knock (and the optional content-free push). When the
peers are next bridged and the session handshake completes, waiting
messages transmit automatically in order. To the network, this is
indistinguishable from live typing.

## 4. The relay

- **Stateless router.** In-memory tables only: `{topic → registered
  connections}` (rendezvous), `{connection → registered CRIDs}`,
  `{CRID → bridged connection pair}`, pending knocks (≤ 60 s each), and
  the rate/push counters below. No database, no disk writes, no logs of
  routing activity in production configuration. The complete at-rest
  inventory of the relay: routing tables in memory, TLS certificates, and
  Nimna's APNs/FCM push credentials (§3.2.1). Nothing about any user is at
  rest, ever. Registrations live only as long as their connection (topic
  registrations additionally capped at 24 h per connection); the code's
  24 h validity is enforced by the creating client, which stops
  re-registering an expired code.
- **Never sees:** plaintext, pairing codes (only their topic derivation —
  and that is a *slow, date-salted* hash precisely so this claim is
  substantive: a fast hash of a 45-bit code would be invertible offline in
  under a GPU-hour, see §3.1.2), public keys' association to real
  identities, message content of any kind. Never stores: push
  device-tokens (used once per knock, then discarded).
- **Necessarily sees:** IPs, connection timing, topic IDs, CRIDs,
  ciphertext sizes; transiently at knock time, a device-token to wake
  (§3.2.1). This is stated plainly in Nimna's privacy documentation.
- **Open source under AGPL-3.0** (the Signal-server/SimpleX precedent:
  anyone operating a modified relay as a service must publish their
  modifications — protecting users' expectations of anything called a
  Nimna relay). The protocol spec is published openly alongside; the app
  remains closed. Reproducible-build/deployment story so third parties can
  verify the deployed code matches the repo (best-effort in v1). **Push
  credentials (APNs/FCM) are deployment configuration, never repository
  content** — the repo ships config slots and a `.gitignore` guard, never
  values; auditors verify push *behavior* in the open code (content-free
  string, token discarded), while credentials only determine whose
  developer account sends. Self-hosted relays supply their own credentials
  or run push-less.
- **Rate limiting & abuse control:** per-IP connection caps, per-connection
  frame-rate caps, max frame size (default **128 KiB** — bounds attachment
  ambitions while accommodating a full MEDIA_CHUNK frame, §5.1), and
  rendezvous-topic throttling to impede code brute-forcing. **Code format,
  fixed permanently: 9 characters, Crockford Base32 (unambiguous, easy to
  read aloud), displayed and entered as XXX-XXX-XXX** — a space of ~35
  trillion codes (~45 bits). The format never changes: validation, QR
  payloads, and user habit stay stable for the product's lifetime.
  Combined with per-IP rendezvous throttling (single-digit attempts per
  minute) and the 24h TTL, guessing any active code is a lottery no one
  wins; the astronomically lucky guesser then still faces a handshake that
  requires the code itself (psk, §3.1.3) and the safety-phrase check.
- **Knock & push rate limits (relay defaults, tunable config):**
  platform-push forwarding capped at **1 push per CRID per 60s, 6 per CRID
  per hour, 20 per CRID per day**; knock forwarding capped at 1 per CRID
  per 10s (duplicates inside the window dropped silently — retries
  collapse, no error). The push counters are in-memory, user-anonymous,
  and reset on restart — the same class of transient state as the routing
  tables. Client-side, the app never auto-retries knocks: each knock is a
  deliberate tap. The receiver's ultimate control is per-channel push
  opt-out, which silences a channel unilaterally and permanently (token
  revocation, §3.2.1).

## 5. Message framing

Every frame the relay forwards is `[routing_id][opaque ciphertext blob]`,
carried in a fixed 18-byte outer header (§5.4). Inside the encrypted blob,
clients use a fixed binary envelope (§5.5) with five types:

```
type: TEXT | ACK | CONTROL | HANGUP | MEDIA_CHUNK
      + msg_id, timestamp, optional expiry, body per type
```

All integers everywhere are **big-endian**. All layouts are fixed and
hand-specified; there is no serialization library in either stack.
Subsections: §5.1 media rules, §5.2 screenshot policy, §5.3
sensitive-content handling (doctrine, carried from v0.1.1 with their
numbering intact); §5.4–§5.7 exact byte layouts (new in v0.2).

- **TEXT:** UTF-8 message body, soft cap 5,000 characters per message
  (frame discipline, not stinginess; longer text chunks transparently
  across messages). Optional per-message `expiry_s` field — the sender's
  disappearing-message instruction ("delete after read + N seconds").
  Enforcement is client-side and honor-system by nature; the UX must say
  so honestly.
- **ACK:** references a `msg_id`; confirms decryption and display on the
  peer device. For media, ACK references the manifest's `msg_id` after
  successful reassembly and hash verification (§5.1).
- **CONTROL:** typing indicators, read receipts (per-channel opt-in),
  screenshot notices (§5.2), device-token refresh/revoke (§3.2.1),
  label-free housekeeping. Indistinguishable from messages to the relay.
- **HANGUP:** the authenticated end-of-session marker (§3.3); body empty.
- **MEDIA_CHUNK (v1):** chunked live transfer of attachments through the
  same pipe (§5.1). No relay-side reassembly ever; to the relay these are
  indistinguishable opaque frames.

### 5.1 Media & documents (v1)

Images and documents (PDF/files) are first-class in v1 — the professional
buyer's sensitive moments frequently involve a photographed contract, a
whiteboard, a screenshot, a document. Rules:

- **Size cap:** 5 MB per attachment (enforced client-side and bounded by
  relay frame/rate limits). A live session moves this in seconds; Nimna is
  a text call, not a file service.
- **Client-side image compression by default**, with an "original quality"
  toggle.
- **Metadata stripping by default:** EXIF/location/device/timestamp
  scrubbed from images **before encryption on the sender's device**.
  Marketed as a feature — the photographed contract shouldn't whisper
  where it was photographed.
- **No auto-save to gallery, ever.** Received media lives only inside
  Nimna's encrypted store (§6), inside the app-lock perimeter and outside
  cloud photo backups. Export is a deliberate user act.
- **Disappearing applies identically to media** — the sender's `expiry_s`
  instruction on the manifest governs attachments exactly as it governs
  text.
- **Chunking — exact layout.** An attachment is one **manifest** envelope
  followed by its **chunk** envelopes, all `type = MEDIA_CHUNK`:
  - **Manifest** (flags bit 1 set; expiry via flags bit 0):
    body = `chunk_count (4) ‖ total_len (8) ‖ content_hash (32) ‖
    mime_len (1) ‖ mime (UTF-8)`. `content_hash` = SHA-256 of the complete
    attachment plaintext (post-compression, post-strip — the bytes that
    will be reassembled). The manifest's `msg_id` names the transfer.
  - **Chunk** (flags bit 1 clear):
    body = `manifest_msg_id (16) ‖ chunk_index (4, 0-based) ‖ chunk_data`.
    Chunk plaintext size is **65,536 bytes** for every chunk except the
    last; `chunk_count = ceil(total_len / 65536)` (≤ 80 at the 5 MB cap).
    Chunks are sent in order; the ordered stream makes reassembly trivial.
  - Receiver reassembles, verifies `SHA-256 == content_hash`, then ACKs
    the manifest `msg_id`. Hash mismatch = discard the transfer, no ACK
    (never a protocol error — a resend is the sender's call).
  - No relay-side reassembly ever; to the relay these are
    indistinguishable opaque frames. A 65,536-byte chunk yields a
    transport frame comfortably inside the relay's 128 KiB default frame
    cap (§4).

### 5.2 Screenshot policy (detect-and-notify)

Nimna cannot prevent screenshots and does not pretend to. Policy,
symmetric on both platforms: **screenshots are possible, and the other
person is always told.** Taking a screenshot of a Nimna session emits a
CONTROL screenshot-notice to the peer. This is disclosed upfront in
onboarding as informed consent, in brand voice: *"Nimna can't stop a
screenshot. It will always tell the other person."* Honest limits, also
disclosed: detection fires only while content is on screen inside the app,
and nothing detects a second camera photographing the screen. Android's
stronger blocking capability (FLAG_SECURE) is deliberately not used, to
keep the promise identical on both platforms. Notice delivery is
honor-system like expiry (a modified client could suppress it); the
trust-your-counterpart caveat already stated for disappearing messages
covers this too.

### 5.3 Sensitive-content handling (on-device only, never moderation)

- **Recipient-side:** incoming images/video are checked **on-device, after
  decryption, before display** using the platform's local nudity-detection
  capability (iOS: SensitiveContentAnalysis framework; Android: no
  first-party public equivalent — path TBD: bundled on-device model, or
  iOS-only at launch). Flagged media renders blurred with a "sensitive
  content — tap to view" warning.
- **Sender-side:** the same on-device check runs at attach time and
  produces a soft, non-blocking whisper — *"This looks like sensitive
  content — send anyway?"* — protecting the sender from the wrong-channel
  disaster.
- **Hard boundary:** detection exists solely for local display decisions.
  Nothing is ever blocked, logged, reported, or transmitted as a result of
  detection; the sender is never informed of recipient-side flags. The
  moment detection has consequences beyond a local blur, Nimna would
  possess moderation infrastructure it promises not to have. Even our
  safety features can't phone home — they have nowhere to call.

### 5.4 Outer frame & frame types (relay-visible)

Every WebSocket binary frame, both planes:

| Offset | Size | Field | Semantics |
|---|---|---|---|
| 0 | 1 | `ver` | Protocol version. `0x01`. |
| 1 | 1 | `frame_type` | Below. |
| 2 | 16 | `routing_id` | Rendezvous frames: the **topic** (§3.1.2). Channel frames: the **CRID** (§3.1.5). |
| 18 | … | `payload` | Per frame type. Opaque to the relay for data-plane types. |

The relay parses exactly 18 bytes and routes; the 18-byte header is also
the AEAD `ad` for transport frames (§3.3.1).

**Relay-plane (routing; payloads visible to the relay by necessity):**

| Value | Name | Dir | routing_id | Payload |
|---|---|---|---|---|
| `0x01` | `REGISTER_TOPIC` | c→r | topic | empty |
| `0x02` | `REGISTER_CRID` | c→r | CRID | empty (one frame per CRID) |
| `0x03` | `KNOCK` | c→r | CRID | empty (no push) **or** `platform (1) ‖ token_len (2) ‖ token` — the peer's push token, §3.2.1. `platform`: `0x01` APNs, `0x02` FCM. |
| `0x04` | `ACCEPT` | c→r | CRID | empty |
| `0x05` | `TEARDOWN` | both | CRID | empty. Client→relay: tear down my bridge. Relay→client: your bridge is gone. Disconnection is an implicit TEARDOWN. |
| `0x10` | `TOPIC_BRIDGED` | r→c | topic | empty. Sent to both ends when a topic's second registrant arrives; the joiner then sends M1. |
| `0x11` | `KNOCK_FWD` | r→c | CRID | empty — the relay **strips any token** before forwarding (§3.2). |
| `0x12` | `SESSION_BRIDGED` | r→c | CRID | empty. Sent to both ends on ACCEPT; the knocker then sends S1. |

There is deliberately **no `PEER_OFFLINE`** and no knock-lapse frame
(§3.2). Malformed or rate-limit-violating traffic is dropped or the
connection closed — the relay never explains itself to an abuser.

**Data-plane (forwarded verbatim; payload opaque to the relay):**

| Value | Name | routing_id | Payload |
|---|---|---|---|
| `0x20` | `PAIR_DATA` | topic | Pairing handshake bytes M1–M4 exactly as tabled in §3.1.3. |
| `0x21` | `SESSION_DATA` | CRID | S1/S2 (§3.3.1), then transport frames: `AEAD ciphertext = encrypt(k_dir, nonce, ad = outer header, plaintext = inner envelope §5.5)`. |

### 5.5 Inner envelope (exact layout; plaintext of every transport AEAD)

| Offset | Size | Field | Semantics |
|---|---|---|---|
| 0 | 1 | `ver` | `0x01`. |
| 1 | 1 | `type` | `0x01` TEXT · `0x02` ACK · `0x03` CONTROL · `0x04` HANGUP · `0x05` MEDIA_CHUNK. |
| 2 | 1 | `flags` | bit 0: expiry present (TEXT and MEDIA_CHUNK-manifest only; must be 0 otherwise). bit 1: MEDIA_CHUNK manifest (MEDIA_CHUNK only). Others reserved, must be 0. |
| 3 | 16 | `msg_id` | Client-generated, 16 random bytes, unique per message. |
| 19 | 8 | `timestamp` | Sender local time, Unix milliseconds, uint64. |
| 27 | 4 | `expiry_s` | **Present only if flags bit 0.** Disappearing instruction: seconds after read (§5.1: applies to media identically). |
| — | … | `body` | Per type: |

- **TEXT:** body = the UTF-8 text (§5 rules).
- **ACK:** body = `acked_msg_id (16)`.
- **CONTROL:** body = `control_type (1) ‖ control_payload`:
  `0x01` typing (empty) · `0x02` read receipt (`msg_id (16)`) ·
  `0x03` screenshot notice (empty; §5.2) · `0x04` device-token
  refresh (`token_payload`, §5.7 — the "absent" form revokes). Unknown
  control types are ignored (forward compatibility), never errors.
- **HANGUP:** body empty.
- **MEDIA_CHUNK:** manifest and chunk bodies per §5.1.

### 5.6 Nonce & key discipline (restated normatively)

Transport nonces are `direction (4) ‖ counter (8)`, per §3.3.1:
initiator→responder `0x00000000`, responder→initiator `0x00000001`;
counters start at 0, strict increment, never reset, `2^64-1` forbidden;
per-message rekey after every encrypt/decrypt; receiver treats any
deviation as a protocol error and kills the session. Pairing M4 uses the
same discipline (direction `0x00000001`, counter 0) as the only
post-handshake pairing frame.

### 5.7 token_payload (inside E2E payloads only)

| Form | Bytes |
|---|---|
| Absent / revoke | `0x00` |
| Present | `0x01 ‖ platform (1: 0x01 APNs, 0x02 FCM) ‖ token_len (2) ‖ token (opaque bytes)` |

Used in pairing payloads M2/M3 (§3.1.3) and CONTROL token-refresh (§5.5).
The relay-plane KNOCK carries `platform ‖ token_len ‖ token` without the
presence byte (§5.4) — presence there is signaled by a non-empty payload.

## 6. Local storage (on-device)

- Channel store: own static keypair, peer static public key, CRID, local
  label, per-channel settings — encrypted at rest using platform keystore
  (iOS Keychain/Secure Enclave, Android Keystore). Nothing else is needed:
  CRID and safety phrase are re-derivable from the statics (§3.1.4,
  §3.1.5); the code, seed, and psk were destroyed at finalization.
- Message history: local database, encrypted at rest. Retention per user
  choice: keep forever (default), per-message delete, per-channel wipe,
  honor received expiry instructions.
- **Panic wipe:** single action that destroys a channel's keys and history
  irrecoverably. Destroying the keys makes any intercepted past ciphertext
  permanently undecryptable: session keys derive from per-session
  ephemerals that were wiped at each hangup, and per-message rekeying
  destroys each transport key as it is used — the statics alone never
  suffice to decrypt anything recorded (§7.3).
- Media store: received attachments live exclusively in the encrypted
  store, never the system gallery; export is a deliberate act (§5.1).
- App lock: PIN/biometric gate on app open (strongly recommended
  default-on).
- No cloud backup: local database is excluded from iCloud/Google backup by
  default. (History sync/migration between devices is explicitly out of
  scope for v1.)

## 6.1 Device loss & reinstall doctrine

A channel *is* its two private keys. If the app is deleted or the device
is lost, the private keys are gone and every channel on that device is
**cryptographically dead — by design, permanently, with no resurrection
path.** Any mechanism that let a fresh install recover old channels would
require durable identity outliving the keys — precisely what Nimna refuses
to have — and would be indistinguishable, from the relay's side, from a
thief, a wiped device's new owner, or a hijacked store account. Doctrine:
**device lost → channels dead → re-pair out-of-band.** Every pair by
definition has an out-of-band relationship (the code traveled it once);
re-pairing costs one message on that same channel. The only thing that
survives reinstall is the paid unlock, restored via platform store
identity (§10). Permitted UX sugar, client-side only: a knock unanswered
for an extended period may surface a local hint — "no answer in a while;
if they lost their device, you'll need to pair again."

## 7. Cryptography (locked)

The complete primitive set — nothing else exists anywhere in the protocol:

| Role | Primitive | Reference |
|---|---|---|
| Key agreement | X25519 | RFC 7748 |
| AEAD | ChaCha20-Poly1305, 96-bit nonce | RFC 8439 |
| Hash | SHA-256 | RFC 6234 |
| KDF | HKDF-SHA-256 | RFC 5869 |
| Slow KDF | Argon2id (v1.3), t=3, m=64 MiB, p=1 | RFC 9106 |
| Handshakes | Noise `XXpsk2` (pairing, §3.1.3) and `KK` (sessions, §3.3.1), suite `25519_ChaChaPoly_SHA256` | Noise spec rev. 34 |

**Why these:** the full comparison (vs. P-256/AES-GCM, Noise-as-a-library,
the Signal Double Ratchet, PAKEs), the library sign-offs for both stacks,
and the grinding/brute-force arithmetic live in
`docs/crypto-evaluation.md`. In one line: the most boring, audited,
both-stacks-native primitives, composed by published patterns, with the
two hardenings (commitment prologue, slow topic hash) that the spec's own
claims require.

**Engine requirements (both implementations, byte-identical):** Noise
revision 34 semantics; in psk patterns the `e` token additionally calls
`MixKey(e.public_key)`; prologue as defined per handshake (M0 for pairing,
zero-length for KK); handshake nonces follow the Noise encoding (32 zero
bits ‖ little-endian n) while post-Split transport uses the Nimna nonce
(§5.6); `REKEY` per Noise §11.3. Both implementations must reproduce the
committed protocol test vectors in `docs/test-vectors/` and pass the
committed third-party Noise vector sets (`KK` directly; `XXpsk2` via its
composing rules, since no published XXpsk2 vector set exists — coverage
detailed in `docs/test-vectors/generator/testdata/README.md`).

**Delivered properties** (v0.1.1 §7 listed these as requirements; they are
now met as follows):

1. **Authenticated key agreement bridgeable through an untrusted relay** —
   `XXpsk2` with the code as psk: completing (or even reading past M1 of)
   the pairing handshake requires the code; the relay never has it
   (§3.1.2, §3.1.3).
2. **End-to-end confidentiality and integrity for all frames** —
   ChaCha20-Poly1305 on every payload byte after M1, with the outer header
   as associated data in transport (§5.4, §3.3.1).
3. **Forward secrecy** — per session: fresh `ee` in every KK handshake,
   ephemerals destroyed at hangup; compromise of both statics never
   decrypts recorded past sessions. Per message: per-message rekey
   (§3.3.1); compromise mid-session exposes nothing already sent. This is
   what makes the §6 panic-wipe promise cryptographically true, and
   post-compromise recovery holds at session granularity (a fresh `ee`
   locks a past intruder out again).
4. **Human-comparable safety phrase** — exactly three words from the
   channel key material (§3.1.4), sound at 2^31 because the commitment
   prologue reduces a MITM to one blind attempt per code (§3.1.3, §3.1.6,
   §9).
5. **Replay protection** — within a session: strict per-direction counter
   nonces over an ordered stream, enforced fail-closed (§3.3.1). Across
   sessions: every session's keys include fresh ephemerals, so recorded
   frames are noise under any later session. Pairing: single-use topic,
   fail-closed code. Relay-plane routing frames are not replay-protected —
   see §9 for why that is acceptable and what it costs.
6. **Well-audited, boring, widely available** — Go: standard library
   (`crypto/ecdh`, `crypto/hkdf`, `crypto/sha256`) plus
   `golang.org/x/crypto` (chacha20poly1305, argon2). Dart: libsodium via
   the `sodium` FFI package plus the Dart-team `crypto` package for
   SHA-256/HMAC, HKDF composed per RFC 5869 and locked to the test
   vectors. Sign-offs and withheld alternatives: `docs/crypto-evaluation.md`
   §11. No novel cryptography, ever.

## 8. Explicit non-goals (v1)

Groups. Voice/video. Multi-device. Server-side anything. Message search
across devices. Identity discovery. Channel resurrection, portability, or
backup of any kind. Screenshot *prevention* (detect-and-notify only,
§5.2). Post-quantum key exchange (noted as a future hybrid candidate in
the evaluation; not v1). Traffic padding/length hiding (sizes are
disclosed metadata, §1.6/§9). Federation (single hosted relay in v1;
bring-your-own-relay is a planned pro feature, and the protocol must not
assume relay trust anywhere — which it doesn't: see the psk design,
§3.1.3).

## 9. Threat-model summary (honest edition)

| Adversary | Protection |
|---|---|
| Relay operator (incl. compelled) | Sees ciphertext + routing metadata only; nothing stored to hand over. Cannot MITM pairing even in principle without the code (psk, §3.1.3); cannot forge a graceful session end (authenticated HANGUP, §3.3); cannot decrypt anything, ever. |
| Relay tries to recover a code from its topic ID (offline brute force) | Argon2id (t=3, m=64 MiB) with a date salt: a full 2^45 sweep costs on the order of a thousand server-years per code, and precomputed tables die daily (§3.1.2). A fast hash here would fall in under one GPU-hour — this row exists because the construction makes §4's "never sees codes" claim substantive. |
| Network observer | TLS to relay + E2E within; sees that a device talked to the Nimna relay. |
| Pairing-time MITM | Requires the code (psk) — relay position alone is insufficient. An attacker who *did* intercept the code gets exactly one attempt (fail-closed, §3.1.6), cannot grind the safety phrase (commitment prologue, §3.1.3), and is caught by the phrase comparison at odds of ~1 in 2.1 billion of surviving it. Code TTL and single-use bound the window. |
| Relay-plane replay/forgery (KNOCK, ACCEPT, TEARDOWN) | Not cryptographically protected — stated honestly. These frames ride inside TLS, so only the relay itself can forge or replay them, and the relay can equally just drop traffic. Consequence is bounded to nuisance: a forged knock yields a push or an in-app knock and, if accepted, a bridge on which the impostor cannot complete the KK handshake — nothing decrypts, nothing is forged, the bridge dies. Rate limits (§4) cap the nuisance. |
| Peer's device seized | Out of scope for protocol; mitigated by app lock, expiry, panic wipe. |
| Your own device seized | App lock, encrypted-at-rest storage, panic wipe, no cloud backups. Past sessions stay undecryptable even with the statics (forward secrecy, §7.3). |
| Counterpart captures content (screenshot / second camera) | Screenshot: detect-and-notify (§5.2), honor-system, disclosed upfront. Second camera: undetectable; disclosed honestly. Trust in your counterpart is an acknowledged part of the model. |
| Metadata correlation (IP/timing/sizes) | Acknowledged limitation in v1; document honestly. Future: relay federation, transport overlays. |

**Structural abuse posture** (for store review and the /security page):
pairing requires a pre-existing out-of-band relationship (no discovery, no
directory — strangers cannot find each other); strictly 1:1 (no
distribution networks); and every channel in existence was initiated under
a paid unlock tied to a store-verified payment instrument (§10). Residual
case, as in every E2E system including Signal and WhatsApp: two consenting
bad actors — no messenger design prevents this, and Nimna does not claim
to.

## 10. Monetization doctrine

- **Model:** initiators pay, receivers never do. Creating channels
  requires an active **yearly subscription, priced regionally via platform
  store tiers** — unlimited channel creation. No price is ever hardcoded
  or published outside the stores: the paywall renders the localized price
  string provided by StoreKit/Play Billing for the user's storefront, and
  marketing surfaces (website, press) describe the model without naming
  numbers. Joining channels and communicating on them is free forever and
  must never surface a paywall.
- **The permanence guarantee (protocol-adjacent, stated as firmly as
  zero-storage):** every channel created while subscribed is **permanent
  and fully functional forever**, regardless of subscription status. A
  lapsed subscription gates only the creation of *new* channels. Nothing
  is ever frozen, degraded, or repossessed. This is structurally enforced
  by the architecture itself: channels are keypairs, the relay has no
  accounts to flag as expired, and entitlement is checked only on the
  initiator's device at creation time. The business model inherits its
  decency from the architecture.
- **Restore:** the unlock is tied to platform store identity (Apple ID /
  Google account), restored natively via StoreKit / Play Billing on
  reinstall or new device — no Nimna account exists or ever will. Restore
  reliability is a top-tier feature: it is the only path to channel
  creation after reinstall. Honest limits, stated plainly in the FAQ:
  entitlements do not cross platforms (iOS ↔ Android requires a new
  purchase, industry standard); Family Sharing is disabled (one initiator,
  one unlock).
- **No trial channel creation.** Creation cannot be tried before paying
  (the receiving experience is the free trial of the product; the paywall
  sells the creation ritual visually). Accepted deliberately for model
  clarity and as an abuse gate: every channel traces to a real payment
  instrument.
