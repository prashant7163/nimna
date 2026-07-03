# Nimna Protocol Specification — v0.1 (Draft)

**Status:** Draft for discussion. Crypto primitives intentionally unspecified in v0.1; to be selected in Session 2 (see Build Plan).

**One-line summary:** Nimna is a synchronous, end-to-end encrypted, account-less 1:1 messaging protocol in which a stateless relay routes ciphertext between two live device connections and never stores anything.

---

## 1. Design principles

1. **Zero server storage.** The relay never writes message content, metadata records, or queues to disk. All routing state lives in memory for the lifetime of active connections only.
2. **No identity.** No accounts, phone numbers, emails, or usernames. A channel is defined solely by two device-held keypairs.
3. **Synchronous only.** Messages flow only when both peers hold live connections to the relay. There is no store-and-forward.
4. **E2E encryption.** The relay routes opaque ciphertext. Plaintext exists only on the two paired devices.
5. **Code is ephemeral.** The pairing code exists only to rendezvous during first pairing. After key exchange, it is discarded and never reused.
6. **Minimal metadata.** The relay necessarily observes: channel routing IDs, connection times, IP addresses, and ciphertext sizes/timing. It observes nothing else. The relay is open source so this claim is auditable.

## 2. Entities and terms

| Term | Meaning |
|---|---|
| **Device** | A phone running the Nimna app. One device per person per channel. |
| **Relay** | The stateless WebSocket router. Open source. |
| **Channel** | A paired 1:1 connection between exactly two devices, identified by their two public keys. Permanent once paired, until either side deletes it. |
| **Pairing code** | Short, human-shareable, single-use code used only for rendezvous during pairing. |
| **Channel routing ID (CRID)** | An opaque identifier derived from the channel's key material, used by the relay to match the two peers. Reveals nothing about the devices. |
| **Knock** | A request from one peer to open a live session on a channel. |
| **Session** | A live window during which both peers are connected and messages flow. |

## 3. Protocol phases

### 3.1 Pairing (one-time per channel)

1. **Initiation.** Device A generates a fresh channel keypair (A_pub, A_priv) and a pairing code `C` (format: short code, e.g., 8–10 chars from an unambiguous alphabet, plus QR encoding of the same). A opens a WebSocket to the relay and registers interest in rendezvous topic `H(C)` — a hash of the code, so the relay never sees the code itself.
2. **Out-of-band share.** A shares `C` with B outside Nimna (verbally, QR in person, any channel). The code has a TTL (default: 24h, configurable at generation; shorter = safer).
3. **Join.** Device B generates its own fresh channel keypair (B_pub, B_priv), connects to the relay, and registers on topic `H(C)`.
4. **Key exchange.** When both are present on `H(C)`, the relay bridges them. A and B exchange public keys and perform an authenticated key agreement (primitive TBD — see §7) through the relay. All subsequent traffic is encrypted end-to-end.
5. **Verification (recommended).** Both apps derive a short **safety phrase** (e.g., word/emoji sequence) from the shared channel key material and display it. Users compare it out-of-band to rule out a man-in-the-middle during pairing. UX: strongly encouraged, not enforced.
6. **Finalization.** Both devices derive the **CRID** from the shared key material, persist the channel locally (peer public key, own keypair, CRID, user-chosen local label), and **discard the pairing code permanently**. The rendezvous topic `H(C)` dies at the relay the moment both sides disconnect; codes are single-use and cannot be replayed.

**Failure modes:** code expires unused → nothing was created, A simply regenerates. A third party who intercepts `C` before B uses it can pair with A in B's place — mitigated by the safety-phrase check and code TTL. Once a channel is finalized, the code is useless to anyone.

### 3.2 Knock (session initiation)

1. Peer A (either side may knock) connects to the relay and sends `KNOCK {crid}`.
2. The relay checks for a live connection registered on the same CRID.
   - **Peer online (app open/connected):** relay forwards the knock; B's app surfaces it in-app.
   - **Peer not connected:** relay responds `PEER_OFFLINE`. Optionally (per-channel, opt-in), the relay dispatches a content-free push notification to B's device: *"New activity"* — no channel, no sender, no content. Push tokens, where used, are registered per-connection in memory and are the only piece of state that may require persistence; v1 keeps push strictly optional and default-off to preserve the zero-persistence claim in its purest form.
3. B opens the app, connects, and sends `ACCEPT {crid}` (or ignores; knocks expire after a short TTL, e.g., 60s at the relay).
4. On accept, the relay marks the CRID as **bridged**: both connections are now paired in memory and traffic flows.

### 3.3 Live session

- Messages are client-encrypted, framed (see §5), and sent as WebSocket binary frames tagged with the CRID. The relay forwards frames verbatim to the bridged peer and retains nothing.
- **Delivery semantics:** fire-and-forward at the relay. End-to-end acknowledgment happens between clients: the recipient returns an encrypted `ACK {msg_id}`; the sender marks the message delivered. Messages not acked remain local-only in "pending" state (see §6).
- **Typing/presence indicators (optional):** encrypted control frames, indistinguishable from messages to the relay.
- **Keepalive:** clients ping every N seconds (e.g., 30s). A connection is considered dropped after a missed-ping window.
- **Session end:** either side disconnects or sends `HANGUP`. The relay tears down the bridge and forgets the CRID immediately. Backgrounding the app keeps the socket alive on a decaying timer (default target: ~10 min since last foreground, platform-permitting) so brief interruptions don't drop the session.

### 3.4 Sending while peer is offline

There is no server queueing. A message composed while the peer is offline is stored **locally on the sender's device only**, marked "waiting." Sending it triggers a knock (and the optional content-free push). When the peers are next bridged, waiting messages transmit automatically in order. To the network, this is indistinguishable from live typing.

## 4. The relay

- **Stateless router.** In-memory tables only: `{connection → registered CRIDs}` and `{CRID → bridged connection pair}`. No database, no disk writes, no logs of routing activity in production configuration.
- **Never sees:** plaintext, pairing codes (only their hashes), public keys' association to real identities, message content of any kind.
- **Necessarily sees:** IPs, connection timing, CRIDs, ciphertext sizes. This is stated plainly in Nimna's privacy documentation.
- **Open source**, with a reproducible-build/deployment story so third parties can verify the deployed code matches the repo (best-effort in v1).
- **Rate limiting & abuse control:** per-IP connection caps, per-connection frame-rate caps, max frame size (bounds attachment ambitions), rendezvous-topic throttling to impede code brute-forcing. Code space must be large enough that guessing an active code within its TTL is infeasible.

## 5. Message framing (client ↔ client, opaque to relay)

Every frame the relay forwards is: `[CRID][opaque ciphertext blob]`. Inside the encrypted blob, clients use a simple envelope:

```
{
  type:      TEXT | ACK | CONTROL | HANGUP | (future: ATTACH_CHUNK)
  msg_id:    client-generated unique id
  timestamp: sender local time
  body:      payload per type
}
```

- **TEXT:** UTF-8 message body. Optional per-message `expiry` field — the sender's disappearing-message instruction (e.g., "delete after read + N minutes"). Enforcement is client-side and honor-system by nature; the UX must say so honestly.
- **ACK:** references a msg_id; confirms decryption and display on the peer device.
- **CONTROL:** typing indicators, read receipts (per-channel opt-in), label-free housekeeping.
- **ATTACH_CHUNK (v1.1, reserved):** chunked live transfer of small attachments through the same pipe, size-capped by relay frame limits. No relay-side reassembly ever.

## 6. Local storage (on-device)

- Channel store: own keypair, peer public key, CRID, local label, per-channel settings — encrypted at rest using platform keystore (iOS Keychain/Secure Enclave, Android Keystore).
- Message history: local database, encrypted at rest. Retention per user choice: keep forever (default), per-message delete, per-channel wipe, honor received expiry instructions.
- **Panic wipe:** single action that destroys a channel's keys and history irrecoverably. Destroying the keys makes any intercepted past ciphertext permanently undecryptable (assuming forward-secret primitives — a Session 2 selection criterion).
- App lock: PIN/biometric gate on app open (strongly recommended default-on).
- No cloud backup: local database is excluded from iCloud/Google backup by default. (History sync/migration between devices is explicitly out of scope for v1.)

## 7. Cryptographic requirements (primitive-agnostic)

v0.1 specifies *requirements*; concrete primitives are selected in Session 2. The chosen scheme must provide:

1. **Authenticated key agreement** during pairing, bridgeable through an untrusted relay.
2. **End-to-end confidentiality and integrity** for all frames (AEAD).
3. **Forward secrecy** across sessions at minimum (compromise of current keys must not decrypt past sessions) — per-message forward secrecy (ratcheting) is preferred and likely cheap given sessions are live.
4. **A human-comparable safety phrase** derivable from the agreed key material.
5. **Replay protection** (nonces/counters within sessions).
6. Well-audited, boring, widely available in Dart/Flutter and on the relay's language of choice. No novel cryptography, ever.

## 8. Explicit non-goals (v1)

Groups. Voice/video. Multi-device. Server-side anything. Message search across devices. Identity discovery. Federation (single hosted relay in v1; bring-your-own-relay is a planned pro feature, and the protocol must not assume relay trust anywhere, which it doesn't).

## 9. Threat-model summary (honest edition)

| Adversary | Protection |
|---|---|
| Relay operator (incl. compelled) | Sees ciphertext + routing metadata only; nothing stored to hand over. |
| Network observer | TLS to relay + E2E within; sees that a device talked to the Nimna relay. |
| Pairing-time MITM | Safety-phrase verification; code TTL and single-use. |
| Peer's device seized | Out of scope for protocol; mitigated by app lock, expiry, panic wipe. |
| Your own device seized | App lock, encrypted-at-rest storage, panic wipe, no cloud backups. |
| Metadata correlation (IP/timing) | Acknowledged limitation in v1; document honestly. Future: relay federation, transport overlays. |
