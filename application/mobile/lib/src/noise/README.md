# lib/src/noise/

The Noise engine, **implemented from the published Noise spec (rev 34) — NO
Noise-library dependency** (crypto lock, DECISIONS 2026-07-04 13:44 Q2 /
2026-07-05 02:20). Composed ONLY from already-signed-off primitives: X25519
(libsodium sumo `crypto_scalarmult` — the SOLE scalarmult site, fenced here),
ChaCha20-Poly1305-IETF (the vetted `AtRestAead` FFI glue), SHA-256
(`package:crypto`), and the in-repo RFC 5869 HKDF. Pure and locale-independent;
byte-locked to `docs/test-vectors/pairing-handshake.json`.

S9 implements the **pairing** handshake (`XXpsk2`) only; the session `KK`
handshake and per-message rekey are S10's.

```
cipher_state.dart     Noise CipherState (§5.1): keyed AEAD + strict nonce
                      counter; handshake-nonce encoding (4 zero bytes ‖ LE
                      counter). Key held in SecureKey native memory.
symmetric_state.dart  Noise SymmetricState (§5.2): ck + h + cipher;
                      MixKey / MixHash / MixKeyAndHash / EncryptAndHash /
                      DecryptAndHash / Split, all over the in-repo HKDF.
dh.dart               X25519 (the ONLY crypto_scalarmult use) + keypair
                      generation; NoiseKeyPair (SecureKey secret).
handshake_state.dart  Noise HandshakeState (§5.3): token processor
                      (e/s/ee/es/se/ss/psk) with the PSK-pattern rule (every
                      `e` also MixKeys its public key, §9.2). WriteMessage /
                      ReadMessage / Split.
xxpsk2.dart           The two §3.1.3 role drivers — NoiseJoinerHandshake
                      (initiator: M1→M2→M3→verify M4) and
                      NoiseResponderHandshake (responder: M1→M2→M3+commit
                      check→M4). M0 prologue, code-psk mix, M4 PAIR_CONFIRM
                      (§5.6), fail-closed wipe on any failure (§3.1.6), and
                      PairingChannelMaterial (peer static, CRID, ss, peer
                      token) at finalization.
```

The joiner controller (`lib/src/pairing/joiner`) drives the joiner; the
creator's `initiator_controller.dart` drives the responder through its
opt-in `attachResponder` write-seam.
