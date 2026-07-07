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
```

**S10 checkpoint fence (S8 intake §1, binding):** the §5.5–§5.8 inner
envelope, nonce/key discipline, and token_payload codecs are NOT here and
may not appear before S10. PAIR_DATA is opaque bytes to this package;
`test/pairing/single_call_site_test.dart` pins the fence.
