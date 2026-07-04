# internal/noise/

Minimal Noise Protocol Framework engine, implemented from the Noise
specification revision 34 (no Noise library — spec v0.2 §7 "Engine
requirements"). Single suite: `25519_ChaChaPoly_SHA256`, from the locked
primitive set only (`crypto/ecdh`, stdlib SHA-256/HMAC,
`x/crypto/chacha20poly1305`).

- `noise.go` — CipherState / SymmetricState / HandshakeState, Noise HKDF,
  Noise nonce encoding (4 zero bytes ‖ little-endian n).
- `patterns.go` — fundamental pattern table (N…IX) + psk-modifier
  application (`psk0` prepends to message 1, `pskN` appends to message N);
  in psk handshakes every `e` token also MixKeys its public key.
- `transport.go` — **Nimna's** post-Split transport (spec §3.3.1/§5.6):
  big-endian direction ‖ counter nonces, outer-header ad, per-message
  REKEY (Noise §11.3), forbidden counter 2^64-1.
- `rfc_test.go` — ChaCha20-Poly1305 (RFC 8439 §2.8.2, A.5), X25519
  (RFC 7748 §5.2 incl. iterated, §6.1), Noise-HKDF ≡ RFC 5869 cross-check.
- `thirdparty_test.go` — runs the committed cacophony + snow vector sets
  offline (see [`testdata/README.md`](../../testdata/README.md)).
