# Relay architecture note — Sessions 3–6

**Author:** tech-architect · **Date:** 2026-07-04 (Session 3 intake;
§§9–13 added 2026-07-04 15:45 +0200 at Session 4 intake; §§14–23 added
2026-07-04 17:09 +0200 at Session 5 intake; §§24–31 added
2026-07-04 22:06 +0200 at Session 6 intake) ·
**Binding for:** `application/relay/` implementation, Sessions 3–6.
**Sources:** spec `docs/nimna-protocol-spec-v0.2.md` (§3.1.2, §3.1.6,
§3.2, §3.2.1, §3.3, §3.3.1, §3.4, §4, §5.4–§5.7),
`docs/crypto-evaluation.md` §10–§12, DECISIONS.md S2/S3/S4 entries, the
work-loop LOGGING & OBSERVABILITY DOCTRINE.
All decisions here are CODE decisions unless marked otherwise.

## 1. Dependencies (network-dep sign-off)

- **WebSocket: `github.com/coder/websocket` v1.8.15 — SIGN-OFF GIVEN.**
  Zero transitive dependencies (its go.mod requires nothing), actively
  maintained (v1.8.15 tagged 2026-06-15), context-first minimal API atop
  stdlib `net/http`, ISC-licensed, the widely-reviewed former
  `nhooyr.io/websocket`. Rejected: `gorilla/websocket` (fine but last tag
  2024-06, larger legacy API, no context plumbing) and
  `golang.org/x/net/websocket` (documented-stale, missing core features).
- **`golang.org/x/crypto` v0.53.0 enters the relay module now**, imported
  **only** by the CLI test client (`argon2`; HKDF/SHA-256 are stdlib).
  Same pin as the test-vector generator (`docs/test-vectors/generator/`);
  brings only `golang.org/x/sys` v0.46.0 indirect. **Invariant:** the
  `cmd/relay` binary's import graph stays x/crypto-free — the relay never
  derives topics (routing_ids are opaque 16-byte values). Reviewer-checked
  per session (`go list -deps ./cmd/relay`); becomes a CI assertion in S5
  alongside the log-scrub check.
- Nothing else. TLS (S6) is stdlib `crypto/tls`.

## 2. Package layout (Go dev implements to these names)

```
cmd/relay/            main: flags/config, HTTP server wiring, signals. No logic.
cmd/testclient/       CLI test client for S3–S4 done-checks (§6 below).
internal/wire/        18-byte outer header parse/build, FrameType enum
                      (ALL §5.4 types 0x01–0x05/0x10–0x12/0x20–0x21),
                      constants (HeaderLen=18, Ver=0x01, MaxFrame=128 KiB).
                      THE ONLY protocol-parsing surface in the module.
internal/ident/       Unloggable identifier wrapper types (§4 below).
internal/rendezvous/  Topic registry + bridging state machine (§5 below).
internal/server/      WebSocket accept loop, connection lifecycle,
                      frame router, single-writer discipline.
```

S4 creates `internal/channel` (CRID registry, knock/accept/bridge — §10)
and `internal/push` (stateless push forwarding — §11). Reserved seams
(do not create yet): `internal/metrics` and `internal/limits` (S5). The
S3 frame router and registry APIs let these plug in without touching
`internal/wire` or the connection lifecycle.

## 3. Concurrency model

- **Per connection:** one read-loop goroutine + one writer goroutine; a
  `context` cancelled once (sync.Once teardown). Read limit set to
  `wire.MaxFrame` (128 KiB) at accept — memory safety from day one; S5
  only makes it config.
- **Single-writer:** all outbound frames go through the connection's
  bounded channel (cap 32) drained by its writer goroutine; nothing else
  touches `ws.Write`. Delivery to a peer is a non-blocking send; **a full
  buffer closes that peer's connection** — the relay never queues (§4
  statelessness), and a slow consumer is indistinguishable from a dead one.
- **Registry locking:** one plain `sync.Mutex` per registry, whole-map.
  Scale is a single small VPS (hundreds–low-thousands of connections,
  tiny critical sections); sharded/RW locks are premature and less boring.
- **Unwind (§4 rule: registrations live only as long as their
  connection):** the teardown path — reached from read error, write error,
  or server shutdown, exactly once — deregisters every topic the
  connection holds (conn keeps its own registration set). A **bridged**
  topic loses its entire entry when either end dies; the survivor gets no
  topic-scoped signal because §5.4 defines none (TEARDOWN is CRID-scoped)
  — clients detect via their own handshake timeout, fail-closed per
  §3.1.6. **Relay-authored** close frames carry no reason text and no
  Nimna-state-dependent status code, ever (silence doctrine; transport
  boundary precisely scoped in §5.1); policy violations use `CloseNow()`.

## 4. Unloggable identifiers — `internal/ident`, shipped in S3

Types: `ident.Topic` (`[16]byte`; this IS the code-hash — doc-comment it),
`ident.CRID` (`[16]byte`), `ident.RemoteAddr`, `ident.DeviceToken`. Each
implements `String()`, `GoString()`, `Format()`, `MarshalText()`,
`MarshalJSON()`, and `slog.LogValuer` — **all** return a fixed tag like
`topic[redacted]` with zero identifier bytes (no truncated hex; partial
values still correlate). `Topic`/`CRID` are comparable, so registries key
maps on them directly without exposing bytes. The only raw accessor is the
deliberately greppable `WireBytes()`, used solely to build outbound frames
in `internal/wire`/`internal/server`; the reviewer audits every call site.
Unit tests assert redaction through `fmt.Sprintf("%v/%s/%+v/%#v")`,
`json.Marshal`, and an `slog` capture handler. The CI log-scrub assertion
itself lands in S5; the types and tests land now.

## 5. S3 scope fence & topic lifecycle

**S3 implements:** connection lifecycle; `REGISTER_TOPIC` (0x01);
`TOPIC_BRIDGED` (0x10) to both ends; `PAIR_DATA` (0x20) forwarded verbatim
between the two bridged ends. **Router default:** any *other* valid frame
type (0x02–0x05, 0x11, 0x12, 0x21 — all defined in `wire` now) is
**silently dropped**; structurally malformed traffic (<18 bytes, wrong
version byte, unknown frame_type, non-binary WebSocket message) **closes
the connection** — per §5.4, the relay never explains itself. S4 fills the
router with REGISTER_CRID/KNOCK/ACCEPT/TEARDOWN/SESSION_DATA + push; S5
adds limits/metrics/soak. No rework: S4 registers handlers on the same
router; TEARDOWN is CRID-plane and therefore wholly S4.

**Topic lifecycle (spec-verbatim, statelessness makes §3.1.6 structural):**

- Entry states: *absent* → `REGISTER_TOPIC` creates *waiting(conn A)* →
  second distinct connection bridges: *bridged(A,B)*, `TOPIC_BRIDGED` to
  both. Registration is silent — no ack frame exists, so "always succeeds
  silently" is structural.
- **First-come-wins / third registrant:** while *bridged*, further
  `REGISTER_TOPIC`s are silently ignored and **no state is kept** for
  them (indistinguishable from acceptance to the sender; keeps memory
  bounded and squatting-free). Re-registration by a connection already in
  the entry is an idempotent no-op; a connection never bridges to itself.
- **Death:** the entry is deleted when either member's connection ends or
  its 24 h cap fires — "completion" from the relay's seat is the bridge
  ending, since `PAIR_DATA` is opaque and the relay cannot see M4. The
  relay keeps **no tombstones**: a later `REGISTER_TOPIC` for the same 16
  bytes creates a fresh *waiting* entry, because a stateless relay cannot
  distinguish expired/used/never-existed — exactly the §3.1.6 doctrine;
  single-use is enforced by the creator client (never re-registers a dead
  code) and by the psk handshake.
- **24 h cap:** each registration records a deadline; a coarse in-memory
  janitor tick (~1 min, under the registry mutex) evicts overdue
  registrations. In-memory only; nothing at rest.
- `PAIR_DATA` on a topic that is not bridged, or from a connection that is
  not one of its two members: silent drop.

### 5.1 Silence doctrine at the transport boundary (S3 review finding B1)

The silence doctrine is scoped to the **Nimna layer**, where it is
absolute: no relay-authored close frame, on any path, ever carries reason
text or a status code that depends on Nimna protocol state — every
Nimna-level failure (malformed outer frame, unbridged `PAIR_DATA`,
expired/used/never-existed topics, third registrants, and from S5 every
rate-limit outcome) is byte-identical silence or a bare `CloseNow()`.

**Bounded carve-out (accepted residue):** `coder/websocket` v1.8.15 itself
emits RFC 6455 compliance closes (status 1002 + generic English text, e.g.
on RSV bits set or an unknown opcode) from internal paths that fire before
relay code runs, with no suppression hook. These are accepted **iff all
of** the following hold, and only then: (a) emitted by the pinned
transport library (or, at S6, stdlib TLS alerts — the same class of
protocol-mandated transport signaling), never by relay code; (b) triggered
strictly below the Nimna outer frame, by malformed WebSocket/TLS bytes
unreachable from any conforming client; (c) the close bytes are a pure
function of the sender's own offending transport bytes and the RFC —
**independent of all relay state**, containing no identifier bytes and
incapable of differentiating any Nimna protocol state. This carve-out can
never be read to excuse a Nimna-level response surface: anything relay
code decides (frame validity, registry state, limits) stays silent.
Suppressing the library closes was considered and rejected — hand-framing
WebSocket or filtering our own output stream trades an audited library's
RFC-mandated behavior for hand-rolled plumbing, a worse posture.

**Invariant sentence for code comments:** "Relay code never sends a close
frame carrying reason text or a Nimna-state-dependent status; the only
close frames with text are the WebSocket library's own RFC 6455
transport-compliance closes (1002), whose bytes are a fixed function of
the sender's malformed transport input and carry no Nimna identifier or
state."

**Covering test (raw TCP):** send RSV-set and unknown-opcode probes;
assert status 1002 with the known generic library text and no identifier
bytes; assert the close bytes are **byte-identical** against an empty
relay and against one holding registered and bridged topics
(state-independence — the property that makes this not a response
surface). Keep the existing assertions that well-formed WebSocket messages
carrying malformed Nimna frames produce a reasonless close.

## 6. CLI test client — `cmd/testclient`

One binary, run twice (`--role create|join`, code as argument) for the
done-check. It performs the **real §3.1.2 derivation**: canonicalize the
9-char Crockford code, `salt = SHA-256("nimna/topic/v1|"+date)[0:16]`,
Argon2id t=3 m=64 MiB p=1 (x/crypto), HKDF-SHA-256 (stdlib) → topic;
the joiner probes today then yesterday. It connects, registers, waits for
`TOPIC_BRIDGED`, and exchanges raw `PAIR_DATA` frames. Its derivation code
lives inside `cmd/testclient/` (client-side logic — it must never leak
into relay packages) and is **validated in its unit tests against
`docs/test-vectors/topic-derivation.json` production-parameter vectors**
(seconds-slow; skipped under `-short`). S4 extends this same binary for
knock/accept/chat.

## 7. Outer-frame invalid-case vectors (S2 deferral, resolved)

They live as **table-driven unit tests in `internal/wire`** (short header,
bad version, unknown type, oversize, empty routing_id semantics), not in
`framing.json` — the committed vectors stay byte-stable and the CI
regenerate-and-diff stays untouched. `internal/wire` tests additionally
load the existing `framing.json` `outer_frames` valid cases (read-only,
via repo-relative path) as conformance fixtures.

## 8. Standing invariants (restated, non-negotiable)

Stateless (at-rest inventory: memory tables, TLS certs, push-credential
config — nothing else, ever; more = USER decision). Wire behavior
byte-for-byte per §5.4. No telemetry. Silence doctrine on every
Nimna-level failure surface, absolute (transport-layer boundary scoped in
§5.1 only). Session-2-locked primitives only; the relay itself contains no
protocol crypto at all.

---

# Session 4 addendum — channel plane, knock, sessions, push forwarding

Added 2026-07-04 15:45 +0200 (Session 4 intake). §§1–8 stand unchanged
and govern everything below; §3's concurrency model and §5.1's transport
carve-out are settled and are not reopened here.

## 9. S4 scope fence & router discipline

**S4 implements** the channel plane on the existing S3 shapes — handlers
registered on the same router map, same conn lifecycle, no rework of
`internal/wire` or `internal/rendezvous`: `REGISTER_CRID` (0x02), `KNOCK`
(0x03), `ACCEPT` (0x04), `TEARDOWN` (0x05, both directions), verbatim
`SESSION_DATA` (0x21) bridging; relay-built `KNOCK_FWD` (0x11) and
`SESSION_BRIDGED` (0x12); pending-knock hold at exactly 60 s with silent
expiry; disconnect-as-implicit-TEARDOWN; stateless push forwarding per
§3.2.1. **Not S4 (S5 per plan):** rate limits (incl. the knock
1/10 s/CRID collapse and the push 1/60 s + 6/hr + 20/day counters),
metrics, per-IP caps, read/idle deadlines, soak. At S4, every valid knock
is processed independently — two knocks are two forwards (or two pushes);
S5 adds the collapse.

**Planes coexist on one connection.** A connection may hold topic and
CRID registrations simultaneously — an app pairing a new channel while
its existing channels stay knock-reachable is the normal case. The conn
carries both registration sets; teardown unwinds both.

**Router discipline additions (S3 §5 rules stand):**

- The relay routes on the 18-byte header alone (§5.4: "parses exactly 18
  bytes and routes"). For relay-plane types whose payload §5.4 defines
  as empty — `REGISTER_CRID`, `ACCEPT`, `TEARDOWN` — payload bytes are
  **ignored**, exactly as shipped for `REGISTER_TOPIC`.
- `KNOCK` is the one relay-plane frame whose payload the relay must
  parse (§5.4: empty, or `platform (1) ‖ token_len (2) ‖ token`). The
  parser lives in `internal/wire` (the module's only protocol-parsing
  surface); a payload that is neither form is **structurally malformed
  traffic and closes the connection** (bare `CloseNow`, S3 discipline).
  Well-formed means: empty; or `platform ∈ {0x01 APNs, 0x02 FCM}`,
  `token_len ≥ 1`, and `token_len` exactly equal to the remaining
  payload length. No token cap is invented beyond the structural bound
  (≤ `MaxFrame` − 21 bytes): a garbage token dies at the push platform,
  which is spec §3.2.1's stale-token semantics ("a push silently
  fails"). The server wraps the raw token bytes in `ident.DeviceToken`
  immediately at the parse boundary.
- **The silence rule that generates every row of §10's table: a
  state-dependent rejection is always a silent drop — a close that
  depended on registry state would itself leak that state through an
  observable close.** Only state-independent structural malformation
  (pure function of the received bytes) ever closes the connection.
- Client-sent relay-emitted types (0x10/0x11/0x12) remain unhandled →
  silently dropped (S3 router default, unchanged).

## 10. `internal/channel` — CRID registry, knock, bridge

Mirrors `internal/rendezvous` in construction: a pure in-memory state
machine, generic over a comparable endpoint `E`, one plain `sync.Mutex`,
operations return endpoints and the caller (`internal/server`) delivers
frames outside the lock. Registries key maps on `ident.CRID` directly;
**no `ident.DeviceToken` ever enters this package** — the registry is
token-free by construction (§11).

**Tables (spec §4 inventory, exactly):** `{CRID → entry}` where an entry
holds the registered-connection set (the `{CRID → registered
connections}` direction), the bridged pair, and at most one pending
knock; plus the conn-side `{connection → registered CRIDs}` set (beside
the S3 topic set), which IS §4's fourth table, kept where teardown can
sweep it. Rate/push counters are S5.

**Entry shape & invariants:** `regs` (set of connections, no cap at S4 —
see below), `bridged` + pair `(a, b)`, `pending` = `{from, deadline}` or
none. Invariants, held under the one mutex: an entry exists **iff**
`regs` is non-empty (an entry never outlives its last registered
connection); `pending.from ∈ regs`; `bridged ⇒ {a, b} ⊆ regs ∧ pending =
none` (a KNOCK on a bridged CRID is dropped, and ACCEPT consumes the
pending, so no pending can coexist with a bridge).

**Why `regs` has no membership cap:** the relay is role-blind and cannot
authenticate CRID membership — that is Noise KK's job (§3.3.1: a
squatter who ACCEPTs gets a bridge whose S1/S2 fails at the clients,
which destroy keys and tear down, fail-closed). Capping at two
first-come-wins — right for topics, where bridging IS the semantics —
would here let a squatter or a stale half-dead connection lock out the
legitimate peer. Memory stays bounded by connection count; S5's per-IP
and frame-rate caps bound that. A per-connection registration-count cap
is an S5 config candidate, not an S4 behavior.

**Operations (names for the implementation; all transitions atomic
under the registry mutex, all delivery outside it):**

- `Register(crid, ep)` — add `ep` to `regs` (create entry if absent).
  Idempotent: a duplicate registration is a silent no-op and does NOT
  re-trigger pending delivery. Returns whether an unexpired pending
  knock from a different connection exists (deliver-on-register, below).
  Registration alone never bridges and never signals anything else.
- `Knock(crid, ep, now)` — validate (`ep ∈ regs`, entry not bridged);
  overwrite `pending ← {ep, now + 60 s}`; return the forward set
  (`regs \ {ep}`). Empty forward set = the peer-offline outcome (the
  caller may dispatch ONE push iff the knock carried a token).
- `Accept(crid, ep, now)` — validate (`ep ∈ regs`, pending exists,
  `now ≤ deadline`, `pending.from ≠ ep`, not bridged); set
  `bridged ← (pending.from, ep)`, consume the pending; return the
  knocker so the caller sends `SESSION_BRIDGED` to both.
- `Forward(crid, ep)` — `SESSION_DATA` resolution, byte-identical
  semantics to the rendezvous `Forward`: the other member iff bridged
  and `ep` is a member; else drop.
- `Teardown(crid, ep)` — validate (bridged, `ep` a member); clear the
  bridge (registrations untouched); return the other member for the
  relay→client `TEARDOWN`.
- `DropConn(crid, ep)` — connection-death unwind for one CRID: remove
  `ep` from `regs`; delete the pending if `pending.from = ep`; if `ep`
  was a bridge member, clear the bridge and return the survivor for the
  implicit-TEARDOWN notify; delete the entry when `regs` empties.
- `Sweep(now)` / `RunJanitor` — hygiene only (below). `Len()`,
  `PendingCount()` — identifier-free counts (§13).

**Edge semantics (normative; the relay never explains itself):**

| # | Input · state | Behavior |
|---|---|---|
| 1 | `REGISTER_CRID`, duplicate from same conn | Silent idempotent no-op; no pending re-delivery |
| 2 | `REGISTER_CRID`, third+ connection | Added to `regs`; no signal (no cap at S4) |
| 3 | `REGISTER_CRID`, unexpired pending from another conn | `KNOCK_FWD` delivered to the registrant (deliver-on-register) |
| 4 | `REGISTER_CRID`/`ACCEPT`/`TEARDOWN` with non-empty payload | Payload ignored; frame processed on its header |
| 5 | `KNOCK` from a conn not registered on the CRID | Silent drop |
| 6 | `KNOCK` on a bridged CRID (member or not) | Silent drop |
| 7 | `KNOCK` with malformed payload (§9 rules) | Connection closed, bare `CloseNow` (structural, state-independent) |
| 8 | `KNOCK` valid, forward set non-empty | Relay-built `KNOCK_FWD` (empty payload) to every registered conn except the knocker; pending overwritten; any token discarded unused; **no push** |
| 9 | `KNOCK` valid, forward set empty, no token | Pending only; total silence |
| 10 | `KNOCK` valid, forward set empty, token present | ONE push dispatch (§11) + pending; total silence to the knocker |
| 11 | Second `KNOCK` while one pending | Pending overwritten (latest knocker, fresh 60 s deadline); forward/push evaluated independently per knock (S5 adds the 1/10 s collapse) |
| 12 | `ACCEPT`, no pending or pending expired | Silent drop |
| 13 | `ACCEPT` from the pending knocker's own connection | Silent drop (a connection never bridges to itself) |
| 14 | `ACCEPT` from a conn not registered on the CRID | Silent drop |
| 15 | `ACCEPT` on an already-bridged CRID | Silent drop (pending was consumed at bridge; guarded anyway) |
| 16 | `ACCEPT` valid | Bridge `(knocker, accepter)`; pending consumed; `SESSION_BRIDGED` (empty) to both members; **first ACCEPT wins**, later ones hit row 12 |
| 17 | `SESSION_DATA` unbridged, or from a non-member | Silent drop |
| 18 | `SESSION_DATA` from a bridge member | Exact received bytes forwarded to the other member (verbatim, payload never inspected) |
| 19 | `TEARDOWN` (c→r) unbridged, or from a non-member | Silent drop — including: a `TEARDOWN` never cancels a pending knock; §5.4 defines no knock-cancel, so none exists |
| 20 | `TEARDOWN` (c→r) from a bridge member | Bridge cleared; relay `TEARDOWN` to the **other member only** (§3.3 "notifies the peer"; the initiator already knows); registrations survive |
| 21 | Disconnect of a bridge member | Implicit TEARDOWN: bridge cleared; relay `TEARDOWN` to the survivor; survivor's registration survives |
| 22 | Disconnect of the pending knocker | Pending deleted silently; an already-delivered `KNOCK_FWD` is not retracted — a late `ACCEPT` hits row 12 and the answerer's client times out ("No answer.") |
| 23 | Simultaneous `TEARDOWN` from both members | First clears and notifies; second hits row 19. An end may thus receive a `TEARDOWN` after sending its own — tolerating that is client work |

Relay-emitted frames (`KNOCK_FWD`, `SESSION_BRIDGED`, r→c `TEARDOWN`)
are always **freshly built** (`wire.Encode`, empty payloads) — never a
forwarded client frame — so `KNOCK_FWD`'s token strip is structural
(DECISIONS S2), not a filtering step. Ordering: an answerer that waits
for `KNOCK_FWD` before `ACCEPT`ing sees `KNOCK_FWD` first (causality),
as does the deliver-on-register path (one producing goroutine); a blind
`ACCEPT` racing the knocker's post-lock send may observe
`SESSION_BRIDGED` first — the two frames come from different producing
goroutines, so per-conn FIFO cannot order them. Harmless (no invariant
breaks), but clients must not assume the strict order.

**Pending-knock delivery (deliver-on-register).** When a connection
registers a CRID holding an unexpired pending knock from a different
connection, the relay immediately delivers `KNOCK_FWD` to the
registrant; the deadline is not refreshed. Reading: §3.2 step 2 "the
relay forwards the knock" and step 3 lets B "connect, register its
CRIDs, and send ACCEPT" inside the 60 s window — but the push is
content-free (no CRID), so without deliver-on-register B's app cannot
know **which** CRID to accept, and step 3 is unsatisfiable on §3.3's
push → tap → reconnect path. The hold table exists to complete delivery,
not merely to validate a blind ACCEPT. No wire behavior is invented:
`KNOCK_FWD` is the §5.4-defined vehicle; only the delivery moment for a
held knock is being read out of step 3. (Flagged for a one-line
editorial clarification at the spec's next touch; no doctrine — silence,
content-free push, statelessness — is affected.)

**KNOCK → SESSION_BRIDGED walk (both-online):** A (registered) sends
`KNOCK` → validate → `pending ← {A, now+60 s}` → outside the lock,
`KNOCK_FWD` to `regs \ {A}`; token, if any, discarded unused; no push.
B sends `ACCEPT` → validate → `bridged ← (A, B)`, pending consumed →
outside the lock, `SESSION_BRIDGED` to both. The knocker then sends S1
as the first `SESSION_DATA` (§3.3.1: the knocker is the Noise
initiator; the relay doesn't care — it forwards verbatim).
**Offline + token:** same walk with an empty forward set → ONE push
dispatch; B connects inside the window, registers (deliver-on-register
fires), `ACCEPT`s identically. **Race discipline:** the conn-side CRID
set mirrors S3's `addTopic` exactly — add, then check ctx; a
teardown-lost race unwinds via `DropConn`.

**Bridge teardown does not consume registrations.** §3.3's "forgets the
CRID immediately" reads as the `{CRID → bridged pair}` entry — the
session state — not the registrations: §4 pins registrations to their
connection's lifetime; §3.2 step 1 registers per connection at connect;
and if teardown wiped registrations, a still-connected B would count as
offline for the next knock and draw a platform push while live on the
socket, contradicting §3.2 step 2's online check. After `TEARDOWN`
(explicit or implicit) surviving members remain registered; re-knock
without re-register is legal and expected.

**Expiry (exactly 60 s) & janitor:** correctness is enforced by deadline
comparison at every consumer — `Accept` and deliver-on-register treat
`now > deadline` as no-pending (and delete it). A **10 s sweep tick**
(finer than the topic janitor's 1 min because the TTL is 60 s) is memory
hygiene only: it clears lapsed pendings sitting inside live entries (the
entry itself lives with its registrations). Expiry is silent — there is
no lapse frame in §5.4, so nothing can be sent. Pending knocks are the
same dies-with-process, in-memory-only class as every other table.

## 11. `internal/push` — stateless push forwarding

**Interface:** `push.Sender` with a single method taking a context, a
platform (`0x01` APNs / `0x02` FCM, straight from the KNOCK payload
byte), and an `ident.DeviceToken` — **and no content parameter**. The
content-free payload is a compile-time constant inside each Sender;
content-freeness is structural: the call surface physically cannot carry
channel, sender, or message data. Spec §3.2.1's transient "wake
device-token Y" observation exists only as handler-local values on the
knock path.

**Dispatcher (bounding the router):** `push.Dispatcher` wraps a Sender
with a bounded queue (cap 32) drained by one worker goroutine with a
10 s per-attempt timeout. Enqueue from the read goroutine is
non-blocking; **a full queue drops the push silently** — push is
best-effort by spec (§3.2.1: a stale token "silently fails"; the
fallback is out-of-band coordination), and the relay never queues
unboundedly (§4 statelessness class). Send errors are discarded at S4;
S5's metrics count aggregate failures. Exactly ONE dispatch per eligible
knock — eligible = valid KNOCK ∧ token present ∧ empty forward set;
dedup/caps are S5.

**Token lifecycle — discarded, not zeroed:** the token's entire life is
KNOCK payload → `ident.DeviceToken` at the parse boundary → dispatch
queue entry → one `Send` call → garbage. It never enters
`internal/channel`, never lands in any map or struct field that outlives
the dispatch, and is unloggable by type. Explicit zeroing after `Send`
is NOT pinned: the bytes are already copied into transport buffers
(TLS/HTTP) beyond our reach, so zeroing would be unverifiable theater —
the guarantee that matters, **never stored**, is structural and
reviewer-audited via the `WireBytes()` call-site audit (§4).

**Content-free payload (relay-side constants, pinned):** a single
constant localization key and nothing else — no channel, sender, count,
or timestamp. The app bundle localizes the key client-side (S15's
problem; the relay never carries localized text). The platform request
bodies are byte-identical across all knocks except addressing — that
constancy IS the auditable content-freeness claim (§4 "auditors verify
push behavior in the open code").

- APNs: body `{"aps":{"alert":{"loc-key":"NEW_ACTIVITY"}}}`, headers
  `apns-push-type: alert`, `apns-priority: 10`,
  `apns-expiration: now + 60 s`.
- FCM v1: `message.android.notification.title_loc_key =
  "NEW_ACTIVITY"`, `message.android.priority = "high"`,
  `message.android.ttl = "60s"`.
- **Push validity = the knock window (60 s), deliberately:** a push
  delivered after the pending knock expired can no longer produce §3.2
  step 3's accept path — it would wake the app onto nothing. Lengthening
  this into a general "come online" nudge is a product-level knob
  (PM/USER), never a silent relay change.

**Mock sink (done-check + tests): a local HTTP sink, config-gated.**
`push.HTTPSink` POSTs to a configured URL with headers
`Nimna-Push-Platform: apns|fcm` and `Nimna-Push-Token: <hex>` (the sink
stands in for the platform, which legitimately receives the token) and
the constant platform body as the request body. Selected by
`-push-sink URL` / `NIMNA_RELAY_PUSH_SINK` (empty default). QA asserts:
exactly one POST per eligible knock, zero for online knocks, and
byte-identical bodies across knocks. In-process mock Senders serve unit
tests; the HTTP sink serves the CLI done-check and, at S6, ops smoke
tests. With no sink and no credentials configured, the Sender is a no-op
(silent drop) — the spec-sanctioned push-less mode.

**Real APNs/FCM transports: explicitly DEFERRED to S6** (deploy — the
first session where credentials exist as deployment config and behavior
is verifiable against real platforms; until then they would be dead
unexercisable code). §3.2.1's forwarding *behavior* — offline check, one
call, structural token discard — lands complete in S4 against the sink;
S6 adds only transport adapters behind the same Sender interface, no new
semantics. **Stdlib suffices — pinned now so S6 needs no dependency
conversation:** APNs = HTTP/2 POST (stdlib `net/http` negotiates h2 on
TLS) + ES256 JWT via `crypto/ecdsa` + `crypto/x509` p8 parsing; FCM v1 =
OAuth2 service-account JWT grant (RS256 via `crypto/rsa`/`crypto/x509`)
+ HTTP POST. JWT assembly is fixed encoding over stdlib signatures —
composition, not hand-rolled crypto — and unit-testable against the
public keys. Sign-off WITHHELD as unnecessary: `golang-jwt`,
`golang.org/x/oauth2`, `sideshow/apns2`, the Firebase admin SDK. None of
this touches x/crypto: **`cmd/relay`'s import graph stays x/crypto-free
even with real transports** (§1 invariant unchanged).

**Config slots (names pinned now; empty defaults = push-less):**
`NIMNA_RELAY_APNS_KEY_FILE` (p8 path), `NIMNA_RELAY_APNS_KEY_ID`,
`NIMNA_RELAY_APNS_TEAM_ID`, `NIMNA_RELAY_APNS_TOPIC` (bundle id),
`NIMNA_RELAY_FCM_SA_FILE` (service-account JSON path), plus the
test-only `NIMNA_RELAY_PUSH_SINK`. File paths and env only — credentials
are deployment configuration, never repository content (§4);
`config.example` with empty slots and the `.gitignore` guard land in S6
per plan.

## 12. Keepalive & liveness

- **S4 adds nothing relay-side for keepalive.** Clients ping ~30 s at
  the WebSocket layer (§3.3); `coder/websocket` v1.8.15 auto-responds to
  pings while a `Read` is in flight, and the relay's read loop is always
  in `Read` — so pongs are automatic, zero relay code. Covering check:
  the S4 testclient sends one WS ping post-bridge and requires the pong
  (the library's `Ping` blocks on it).
- **Read/idle-deadline enforcement (reaping silently-dead connections
  TCP hasn't noticed) is S5 hardening**, with one design constraint
  pinned now: it must count client WS pings as liveness (the library
  exposes no ping callback, so S5 will decide between TCP keepalive +
  write-path failure and a transport-level wrapper — decided then, not
  here). Until then, dead connections are detected via read/write errors
  and OS TCP behavior.
- **"Online" at the relay = a live connection registered on the CRID at
  the instant the knock is processed. Nothing else exists.** The ~30 s
  background grace (§3.3) is client-side semantics only — the client
  holds its socket open after backgrounding; the relay keeps no
  "backgrounded" state, no grace timers, no presence. The relay's
  offline check exists only to drive the push call and is never reported
  (§3.2).

## 13. S4 test client & done-check verification

**Same single binary**, two new roles beside `create`/`join`:

- `--role knock`: connect, `REGISTER_CRID`, send `KNOCK` (with
  `--token <hex> --platform apns|fcm`, both-or-neither), wait for
  `SESSION_BRIDGED` (up to `--wait`, default 75 s > the 60 s window),
  chat as initiator (speaks first, mirroring §3.3.1's S1), send one WS
  ping (§12 check), then `TEARDOWN` and exit 0. No `SESSION_BRIDGED` in
  time → exit non-zero ("no answer" — the knocker-visible surface is
  ACCEPT or silence, §3.2).
- `--role answer`: connect, `REGISTER_CRID`, wait for `KNOCK_FWD`
  (delivered live or via deliver-on-register), send `ACCEPT`, wait for
  `SESSION_BRIDGED`, chat as responder (replies), then wait for the
  relay `TEARDOWN` and exit 0.
- Chat = `--rounds N` raw `SESSION_DATA` ping-pong; payload bytes are
  arbitrary demo content (real Noise KK is app work, S10+; the relay
  forwards verbatim and never parses them).

**CRID source (no real handshake exists until S8/9):** deterministic
test derivation, in `cmd/testclient` only —
`SHA-256("nimna/testclient/crid/v1|" + canonical_code)[0:16]`, stdlib
`crypto/sha256` (no x/crypto growth), doc-commented as explicitly NOT
the §3.1.5 derivation (which needs pairing statics that don't exist
yet). Both ends of a pair derive the same CRID from the shared code;
`--crid <32 hex>` overrides so channel-plane tests can skip the slow
pairing derivation entirely. Client-side logic stays in
`cmd/testclient`; the relay treats CRIDs as opaque 16 bytes.

**Done-check script shape** ("CLI clients pair, disconnect, knock (with
and without token), accept, chat, hang up — relay memory empty after; a
mock push sink receives exactly one content-free call per eligible
knock"):

1. Pair: `create`/`join` with a code (S3 path); both exit 0 and
   disconnect (topics unwound).
2. Online knock, no token: start `answer`, then `knock`, same code →
   `KNOCK_FWD` → `ACCEPT` → `SESSION_BRIDGED` both → N rounds + ping →
   `TEARDOWN` → both exit 0. Sink: zero calls.
3. Offline knock, token: relay running with `-push-sink`; start `knock
   --token … --platform …` with no answerer connected → sink receives
   exactly ONE POST (constant body); within 60 s start `answer` →
   deliver-on-register fires → accept → chat → hang up.
4. Online knock WITH token: sink receives zero calls (forward and push
   are mutually exclusive; the token is discarded unused).

**"Relay memory empty after" (QA verification path):**
`channel.Registry` exposes `Len()` and `PendingCount()` — identifier-free
counts, the same class as `rendezvous.Len()`, doubling as the S5 metrics
feed. The memory assertion runs as an in-process integration test in
`internal/server`: it drives the full flows of steps 1–4 over real
WebSocket connections against an in-process Server + mock Sender, then
asserts topic count, CRID-entry count, and pending count are all zero
once every client connection closes, and that the mock saw exactly one
call per eligible knock. **No network introspection surface exists** —
nothing is added to the relay binary for this (S5's metrics endpoint
will expose the same counts as aggregate gauges; nothing lands early).

---

# Session 5 addendum — hardening, rate limits & observability

Added 2026-07-04 17:09 +0200 (Session 5 intake). §§1–13 stand unchanged
and govern everything below. §12's one deferred choice (read/idle
deadline mechanism) is resolved in §17; §1's deferred x/crypto CI
assertion and §4's deferred log-scrub assertion land in §20. Nothing
here touches the wire: **S5 adds no frame types and no response
surfaces** — the byte-level §5.4 surface is exactly what S3/S4 shipped.

## 14. S5 scope fence & config surface

**S5 implements:** `internal/limits` (every spec §4 limit class as
config with defaults), the liveness listener (§17), `internal/metrics`
+ the ops listener (§18), the operational-log/tracing/panic discipline
(§19), both CI assertions (§20), `cmd/soak` (§21), and the shutdown
delta (§22). **Not S5 (S6 per plan):** TLS, real APNs/FCM transports,
`/healthz`, deploy, `config.example`.

Config follows `cmd/relay`'s existing pattern exactly: a flag whose
default is seeded from a `NIMNA_RELAY_*` env var; flag wins. Every
value below is a CODE-pinned boring default; spec-named numbers are
spec-verbatim. Durations use Go duration syntax.

| Limit / knob | Flag · env (`NIMNA_RELAY_`) | Default | Rationale (one line) |
|---|---|---|---|
| Per-IP connection cap | `-max-conns-per-ip` · `MAX_CONNS_PER_IP` | 64 | Generous for CGNAT households sharing one v4 address; tiny against single-VPS capacity |
| Per-conn frame rate | `-frame-rate` · `FRAME_RATE` | 50 /s | Sustained 50 frames/s is far beyond any legitimate 1:1 session, small against the CPU budget |
| Per-conn frame burst | `-frame-burst` · `FRAME_BURST` | 100 | Burst covers a full 5 MB attachment (80 MEDIA_CHUNK frames) plus session chatter in one gulp |
| Max frame size | `-max-frame` · `MAX_FRAME` | 131072 | Spec §4 default 128 KiB: a MEDIA_CHUNK (64 KiB plaintext + envelope + AEAD tag + 18-byte header) fits with room, while attachment ambitions stay bounded |
| Rendezvous throttle (per IP) | `-rendezvous-per-min` · `RENDEZVOUS_PER_MIN` | 6 | Spec says "single-digit attempts per minute"; a joiner costs 2 registrations (today+yesterday probe), so 6 = three code entries a minute — typo-friendly, brute-force-hostile |
| Registrations per conn, per plane | `-max-regs-per-conn` · `MAX_REGS_PER_CONN` | 256 | The §10-flagged candidate, now decided: hundreds of held lines per device is beyond the product's design; 256 keeps worst-case per-conn registry cost trivial |
| Knock collapse window | `-knock-interval` · `KNOCK_INTERVAL` | 10s | Spec §4, verbatim |
| Push min interval (per CRID) | `-push-min-interval` · `PUSH_MIN_INTERVAL` | 60s | Spec §4, verbatim |
| Push per hour (per CRID) | `-push-per-hour` · `PUSH_PER_HOUR` | 6 | Spec §4, verbatim |
| Push per day (per CRID) | `-push-per-day` · `PUSH_PER_DAY` | 20 | Spec §4, verbatim |
| Push hour window | `-push-hour-window` · `PUSH_HOUR_WINDOW` | 1h | Acceleration knob for soak/CI runs (the closing sentence below, made concrete); production leaves the spec's hour |
| Push day window | `-push-day-window` · `PUSH_DAY_WINDOW` | 24h | Acceleration knob for soak/CI runs (the closing sentence below, made concrete); production leaves the spec's day |
| Idle deadline | `-idle-timeout` · `IDLE_TIMEOUT` | 90s | Three missed 30 s client ping intervals — §3.3's own missed-ping heuristic, relay-side |
| Metrics listener | `-metrics-listen` · `METRICS_LISTEN` | 127.0.0.1:9441 | §18; empty string disables |
| Debug tracing | `-debug-trace` · `DEBUG_TRACE` | off | §19; never in production |

The spec marks the knock/push numbers "relay defaults, tunable config"
— tests and the soak tool accelerate by shrinking the windows via
config; the defaults stay spec. The per-CRID rate-table hard cap
(65,536, §15) is a pinned constant, not a knob — the knob count stays
small and the cap is a memory guard, unreachable in legitimate use.

## 15. `internal/limits` — counters, windows, cardinality

**Mechanism choices (simplest thing that honors spec wording):**

- **Frame rate: hand-rolled token bucket** (~15 lines: `tokens =
  min(burst, tokens + elapsed·rate)`; wait if < 1; spend 1). This is
  rate arithmetic, not crypto — no `x/time/rate` dep for a fmt-sized
  loop. Charged **one token per WebSocket message read, before parse**
  — uniform and content-blind across both planes. Injectable clock,
  like the registries.
- **Rendezvous throttle: fixed 60 s window counter per IP**, counting
  `REGISTER_TOPIC` frames only — the throttle exists to impede code
  brute-forcing (spec §4); `REGISTER_CRID` is not a guessing surface
  (128-bit identifiers) and is bounded by the frame-rate and
  registration caps instead.
- **Knock collapse: last-accepted-knock timestamp per CRID.** A knock
  inside the window is dropped **before any state change** (§16);
  drops do not refresh the timestamp — the window anchors on accepted
  knocks, honoring "1 per 10 s".
- **Push caps: min-interval timestamp + fixed hour/day window
  counters per CRID.** Fixed windows over sliding: simplest reading of
  "per 60s / per hour / per day", and the 60 s floor already bounds
  any window-boundary burst.

**Tables (all in `internal/limits`, all in-memory, all reset on
restart):** `{ip-key → live-conn count}` (event-driven; entry deleted
at zero), `{ip-key → rendezvous window}` (lazy expiry + janitor
sweep), and **one** per-CRID rate table `{CRID → {lastKnock, lastPush,
hourWin/hourCount, dayWin/dayCount}}`.

**Per-IP key, canonicalized in `internal/ident`:** `RemoteAddrFrom`
now canonicalizes at the accept boundary — port stripped; **IPv4 = the
exact address; IPv6 = the /64 prefix** (stdlib `net/netip`) — because
a single v6 host owns a /64, and exact-address v6 keying would be a
free cap bypass. The doc-comment updates; the type keeps its redaction
surfaces and gains no raw accessor: the canonical key is the only
address form held anywhere, and it never round-trips to a dialable
address.

**Why the per-CRID rate state does NOT live on the channel entry:** a
§10 entry exists iff its registration set is non-empty and dies with
its last connection — a counter riding the entry resets on reconnect
churn and structurally cannot honor a 20/day cap. The rate table is
therefore its own map, keyed by `ident.CRID` (comparable, unloggable),
holding counters and timestamps only — no connection references, no
tokens, nothing about any user.

**Cardinality stays bounded and stateless:** entries are evicted when
idle longer than 24 h (the longest window), swept by a 60 s janitor
tick; a hard cap of 65,536 entries (~4 MB worst case) backstops
abuse. **At cap: fail-open on the forward, fail-closed on the push** —
an untracked knock still forwards (harmless; bounded by frame-rate and
per-IP caps) but a dispatch that cannot be counted is silently refused
(filling the table must never mint pushes at the platform, the scarce
external resource). Cap trips are metered (§18).

**§4 inventory reading, pinned:** spec §4's own table list names "the
rate/push counters below" as one of the in-memory tables. Every S5
table above IS that named class — in-memory, user-anonymous, reset on
restart, dies with the process. Nothing enters the at-rest inventory;
its three-item reading (memory tables, TLS certs, push-credential
config) is unchanged.

## 16. Enforcement semantics — the silence adjudication

The generating rule, extending §9's: **an S5 limit outcome may be
observable (a refused accept, a close) only when it is a pure function
of the offender's own transport behavior — its IP's live-connection
count, its own frames' sizes and timing. Any limit keyed on state
other principals can reach (the per-CRID knock/push windows, where
another connection's knock opens the window) MUST be
indistinguishable-silent**, because an observable outcome would let
one end probe the other's activity. §5.1's sentence — every rate-limit
outcome is byte-identical silence or bare `CloseNow` — is satisfied
throughout; two rows below produce zero outcome bytes at all, the
strongest form.

| Limit | Outcome | Admissibility |
|---|---|---|
| Per-IP conn cap | **Refused at accept: immediate TCP close from the limit listener, zero bytes written** | Pre-Nimna, pre-HTTP; function of the connecting IP's own live-conn count only; see adjudication below |
| Frame rate | **Backpressure**: the read loop waits for a token before reading the next message — no drop, no close, zero outcome bytes; the sender experiences throughput, never an error | Dropping data frames would break the per-message rekey chain invisibly for legitimate bursts; closing would kill a legitimate 5 MB media send; TCP backpressure shapes with zero state and zero surface |
| Max frame size | Bare `CloseNow` (S3's existing structural close, now reading the configured bound) | Pure function of the received bytes; state-independent |
| Rendezvous throttle | Silent drop of the registration | Registration has no ack (§3.1.6): a throttled `REGISTER_TOPIC` is byte-identical to an accepted one — the prober cannot even tell which probes counted |
| Registration cap | Silent drop of the registration | Same ack-less identity; deliver-on-register simply does not fire for a dropped `REGISTER_CRID` |
| Knock collapse | Silent drop **before any state change**: no forward, no push, no pending overwrite, no deadline refresh; any token discarded unused | Spec-verbatim "duplicates inside the window dropped silently — retries collapse, no error"; keyed on shared per-CRID state, so it must be silent |
| Push caps (60 s / hr / day) | The knock is processed normally — pending set, forward logic untouched; **only the dispatch is suppressed**, silently | Spec caps "platform-push forwarding", not knocks; keyed on shared per-CRID state, so it must be silent |
| Rate-table cap | Forward fail-open, push fail-closed (§15) | Both arms silent; the observable world is identical to the un-capped path minus the platform call |
| Idle deadline | Bare `CloseNow` from the liveness janitor (§17) | Pure function of the connection's own inbound-byte timing |

**Accept-time refusal, adjudicated:** it is **not** inside §5.1's
transport carve-out — that class is library/stdlib-emitted, and this
is relay code deciding. It is a separately-stated class with its own
test: the refusal happens at the TCP accept boundary, **before** the
WebSocket (and, at S6, TLS) layer exists, writes zero bytes, and
depends on nothing but the transport-layer count of live connections
from that IP key. An over-cap client experiences connection loss
indistinguishable from network failure. HTTP 429 was considered and
rejected: it spends HTTP parsing on exactly the traffic the cap exists
to shed, and it adds a fingerprintable response surface where zero
bytes is available. Residual observability accepted: a CGNAT neighbor
can infer its shared IP's aggregate connection count — transport-layer
information about its own address bucket, carrying zero Nimna-layer
content.

**Invariant sentence for code comments:** "An over-cap connect is
closed at the TCP accept boundary with zero bytes written; the refusal
is a pure function of the connecting IP key's own live-connection
count and of no Nimna registry state — an over-cap client experiences
only connection loss, byte-identical against an empty relay and a
loaded one."

**Covering test:** drive an IP to cap against an empty relay and
against one holding registered topics, bridged pairs, and pending
knocks; assert the over-cap connect sees a connection close with zero
bytes received in both worlds, and that under-cap connects are
unaffected.

## 17. Liveness — §12's deferred choice, resolved

**Decision: the transport-level wrapper.** `internal/limits` provides
a `net.Listener` wrapper (the **limit listener**) that wraps the raw
TCP listener and is the single home for all transport-boundary
enforcement:

- **Per-IP accounting:** increment on accept, decrement on close;
  at-cap connections are closed immediately in accept with zero bytes
  (§16).
- **Liveness clock:** each wrapped conn bumps an atomic
  last-inbound-byte timestamp in `Read`. **WS pings are inbound bytes,
  so pings count as liveness structurally** — the §12 constraint is
  satisfied without a ping callback the library doesn't offer.
- **Liveness janitor:** a 30 s tick closes conns whose last inbound
  activity is older than the idle deadline (default 90 s = three
  missed 30 s ping intervals, mirroring §3.3's client-side heuristic).
  The close surfaces as a read error in the WS loop → the normal
  `sync.Once` teardown unwinds both planes' registrations. Reap lands
  between 90 and 120 s.

**Rejected: TCP keepalive + write-path failure alone.** OS keepalive
only detects peers whose stack is dead or unreachable — a hung app on
a live OS ACKs probes forever and would hold registrations until some
write happens to fail; and keepalive timing is opaque and
platform-dependent, so the reap bound would be unauditable. Stdlib TCP
keepalive stays **enabled with Go defaults as an OS-level backstop**
for the write path; the wrapper deadline is the enforced bound.

**S6 ordering, pinned now:** raw TCP → limit listener → `tls.NewListener`
→ HTTP. Over-cap abusers cost zero TLS handshakes, and the liveness
clock counts ciphertext bytes — correct, since liveness is a
transport-level property.

**Accepted residue (slowloris):** a client trickling bytes forever
stays "live" by this metric. It holds one bounded read buffer and one
slot inside its IP's cap, with zero amplification; no per-frame read
deadline is invented for it.

## 18. `internal/metrics` — identifier-free aggregates

**Shape:** a `Metrics` struct of `sync/atomic` counters incremented at
event sites, plus a scrape-time collector that reads the registries'
identifier-free counts and `runtime` stats. No background aggregation
goroutine. The registries gain `BridgedCount()` (rendezvous and
channel) beside the existing `Len()`/`PendingCount()` — same
identifier-free class; the S4 integration test's counts and the
metrics gauges are the same numbers.

**Exposition: hand-rolled Prometheus text format** (version 0.0.4:
`# TYPE` lines, `_total` counter suffix, gauges plain) — chosen over
JSON because every ops agent scrapes it natively and it hand-writes as
a ~30-line `fmt.Fprintf` loop; `prometheus/client_golang` is a
dependency tree for that same loop and is not taken.

**Where it listens: a separate ops listener**, default
`127.0.0.1:9441` (`-metrics-listen`; empty disables), serving `GET
/metrics`; everything else 404s. Chosen over a path on the main mux so
the public port speaks exactly one thing — WebSocket upgrade or
upgrade failure — keeping the minimal-surface claim auditable by port,
and so metrics stay operator-eyes-only by default (aggregate counts
still carry timing information; the operator already owns process
memory, so localhost exposition adds nothing to the threat model).
Plain HTTP, `ReadHeaderTimeout` set, no TLS (localhost; remote access
is the operator's tunnel/firewall problem). **S6's `/healthz` lands on
this same listener** — seam noted, nothing built early.

**Inventory (pinned):** prefix `nimna_relay_`; label values are fixed
compile-time enumerations only (`plane`, `limit`, `class`, `outcome`,
`site`) — never free-form, so every series' cardinality is fixed at
build time and **no identifier can ever be a label by construction**.

- Gauges: `connections`, `topics`, `topic_bridges`, `crid_entries`,
  `pending_knocks`, `session_bridges`, `rate_entries` (per-CRID rate
  table size), `goroutines`, `heap_alloc_bytes`, `heap_sys_bytes`.
- Counters: `connections_total`,
  `frames_forwarded_total{plane="pair|session"}`,
  `knocks_forwarded_total`,
  `pushes_total{outcome="sent|failed|dropped|refused"}` (attempted =
  the sum across outcomes, not a separate series),
  `limit_trips_total{limit="conn_ip|frame_rate|frame_size|rendezvous|
  reg_cap|knock_collapse|push_min|push_hour|push_day|rate_table_cap|
  idle"}` (collapsed knocks are `knock_collapse` trips — no duplicate
  series),
  `closes_total{class="structural|oversize|idle|read_error|
  write_error|send_overflow|shutdown"}`,
  `teardowns_total{cause="explicit|implicit"}`,
  `panics_total{site="read|write|janitor|push|http"}`.

The developer may add series within these constraints (identifier-free,
fixed enumerations, `nimna_relay_` prefix); nothing may be removed.

## 19. Operational log, debug tracing, panic scrub

**"Structured errors", interpretation pinned:** the build-plan phrase
means **internal `slog` records with structured attrs — never a wire
surface**. The wire has no error surface at all (silence doctrine);
nothing in S5 changes that. The operational log's exhaustive scope:
process lifecycle (start/stop, listen addresses), config summary at
boot (limit values and listener addresses — never credentials, never
paths' contents), TLS events (S6), panic recoveries (below), and push
transport status — a fixed-field Warn line carrying **platform and
HTTP status code only** (no token, no CRID; the S4 "errors discarded"
note upgrades to: metrics always count, the log sees status codes
only). Default level Info, text handler, stderr — as shipped.

**Debug tracing:** `-debug-trace` raises the level to Debug and
enables per-connection event tracing — conn open/close keyed by an
opaque process-local sequence number, frame types routed, limit
decisions. Identifiers pass through `ident` types everywhere, so even
debug output is structurally identifier-free — but the flag is still
documented **never-in-production** (flag help text + relay README),
and both configs are visible in the open repo so the claim is
auditable. The CI scrub (§20) asserts against production config, per
the doctrine's letter.

**Panic recover-and-scrub — placement:** a recover wrapper at the top
of every long-lived goroutine the relay owns: per-conn read loop,
per-conn writer, both registry janitors, the liveness janitor, the
push worker, and the WS HTTP handler (net/http's own recovery prints
via an ErrorLog we already discard, and hijacked WS goroutines are
ours regardless). **"Scrub" means concretely:** the recovery logs a
fixed line — component site and the panic value's Go type (`%T`) only
— **never the value's rendering and never a stack trace at production
level**. The `ident` types redact themselves, but a panic value or Go
register-ABI stack arguments can carry raw bytes from *any* type; the
scrub rule assumes nothing about what panicked. It increments
`panics_total{site}`, then tears down the connection (conn-scoped
sites) or restarts the loop (janitors, push worker). Debug config may
additionally log the stack. `GOTRACEBACK` stays default: an escaped
runtime-level crash should dump for the operator — the recover net
exists precisely so identifier-bearing dumps never happen in steady
state, and muting real crashes would trade auditability for nothing.

## 20. CI assertions (relay workflow)

**(1) Log-scrub — a Go test, `cmd/relay/logscrub_test.go`.** Chosen
over a shell script: portable, race-managed process control, and it
runs under the exact `go test ./...` step CI already executes — no new
step to forget. Shape: build the real relay binary into `t.TempDir()`
(`go build -o`), start it in **production config** (no debug flag;
short limit windows via config to reach every limit path fast;
`-push-sink` at a local test server that returns one 500 so the
transport-status log line fires), capture **all** stdout+stderr; drive
identifier-bearing traffic over real WebSockets — known-byte topics
registered/bridged/`PAIR_DATA`'d, known-byte CRIDs
registered/knocked-with-known-token/accepted/`SESSION_DATA`'d/torn
down, malformed frames (close path), and every limit tripped (per-IP
cap, frame rate, oversize, rendezvous throttle, reg cap, collapse,
push caps, idle) — then SIGTERM for the shutdown lines. Assert over
the entire output: **zero occurrences of every known identifier** in
lower/upper hex, std/URL base64 (padded and raw), and raw-byte form;
zero occurrences of the client IP and port; plus coarse sweeps (any
≥ 32-char hex run; any dotted-quad other than the configured listen
addresses). Not skipped under `-short` (seconds-fast; no Argon2 —
the relay never derives).

**(2) x/crypto-free import graph — an explicit named step in
`.github/workflows/relay.yml`**, after build:
`test "$(go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto')" -eq 0`
— the ANCHORED form pinned in S3 PROGRESS (an unanchored grep
false-positives on Go's stdlib-vendored `vendor/golang.org/x/crypto`
TLS paths, present in any HTTP binary). A visible workflow step, not a
buried test, so the public repo shows the assertion on its face.

## 21. Soak & abuse driver — `cmd/soak`

**Location: a third main package, `cmd/soak`**, beside
`relay`/`testclient`. Chosen over a shell script (a Go tool holds
thousands of connections and controls churn deterministically) and
over anything inside the relay: a separate binary leaves `cmd/relay`'s
size and import graph untouched (`coder/websocket` + stdlib only — no
x/crypto growth, no new deps). As a committed session deliverable it
lives in the module under the same gofmt/vet/test CI, per repo
conventions (`temp/` is for throwaway scripts; this is not one).

**Drives:** connection churn (dial/register/drop cycles), full
rendezvous flows (register → bridge → `PAIR_DATA` → drop), full
channel flows (register → knock → accept → `SESSION_DATA` →
`TEARDOWN`), offline knocks with tokens against a sink, and an
`-abuse` mode that probes every limit: over-cap connects from
localhost (expect zero-byte close), frame flood (expect pacing, not
errors — measured throughput ceiling), oversize frame (expect close),
rendezvous over-throttle (verified behaviorally — a probe pair
registering past the window must NOT bridge — plus the
`limit_trips_total` delta), duplicate knocks (expect exactly one
`KNOCK_FWD`), push over-cap (expect the sink-count floor).

**Measures:** samples the metrics endpoint (default every 30 s) for
`heap_alloc_bytes`, `goroutines`, and all table gauges; prints the
time series and a verdict. Flags: `-relay`, `-metrics`, `-duration`
(default 30m), churn-rate knobs, `-abuse`, `-sample`.

**Pinned flat-memory verdict:** after load stops plus a 2×-janitor
drain interval, **all table gauges return to zero** (connections,
topics, bridges both planes, CRID entries, pendings, rate entries),
and heap shows no monotonic growth — median `heap_alloc_bytes` of the
final quarter ≤ median of the second quarter × 1.10.

**Honest evidence standard, pinned:** the S5 done-check runs an
**accelerated soak in-session** — high churn, tens of minutes — and
the tool takes arbitrary `-duration` for a true overnight run.
PROGRESS.md reports exactly which was run; the deviation from
"overnight" is reported, never hidden. QA's "abuse scripts bounce off
every limit" = `cmd/soak -abuse` plus targeted testclient probes, with
windows shortened via config (defaults stay spec).

## 22. Graceful shutdown — the S5 delta

S5 adds only: the ops listener shuts down alongside the main one; the
liveness janitor and limits sweeps stop via the same context; a final
lifecycle log line. **Explicitly NO drain semantics:** no waiting on
live sessions, no flushing pending knocks or queued pushes — they are
the dies-with-process class (§4), clients fail closed and re-knock,
and a drain would be a queue by another name. The existing bounded
shutdown (5 s) stands.

## 23. Restated for S5 (non-negotiable)

**Zero new dependencies:** limits, metrics, liveness, and soak are
stdlib plus the existing `coder/websocket` pin — no Prometheus client,
no `x/time/rate`, nothing. **Statelessness inventory unchanged:**
every S5 table is spec §4's own named "rate/push counters" transient
class — in-memory, user-anonymous, reset on restart. **Wire behavior
untouched:** no new frame types, no new response surfaces; the only
externally observable additions — zero-byte accept refusal, read
pacing, idle closes — are adjudicated in §§16–17 and carry no
Nimna-layer bytes. The metrics listener is operator-local and is not
part of the public wire surface.

---

# Session 6 addendum — TLS, real push transports, deploy kit, public-repo readiness

Added 2026-07-04 22:06 +0200 (Session 6 intake). §§1–23 stand unchanged
and govern everything below. Governing USER decisions (DECISIONS.md,
2026-07-04 21:59 +0200): repo **prepared now, published at S19**
(dry-run split verified in-session); **no VPS exists** — S6 delivers
the complete deploy kit and the done-check runs against a local
production-shaped deployment, with "relay live on relay.nimna.app"
a logged deferral; real APNs/FCM transports **land now**, live-platform
verification **deferred to S15** (S6 verifies against local mock
platform servers checking JWT signatures and exact request shapes);
AGPL-3.0 copyright holder is **"The Nimna Authors"**. Nothing here
touches the wire: S6 adds no frame types and no Nimna-level response
surfaces — the public port's behavior change is exactly "TLS first."

## 24. S6 scope fence & config surface

**S6 implements:** TLS on the public listener (§25), `/healthz` on the
ops listener (§26), real APNs/FCM Senders behind the S4 `push.Sender`
interface (§27), the deploy kit under `application/relay/deploy/`
(§28), and public-repo readiness of the relay tree incl. the dry-run
split (§29). **Not S6:** the actual VPS deployment and DNS (deferred
with the VPS), live-platform push verification (S15), the publish
click (S19), go-import meta tags on nimna.app (S19 website work).

New config, following `cmd/relay`'s existing flag-seeded-from-env
pattern (§14). The push credential slots keep the §11-pinned env names
and gain matching flags (uniform surface; env is the deployment path
via `EnvironmentFile`, flags exist for parity and local runs):

| Knob | Flag · env (`NIMNA_RELAY_`) | Default | Notes |
|---|---|---|---|
| TLS certificate | `-tls-cert` · `TLS_CERT` | empty | PEM chain path (certbot `fullchain.pem`) |
| TLS key | `-tls-key` · `TLS_KEY` | empty | PEM key path (certbot `privkey.pem`) |
| APNs key file | `-apns-key-file` · `APNS_KEY_FILE` | empty | .p8 path (§11 slot) |
| APNs key id | `-apns-key-id` · `APNS_KEY_ID` | empty | §11 slot |
| APNs team id | `-apns-team-id` · `APNS_TEAM_ID` | empty | §11 slot |
| APNs topic | `-apns-topic` · `APNS_TOPIC` | empty | bundle id (§11 slot) |
| FCM service account | `-fcm-sa-file` · `FCM_SA_FILE` | empty | JSON path (§11 slot) |

**Config validity rules (all violations boot-fatal, loud):** TLS
cert/key are both-or-neither — one without the other is a config error,
not a mode; both empty = plain listener (dev, tunnel/LB-terminated
deployments — the local done-check and CI run this daily, so plaintext
mode stays first-class, not a rot path). The four APNs slots are
all-or-nothing; a partial set is boot-fatal (the error names the
missing *slot names* only — never values). The FCM file must parse at
boot (§27). `-push-sink` set together with **any** real credential
slot is **boot-fatal** (§27). Rationale for loud-vs-fallback: §14's
malformed-env fallback covers *values* of a limit that has a safe
default; a contradictory or half-configured *transport* has no safe
default — silently running push-less against operator intent, or
silently swallowing production pushes into a test sink, are exactly
the classes of quiet misbehavior the boot log exists to prevent.

The boot config summary gains: `tls` = `on|off`, the cert/key *paths*
(config values, never contents), and `push_mode` widened to the fixed
enumeration `push-less|sink|apns|fcm|apns+fcm`.

## 25. TLS on the public listener

**Stdlib `crypto/tls` only.** `golang.org/x/crypto/acme/autocert` is
structurally forbidden: it lives under `golang.org/x/crypto`, and §20's
anchored CI step asserts `cmd/relay`'s import graph is x/crypto-free —
the invariant that keeps "no protocol crypto in the relay" auditable at
a glance would be dead the day an ACME client imports the same module
path. Issuance and renewal belong to certbot (§28); the relay only
*serves* what the deployment provides. Listener ordering is §17's pin,
restated: **raw TCP → limit listener → `tls.NewListener` → HTTP** —
over-cap abusers cost zero handshakes, and the liveness clock counts
ciphertext bytes.

**Certificate reload: in-process, mtime-checked, via
`tls.Config.GetCertificate` — not restart-on-renew.** A ~30-line
reloader holds an `atomic.Pointer[tls.Certificate]`; `GetCertificate`
returns the current pointer, and at most once per 60 s (stat throttle,
handshake-driven, no goroutine) it stats the cert file and reloads the
pair via `tls.LoadX509KeyPair` when mtime moves. Boot-fatal if the
initial load fails; on a later reload failure it **keeps serving the
old cert** and logs a fixed Warn. Restart-on-renew was weighed and
rejected: dies-with-process is doctrine-compatible, but a scheduled
cert renewal killing every live session (bridged pairs torn down,
pending knocks lost) is a needless product cost when the stdlib
alternative is this small; the deploy hook (§28) becomes a pure file
copy with no service coupling. External SIGHUP protocols were also
rejected — mtime is the certbot-native signal and needs no operator
verb.

**Posture, pinned:** `MinVersion: tls.VersionTLS13`. Both clients are
ours (Flutter app, testclient) and speak 1.3; 1.3 removes the entire
cipher-suite configuration surface (Go exposes no 1.3 suite knobs),
is all-AEAD, and gives forward secrecy unconditionally. A 1.2 floor
serves no client we ship and was rejected. `NextProtos:
["http/1.1"]` — **h2 is disabled on the public listener**: the port
speaks WebSocket-upgrade-or-nothing (§18's by-port auditability), the
upgrade requires HTTP/1.1 hijack, and an h2 negotiation surface would
only add a protocol whose sole possible outcome here is a failed
upgrade. (The *outbound* APNs client negotiates h2 for itself — §27 —
unaffected.) No client certificates, no session-ticket configuration
beyond stdlib defaults, no curve/suite tuning: every knob not taken is
surface that cannot be misconfigured.

**Silence doctrine at the TLS layer:** handshake alerts are
stdlib-emitted, live strictly below the Nimna outer frame, and are a
pure function of the offending transport bytes and the RFC plus the
*deployment-configured* certificate — no Nimna protocol state can
reach them. This is precisely the §5.1 carve-out class, already
adjudicated there ("or, at S6, stdlib TLS alerts"). Covering test
extension: TLS-layer probes (plain HTTP to the TLS port, bad ALPN,
1.2-only ClientHello) produce byte-identical behavior against an empty
relay and a loaded one.

**TLS events in the log (§19's reserved slot, now defined
exhaustively):** (a) boot summary — `tls=on|off` + configured paths;
(b) reload success — one Info line whose only variable is the new
leaf's `notAfter` (cert metadata, operator-relevant,
identifier-free); (c) reload failure — one Warn line; inputs are
operator-owned files, so the error rendering may appear (it can carry
paths — config — but never user data). **Per-handshake errors are
never logged:** `net/http`/`tls` handshake failures embed remote
addresses; they go to the `http.Server.ErrorLog` we already discard
(§19) and stay discarded. The §20 logscrub test extends to: relay
booted with TLS, a client that fails its handshake on purpose, real
flows over `wss://` — asserting the client IP and all known
identifiers still never appear.

## 26. `/healthz` — ops listener

Lands on the S5 ops listener exactly as §18 reserved: the ops mux now
serves `GET /metrics` and `GET /healthz`; everything else still 404s.
**Semantics:** 200 means "the process is alive and serving." A
stateless relay has no deeper health — no database, no disk, no
downstream dependency whose degradation a handler could report; the
handler is static and cannot return non-200, so absence-of-answer is
the failure signal, by design. **Body, pinned:**
`ok nimna-relay <version>\n`, `text/plain` — fixed shape,
identifier-free by construction; this plus the boot log line are where
the §28 version stamp surfaces. **External liveness is explicitly not
this endpoint's job:** the ops listener is 127.0.0.1 (§18) and stays
so; "is it up from the internet" is a TLS/WSS probe of the public
port — the runbook's problem (§28), never a new public surface.

## 27. Real push transports — `internal/push` grows `apns.go`, `fcm.go`

§11's stdlib-only pin executes unchanged: no `golang-jwt`, no
`x/oauth2`, no `sideshow/apns2`, no Firebase SDK — sign-off remains
withheld as unnecessary. JWT assembly is fixed base64url/JSON encoding
over stdlib `crypto/ecdsa` / `crypto/rsa` signatures — composition,
not hand-rolled crypto — verified in tests against the public keys.
`cmd/relay`'s import graph stays x/crypto-free (§1, CI-asserted).

**Wiring shape:** a `push.Router` (implements `Sender`) holds an
optional APNs sender and an optional FCM sender and routes on the
platform byte. **Per-platform missing credentials, pinned:** a
dispatch for an unconfigured platform is a **silent drop counted as
`outcome="dropped"`** — the same best-effort class as queue overflow;
the label enumeration does not grow. A one-platform deployment is
legal and spec-sanctioned (§3.2.1: self-hosters "run push-less" — or
half-push-less). Mode precedence: `-push-sink` + any credential =
boot-fatal (§24). Goroutine placement unchanged: the single §11
dispatcher worker calls `Send` inline; token/JWT refresh happens
lazily inline on that worker — **zero new goroutines**.

**APNs (`apns.go`):** production endpoint `https://api.push.apple.com`
(the 2197 alternative not used; a sandbox-endpoint switch is *not*
added — S15 adds one flag if dev-build tokens require it, YAGNI now).
Request: `POST {base}/3/device/<hex(token)>` with headers
`authorization: bearer <jwt>`, `apns-topic: <config>`,
`apns-push-type: alert`, `apns-priority: 10`, `apns-expiration:
now+60s` (the §11 knock-window pin), body = the `apnsBody` constant,
byte-identical across all pushes. APNs requires HTTP/2; stdlib
`net/http` negotiates it transparently over TLS (mock tests assert
`ProtoMajor == 2`). **JWT:** ES256; header `{alg, kid}`, claims
`{iss: team-id, iat}`; cached in memory and reused until **40 min
old**, then re-signed lazily — inside Apple's window (≥ 20 min between
refreshes, ≤ 60 min validity) with margin on both sides for clock
skew. The .p8 must parse at boot as a PKCS#8 ECDSA P-256 key
(boot-fatal otherwise — a relay that discovers its key is garbage at
first dispatch has been silently push-less all along).

**FCM (`fcm.go`):** the service-account JSON supplies `client_email`,
`private_key` (RSA, must parse at boot), `token_uri`, and
`project_id` — no extra env slots. OAuth2 JWT-bearer grant: RS256 JWT
`{iss: client_email, scope:
https://www.googleapis.com/auth/firebase.messaging, aud: token_uri,
iat, exp: iat+1h}` posted to `token_uri`
(`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`) →
`access_token`/`expires_in`, **cached until expiry − 5 min**,
refreshed lazily. Message: `POST
https://fcm.googleapis.com/v1/projects/<project_id>/messages:send`,
`Authorization: Bearer <access_token>`, body = the §11 constant
message (`title_loc_key: NEW_ACTIVITY`, `priority: high`, `ttl: 60s`)
plus **exactly one per-dispatch field: `message.token`**, built by
`json.Marshal` of a fixed struct (correct escaping, fixed shape). §11
already states the constancy claim as "byte-identical except
addressing"; for APNs addressing is the URL path, for FCM it is this
one field — restated so the audit claim reads precisely.

**Token bytes contract (client-facing, documented here and in the
relay README):** the KNOCK token field carries the **platform-native
token verbatim** — APNs: the raw 32-byte binary device token (the
relay hex-encodes it into the URL path); FCM: the registration
token's ASCII bytes (inserted as the JSON string value). Consistent
with §5.4's opaque-bytes definition; flagged for a one-line editorial
note at the spec's next touch, like §10's deliver-on-register flag.
The app implements this at S15; testclient's `--token <hex>` already
models the APNs form.

**Why the JWT/access-token caches don't touch the statelessness
claim:** both are in-memory *derivatives of the credential config* —
recomputable from the .p8/SA-file at any instant, containing zero
user, channel, or token data — i.e. the push-credential item of §4's
at-rest inventory, held in its working form. They die with the
process; nothing new is at rest.

**Errors → log/metrics:** platform responses are drained (bounded)
and **discarded — never parsed, never logged**; non-2xx returns the
existing `StatusError{code}`, so the §19 fixed-field Warn (platform +
HTTP status only) and `pushes_total{outcome}` cover the real
transports with no new code paths. APNs 410/FCM 404 on a stale token
IS spec §3.2.1's "a push silently fails" — and since no token registry
exists, there is deliberately no feedback loop to act on it.

**HTTP clients:** one `http.Client` per sender, default-Transport
based, keep-alives on (APNs explicitly favors long-lived
connections); the per-attempt bound stays the dispatcher's 10 s
context — one timeout, not two competing ones (the `HTTPSink` pattern,
kept).

**Test injection (USER decision 3 executed):** base URLs are
**constructor parameters** — APNs endpoint, FCM `messages:send` base;
the FCM `token_uri` already comes from the SA file, so a test SA file
points it at the mock. **No new flags:** the public flag surface
carries no test knobs; `-push-sink` remains the only test-mode flag.
Mock platform servers are in-package `httptest` TLS servers (h2 for
APNs) that verify the ES256/RS256 signatures against the public keys
and assert the exact request shape (path, headers, body bytes). Test
keys are **generated at test runtime** (`ecdsa.GenerateKey`,
`rsa.GenerateKey`) and serialized into .p8/SA-JSON shapes in
`t.TempDir()` — no key-shaped file is ever committed, so the §29
secret scan stays trivially and unambiguously clean.

## 28. Deploy kit — `application/relay/deploy/`

**Location pinned: inside the relay tree**, so the public repo ships
its own deployment story (spec §4's reproducible-deployment claim is
only auditable if the unit file and build script are in the audited
repo). Contents: `nimna-relay.service`, `relay.env.example`,
`build.sh`, `certbot-deploy-hook.sh`, `RUNBOOK.md`, `README.md`
(folder convention). `relay.env.example` — in systemd
`EnvironmentFile` syntax, all `NIMNA_RELAY_*` slots present, **push
and TLS slots empty** — IS the build plan's "config.example"
deliverable, realized in the form the unit actually consumes.

**systemd unit (hardening set pinned):**

- **Dedicated system user `nimna-relay`** — not `DynamicUser`:
  certbot-renewed certs and credential files need stable ownership
  that a deploy hook can `chown` to; ephemeral UIDs can't own files
  across restarts. `User=nimna-relay`, `Group=nimna-relay`.
- **Port 443 via `AmbientCapabilities=CAP_NET_BIND_SERVICE`** (+
  `CapabilityBoundingSet=CAP_NET_BIND_SERVICE`). Listening high behind
  an nftables redirect was rejected: it adds a second moving part that
  can silently diverge from the unit.
- **The statelessness claim as a unit property:** `ProtectSystem=strict`
  with **no `StateDirectory`, no `CacheDirectory`, no `LogsDirectory`,
  no `ReadWritePaths`** — the service structurally cannot write to the
  filesystem at all. The sandbox enforces zero-at-rest; an auditor
  reads it off the unit file in one line.
- Rest of the set: `NoNewPrivileges=yes`, `ProtectHome=yes`,
  `PrivateTmp=yes`, `PrivateDevices=yes`, `ProtectKernelTunables=yes`,
  `ProtectKernelModules=yes`, `ProtectKernelLogs=yes`,
  `ProtectControlGroups=yes`, `RestrictNamespaces=yes`,
  `RestrictRealtime=yes`, `RestrictSUIDSGID=yes`,
  `LockPersonality=yes`, `MemoryDenyWriteExecute=yes` (Go doesn't
  JIT), `SystemCallFilter=@system-service`,
  `SystemCallArchitectures=native`,
  `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`, `UMask=0077`,
  `LimitNOFILE=65536`, `Restart=always`,
  `EnvironmentFile=/etc/nimna-relay/relay.env`.
- File layout: `/etc/nimna-relay/relay.env` (root:nimna-relay 0640),
  `/etc/nimna-relay/tls/{fullchain,privkey}.pem` and
  `/etc/nimna-relay/credentials/` (same ownership; dirs 0750),
  binary at `/usr/local/bin/nimna-relay`.

**Certbot, pinned: `certonly --standalone` (http-01 on :80) + deploy
hook.** The relay owns 443 and serves no files, so webroot has no
web server to lean on; standalone binds :80 only during renewal, and
:80 stays otherwise unbound — no HTTP redirect service exists because
the relay is not a website and nothing legitimate speaks plain HTTP to
it. `certbot-deploy-hook.sh` copies fullchain/privkey into
`/etc/nimna-relay/tls/` with nimna-relay group-read — **a pure file
copy, no restart**: §25's mtime reloader picks it up within ~60 s and
live sessions survive renewal.

**`build.sh`:** `CGO_ENABLED=0 GOOS=linux GOARCH={amd64,arm64} go
build -trimpath -ldflags "-s -w -X main.version=<git describe
--tags --always>" ./cmd/relay` → `dist/nimna-relay-linux-<arch>`
(`dist/` git-ignored). Best-effort reproducibility per spec §4: pinned
toolchain (go.mod), `-trimpath`, CGO off — same toolchain, same
commit, byte-identical binary; stated in the RUNBOOK so third parties
can verify the deployed binary against the repo. The version stamp
surfaces in the boot log line (exists), `-version` (exists), and the
`/healthz` body (§26).

**`RUNBOOK.md` contents list (pinned):** 1 provision — Debian stable
minimal, `systemd-timesyncd` on (JWT `iat`/`exp` and cert validation
need a sane clock — a skewed clock is a push outage), firewall
22/80/443 only; 2 DNS — A/AAAA `relay.nimna.app`; 3 user + dirs +
permissions; 4 binary install; 5 certs — certbot standalone + hook;
6 `relay.env` from the example; 7 `systemctl enable --now`; 8 verify —
journalctl boot lines, `curl 127.0.0.1:9441/healthz` on-host, external
`wss://` probe via testclient from a second machine, metrics scrape;
9 operate — metrics via SSH tunnel only (never exposed), renewal
dry-run, upgrade = replace binary + restart, and the incident
doctrine verbatim: **"restart is always safe — the relay is
stateless; the entire recovery procedure is `systemctl restart
nimna-relay`; live pairs re-knock."** Logs are identifier-free by
construction, so journalctl output is shareable in incident notes.

## 29. Public-repo readiness & publish mechanics

**The published artifact is the `application/relay` subtree**, split
with history (`git subtree split --prefix=application/relay`).
History-preserved is the CODE default — the commit trail *is*
auditability evidence (the invariants visibly held over time) — with
squash-to-single-commit documented in the publish runbook as the S19
alternative; the choice is revisitable at the publish click with zero
rework. Everything the public repo needs must therefore live **inside**
`application/relay/`:

- **LICENSE** — full AGPL-3.0 text, copyright line "The Nimna Authors"
  (USER, 2026-07-04). The README states the AGPL rationale in spec §4's
  own terms (Signal-server/SimpleX precedent).
- **README rework** (developer implements; content list pinned): leads
  with the zero-storage claim and **how to audit it** — spec §4's
  at-rest inventory, `internal/ident` unloggable types, the
  real-binary logscrub test, the anchored x/crypto CI step, the
  silence-doctrine tests, `deploy/` reproducible build; then build/run,
  config table, demos (all existing material survives below the fold).
  Plus the §27 token-bytes contract and the vanity-path build note
  below.
- **CONTRIBUTING.md** — small fixes welcome; DCO `Signed-off-by`
  required, no CLA; **protocol behavior is spec-governed and not
  changeable by PR** — wire formats, limits, TTLs, silence semantics
  change only via the spec; security contact lands at S19 (needs the
  domain mailbox).
- **Spec copy, pinned:** byte-identical at
  `application/relay/docs/nimna-protocol-spec-v0.2.md`. Spec §4 says
  "published openly alongside"; a README link to a website that does
  not exist until S19 would leave the split repo unauditable
  offline — self-containment wins. Provenance lives in the relay tree's
  `docs/README.md` (keeping the spec copy itself byte-identical);
  drift is prevented by a monorepo CI `cmp` step (below).
- **Test vectors vendored:** `docs/test-vectors/framing.json` →
  `internal/wire/testdata/framing.json`;
  `docs/test-vectors/topic-derivation.json` →
  `cmd/testclient/testdata/topic-derivation.json`. The three test
  files currently reach `../../../../docs/test-vectors/` — paths that
  **escape the subtree and break `go test ./...` in the split repo**;
  they switch to testdata-relative paths (idiomatic Go). The 681 KB
  duplication is accepted: self-containment outranks bytes. Symlinks
  rejected (dangle on split); runtime fallback-and-skip rejected
  (conformance tests that silently skip in the public tree would
  hollow the audit claim). Byte-equality with the monorepo sources is
  a CI `cmp` step; provenance noted in each `testdata/README.md`.
- **CI the split can carry, pinned mechanism:**
  `application/relay/.github/workflows/ci.yml` — committed **inside
  the relay tree**, inert in the monorepo (GitHub reads only the root
  `.github/`), active verbatim in the public repo. Same steps as
  relay.yml minus `working-directory`: gofmt, vet, build, the anchored
  x/crypto step, `go test ./...`. The monorepo `relay.yml` stays, and
  gains the byte-sync `cmp` steps (spec copy, both vendored vectors,
  and ci.yml-vs-relay.yml step parity is reviewer-checked, not
  CI-diffed) with its trigger paths extended to `docs/test-vectors/**`
  and the spec file.
- **go.mod module path: keep `nimna.app/relay`.** The relay is a
  binary — nothing imports it; the vanity path is a
  hosting-independent identity. `go install
  nimna.app/relay/cmd/relay@latest` requires go-import meta tags on
  nimna.app — **an S19 website work item**, logged; until then the
  README documents clone + `go build` (which needs no meta tags).
  Renaming to a github path was rejected: it couples module identity
  to a hosting choice and a repo name that isn't final.
- **`cmd/testclient` and `cmd/soak` SHIP in the public repo.** They
  are the hands-on audit tools — anyone can drive a relay and watch
  the silence and the limits. Consequence, stated explicitly: the
  split tree's go.mod/go.sum carry `golang.org/x/crypto` (testclient's
  argon2). Acceptable because the invariant was never module-scoped:
  it is "**`cmd/relay`'s import graph** is x/crypto-free," asserted by
  the anchored CI step that ships in the public workflow, visible on
  the repo's face (§20's exact intent).
- **`.gitignore` guard extended** (relay tree): existing `*.pem`,
  `*.p8`, `*.json.key`, `config.local.*` plus `/soak`, `/dist/`,
  `*.key`, `*.crt`, `.env`, `*.env`, `service-account*.json`.
  (`relay.env.example` is not matched — correct.)
- **READMEs per repo convention:** `deploy/`, relay-tree `docs/`, and
  both `testdata/` folders carry READMEs.

**Publish runbook (private side):**
`docs/release/relay-publish-runbook.md` — monorepo-only, not part of
the split.
Contents pinned: the split procedure (`git subtree split
--prefix=application/relay HEAD -b relay-public`; squash alternative
noted for S19); fresh-clone verification of the split tree — `go
build/test/vet ./...`, `gofmt -l .`, the anchored x/crypto check,
presence checks (LICENSE, README, CONTRIBUTING, docs/spec copy,
deploy/, ci.yml, testdata vectors), and a **history-wide secret
scan** (`git log -p` grepped for `BEGIN.*PRIVATE KEY`,
`private_key_id`, key-file magic, credential-shaped filenames via
`git log --diff-filter=A --name-only`) — history ships, so history is
scanned; the S19 trigger sequence (push split branch to the public
remote, branch protection, publish click = launch step 1, then S19
website items: go-import meta tags, README links).

## 30. Done-check adaptation — local production-shaped deployment

USER decision 2 executed. "Production-shaped" means the real binary
under production config with real TLS — **not** macOS service
management (launchd is NOT required; the systemd unit is verified as a
deliverable by review, its live verification is part of the deferred
VPS clause). QA runs, minimum:

1. **Build:** `deploy/build.sh` produces both linux binaries
   (cross-compile must succeed); a host-native build runs locally.
2. **TLS smoke:** a throwaway local CA + leaf for `localhost`
   generated at check time (script writes under git-ignored `temp/`,
   per repo convention); relay booted with `-tls-cert/-tls-key` and an
   env file shaped like `relay.env.example`; **testclient gains
   `wss://` URL support and a `-tls-ca <file>` flag** (loads a PEM
   pool into `tls.Config.RootCAs` for the dial). Pinned: **no
   insecure-skip-verify flag exists anywhere** — a verify-off switch
   is a standing footgun and the CA flag costs the same line count.
   Full create/join and knock/answer flows run over `wss://`.
3. **`/healthz`:** `curl http://127.0.0.1:9441/healthz` → 200, body
   `ok nimna-relay <version>`.
4. **Push transports:** `go test ./internal/push` — mock platform
   servers verify ES256/RS256 signatures against the public keys,
   exact request shapes, h2 for APNs (USER decision 3's S6
   verification standard); plus the sink-based end-to-end knock flow
   unchanged. Live-platform verification: S15, logged.
5. **Dry-run split:** subtree split → fresh clone into scratch → the
   full §29 verification suite green, including the history secret
   scan.
6. **PROGRESS.md** records the two logged deferrals verbatim: "relay
   live on relay.nimna.app" (awaits VPS) and live-platform push
   (S15).

## 31. Restated for S6 (non-negotiable)

**Zero new dependencies:** TLS, both push transports, `/healthz`, and
the deploy kit are stdlib plus the existing pins; autocert, ACME
clients, JWT libraries, oauth2, and push SDKs all remain withheld —
the S6 go.mod diff is empty. **Statelessness inventory unchanged:**
TLS certs and push credentials were *always* the two non-memory items
of spec §4's at-rest inventory; S6 is the session that makes them
real, and adds nothing beside them — the JWT/access-token caches are
in-memory credential derivatives (§27), and the systemd sandbox makes
no-writes structural (§28). **Wire behavior untouched:** no new frame
types, no Nimna-level response surfaces; TLS alerts are the §5.1
carve-out class as pre-adjudicated, covering-tested for
state-independence. **Silence doctrine untouched:** every Nimna-level
failure remains byte-identical silence or a bare close; TLS handshake
failure is below the Nimna layer and independent of all relay state.
**Identifier-free logging extended, not relaxed:** TLS events are
boot/reload lines carrying config paths and cert `notAfter` only;
handshake errors (which embed remote addresses) stay in the discarded
ErrorLog; push transport lines remain platform + HTTP status only;
the logscrub test grows TLS and real-transport coverage (§25, §27).
