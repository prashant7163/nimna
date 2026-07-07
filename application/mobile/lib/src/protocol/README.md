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
inner_envelope.dart  §5.5–§5.8 — the INNER envelope (the plaintext of every
                   transport AEAD): InnerType (TEXT/ACK/CONTROL/HANGUP/
                   MEDIA_CHUNK/REACTION), the header codec (ver‖type‖flags‖
                   msg_id‖timestamp‖[expiry_s]‖[reply_to], flag-bit field
                   order), and the per-type body codecs — AckBody,
                   ControlBody (typing/read-receipt/screenshot/token-refresh;
                   unknown control_type ignored, never an error), ManifestBody
                   / ChunkBody (§5.1, full body surface — S11 consumes it).
                   Full structural-error set → InnerEnvelopeError (no bytes).
reaction_body.dart  §5.5/§5.8 — the REACTION body (ref_msg_id‖op‖emoji_len‖
                   emoji): ReactionOp add/remove, 1–64-byte valid-UTF-8 emoji,
                   NEVER grapheme-segmented (spec §5.5). Structural violations
                   throw InnerEnvelopeError.
```

**S10 checkpoint (this session OPENS the S8/S9 fence):** the §5.5–§5.8 inner
envelope, its body codecs, and the reaction/reply codecs are now implemented
in `inner_envelope.dart` + `reaction_body.dart` — and ONLY there.
`test/pairing/single_call_site_test.dart` now pins the codec's single home
(no second definition may sprawl in the protocol tree). Transport-key STATE
(nonce/counter/rekey, §5.6) is NOT here — it lives in `lib/src/noise`
(`noise_transport.dart`) so this codec stays pure and stateless. §5.7
token_payload (`token_payload.dart`) is reused verbatim by CONTROL
token-refresh; the 18-byte §5.4 outer header (`outer_frame.dart`) is reused
as the transport AEAD `ad`.
