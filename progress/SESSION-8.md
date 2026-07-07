# Session 8 — Pairing: initiator side (worktree log)

Branch `session-8-pairing-initiator` off main `a597c77`. Parallel group G1
(peer: S13, non-protocol, disjoint tree). Appended per the parallel-session
rule; orchestrator folds at merge.

---

## 2026-07-07 00:58 +0200 · tech-architect intake note (protocol-touching session — mandatory intake)

**Sources read (this worktree):** spec v0.2.1 §3.1–§3.1.2, §3.1.3 (boundary
only — S9), §3.1.6, §4, §5.4; `docs/test-vectors/README.md` +
`topic-derivation.json` + `framing.json` (outer-frame cases);
`docs/architecture/app-architecture.md` §§1–11 (binding);
`application/relay/cmd/testclient/` (README, main.go);
`designs/wireframes/f2-create-channel.html`, `designs/system/components.md`,
`designs/brand/voice-and-microcopy.md`; DECISIONS.md. All decisions below
are CODE unless flagged.

### 1. Scope fence (codec checkpoint — binding)

S8 is the only protocol-envelope-touching session in flight. It implements
**only**:

- §3.1.1 code generation + canonicalization + QR payload string
  (`nimna:XXX-XXX-XXX`).
- §3.1.2 topic/psk derivation (date-salted SHA-256 → Argon2id t=3/m=64 MiB/
  p=1 → HKDF-SHA-256 topic[16]/psk[32]). The psk is derived and held
  (SecureKey) because S9's handshake needs it, but **nothing consumes it in
  S8**.
- §5.4 outer frame: the 18-byte header codec (`ver ‖ frame_type ‖
  routing_id[16] ‖ payload`) and the full frame-type enum (all §5.4 values
  — the enum is outer-frame surface, in scope). Payload interpretation only
  for what S8 sends/receives: `REGISTER_TOPIC` (empty) out,
  `TOPIC_BRIDGED` (empty) in, `PAIR_DATA` as **opaque bytes** surfaced to
  the pairing layer (S9 gives them meaning).

**Explicitly NOT built:** §5.5 inner envelope, §5.6 nonce/key discipline,
§5.7 token_payload, §5.8 — all S10's codec (the checkpoint). No Noise
(§3.1.3), no safety phrase (§3.1.4), no CRID (§3.1.5) — S9. No speculative
"envelope stub" types: the protocol package exposes `PairData(bytes)` as an
opaque payload and stops there. Reviewer checks this fence.

### 2. Module boundaries (dependency arrows point down; §8.1 layering holds)

```
lib/src/ui/…                    F2 screens (see §5)
lib/src/pairing/initiator/      flow controller + create-line entry (§4, §5)
lib/src/protocol/               pure codec/derivation — no I/O, no state
lib/src/transport/              WS client — dart:io, no protocol semantics
lib/src/crypto/                 existing S7 layer (sodium FFI, HKDF) — extended, not forked
```

- **`lib/src/protocol/`** (pure, locale-independent, no Flutter imports):
  - `code.dart` — generation (9 chars uniform over the Crockford alphabet
    via `randombytes_uniform(32)` per character — no modulo bias),
    canonicalization exactly per §3.1.1 (strip space/tab/CR/LF + hyphens,
    uppercase fold, I→1 L→1 O→0, U and non-alphabet reject, length-9
    exact), display formatting `XXX-XXX-XXX`, QR payload string.
  - `rendezvous.dart` — §3.1.2 derivation: creator-side (code-creation UTC
    date). Salt = `SHA-256("nimna/topic/v1|" + date)[0:16]` via
    `package:crypto`; seed = Argon2id via the sodium package's `pwhash`
    (see §3); topic/psk via the existing in-repo RFC 5869 HKDF
    (`lib/src/crypto/hkdf.dart`) with the exact info labels. Argon2id
    params are named constants asserted against the spec values in tests.
    Parameterized cost inputs so the reduced-cost vector set (t=1,
    m=8 MiB) runs in unit tests; production cost is the default and the
    only cost reachable from app code.
  - `outer_frame.dart` — §5.4 codec + frame-type enum, big-endian, exact
    18-byte header, encode/decode with strict rejects (bad ver, short
    frame).
- **`lib/src/transport/`**: `relay_socket.dart` — a thin `dart:io
  WebSocket` wrapper: connect (`ws://`/`wss://`), binary-frame send/receive
  of decoded `OuterFrame`s (imports `protocol/` for the codec — transport
  knows framing, never meaning), connection-state notifier, clean close,
  and a **no-hammer reconnect policy** (foreground-resume re-register per
  F2.4; backoff on failure; never a tight retry loop — §4 rendezvous
  throttling means the client must behave like one polite registrant).
  Relay URL is injected config (dev default per relay docs), not hardcoded
  in transport.
- **`lib/src/pairing/initiator/`**: flow controller (ChangeNotifier per
  §8.2) owning the initiator state machine:
  `generating → registered/waiting → bridged (hold) | expired | cancelled`.
  On `TOPIC_BRIDGED` it enters *hold* and keeps the socket — S8's terminal
  success state ("holds rendezvous"); the S9 responder engine will attach
  exactly here (it consumes the opaque `PAIR_DATA` stream + psk + static
  keypair the controller already holds). TTL expiry: wall-clock deadline
  from generation, checked by timer while foregrounded and on every
  resume/launch; on expiry stop re-registering, discard code+keypair,
  surface F2.8.

**G1 non-overlap:** S8 touches `lib/src/transport|protocol|pairing/
initiator` + its `ui/` screens + namespaced ARB keys; S13 (lock/wipe)
touches `app/lock` + `storage/keys` UI seams. No shared files. ARB keys
namespaced `pairingCreate*` per the merge-fold rule.

### 3. Crypto reuse (S2 lock; no new crypto surface)

- **X25519 static keypair:** libsodium via the existing `sodium` package —
  `crypto_box` keypair (Curve25519). Private key lives in `SecureKey` from
  birth; it is serialized only into an encrypted at-rest record (§6 below)
  using the S7 at-rest AEAD, mirroring how channel records will hold
  statics (app-architecture §4 anticipates exactly this).
- **Argon2id:** libsodium `crypto_pwhash` (ALG_ARGON2ID13) with explicit
  opslimit=3, memlimit=64 MiB, out=32, the 16-byte pre-hashed salt —
  matching the Go side (`x/crypto/argon2`, p=1) byte-for-byte per the
  committed vectors. **Day-one spike (carried from app-architecture §11):**
  confirm `pwhash` is reachable from the standard `sodium` API on host
  tests; if it requires the sumo variant, initialize via `SodiumSumoInit`
  from the SAME package — a `SodiumInstance` widening, zero new
  dependencies. Either way it is audited libsodium computing every byte;
  any Dart-land Argon2 implementation is REJECTED outright (crypto lock).
- **HKDF:** the existing vector-locked `lib/src/crypto/hkdf.dart` — no
  second HKDF. Labels `nimna/topic/v1` / `nimna/psk/v1` live in
  `protocol/`, structurally disjoint from the `nimna/app/…` namespace.
- **FFI fence:** if `pwhash` needs pointer glue beyond the package's Dart
  API (not expected), it goes through `lib/src/crypto/at_rest_aead.dart`'s
  adjudicated fence pattern — a sibling file in `src/crypto/` with the same
  marshalling-only rule, noted for reviewer audit. No crypto arithmetic in
  Dart, ever.

### 4. G2 opening condition — the single create call site (binding design)

- One file, `lib/src/pairing/initiator/create_line_entry.dart`, exports
  the **only** function that begins code creation (say
  `Future<void> startCreateLine(BuildContext …)` — pushes the F2.1 route /
  kicks the controller). The F4 channel-list "+" action calls it; nothing
  else in the tree constructs the initiator flow or its controller
  directly (controller constructor is not exported outside `pairing/
  initiator/`; screens receive it via the flow's own route wiring).
- S17 wires the paywall gate by editing exactly this file (entitlement
  check before the flow starts; F9 intercept on failure). Test pins the
  invariant: a unit/analysis test asserts exactly one call site of the
  flow-starting symbol outside the file itself (grep-style source test,
  same class as the S7 string-scan tests).
- Pairing tree ships as `lib/src/pairing/initiator/…` only; **no
  `pairing/common`, no shared mutable scaffolding** — S9's `joiner/` is a
  sibling that shares only the pure `protocol/` + `transport/` layers
  (stateless/immutable APIs). Anything the joiner will also need
  (canonicalization, derivation, socket) already lives there by design.

### 5. UI surface (F2, binding designs)

Screens: F2.1 (generate: TTL choice + Create), F2.2/F2.4 (one screen:
code + QR simultaneous, Copy/Share, waiting state with dotted-line
language), F2.3 (share sheet with string 13 verbatim as header caption:
"Works once, expires in 24h — share it like a password."), F2.8 (expired
edge). F2.5–F2.7 (bridged moment, safety phrase, naming) are S9 — S8's
bridged state holds quietly at the F2.4→F2.5 boundary. All strings via ARB
(EN crafted, non-EN `@@locale`-only until S16); the Nimna code itself and
QR payload are protocol output — locale-independent, mono face,
`XXX-XXX-XXX` everywhere. Waiting copy promises the code's lifetime, never
background presence (USER copy decision 2026-07-04): no push, no background
socket claim; ~30 s background grace then re-register on resume. Offline at
F2.1 → the wireframe's "You're offline…" line; nothing generated without a
live registration (no phantom codes).

**TTL preset list (CODE, within rails):** designs say "configurable at
generation, default 24 h, shorter is safer" but enumerate no options.
Decision: presets **1 hour · 8 hours · 24 hours**, default 24 h. Rail: the
protocol caps at 24 h (joiner's two-topic candidates cover TTL ≤ 24 h,
§3.1.2; relay registration cap 24 h, §4) — no longer option can ever
exist. Precedent: disappearing-timer presets were CODE (DECISIONS
2026-07-03). PM may contest wording/values at review; not a USER item.

### 6. Pending-pairing persistence (at-rest, pre-channel)

The creator must (a) re-register across app restarts within the TTL (F2.4)
and (b) hold its own outstanding codes for the §3.1 self-join guard (S9
reads them). No channel exists yet, so this lands as an encrypted record in
the existing S7 store — **meta store** (`k = 'pending_pairings'`, value =
AEAD ciphertext containing a small list of {code canonical bytes, creation
UTC date, TTL, X25519 keypair}). Zero schema change, zero new plaintext
columns — the §4 plaintext budget is untouched. Cancelled/expired/finalized
entries are deleted (code+keypair discard is a real erase, §3.1 step 6 /
F2.8 "no residue"). Wipe semantics inherit from MK destruction. This is
client-side at-rest state, not relay state — statelessness invariant
untouched.

### 7. Dependencies (architect adjudication; pin exact versions at implementation)

| Dep | Verdict | Rationale |
|---|---|---|
| `dart:io WebSocket` | **APPROVED (stdlib)** | Stdlib-first. Mobile-only targets, binary frames, custom `HttpClient`/SecurityContext for QA CAs. Rejected: `web_socket_channel` (a wrapper for web-platform abstraction we don't need). |
| `qr` (pub.dev, pure-Dart QR encoder) | **SIGN-OFF GIVEN** (network-free, zero transitive deps beyond meta) | Rendering via an in-repo `CustomPainter` over its module matrix — matches the design system's CustomPainter iconography and tokens. Rejected: **hand-rolled QR** (Reed–Solomon GF(256) by hand — same discipline as the crypto lock: an audited boring encoder exists; correctness of the code's only machine-readable form is load-bearing); **`qr_flutter`** (widget wrapper around the same `qr` engine that we'd restyle anyway — needless surface). Correctness pinned by a committed expected-matrix test (matrix generated once with an independent decoder, committed as a fixture) + §3.1.1 payload-string tests. |
| `share_plus` (fluttercommunity) | **SIGN-OFF GIVEN, scoped** | Platform share only (text + QR PNG). Hand-rolled channel rejected on the image path: Android `FileProvider`/content-URI plumbing is real accumulated quirk-absorption; text-only-by-channel would drop the "share the QR as an image" design requirement. Conditions: no telemetry/network in the dependency (reviewer verifies at pin time); one call-site module (`pairing/initiator/share.dart`); the decrypt-to-temp-for-share cleanup pattern from app-architecture §5 applies to the QR PNG (delete after handoff). |
| `sodium` (existing) | Already signed off (S2/S7) | §3 above; possible sumo-init widening is the same package, not a new dep. |

No other additions. `mobile_scanner`/pickers are S9; `firebase_messaging`
remains S15's fight.

### 8. Test strategy (vs committed vectors)

- **Vector-locked (must reproduce byte-for-byte, `topic-derivation.json`):**
  canonicalization — every valid + reject case (I/L/O mapping, U reject,
  length, invalid chars); salt derivation; seed/topic/psk under the
  reduced-cost set in the default test run, production-cost set in a
  tagged/opt-in test (mirrors the Go `-short` split) — production outputs
  are what the device produces, so the production set must pass at least
  in CI's tagged lane and once on-device in QA evidence.
- **Vector-locked (`framing.json`):** outer-frame example for every
  frame_type enum value, encode + decode + reject cases (short header,
  wrong ver).
- **Unit:** code generation (format, alphabet, distribution sanity, no
  modulo bias by construction), QR payload string, TTL state machine with
  injectable clock (expiry while open, expiry discovered on resume),
  pending-pairings record round-trip + discard-erases, transport state
  machine over an in-memory fake socket (register → bridged → hold;
  disconnect → resume re-register; no retry storm).
- **Widget:** F2.1/F2.2/F2.4/F2.8 render canonical ARB strings in all five
  locales (EN fallback pre-S16); code renders mono `XXX-XXX-XXX`; QR and
  text code present simultaneously; German-length survival.
- **Source-scan:** single-call-site test for the G2 invariant (§4); the
  standing no-hardcoded-strings and diag no-String checks cover the new
  trees. Diag: new events (codeCreated, topicRegistered, bridged, expired,
  cancelled) are enum members only — the code, topic, and keys are
  structurally unloggable.
- **Integration / done-check (CLI peer):** relay from
  `application/relay` (`go run ./cmd/relay`) + app on simulator/emulator:
  app creates a code → `go run ./cmd/testclient --role join --code <code>
  --rounds 0` → testclient bridges and exits 0; app shows/holds the
  bridged state with the socket open. **`--rounds 0` is load-bearing:**
  with rounds > 0 the joiner sends demo PAIR_DATA and *expects a reply*,
  which the S8 app must not fabricate (no test-only wire behavior in the
  app — the real M2 responder is S9). Also scripted: expiry path (short
  TTL via the preset or a dev-injectable clock), restart → re-register →
  join still bridges, cancel → joiner gets silence (testclient exits
  non-zero on its own timeout: "that code didn't match anything").

### 9. Invariant check (architect lane)

- Relay untouched this session; statelessness N/A beyond noting §6's
  persistence is client-side.
- Wire behavior spec-verbatim: §5.4 layout, §3.1.1 formats, §3.1.2
  constants — all vector-pinned; no silent improvements (e.g., no extra QR
  metadata, no client retry cleverness around throttling).
- Crypto: S2-locked primitives only, via the existing sodium/HKDF layer;
  Argon2id and X25519 computed by libsodium exclusively.
- Silence doctrine: the initiator UI surfaces nothing about join attempts;
  failure states are TTL-expiry and user-cancel only.

### 10. USER decisions foreseen

**None.** TTL presets, QR/share/WS dependency choices, and pending-pairing
storage shape are CODE decisions within existing rails (recorded above; to
be folded into DECISIONS.md at merge). The paywall gate itself stays S17;
S8 ships creation ungated per the plan.

— tech-architect, 2026-07-07 00:58 +0200

---

## 2026-07-07 01:46 +0200 · mobile-developer-flutter — implementation notes

Implemented the intake note verbatim. `flutter analyze` clean ·
`flutter test` **159/159** (S7's 71 + 88 new) · `dart format` clean.

### What landed (all under `application/mobile/`)

- **`lib/src/protocol/`** (pure, no I/O, no Flutter): `pairing_code.dart`
  (§3.1.1 — uniform generation via injected sampler, canonicalization,
  `XXX-XXX-XXX`, `nimna:` QR payload; `toString` redacted),
  `rendezvous.dart` (§3.1.2 — package:crypto SHA-256 salt, libsodium
  `crypto_pwhash` Argon2id via the sumo API, in-repo HKDF; production cost
  is the default and the only cost reachable from app code —
  `Argon2Cost.reducedTestOnly` is `@visibleForTesting`), `outer_frame.dart`
  (§5.4 — 18-byte header codec + full frame-type enum, strict rejects).
- **`lib/src/transport/relay_socket.dart`**: `RelayConfig` (URL injected;
  dev default `ws://127.0.0.1:9440` via `--dart-define NIMNA_RELAY_URL`),
  `RelayConnector`/`RelayConnection` interfaces + `dart:io` impl (malformed
  inbound frames dropped silently; failures = one indistinct
  `RelayUnreachableError`), `ReconnectBackoff` (2 s → 60 s cap) — no layer
  auto-retries in a loop.
- **`lib/src/pairing/initiator/`**: `initiator_controller.dart`
  (state machine per intake §2: setup → generating → waiting ⇄ grace/
  backoff → **bridged (hold)** | expired | cancelled | **spent**; PAIR_DATA
  buffered opaquely, psk + static keypair held for S9; TTL presets
  1/8/24 h default 24 h; wall-clock expiry via timer + resume checks; 30 s
  background grace), `pending_pairing.dart` (meta-store record
  `pending_pairings`: versioned fixed binary of {code, creation UTC date,
  TTL, created_at, X25519 keypair}; remove = real erase, row deleted),
  `create_line_entry.dart` (**the G2 single entry** `startCreateLine` +
  `resumeCreateLineIfPending`), `share.dart` (the one share_plus call
  site; QR PNG → temp file → share → delete), `qr_matrix.dart` (the one
  `qr`-encoder call site, EC level M), `pairing_initiator_service.dart`
  (DI bundle in AppScope; boot-time pending read handed over
  synchronously — the widget layer never queries the DB for resume).
- **`lib/src/storage/db/meta_records.dart`**: encrypted meta values under
  `k_meta` (record id = `SHA-256(ascii(k))[0:16]` bound into AD; fresh
  nonce per rewrite). Zero schema change; plaintext budget untouched.
- **UI (`lib/src/ui/screens/pairing/`, `lib/src/ui/widgets/`)**: F2.1
  setup (+ TTL sheet, offline edge line), F2.2/F2.4 as ONE screen (QR card
  true-white + `codeDisplay` mono simultaneously, Copy → "Code copied."
  toast, Share → F2.3 sheet with string 13 as header caption, dotted idle
  line + waiting captions, Cancel this code, back-confirm modal), F2.8
  expired + spent endings, flow host with `AnimatedSwitcher`
  (disableAnimations honored) and lifecycle forwarding. Channel list:
  "Create a code" now live (sole `startCreateLine` call site), "Enter a
  code" still S9-stubbed; boot-time pending-pairing resume on first frame.
- **Diag**: five new events `pairingCodeCreated/TopicRegistered/Bridged/
  Expired/Cancelled` (ids 11–15) + code `relayUnreachable` (8) — enums
  only, string-free surface unchanged.
- **ARB**: 24 new `pairing_*` keys in `app_en.arb` (canonical strings
  byte-exact: string 13 §3.1 one-liner, F2.1/F2.4/F2.8 wireframe copy,
  hi-fi captions); non-EN ARBs stay `@@locale`-only per the S16 rule;
  gen_l10n regenerated.
- **Deps added (per intake §7 sign-offs)**: `qr ^3.0.2` (pins 3.0.2;
  runtime deps: meta only), `share_plus ^13.2.0` (pins 13.2.0; **zero
  telemetry verified at pin time** — greped the package source: no network
  code; its url_launcher_* transitives serve desktop/web mailto fallbacks,
  mobile is a platform channel), `meta ^1.16.0` (annotations only, already
  transitive — needed for `@visibleForTesting` in the Flutter-free
  protocol layer). `sodium` widened to `SodiumSumoInit` (same package —
  intake §3): **spike confirmed** — sumo `pwhash` loads and passes the
  production-cost vectors under host `flutter test`.

### Tests (88 new)

- Vector-locked: §3.1.1 canonicalization (all 9 committed cases), §3.1.2
  salts + seed/topic/psk under BOTH cost sets — reduced is the fast
  default lane; the production set is tagged `production-cost`
  (dart_test.yaml; ~0.3 s/vector on this host, runs in the default suite
  AND is CI-selectable/excludable — the Go `-short` mirror), §5.4 all 11
  outer-frame cases + full-enum coverage assertion + strict rejects.
- Controller state machine over an in-memory fake relay: create/register/
  persist; offline edge (no phantom codes); foreign-topic frames dropped;
  bridged hold buffers PAIR_DATA opaquely and **never fabricates a
  reply**; drop → backoff re-register (spacing asserted — no storm);
  TTL expiry live + discovered-on-resume; resume re-registers the
  **original creation-date** topic; cancel = silence (no extra frames);
  bridged-drop → spent (fail-closed, record erased); background grace;
  diag events-only.
- Storage: meta-records round-trip/rewrite/delete, ciphertext-on-disk +
  restart, AD transplant rejection, sealed perimeter; pending-pairings
  round-trip incl. keypair, raw-disk absence of code/pub/sec bytes,
  remove-is-erase.
- QR: committed expected-matrix fixture
  (`test/fixtures/qr_nimna_kr7-fm2-xq4_ecM.txt`) — **verified with an
  independent decoder**: Apple Vision `VNDetectBarcodesRequest` decoded
  the rendered matrix back to `nimna:KR7-FM2-XQ4` byte-exact (intake §7
  condition met).
- Source pins: `startCreateLine` exactly one call site outside its file;
  share_plus fenced to `share.dart`; qr fenced to `qr_matrix.dart`; no
  inner-envelope identifiers in `protocol/` (S10 fence).
- Widget: F2.1/F2.2+F2.4/F2.8 canonical strings in all five locales; QR +
  code simultaneous; TTL sheet exactly three presets; offline edge; copy
  toast lifecycle; F2.3 caption; back-confirm vocabulary; 320 px
  narrow-frame survival (the test font renders every glyph 1 em wide — a
  built-in long-string stress; the share-screen title needed
  Expanded+ellipsis to pass).

### Pre-QA end-to-end evidence (scratch harness, deleted; relay + probe in `temp/`)

Local relay (`go run ./cmd/relay`) + the REAL protocol/transport stack
(scratch `dart run` harness): generated `X97-X85-E2Y`, derived the
production-cost topic, sent REGISTER_TOPIC; then
`go run ./cmd/testclient --role join --code X97-X85-E2Y --rounds 0`
derived the **identical topic** (cross-stack §3.1.2 live match), bridged,
exited 0; our side received TOPIC_BRIDGED and held. The app-on-simulator
done-check run is QA's.

### CODE decisions (for merge fold into DECISIONS.md)

1. **TTL presets 1 h · 8 h · 24 h, default 24 h** — already adjudicated in
   the intake (§5); implemented as stated.
2. **F2.4 lifetime caption is TTL-honest via l10n plural**: "Your code
   works for {hours} — come back anytime…" renders byte-identical to the
   wireframe at the 24 h default and stays claim-accurate for 1 h/8 h
   codes. String 13 ("…expires in 24h…") stays spec-canonical verbatim
   regardless of preset. PM may contest at review.
3. **F2.2 caption follows the hi-fi screen** (02-create-code.html:
   string 13 + "The words or the square — either one pairs you.") over the
   wireframe's older "Works for 24 hours, once…" — hi-fi is the later,
   styled artifact; flagged as designs-internal drift, not a copy
   invention.
4. **Back-confirm modal buttons** ("Stop waiting? The code stops
   working."): ghost "Not now" + confirming "Cancel this code" — both from
   the designed vocabulary; the wireframe named no buttons.
5. **Bridged-then-dropped → the F2.5 edge line** ("That didn't finish. The
   code is spent — make a new one.", wireframe verbatim) with the F2.8
   button pair — the §3.1.6 fail-closed case needed a surface and this is
   its designed copy; everything is discarded first.
6. **Meta record identity**: AD/record-key id for meta rows =
   `SHA-256(ascii(key))[0:16]` — deterministic per key, keeps rewrite
   identity and cross-key transplant rejection with zero schema change.
7. **Boot-time pending read** (not widget-time): bootstrap reads
   `pending_pairings` once, hands the newest entry to the flow
   synchronously; corrupt record ⇒ diag `storageError/recordCorrupt` +
   erase (fail-closed — those codes are unrecoverable by design).
8. **Argon2id runs on the main isolate** at create/resume (~0.2–0.8 s,
   once per pairing): a visible sub-second hold on the disabled Create
   button. Acceptable for S8; if QA finds device jank objectionable, the
   sodium package's isolate path is the follow-up (no new dependency).
9. **`production-cost` tag runs by default** and exists for CI lane
   control; reduced-cost remains the fast inner loop.
10. **Chevron/disclosure glyphs**: back arrow is an in-repo CustomPainter
    from the hi-fi svg geometry; the TTL row's disclosure uses a Material
    arrow icon pending the S-later icon-set port (flutter-notes names a
    CustomPainter icon set; only these two glyphs were needed).

### Route registrations (for the orchestrator's merge fold)

**None in `routes.dart`.** The F2 flow deliberately owns its own route:
`startCreateLine`/`resumeCreateLineIfPending` push a `NimnaPageRoute`
carrying `CreateLineFlow` directly (intake §4: nothing outside
`pairing/initiator/` constructs the flow; a named route would be a second
door). The named-route table is unchanged.

### Blocked / escalations

None. No new USER questions. Real-device evidence (app on simulator/
device vs testclient) is the senior-qa done-check run.

— mobile-developer-flutter, 2026-07-07 01:46 +0200
