# lib/src/protocol/

Pure protocol codec/derivation — **no I/O, no state, no Flutter imports,
locale-independent by definition**. Everything here is vector-locked to
`docs/test-vectors/` and byte-identical to the Go stack.

```
pairing_code.dart  §3.1.1 — Crockford Base32 code: uniform generation
                   (injected sampler; libsodium randombytes_uniform in
                   production — bias-free by construction),
                   canonicalization (strip/fold/I→1 L→1 O→0, U rejected,
                   length-9 exact), XXX-XXX-XXX display, nimna: QR payload.
                   toString is redacted — a code can never leak through
                   interpolation.
rendezvous.dart    §3.1.2 — date-salted SHA-256 → Argon2id (libsodium
                   pwhash, sumo API; t=3, m=64 MiB, p=1) → in-repo
                   HKDF-SHA-256 → topic[16] + psk[32] (SecureKey, held for
                   S9). Reduced test cost exists but is @visibleForTesting;
                   production cost is the only one reachable from app code.
outer_frame.dart   §5.4 — the fixed 18-byte outer header codec + the FULL
                   frame-type enum; strict decode rejects (short header,
                   wrong ver, unknown type).
commitment.dart    §3.1.3 — M0 = SHA-256("nimna/commit/v1"‖eB_pub‖sB_pub),
                   the joiner's commitment used as the Noise prologue (S9).
token_payload.dart §5.7 — the pairing-plane device-token leaf carried E2E
                   inside the handshake payloads M2/M3 (§3.1.3): absent 0x00
                   / present 0x01‖platform‖len‖token. NOT the §5.5 inner
                   envelope (that references it; S10 owns the envelope).
channel_identity.dart  §3.1.4/§3.1.5 — from the static-static ss (computed
                   in lib/src/noise, the sole scalarmult site) + salt2:
                   CRID[16], and the 3-word safety phrase (uint64→base-1296
                   via BigInt; one global wordlist, identical in every
                   locale — protocol output, never UI copy).
```

**S10 checkpoint fence (binding):** the §5.5–§5.8 INNER envelope (TEXT/ACK/
CONTROL/HANGUP/MEDIA_CHUNK/REACTION), nonce/key discipline, and reaction/
reply codecs are NOT here and may not appear before S10. S9 adds only the
pairing-plane slices above (M0, §5.7 token_payload, CRID, safety phrase);
`test/pairing/single_call_site_test.dart` pins the fence (§5.7 token_payload
is explicitly allowed — it is the handshake leaf, not the inner envelope).
