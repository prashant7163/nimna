# internal/derive/

Nimna's deterministic derivations from spec v0.2 §3.1:

- `derive.go` — pairing-code canonicalization (§3.1.1: case fold, strip
  hyphens/whitespace, I/L→1, O→0, U rejected, exactly 9 alphabet bytes);
  date-salted Argon2id seed + HKDF topic/psk (§3.1.2); commitment M0
  (§3.1.3); ss/salt2, CRID (§3.1.5) and safety-phrase bytes → base-1296
  indices (§3.1.4); pinned-wordlist parsing.
- `derive_test.go` — canonicalization matrix, salt/commitment shapes,
  phrase-index boundaries (0, 1296³−1, 1296³ wrap, 2^64−1).
- `rfc_test.go` — HKDF RFC 5869 Appendix A (SHA-256 cases) through the
  stdlib entry points used here; Argon2id reference-implementation vectors
  (RFC 9106 §5.3 itself needs secret+AD inputs that x/crypto's `IDKey`
  deliberately does not expose — see the honesty note in the file).
