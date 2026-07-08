# SESSION 12 — Knock, presence, offline-compose, reconnect (worktree `session-12-presence`)

Group G4 (∥ S11). Consumes the FROZEN v0.2.1 codec (S10) — no envelope changes.
Owns: `lib/src/presence` (knock UX, outbox, reconnect, background grace,
token-refresh CONTROL usage, push opt-in) + connection-state files inside
`lib/src/session/connection`.

Spec: `docs/nimna-protocol-spec-v0.2.1.md` §3.2 knock/push, §3.3 background grace,
§3.4 offline-compose, §6.1 stale-knock hint.
Plan: `nimna-build-plan-v3-sessions.md` Session 12.

Done-when: compose-offline → knock (+push when enabled) → accept → backlog
delivers in order; token rotation survives; push-off channels function as pure
burner-line mode.

---

## Intake

_Tech-architect intake (binding). Stamp: 2026-07-07 21:25 +0200. Analysis only —
no production code written this pass._

### 0. Ground truth confirmed in the worktree

- `SessionController` (`session/connection/session_controller.dart`) is the
  Flutter-free connection lane, S12-owned by the G4 split. It already carries
  the exact `// TODO(S12)` seams this session lands: knock-accept gating,
  offline-outbox flush, background grace, reconnect, token-refresh,
  push-in-KNOCK. The import-direction fence
  (`test/session/import_direction_test.dart`) is what makes S11 ∥ S12 safe.
- The v0.2.1 codec is FROZEN and sufficient — **no envelope change is needed
  or permitted.** Everything S12 needs already exists: `FrameType.knock`
  (payload `platform(1)‖token_len(2)‖token`, §5.4), `FrameType.accept/teardown`,
  `ControlType.tokenRefresh (0x04)` with `TokenPayload` codec
  (`protocol/token_payload.dart`, §5.7 present/absent), `ControlBody.validate`
  already accepts token-refresh.
- Storage already has the fields: `ChannelRecord.pushOptIn` (DEFAULT OFF) and
  `ChannelRecord.peerDeviceToken` (encrypted, in-record) — S9 provisioned them,
  push-off, so **no schema/model change to `channel_record.dart` is required.**
- Reconnect *policy* primitive exists: `ReconnectBackoff` (`transport/
  relay_socket.dart`) — "asks `nextDelay()`, never loops on its own." S12
  supplies the (bounded) caller.
- Copy already authored in ARB: `session_lineDropped` ("The line dropped.
  Trying to reconnect…"), `session_lineRecovered` ("You're both here."),
  `session_lineLost` ("The line dropped." terminal). **S12 wires them to states;
  no new session_ strings for string 10.**
- Headless harness exists: `test/helpers/fake_relay.dart` +
  `test/session/session_controller_test.dart` (two controllers over an
  in-memory bridge) — the done-check reuses it.

### 1. Module layout

**New: `lib/src/presence/` (S12-owned, disjoint from S11).**

| File | Lane | Responsibility |
|---|---|---|
| `session_launcher.dart` | pure Dart | THE factory: builds a `SessionController` from a `ChannelRecord` (wires sodium/aead/connector/messages/crid/statics/role + the KNOCK push payload). Replaces the "entry points that construct the controller are S12" TODO in `routes.dart`/`chat_screen.dart`. |
| `knock_controller.dart` | `ChangeNotifier` | Outgoing knock/waiting/lapse UX for one channel (F5 status line): 60 s waiting countdown, lapse → **"No answer."** + manual **"Knock again"**, §6.1 stale hint after an extended stretch. Drives the knocker launcher; **never auto-retries the cold knock** (spec §4 / string 6). |
| `incoming_knock_controller.dart` | `ChangeNotifier` | F6 receiving-knock banner/screen state (label + Pick up / Ignore, 60 s auto-dismiss). Pick up → `SessionController.acceptKnock()`; Ignore → drop (relay expires the pending knock at 60 s). |
| `reconnect_coordinator.dart` | pure Dart | Bounded automatic recovery of a **live-session** drop (keepalive/bridge death). Rebuilds a fresh `SessionController` via the launcher (keys are destroyed per session — §3.3.1 — so "reconnect" = fresh knock+KK), driven by `ReconnectBackoff`. Surfaces reconnecting → recovered ("You're both here.") or terminal ("The line dropped.") on exhaustion. Distinct from the cold knock (§ USER doctrine below). |
| `background_grace.dart` | pure Dart | The ~30 s grace timer (injectable clock): start-on-background, cancel-on-foreground, on-expiry callback closes the session. Client-side only — **no relay state.** |
| `app_lifecycle_gate.dart` | **Flutter** (the ONLY Flutter file here) | `WidgetsBindingObserver`: maps `AppLifecycleState.paused/resumed` → `background_grace` start/cancel → `SessionController.dispose()` on grace expiry. Thin, fence-pinned. |
| `push_opt_in.dart` | pure Dart | Reads/writes `ChannelRecord.pushOptIn` via `ChannelRepository`; **builds the KNOCK payload** from the stored `peerDeviceToken` when opt-in is on (see §3). Binds string 18 honest copy. Zero push SDK. |
| `peer_token_store.dart` | pure Dart | Receive-side handler: persists a peer token-refresh CONTROL to the channel record (present→store, absent→revoke/delete). Also the `sendTokenRefresh(TokenPayload)` seam contract that **S15** supplies a real own-token to. |
| `README.md` | — | Per the folder-README rule. |

**Edited (S12-owned): `lib/src/session/connection/session_controller.dart`** —
minimal, surgical deltas only (details §2):
1. **Knock-accept gating** — stop auto-ACCEPTing on `KNOCK_FWD`; emit an
   `IncomingKnock` event and add `acceptKnock()` / `ignoreKnock()`.
2. **Outbox auto-flush** — on handshake-complete (`live`), seal+send all
   `DeliveryState.waiting` records in `seq` order (waiting → sent).
3. **KNOCK push payload** — inject an optional `Uint8List? knockPushPayload`
   into `start()` (built by `push_opt_in`), replacing the empty-payload
   `// TODO(S15)` at the knock send.
4. **Token-refresh receive** — implement `case ControlType.tokenRefresh` →
   `onPeerTokenRefresh(TokenPayload)` callback (persisted by `peer_token_store`).
5. **Token-refresh send seam** — `sendTokenRefresh(TokenPayload)` (S15 calls it
   with the acquired own-token).

Background grace and reconnect need **no new SessionController state** — they use
existing `dispose()` + rebuild-via-launcher. That keeps the shared-ish
controller touch small.

**File-disjointness proof vs S11 (`lib/src/media` + `lib/src/session/chat`):**
S12 writes only `lib/src/presence/**` and the single file
`lib/src/session/connection/session_controller.dart`. S11 writes `lib/src/media/**`
and `lib/src/session/chat/**` (composer/bubbles/chat_screen/message_actions).
Zero directory overlap. **Merge hotspots (shared, append-only, serialized at
fold):**
- `lib/src/session/model/chat_event.dart` — S12 appends `IncomingKnock` (and any
  reconnect notification) to the `ChatEvent` sealed set and extends the
  `SessionLineState` enum (waiting / reconnecting) — the enum's own doc already
  says "S12 extends the rich presence choreography." S11 appends media events.
  Additions are in disjoint regions; orchestrator folds serially.
- `lib/src/diag/diag_events.dart` — S12 appends identifier-free events (see §Decisions);
  S11 appends media events. Coordinate integer wire IDs at fold.
- `lib/l10n/app_en.arb` + siblings — namespaced `knock_*` / `presence_*` / `push_*`
  (see §7); S11 uses `media_*`. Fold union.
- `lib/src/pairing/joiner/join_controller.dart:281` — ONE line, to make the
  persisted `peerDeviceToken` platform-preserving (see §3). Pairing is not S11's
  lane; safe, but it is outside S12's declared dirs — flagged for the fold.

`session/model/message_view.dart` is **not** expected to change in S12 (media adds
its fields — S11). If S12 must touch it, that is the second hotspot — flag then.

### 2. Reconnect / grace / outbox design (spec-grounded)

**Offline-compose outbox (§3.4).** No new store. A message composed offline is
already persisted `DeliveryState.waiting` by `sendText` (the plaintext budget is
untouched — surrogate 16-byte id + int `sort`/`purge_at` only; body stays inside
the channel-CDK ciphertext). S12 adds the flush: on the `live` transition, iterate
`_records` in insertion (`seq`) order, and for each `direction == sent &&
deliveryState == waiting`, seal the inner envelope and advance waiting → sent
(`delivered` still arrives via the peer ACK). Order is guaranteed by the ordered
`_records`/`seq`; "indistinguishable from live typing" (§3.4) holds because it is
the same seal path. **Knocks are never auto-sent by the flush** — the flush runs
only *after* a bridge already exists.

**Background grace (§3.3, ~30 s, client-side only).** `app_lifecycle_gate`
(Flutter) observes `paused` → starts `background_grace` (30 s, injected clock);
within the window the live socket stays up so an inbound message/knock lands as if
foregrounded; `resumed` cancels it; on expiry the gate calls
`SessionController.dispose()` (socket closes = implicit TEARDOWN, §5.4). **No relay
state, no VoIP/background-audio hacks** (review-fatal, §3.3). After grace, re-entry
is the knock→(push)→reconnect path — i.e. a fresh session, not a resumed one.

**Reconnect (§3.3 keepalive; string 10).** Scope = recovery of a **mid-session
drop only** (a `connectionLost` that followed a `live` state). Because §3.3.1
destroys all keys at teardown and "every session starts from a fresh handshake,"
reconnect = the `reconnect_coordinator` rebuilds a fresh `SessionController` via the
launcher and re-runs connect → REGISTER_CRID → (knocker) KNOCK, spaced by
`ReconnectBackoff`, for a **bounded** window. Success → new bridge + KK → recovered
("You're both here."); the fresh session's `live` transition auto-flushes any
messages that queued during the gap. Exhaustion / peer absent → terminal
`connectionLost` ("The line dropped."). The relay's own 1/10 s knock-collapse
(§4, S5) throttles the re-knock regardless.

**State machine deltas to `SessionLineState`** (enum in `session/model`, hotspot):
add `waiting` (knocked, 60 s countdown running — knocker) and `reconnecting`
(drop recovery in flight). Mapping to copy: `connecting`→(status), `waiting`→string 6,
lapse→`knock_noAnswer`, `reconnecting`→`session_lineDropped`, recovered→
`session_lineRecovered`, terminal→`session_lineLost`. `endedByYou/Peer` unchanged.

**Device-token refresh in live sessions (§3.2.1 / §5.5).** Receive: `peer_token_store`
persists the decoded `TokenPayload` to `ChannelRecord.peerDeviceToken` (present→store
encoded form, absent→delete = unilateral revoke). Send: the `sendTokenRefresh` seam
exists in S12 but is **called by S15** with the real acquired own-token (§3 boundary).

### 3. Push opt-in + the S12 / S15 boundary

- **Per-channel, DEFAULT OFF** — already `ChannelRecord.pushOptIn = false`.
  Persistence is the existing encrypted channel record; **no new store.**
- **Honest one-line trade (string 18)** rendered as always-visible `caption`
  under the toggle (components.md: "the caption is the disclosure, not a one-time
  dialog"). Turning it on re-states it, confirm-free.
- **Token into the KNOCK payload only when enabled.** `push_opt_in` builds the
  §5.4 KNOCK payload `platform(1)‖token_len(2)‖token` from the stored
  `peerDeviceToken` iff `pushOptIn && peerDeviceToken != null`; otherwise the
  KNOCK payload is **empty** (pure burner-line, zero third-party touch). The relay
  strips the token before `KNOCK_FWD` (§3.2) and forgets it — nothing S12 controls.
- **Platform-preservation invariant (CODE decision, §Decisions).** The KNOCK
  payload and the token-refresh CONTROL both need the `PushPlatform` byte, but
  `join_controller.dart:281` currently persists `material.peerToken.token` (raw
  token, platform dropped). S12 sets the invariant: **`peerDeviceToken` persists
  the §5.7 *present-form* `token_payload` bytes** (`0x01‖platform‖len‖token`).
  The KNOCK payload = those bytes minus the leading `0x01`; the CONTROL
  token-refresh body = those bytes verbatim. Requires a one-line change to the
  pairing writer (store `peerToken.encode()`), safe because push is off in all
  shipped/headless data (no present token exists yet). No `channel_record.dart`
  struct change.
- **S12 ⟂ S15 boundary — explicit:**
  - **S12 owns:** the opt-in flag UI+persistence; the honest copy; building the
    token-into-KNOCK payload; the token-refresh **receive-and-persist** path; the
    `sendTokenRefresh` **seam** (method signature + wire path); the
    platform-preservation invariant.
  - **S15 owns:** acquiring THIS device's own token from APNs/FCM (the platform
    push SDK/registration), **calling** `sendTokenRefresh` with it at session
    start, the relay-side APNs/FCM outbound call is already S5, and the
    content-free-push→tap→app-launch→reconnect routing. **No push SDK is added in
    S12.**

### 4. Attribution-free lapsed knock — confirmed

The relay gives the knocker nothing to attribute with: **no `PEER_OFFLINE`, no
lapse frame** (§5.4 / §3.2, DECISIONS 2026-07-04). The knocker's client simply
times out and renders **exactly "No answer."** (`knock_noAnswer`) — never
"offline", "didn't pick up", or any attribution (voice guide register line 129).
Offline vs saw-and-ignored is indistinguishable by construction. The §6.1
stale-knock hint (string 16) is a **LOCAL-only** heuristic surfaced after an
extended unanswered stretch — **no wire signal, no relay involvement.**

### 5. Dependency decisions

**No new dependencies.** S12 reuses `dart:async` `Timer` (grace / reconnect /
60 s countdown), the existing `RelayConnector` / `ReconnectBackoff` /
`RelaySocket`, `ChannelRepository` / `MessageRepository`, and the FROZEN codecs
(`TokenPayload`, `OuterFrame`, `InnerEnvelope`). `WidgetsBindingObserver` is
Flutter SDK (no package). **No crypto/network/push package is proposed → no
sign-off required.** Nothing at rest is added on the relay (S12 is app-only).

### 6. Done-check plan (headless evidence for senior-qa)

Harness: `test/helpers/fake_relay.dart` bridge + two `SessionController`s (extend
`session_controller_test.dart`).

| Done-when clause | Headless evidence |
|---|---|
| compose-offline → knock → accept → **backlog delivers in order** | Knocker offline (connector throws / no bridge); compose 3 texts → assert all `waiting`. Bring accepter online; knocker `start()`+KNOCK; accepter `acceptKnock()` → bridge → KK → assert knocker seals the 3 in `seq` order, accepter receives in order + ACKs, knocker → `delivered`. |
| **+ push when enabled** | `pushOptIn=true` + stored `peerDeviceToken` → assert KNOCK `OuterFrame.payload == platform‖len‖token`; `pushOptIn=false` → assert payload **empty**. |
| **token rotation survives** | Live session: accepter sends CONTROL token-refresh (present, new token) → assert knocker's `ChannelRecord.peerDeviceToken` updated (encoded form); absent form → assert token deleted; a subsequent KNOCK carries the rotated token. |
| **push-off = pure burner-line** | `pushOptIn=false` → KNOCK payload empty; **CI/import-fence assert: no APNs/FCM/push SDK imported anywhere** (S12 adds none). |
| reconnect (string 10) | Live, then kill bridge (accepter dispose) → knocker `connectionLost` after `live` → coordinator re-knocks (injected backoff/clock); accepter returns → re-bridge → `recovered`; exhaustion → terminal `lineLost`. |
| background grace | Injected-clock `background_grace`: `paused`→timer; inbound within 30 s lands; expiry→`dispose()` (socket closed). |
| lapsed knock | No bridge within 60 s → state `lapse`, caption exactly `knock_noAnswer`; extended → `knock_staleHint` surfaces (local). |

**Device-deferred rungs (S7/S18 pattern):** real APNs/FCM delivery, push-tap
app-launch, real OS 30 s background socket-hold, real platform token rotation, and
the F6 push→knock-screen route — proven on-device in S18. Headless proves the wire
bytes + logic; the device proves OS integration.

### 7. ARB namespace + route registrations (for fold-in)

**ARB (namespaced):**
- `knock_waitingTitle`, `knock_waitingCaption` (string 6), `knock_noAnswer`
  ("No answer."), `knock_again` ("Knock again"), `knock_staleHint` (string 16),
  `knock_incomingKnocking` (F6, ICU `{label}`), `knock_pickUp`, `knock_ignore`.
- `presence_composeOfflineTitle`, `presence_composeOfflineBody` (string 5).
- `push_toggleLabel`, `push_tradeOff`, `push_tradeOn` (string 18 two lines).
- **Reused, not re-added:** `session_lineDropped` / `session_lineRecovered` /
  `session_lineLost` (string 10, already present — S12 only wires them).
- The chat-bubble "WAITING — ON YOUR PHONE ONLY" group header is chat-lane (S11)
  chrome — **not** an S12 string; coordinate so it is not double-added.

**Routes (`app/routes.dart`):**
- `/chat` already registered (S10). S12 supplies the *builder* entry
  (`session_launcher`) that constructs the controller — **no new route** for
  knock/wait/reconnect (they live on the F5 chat surface + the incoming-knock
  overlay/banner).
- **Candidate (scope-flagged):** `Routes.channelSettings` (F7) IF S12 hosts the
  push toggle on a dedicated channel-settings screen — see USER/PM Q3.
- The F6 push→knock **screen** route is S15 (push-launch), not S12.

### 8. Consolidated USER / PM questions

1. **Reconnect doctrine + threshold (PM/USER).** The designs sanction the
   `reconnecting` state (components.md line 131; string 10 "wired S12"). S12's
   mechanism re-KNOCKs (bounded, backoff, relay-10 s-collapse-protected) to
   recover a **mid-session** drop. Confirm this is squarely distinct from the
   cold-knock "app never auto-retries" doctrine (which governs an *unanswered*
   knock only), and pick the give-up feel — how long "Trying to reconnect…" runs
   before it becomes terminal "The line dropped." (proposed default: the
   `ReconnectBackoff` schedule for ~60–90 s, then terminal — non-blocking).
2. **Offline-composed REACTION outbox scope (PM).** components.md says an offline
   reaction "rides the outbox silently" (§3.4), but the current model has no
   pending-reaction marker — an offline reaction updates local state and is not
   re-sent on the next bridge. Include reaction-outbox flush in S12 (needs a small
   pending marker, likely a `message_record` field = a shared-domain-model touch)
   or defer to a follow-up? The done-check requires only **text** backlog ordering,
   so this is genuine scope, not correctness.
3. **Push-toggle surface / F7 scope (PM).** Does S12 build the F7 channel-settings
   screen to host the push toggle + string 18 (adding `Routes.channelSettings`),
   or mount the toggle minimally pending a fuller F7 session? F7 also carries the
   typing toggle and default-expiry, which may belong to other sessions.

_Architecture boundaries I am setting (orchestrator may override, not USER
decisions): the cross-channel always-connected KNOCK_FWD listener (register all
CRIDs on foreground) + push-tap→channel routing is **S15** — S12 handles
per-channel accept on an engaged channel, which is all the done-check needs._

_The string-10 copy itself is **not** an open question — it is already authored in
ARB; only the state→string mapping wants a PM claim-accuracy nod (Q1)._

## Implementation

_Mobile dev, 2026-07-07. Branch `session-12-presence`. Analyze + full test
(360 tests) + format all GREEN in the worktree._

### New tree `lib/src/presence/**` (S12-owned)
- `session_launcher.dart` (pure Dart) — THE factory: builds a `SessionController`
  from a stored channel (own static = record public + repo-held SecureKey,
  never disposed by the controller), wires the receive-side token-refresh sink
  and the KNOCK push payload, seeds offline reactions across a reconnect
  rebuild.
- `knock_controller.dart` (`ChangeNotifier`) — outgoing knock: ONE knock, 60 s
  window (injected timer), lapse → `KnockState.lapsed` (logs `knockLapsed`) +
  manual `knockAgain()`, §6.1 stale hint after repeated unanswered knocks
  (local heuristic, no wire signal). NEVER auto-retries.
- `incoming_knock_controller.dart` (`ChangeNotifier`) — F6 banner: watches for
  `IncomingKnock`, `pickUp()`→`acceptKnock()`, `ignore()`→`ignoreKnock()`, 60 s
  auto-dismiss.
- `reconnect_coordinator.dart` (pure Dart) — bounded (~20 s) auto-recovery of a
  LIVE-session drop only: rebuilds a fresh controller via the launcher
  (`ReconnectBackoff`-spaced, injected sleeper+clock), phases
  reconnecting→recovered/lost (→ string 10). Adopts a controller and watches
  for a `connectionLost` that followed `live`.
- `background_grace.dart` (pure Dart) — 30 s client-only grace (injected timer):
  onBackground/onForeground/expiry→`onExpired` + `backgroundGraceExpired`.
- `app_lifecycle_gate.dart` (**Flutter**, WidgetsBindingObserver) — maps
  paused/hidden→onBackground, resumed→onForeground.
- `push_opt_in.dart` (pure Dart) — per-channel flag persistence + derives the
  §5.4 KNOCK payload (`platform‖len‖token`) from the stored present-form token
  when on; EMPTY when off (pure burner-line).
- `push_opt_in_tile.dart` (**Flutter** widget) — the F7 toggle row + string-18
  always-visible disclosure. (Second Flutter file beyond the intake's
  "app_lifecycle_gate only" note — justified by USER decision 2 "ship the
  toggle". Leaf widget, ready to mount; see fold note.)
- `peer_token_store.dart` (pure Dart) — receive-side: persists a peer
  token-refresh to the channel record (present→store encoded form, absent→
  revoke); names the `SendTokenRefresh` seam S15 fulfils.
- `README.md`.

### Reconnect / grace / outbox as built
- **Offline outbox (text)** — no new store. On the `live` transition
  (`_flushOutbox`, in `_onHandshakeFrame`), every `sent`+`waiting` TEXT record
  is re-sealed in `seq` order (waiting→sent; `delivered` still arrives via the
  peer ACK). Media waiting records are deliberately skipped — S11's lane.
- **Offline REACTION outbox (decision 3)** — an offline `sendReaction` records a
  pending marker (`Map<referentRecordHex, PendingReaction>`, collapsed per
  referent); `_flushPendingReactions` re-sends on `live`. Carried across a
  reconnect via `pendingReactions` getter → launcher `seedPendingReactions` →
  applied after history load.
- **Background grace** — client-only 30 s timer; expiry disposes the session
  (socket close = implicit TEARDOWN). No relay state.
- **Reconnect** — fresh `SessionController` per attempt (keys die per session,
  §3.3.1); bounded window; recovers to `live` (auto-flushes the gap's outbox)
  or terminal loss. Distinct from the cold knock (never auto-retried).

### Push opt-in + S12/S15 boundary as built
- Per-channel `pushOptIn` (DEFAULT OFF) via existing encrypted record; no new
  store. `PushOptInTile` renders string 18 both lines as the always-visible
  caption. Token rides the KNOCK payload ONLY when `pushOptIn && stored token`;
  empty otherwise (verified: `no_push_sdk_test` asserts zero push SDK imports).
- S12 owns: opt-in persistence, honest copy, token-into-KNOCK, token-refresh
  **receive+persist**, `SessionController.sendTokenRefresh` **seam**, the
  platform-preservation invariant. S15 owns: acquiring THIS device's own token
  and CALLING the seam + push-tap routing. **No push SDK added.**

### Controller deltas (`session/connection/session_controller.dart`, S12-owned)
Knock-accept gating (stop auto-ACCEPT → emit `IncomingKnock` +
`acceptKnock()`/`ignoreKnock()`); `start({knockPushPayload})` sends KNOCK with
payload + logs `knockSent` + sets `waiting`; outbox auto-flush on `live` (text +
reactions); `case ControlType.tokenRefresh` → decode + `peerTokenRefreshed` +
`onPeerTokenRefresh` callback; `sendTokenRefresh(TokenPayload)` seam;
`_onConnectionClosed` treats `waiting` as an honest loss. Media regions
untouched.

### Device-deferred (implemented fully, honestly marked)
Real APNs/FCM delivery + own-token acquisition (S15), OS 30 s background
socket-hold + push-tap→knock-screen route (S15/S18). Headless proves the wire
bytes + logic; the device proves OS integration. Nothing faked.

## Decisions (fold candidates — USER vs CODE)

- **CODE (2026-07-07 21:25 +0200):** `ChannelRecord.peerDeviceToken` persists the
  §5.7 **present-form `token_payload`** bytes (`0x01‖platform‖token_len‖token`),
  platform-preserving — not the raw token. The KNOCK payload derives by dropping
  the leading `0x01` presence byte; the token-refresh CONTROL body is the stored
  bytes verbatim. Aligns the one existing writer (`join_controller.dart:281`,
  `peerToken.encode()`); safe because no present token exists in any shipped or
  headless channel (push default-off). No `channel_record.dart` struct change.
- **CODE (2026-07-07 21:25 +0200):** "Reconnect" = a fresh `SessionController`
  (fresh knock + KK) rebuilt by `reconnect_coordinator`, not a resumed transport —
  §3.3.1 destroys keys per session and mandates a fresh handshake. Automatic
  reconnect applies ONLY to a **mid-session** drop (a `connectionLost` after a
  `live` state); the cold unanswered knock is never auto-retried (§4 / string 6).
  [Threshold/doctrine confirm → USER Q1.]
- **CODE (2026-07-07 21:25 +0200):** Background grace is a client-only 30 s timer
  (`background_grace` + `app_lifecycle_gate`) that ends the live session on expiry
  via existing `SessionController.dispose()`. No relay state; no VoIP/background-
  audio socket extension (review-fatal, §3.3).
- **CODE (2026-07-07 21:25 +0200):** Knock-accept is gated behind explicit pick-up
  — `SessionController` stops auto-ACCEPTing on `KNOCK_FWD`, emits `IncomingKnock`,
  and exposes `acceptKnock()` / `ignoreKnock()` (F6). Ignore = silence; the relay
  expires the pending knock at 60 s.
- **CODE (2026-07-07 21:25 +0200):** Push token-refresh is split S12 (receive +
  persist + `sendTokenRefresh` seam) / S15 (own-token acquisition + invocation +
  push-tap launch). No push SDK is added in S12.
- **Proposed diag events (identifier-free; append to `diag_events.dart`, fold
  hotspot — coordinate integer wire IDs with S11):** `knockSent`, `knockLapsed`,
  `sessionReconnecting`, `sessionRecovered`, `backgroundGraceExpired`,
  `peerTokenRefreshed`. Events only — never tokens/CRIDs/content (CLAUDE.md logging
  rule; the token-refresh event carries no token bytes). **LANDED as ids 19–24.**

_Added during implementation (CODE, mobile dev, 2026-07-07):_
- **CODE:** the offline-REACTION pending marker (`PendingReaction`, decision 3)
  lives in `chat_event.dart` + in session memory, carried across a reconnect via
  the launcher seed. A PERSISTED `MessageRecord` flag (restart-durable) is
  DEFERRED to the fold with S11 — S12 stays out of `message_record.dart` (not its
  lane). The done-check (reconnect/bridge re-send) is met.
- **CODE:** shipped a second Flutter file in `presence/` — `push_opt_in_tile.dart`
  — beyond the intake's "app_lifecycle_gate is the only Flutter file" note, to
  satisfy USER decision 2 (ship the toggle + string 18). It is a leaf widget
  (value+onChanged), NOT mounted into a screen this session (no owned per-channel
  surface; F7 = S16) — the mount is a flagged fold item.
- **CODE:** the outbox auto-flush handles TEXT + REACTION only; MEDIA waiting
  records are left for S11's flush branch (lane-disjoint).
- **CODE:** the §6.1 stale-knock hint is a local heuristic surfaced after ≥ 2
  consecutive unanswered knocks — no wire signal, no attribution.

## Deps added (architect sign-off required)

**None.** S12 adds no packages. It reuses `dart:async` `Timer`, the existing
transport (`RelayConnector` / `ReconnectBackoff` / `RelaySocket`), storage
(`ChannelRepository` / `MessageRepository`), the FROZEN codecs (`TokenPayload` /
`OuterFrame` / `InnerEnvelope`), and Flutter-SDK `WidgetsBindingObserver`. No
crypto/network/push dependency is proposed, so no sign-off is required. The relay's
at-rest inventory is untouched (S12 is app-only).

## ARB keys added (namespaced `presence_*` / `knock_*`)

EN canonical (`app_en.arb`); non-EN siblings stay `@@locale`-only (S16 crafted
pass), matching S10. Eleven keys, all verbatim from the voice guide / designs:

- `knock_waitingTitle` (string 6 line 1), `knock_waitingCaption` (string 6
  line 2), `knock_noAnswer` ("No answer.", verbatim, attribution-free),
  `knock_again` ("Knock again"), `knock_staleHint` (string 16),
  `knock_incomingKnocking` ("{label} is knocking.", ICU `{label}`, F6.1),
  `knock_pickUp` ("Pick up"), `knock_ignore` ("Ignore").
- `push_toggleLabel` ("Notify me when they knock", F7), `push_tradeOff`
  (string 18 line 1), `push_tradeOn` (string 18 line 2).

**Reused, NOT re-added (avoids collision):** `session_lineDropped` /
`session_lineRecovered` / `session_lineLost` (string 10 — S12 only WIRES them to
`reconnecting`/recovered/`connectionLost`); `chat_peerOfflineHeadline` /
`chat_peerOfflineBody` (string 5, already authored by S10's chat lane — the
presence outbox needs no own copy); `chat_waitingHeader` ("WAITING — ON YOUR
PHONE ONLY", S10 chat chrome). No `presence_composeOffline*` added — would
duplicate the existing chat-lane string 5.

**Fold:** ARB union with S11's `media_*`; no namespace collision (S12 uses
`knock_*`/`push_*`).

## Route registrations

No new routes (per intake + USER decision 2 — no `Routes.channelSettings`).
`session_launcher` is the *builder* entry that constructs the controller for the
existing `/chat` route; knock/wait/reconnect live on the F5 surface + the
incoming-knock overlay. The F6 push→knock-screen route is S15.

### Shared-file touches (FOLD COORDINATION — list for the serial fold)
S11 merges first; this branch rebases onto updated main. All S12 edits are
region-localized and `S12`-commented for a clean reconcile.

1. `lib/src/session/model/chat_event.dart` — appended `SessionLineState.waiting`
   + `.reconnecting`, `IncomingKnock` event, `PendingReaction` marker
   (append-only, disjoint from S11's media additions).
2. `lib/src/diag/diag_events.dart` — appended events **19–24** (`knockSent`,
   `knockLapsed`, `sessionReconnecting`, `sessionRecovered`,
   `backgroundGraceExpired`, `peerTokenRefreshed`). **Coordinate wire ids with
   S11's media events at fold** — renumber only if S11 claimed one first
   (nothing shipped).
3. `lib/src/session/chat/chat_screen.dart` (**S11 lane — flagged**) — TWO cases
   added to the exhaustive `_statusLine` switch (`waiting`→`knock_waitingTitle`,
   `reconnecting`→`session_lineDropped`) purely to keep analyze green after the
   enum grew. Final F5/knock-screen presentation is the chat lane's — the fold
   may re-map. `// S12 FOLD HOTSPOT` comments mark both.
4. `lib/src/pairing/joiner/join_controller.dart` (**outside declared dirs —
   flagged**) — ONE line: persist `material.peerToken.encode()` (§5.7
   present-form, platform-preserving) instead of the bare `.token`. Safe (push
   off everywhere shipped/headless; no present token exists yet).
5. `test/session/session_controller_test.dart` — `_Session.establish` now calls
   `acceptKnock()` (a consequence of the knock-accept gating; the accepter no
   longer auto-ACCEPTs).
6. `test/pairing/join_controller_test.dart` — the persisted-token assertion now
   expects `creatorToken.encode()` (paired with touch #4).

### Reaction-outbox shared-model marker (fold coordination with S11)
`PendingReaction` lives in `chat_event.dart`; the controller tracks offline
reactions in memory and hands them across a reconnect via `pendingReactions` +
the launcher seed. **DEFERRED to the fold with S11:** a *persisted* pending flag
on the `MessageRecord` domain model, so an offline reaction also survives an app
**RESTART** (not just an in-run reconnect). S12 does not touch `message_record.dart`
(outside its lane); the done-check (reconnect/bridge re-send) is covered.

### Push-toggle mount (fold coordination)
`PushOptInTile` + `PushOptIn` are built and unit-tested, but NOT mounted into a
running screen this session — no per-channel screen exists in S12's lane and
S11 owns the chat surface in parallel. The one-line mount (into F7
channel-settings, S16 — or any minimal existing surface) is a flagged fold
item, same treatment as touch #4.

## Review

Code review PASSED (no blocking). Two items applied in-worktree (2026-07-07):
- **S-2 (SHOULD-FIX):** added a direct test for the reconnect coordinator's
  cold-vs-live gate — `presence_flow_test.dart` "a cold knock that drops before
  going live does NOT reconnect": adopt a knocker that goes `connectionLost`
  from `waiting` (never live) and assert the coordinator stays `idle`, emits no
  phase, and re-knocks nothing (only the one original KNOCK on the wire).
  Verified it FAILS with `&& _hasBeenLive` removed (the cold knock would be
  auto-retried, violating §4) and passes with it — the defense-in-depth gate is
  now covered.
- **N-2 (nit):** `reconnect_coordinator._reconnect` now disposes the dropped
  adopted controller (cancels the sub AND closes its broadcast event stream) on
  the drop path — no leak; transport/keys were already destroyed.

Per PM ruling, the push-toggle mount stays deferred to S16 F7 (model + tile
unchanged) and the offline-reaction restart-durability flag stays a fold/S11
item — both untouched.

### Done-check de-flake (test-only; production `session_controller.dart` correct, untouched)
QA found the core done-check test non-deterministic under full-suite CPU load.
Two passes:
- **Pass 1 (2026-07-07):** replaced fixed-turn `settle()` waits with condition
  waits + a teardown DB-queue drain. Cut the flake from ~30% but a ~3% residual
  remained (QA: 1/32).
- **Pass 2 (2026-07-08):** root-caused the residual — `pumpUntil` polled with
  `Future.delayed(Duration.zero)`, which does NOT yield the CPU, so on an
  oversubscribed host the main isolate burned the tick cap while the descheduled
  sqflite FFI isolate never committed the trailing delivery-state write.
  Rewrote `pumpUntil` to a real WALL-CLOCK deadline (~30 s) polled with a NON-ZERO
  1 ms delay (which actually yields the CPU so a starved isolate is scheduled and
  its write lands; a healthy run resolves in ms). Applied the same non-zero yield
  to the teardown drain. All async end-state waits in the flow tests now use it.

## QA done-check

## Next / follow-ups

- **S15 (push):** call `SessionController.sendTokenRefresh(ownToken)` at session
  start with the acquired APNs/FCM token; push-tap → app-launch → reconnect
  routing; the cross-channel always-connected KNOCK_FWD listener (register all
  CRIDs on foreground) + push-tap→channel routing.
- **S16:** the full F7 channel-settings screen hosting `PushOptInTile` (+ typing
  toggle, default-expiry); the non-EN crafted translations for the 11 new keys.
- **S18:** on-device proof — real background 30 s socket-hold, real push
  delivery/tap, real platform token rotation.
- **Fold with S11:** the persisted `MessageRecord` pending-reaction flag
  (restart-durable offline reactions); diag wire-id 19–24 coordination; the
  chat_screen status-line cases; the join_controller one-liner; the
  `PushOptInTile` mount.

## Verification (this worktree)

- `flutter analyze` → **No issues found.**
- `flutter test` → **All 361 tests passed** (incl. 17 new S12 tests in
  `test/presence/`: offline text outbox ordered delivery, offline reaction
  re-send over reconnect, knock-accept gating, ignore=silence, token
  rotate+revoke persist, push-off empty / push-on token payload, reconnect
  recover vs terminal exhaustion, cold-knock-drops-before-live does-NOT-reconnect
  (the review S-2 gate test), background-grace expiry/cancel, cold-knock lapse
  "No answer." + never-auto-retry + stale hint, push opt-in payload, peer-token
  store, no-push-SDK source fence).
- `dart format --set-exit-if-changed` → **clean.**
- l10n regenerated (`flutter gen-l10n`) and builds.
- **No new dependencies** (`pubspec.yaml` unchanged) — reuses `dart:async`
  Timer, existing transport/storage/codecs, Flutter SDK. No architect sign-off
  required.
