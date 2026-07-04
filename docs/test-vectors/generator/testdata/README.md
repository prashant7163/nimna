# generator/testdata/

Third-party Noise Protocol test vectors used to validate the in-repo Noise
engine against implementations we did not write
(`internal/noise/thirdparty_test.go` runs them fully offline).

Both files are **filtered subsets** of their upstream originals, produced
by selecting only the vectors this engine can and should run: fundamental
handshake patterns (one-way N/K/X and interactive NN…IX), with any psk
modifiers, under Nimna's exact production suite
`25519_ChaChaPoly_SHA256`. Deferred patterns (`NK1`, `XX1`, `I1K`, …) and
other DH/cipher/hash suites were dropped; kept vector objects are
unmodified in content (re-serialized field-for-field).

| File | Vectors | Source | Retrieved | License |
|---|---|---|---|---|
| `cacophony-25519-chachapoly-sha256.json` | 36 of 944 | [cacophony](https://github.com/haskell-cryptography/cacophony) `vectors/cacophony.txt`, commit `18b7348c54fd61fcd0c220298883de0d09c8364d` | 2026-07-04 | Public domain (Unlicense) |
| `snow-25519-chachapoly-sha256.json` | 28 of 408 | [snow](https://github.com/mcginty/snow) `tests/vectors/snow.txt`, commit `d00b360cc61a7fe519ce7539974dca4f36c4654a` | 2026-07-04 | MIT / Apache-2.0 (dual) |

Coverage relevant to Nimna's two locked patterns:

- **KK** — exactly: `Noise_KK` (both files), `Noise_KKpsk0`,
  `Noise_KKpsk2` (cacophony), `Noise_KKpsk0+psk2` (snow).
- **XXpsk2** — no third-party vector set publishes a pure
  `Noise_XXpsk2_25519_ChaChaPoly_SHA256` vector (checked: cacophony, snow,
  noise-c — the last uses pre-rev-34 `NoisePSK_` semantics and is
  unusable). Closest published coverage, all passing: `Noise_XX` (base
  pattern), `Noise_XXpsk3` (psk-mode e/MixKey rule in XX),
  `Noise_XXpsk0+psk2` and `Noise_XXpsk0+psk1+psk2+psk3` (the exact psk2
  insertion position in XX), plus `Noise_KKpsk2` (psk2 in a two-message
  pattern). Together these exercise every rule XXpsk2 is composed of. The
  committed `pairing-handshake.json` XXpsk2 transcripts were additionally
  verified against an independent from-spec reimplementation during
  Session 2.

The remaining 27 vectors (other fundamental patterns and psk placements)
are kept because they validate the same engine machinery for free.
