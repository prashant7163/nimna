# lib/src/noise/

The Noise engine, **implemented from the published Noise spec (rev 34) — NO
Noise-library dependency** (crypto lock, DECISIONS 2026-07-04 13:44 Q2 /
2026-07-05 02:20). Composed ONLY from already-signed-off primitives: X25519
(libsodium sumo `crypto_scalarmult` — the SOLE scalarmult site, fenced here),
ChaCha20-Poly1305-IETF (the vetted `AtRestAead` FFI glue), SHA-256
(`package:crypto`), and the in-repo RFC 5869 HKDF. Pure and locale-independent;
byte-locked to `docs/test-vectors/pairing-handshake.json`.

S9 implemented the **pairing** handshake (`XXpsk2`); **S10 (the codec
checkpoint)** adds the **session** handshake (`KK`, §3.3.1) and the
post-Split per-message-rekey transport (§5.6), reusing the same engine.

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
                      (e/s/ee/es/se/ss/psk). Parameterized for both patterns
                      (S10): `mixKeyOnEphemeral` applies the psk-pattern `e`
                      rule (§9.2) — true for XXpsk2, false for KK; KK also
                      passes its two static pubkeys as `preMessagePublicKeys`
                      (mixed into `h`, initiator's first) and its known peer
                      static as `remoteStaticPublic` (no `s` token on the
                      wire). WriteMessage / ReadMessage / Split.
xxpsk2.dart           The two §3.1.3 role drivers — NoiseJoinerHandshake
                      (initiator: M1→M2→M3→verify M4) and
                      NoiseResponderHandshake (responder: M1→M2→M3+commit
                      check→M4). M0 prologue, code-psk mix, M4 PAIR_CONFIRM
                      (§5.6), fail-closed wipe on any failure (§3.1.6), and
                      PairingChannelMaterial (peer static, CRID, ss, peer
                      token) at finalization.
session_kk.dart       The two §3.3.1 KK role drivers (S10) —
                      SessionInitiatorHandshake (knocker: write S1 → read S2 →
                      Split) and SessionResponderHandshake (accepter: read S1
                      → write S2 → Split). Zero-length prologue/payloads;
                      48-byte S1/S2; fail-closed wipe on any failure; yields a
                      SessionTransport (send/receive) per role.
noise_transport.dart  Nimna post-Split transport (S10, §3.3.1/§5.6) — NOT the
                      generic Noise transport: `direction‖counter` nonce,
                      strict counter from 0 (2^64-1 forbidden), 18-byte outer
                      header as AEAD `ad`, per-message REKEY (Noise §11.3, old
                      key zeroized), receiver fail-closed → TransportError on
                      any AEAD failure. Keys in SecureKey native memory. This
                      is the ONLY transport-key STATE; the §5.5 codec stays
                      pure.
```

The joiner controller (`lib/src/pairing/joiner`) drives the joiner; the
creator's `initiator_controller.dart` drives the responder through its
opt-in `attachResponder` write-seam. The future session layer
(`lib/src/session`, Phase B) drives `session_kk.dart` on `SESSION_BRIDGED`
and pumps `noise_transport.dart` for live traffic.
