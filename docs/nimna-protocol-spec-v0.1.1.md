> **DEPRECATED — historical record only. The sole normative spec is
> [`nimna-protocol-spec-v0.2.1.md`](nimna-protocol-spec-v0.2.1.md).**

# Nimna Protocol Specification — v0.1.1 (Draft)

**Status:** Draft for discussion. Crypto primitives intentionally unspecified; to be selected in Session 2 (see Build Plan). v0.1.1 adds: media & documents in v1, screenshot policy, on-device sensitive-content handling, pairing/join methods, platform-honest keepalive, device-loss doctrine, and monetization doctrine.

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
| **Pairing code** | Short, human-shareable, single-use code used only for rendezvous during pairing. User-facing name: **"Nimna code."** |
| **Channel routing ID (CRID)** | An opaque identifier derived from the channel's key material, used by the relay to match the two peers. Reveals nothing about the devices. |
| **Knock** | A request from one peer to open a live session on a channel. |
| **Session** | A live window during which both peers are connected and messages flow. |

## 3. Protocol phases

### 3.1 Pairing (one-time per channel)

1. **Initiation.** Device A generates a fresh channel keypair (A_pub, A_priv) and a pairing code `C` (format: **9 characters, Crockford Base32, displayed as XXX-XXX-XXX** — fixed permanently, see §4). The app displays **both the text code and its QR encoding simultaneously**, each independently shareable through different channels. A opens a WebSocket to the relay and registers interest in rendezvous topic `H(C)` — a hash of the code, so the relay never sees the code itself.
2. **Out-of-band share.** A shares `C` with B outside Nimna (verbally, QR in person, any channel). The code has a TTL (default: 24h, configurable at generation; shorter = safer). The share sheet carries a one-line briefing: *"Works once, expires in 24h — share it like a password."* Beyond that nudge, the sharing channel is the user's domain and its risks are theirs; Nimna does not pretend to control it.
3. **Join.** Device B generates its own fresh channel keypair (B_pub, B_priv), connects to the relay, and registers on topic `H(C)`. B may supply the code by any of four methods: (i) manual entry, (ii) paste from clipboard, (iii) live QR scan, (iv) upload of a QR image or PDF.
4. **Key exchange.** When both are present on `H(C)`, the relay bridges them. **First-come-wins:** the first joiner on the topic completes the exchange; the topic then closes. A and B exchange public keys and perform an authenticated key agreement (primitive TBD — see §7) through the relay. All subsequent traffic is encrypted end-to-end.
5. **Verification (recommended).** Both apps derive a short **safety phrase** (e.g., word/emoji sequence) from the shared channel key material and display it. The phrases on the two legitimately paired devices always match; the check works only when compared **out-of-band with the intended human** (a call, or in person — the same trusted channel the code traveled). If a MITM interposed, the two victims' phrases derive from different keys and won't match; if an interceptor paired in B's place, the real B has no phrase at all. UX: designed as the natural closing ritual of pairing ("call them and compare"), strongly encouraged, not enforced.
6. **Finalization.** Both devices derive the **CRID** from the shared key material, persist the channel locally (peer public key, own keypair, CRID, user-chosen local label), and **discard the pairing code permanently**. The rendezvous topic `H(C)` dies at the relay the moment both sides disconnect; codes are single-use and cannot be replayed.

**Failure modes:** code expires unused → nothing was created, A simply regenerates. A third party who intercepts `C` before B uses it can pair with A in B's place — mitigated by the safety-phrase check and code TTL; a misplaced code is abusable at most once, within its window. Once a channel is finalized, the code is structurally dead: later attempts hit a rendezvous topic that no longer exists and receive silence. **No failed-attempt notifications** are ever surfaced to the user — there is nothing actionable to report, and a discretion product does not manufacture anxiety.

### 3.2 Knock (session initiation)

1. Peer A (either side may knock) connects to the relay and sends `KNOCK {crid, peer_device_token?}`. The optional `peer_device_token` is B's push device-token, which A holds locally (exchanged during pairing and refreshed in sessions — see §3.2.1); it is included only if the channel has push enabled.
2. The relay checks for a live connection registered on the same CRID.
   - **Peer online (app open/connected or within background grace):** relay forwards the knock; B's app surfaces it in-app. Any device-token in the knock is ignored and discarded.
   - **Peer not connected:** relay responds `PEER_OFFLINE` to A. If the knock carried a device-token, the relay makes one outbound call to APNs/FCM using Nimna's server-side push credentials, delivering a content-free notification to that device-token: *"New activity"* — no channel, no sender, no content — then **discards the device-token immediately**. The relay stores no token registry, no CRID→device mapping, nothing. It is a stateless push *forwarder*, never a token *registry*.
3. B opens the app, connects, and sends `ACCEPT {crid}` (or ignores; knocks expire after a short TTL, e.g., 60s at the relay).
4. On accept, the relay marks the CRID as **bridged**: both connections are now paired in memory and traffic flows.

**Push is per-channel opt-in, default-off.** With push off, knocks reach only online/grace-window peers, and coordination happens out-of-band — the pure burner-line mode, with zero third-party touch.

### 3.2.1 Device-token exchange (peer-held, never server-held)

- During pairing, each side's key-exchange payload includes its current push device-token **inside the E2E-encrypted channel** (omitted if the user hasn't enabled push). Each device stores its *peer's* device-token locally, encrypted at rest like all channel data. To the relay, tokens at this stage are indistinguishable ciphertext.
- Platforms rotate device-tokens; peers refresh each other via an encrypted CONTROL frame whenever a live session occurs. A stale device-token means a push silently fails — the fallback is out-of-band coordination, identical to push-off behavior.
- **Disclosure (honest edition):** at knock time, the relay transiently observes "wake device-token Y for CRID X" — a momentary in-memory linkage of a channel to a device, unlogged and unstored. Apple/Google observe that their infrastructure delivered a content-free push from Nimna's credentials to that device at that time; they never see channel, counterpart, or content. This transient linkage and the platform's delivery knowledge are the full price of push, which is why it remains opt-in.
- Nimna's APNs/FCM credentials live on the relay server only (never in the app binary) and identify *Nimna the sender*, not any user. Consequence for future self-hosted relays: operators need their own push credentials or run push-less.

### 3.3 Live session

- Messages are client-encrypted, framed (see §5), and sent as WebSocket binary frames tagged with the CRID. The relay forwards frames verbatim to the bridged peer and retains nothing.
- **Delivery semantics:** fire-and-forward at the relay. End-to-end acknowledgment happens between clients: the recipient returns an encrypted `ACK {msg_id}`; the sender marks the message delivered. Messages not acked remain local-only in "pending" state (see §6).
- **Typing/presence indicators (optional):** encrypted control frames, indistinguishable from messages to the relay.
- **Keepalive:** clients ping every N seconds (e.g., 30s). A connection is considered dropped after a missed-ping window.
- **Session end:** either side disconnects or sends `HANGUP`. The relay tears down the bridge and forgets the CRID immediately.
- **Background grace:** after the app is backgrounded, the socket is held alive for **~30 seconds** on both platforms (this matches the iOS background execution grace; Android is kept symmetric by policy so the promise is identical everywhere). Within the grace window, an incoming knock or message reaches the app as if foregrounded. After the grace window the socket closes; longer gaps are bridged by the knock → content-free push → tap → reconnect path (§3.2), which resumes a session in about a second. No VoIP/background-audio workarounds are ever used to extend socket life — they are review-fatal for a non-call app.

### 3.4 Sending while peer is offline

There is no server queueing. A message composed while the peer is offline is stored **locally on the sender's device only**, marked "waiting." Sending it triggers a knock (and the optional content-free push). When the peers are next bridged, waiting messages transmit automatically in order. To the network, this is indistinguishable from live typing.

## 4. The relay

- **Stateless router.** In-memory tables only: `{connection → registered CRIDs}` and `{CRID → bridged connection pair}`. No database, no disk writes, no logs of routing activity in production configuration. The complete at-rest inventory of the relay: routing tables in memory, TLS certificates, and Nimna's APNs/FCM push credentials (§3.2.1). Nothing about any user is at rest, ever.
- **Never sees:** plaintext, pairing codes (only their hashes), public keys' association to real identities, message content of any kind. Never stores: push device-tokens (used once per knock, then discarded).
- **Necessarily sees:** IPs, connection timing, CRIDs, ciphertext sizes; transiently at knock time, a device-token to wake (§3.2.1). This is stated plainly in Nimna's privacy documentation.
- **Open source under AGPL-3.0** (the Signal-server/SimpleX precedent: anyone operating a modified relay as a service must publish their modifications — protecting users' expectations of anything called a Nimna relay). The protocol spec is published openly alongside; the app remains closed. Reproducible-build/deployment story so third parties can verify the deployed code matches the repo (best-effort in v1). **Push credentials (APNs/FCM) are deployment configuration, never repository content** — the repo ships config slots and a `.gitignore` guard, never values; auditors verify push *behavior* in the open code (content-free string, token discarded), while credentials only determine whose developer account sends. Self-hosted relays supply their own credentials or run push-less.
- **Rate limiting & abuse control:** per-IP connection caps, per-connection frame-rate caps, max frame size (bounds attachment ambitions), and rendezvous-topic throttling to impede code brute-forcing. **Code format, fixed permanently: 9 characters, Crockford Base32 (unambiguous, easy to read aloud), displayed and entered as XXX-XXX-XXX** — a space of ~35 trillion codes (~45 bits). The format never changes: validation, QR payloads, and user habit stay stable for the product's lifetime. Combined with per-IP rendezvous throttling (single-digit attempts per minute) and the 24h TTL, guessing any active code is a lottery no one wins; the astronomically lucky guesser then still faces the safety-phrase check.
- **Knock & push rate limits (relay defaults, tunable config):** platform-push forwarding capped at **1 push per CRID per 60s, 6 per CRID per hour, 20 per CRID per day**; knock forwarding capped at 1 per CRID per 10s (duplicates inside the window dropped silently — retries collapse, no error). The push counters are in-memory, user-anonymous, and reset on restart — the same class of transient state as the routing tables. Client-side, the app never auto-retries knocks: each knock is a deliberate tap. The receiver's ultimate control is per-channel push opt-out, which silences a channel unilaterally and permanently.

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

- **TEXT:** UTF-8 message body, soft cap 5,000 characters per message (frame discipline, not stinginess; longer text chunks transparently). Optional per-message `expiry` field — the sender's disappearing-message instruction (e.g., "delete after read + N minutes"). Enforcement is client-side and honor-system by nature; the UX must say so honestly.
- **ACK:** references a msg_id; confirms decryption and display on the peer device.
- **CONTROL:** typing indicators, read receipts (per-channel opt-in), screenshot notices (§5.2), device-token refresh (§3.2.1), label-free housekeeping.
- **MEDIA_CHUNK (v1):** chunked live transfer of attachments through the same pipe. No relay-side reassembly ever; to the relay these are indistinguishable opaque frames.

### 5.1 Media & documents (v1)

Images and documents (PDF/files) are first-class in v1 — the professional buyer's sensitive moments frequently involve a photographed contract, a whiteboard, a screenshot, a document. Rules:

- **Size cap:** 5 MB per attachment (enforced client-side and bounded by relay frame/rate limits). A live session moves this in seconds; Nimna is a text call, not a file service.
- **Client-side image compression by default**, with an "original quality" toggle.
- **Metadata stripping by default:** EXIF/location/device/timestamp scrubbed from images **before encryption on the sender's device**. Marketed as a feature — the photographed contract shouldn't whisper where it was photographed.
- **No auto-save to gallery, ever.** Received media lives only inside Nimna's encrypted store (§6), inside the app-lock perimeter and outside cloud photo backups. Export is a deliberate user act.
- **Disappearing applies identically to media** — the sender's `expiry` instruction governs attachments exactly as it governs text.
- **Chunking:** attachments split into MEDIA_CHUNK frames with an encrypted manifest (chunk count, content hash for integrity); receiver reassembles, verifies, acks.

### 5.2 Screenshot policy (detect-and-notify)

Nimna cannot prevent screenshots and does not pretend to. Policy, symmetric on both platforms: **screenshots are possible, and the other person is always told.** Taking a screenshot of a Nimna session emits a CONTROL screenshot-notice to the peer. This is disclosed upfront in onboarding as informed consent, in brand voice: *"Nimna can't stop a screenshot. It will always tell the other person."* Honest limits, also disclosed: detection fires only while content is on screen inside the app, and nothing detects a second camera photographing the screen. Android's stronger blocking capability (FLAG_SECURE) is deliberately not used, to keep the promise identical on both platforms. Notice delivery is honor-system like expiry (a modified client could suppress it); the trust-your-counterpart caveat already stated for disappearing messages covers this too.

### 5.3 Sensitive-content handling (on-device only, never moderation)

- **Recipient-side:** incoming images/video are checked **on-device, after decryption, before display** using the platform's local nudity-detection capability (iOS: SensitiveContentAnalysis framework; Android: no first-party public equivalent — path TBD: bundled on-device model, or iOS-only at launch). Flagged media renders blurred with a "sensitive content — tap to view" warning.
- **Sender-side:** the same on-device check runs at attach time and produces a soft, non-blocking whisper — *"This looks like sensitive content — send anyway?"* — protecting the sender from the wrong-channel disaster.
- **Hard boundary:** detection exists solely for local display decisions. Nothing is ever blocked, logged, reported, or transmitted as a result of detection; the sender is never informed of recipient-side flags. The moment detection has consequences beyond a local blur, Nimna would possess moderation infrastructure it promises not to have. Even our safety features can't phone home — they have nowhere to call.

## 6. Local storage (on-device)

- Channel store: own keypair, peer public key, CRID, local label, per-channel settings — encrypted at rest using platform keystore (iOS Keychain/Secure Enclave, Android Keystore).
- Message history: local database, encrypted at rest. Retention per user choice: keep forever (default), per-message delete, per-channel wipe, honor received expiry instructions.
- **Panic wipe:** single action that destroys a channel's keys and history irrecoverably. Destroying the keys makes any intercepted past ciphertext permanently undecryptable (assuming forward-secret primitives — a Session 2 selection criterion).
- Media store: received attachments live exclusively in the encrypted store, never the system gallery; export is a deliberate act (§5.1).
- App lock: PIN/biometric gate on app open (strongly recommended default-on).
- No cloud backup: local database is excluded from iCloud/Google backup by default. (History sync/migration between devices is explicitly out of scope for v1.)

## 6.1 Device loss & reinstall doctrine

A channel *is* its two private keys. If the app is deleted or the device is lost, the private keys are gone and every channel on that device is **cryptographically dead — by design, permanently, with no resurrection path.** Any mechanism that let a fresh install recover old channels would require durable identity outliving the keys — precisely what Nimna refuses to have — and would be indistinguishable, from the relay's side, from a thief, a wiped device's new owner, or a hijacked store account. Doctrine: **device lost → channels dead → re-pair out-of-band.** Every pair by definition has an out-of-band relationship (the code traveled it once); re-pairing costs one message on that same channel. The only thing that survives reinstall is the paid unlock, restored via platform store identity (§10). Permitted UX sugar, client-side only: a knock unanswered for an extended period may surface a local hint — "no answer in a while; if they lost their device, you'll need to pair again."

## 7. Cryptographic requirements (primitive-agnostic)

v0.1 specifies *requirements*; concrete primitives are selected in Session 2. The chosen scheme must provide:

1. **Authenticated key agreement** during pairing, bridgeable through an untrusted relay.
2. **End-to-end confidentiality and integrity** for all frames (AEAD).
3. **Forward secrecy** across sessions at minimum (compromise of current keys must not decrypt past sessions) — per-message forward secrecy (ratcheting) is preferred and likely cheap given sessions are live.
4. **A human-comparable safety phrase** derivable from the agreed key material.
5. **Replay protection** (nonces/counters within sessions).
6. Well-audited, boring, widely available in Dart/Flutter and on the relay's language of choice. No novel cryptography, ever.

## 8. Explicit non-goals (v1)

Groups. Voice/video. Multi-device. Server-side anything. Message search across devices. Identity discovery. Channel resurrection, portability, or backup of any kind. Screenshot *prevention* (detect-and-notify only, §5.2). Federation (single hosted relay in v1; bring-your-own-relay is a planned pro feature, and the protocol must not assume relay trust anywhere, which it doesn't).

## 9. Threat-model summary (honest edition)

| Adversary | Protection |
|---|---|
| Relay operator (incl. compelled) | Sees ciphertext + routing metadata only; nothing stored to hand over. |
| Network observer | TLS to relay + E2E within; sees that a device talked to the Nimna relay. |
| Pairing-time MITM | Safety-phrase verification; code TTL and single-use. |
| Peer's device seized | Out of scope for protocol; mitigated by app lock, expiry, panic wipe. |
| Your own device seized | App lock, encrypted-at-rest storage, panic wipe, no cloud backups. |
| Counterpart captures content (screenshot / second camera) | Screenshot: detect-and-notify (§5.2), honor-system, disclosed upfront. Second camera: undetectable; disclosed honestly. Trust in your counterpart is an acknowledged part of the model. |
| Metadata correlation (IP/timing) | Acknowledged limitation in v1; document honestly. Future: relay federation, transport overlays. |

**Structural abuse posture** (for store review and the /security page): pairing requires a pre-existing out-of-band relationship (no discovery, no directory — strangers cannot find each other); strictly 1:1 (no distribution networks); and every channel in existence was initiated under a paid unlock tied to a store-verified payment instrument (§10). Residual case, as in every E2E system including Signal and WhatsApp: two consenting bad actors — no messenger design prevents this, and Nimna does not claim to.

## 10. Monetization doctrine

- **Model:** initiators pay, receivers never do. Creating channels requires an active **yearly subscription, priced regionally via platform store tiers** — unlimited channel creation. No price is ever hardcoded or published outside the stores: the paywall renders the localized price string provided by StoreKit/Play Billing for the user's storefront, and marketing surfaces (website, press) describe the model without naming numbers. Joining channels and communicating on them is free forever and must never surface a paywall.
- **The permanence guarantee (protocol-adjacent, stated as firmly as zero-storage):** every channel created while subscribed is **permanent and fully functional forever**, regardless of subscription status. A lapsed subscription gates only the creation of *new* channels. Nothing is ever frozen, degraded, or repossessed. This is structurally enforced by the architecture itself: channels are keypairs, the relay has no accounts to flag as expired, and entitlement is checked only on the initiator's device at creation time. The business model inherits its decency from the architecture.
- **Restore:** the unlock is tied to platform store identity (Apple ID / Google account), restored natively via StoreKit / Play Billing on reinstall or new device — no Nimna account exists or ever will. Restore reliability is a top-tier feature: it is the only path to channel creation after reinstall. Honest limits, stated plainly in the FAQ: entitlements do not cross platforms (iOS ↔ Android requires a new purchase, industry standard); Family Sharing is disabled (one initiator, one unlock).
- **No trial channel creation.** Creation cannot be tried before paying (the receiving experience is the free trial of the product; the paywall sells the creation ritual visually). Accepted deliberately for model clarity and as an abuse gate: every channel traces to a real payment instrument.
