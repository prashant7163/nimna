# Relay architecture note — Sessions 3–6

**Author:** tech-architect · **Date:** 2026-07-04 (Session 3 intake) ·
**Binding for:** `application/relay/` implementation, Sessions 3–6.
**Sources:** spec `docs/nimna-protocol-spec-v0.2.md` (§3.1.2, §3.1.6, §4,
§5.4–§5.7), `docs/crypto-evaluation.md` §10–§12, DECISIONS.md S2 entries.
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

Reserved seams (do not create yet): `internal/channel` (S4: CRID registry,
knock/accept/session bridging), `internal/push` (S4: APNs/FCM forwarding),
`internal/metrics` and `internal/limits` (S5). The S3 frame router and
registry APIs must let these plug in without touching `internal/wire` or
the connection lifecycle.

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
