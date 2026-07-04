# cmd/testclient/

The Session 3/4 done-check tool: one binary, four roles, run in pairs —
`create`/`join` drive the rendezvous plane (PAIR_DATA), `knock`/`answer`
drive the channel plane (knock → accept → SESSION_DATA → teardown).

- `main.go` — flags and role dispatch, plus the Session 3 roles:
  `--role create|join`, `--relay` URL, `--code`; the creator registers its
  topic and waits for `TOPIC_BRIDGED`; the joiner probes today's topic,
  then also registers yesterday's (spec §3.1.2 — two candidates cover a
  TTL ≤ 24 h); after the bridge the joiner initiates a demo exchange of
  raw PAIR_DATA frames (arbitrary bytes — real Noise is app work,
  Sessions 8/9; the relay forwards them verbatim). Exits non-zero on any
  failure so QA can script it.
- `channel.go` — the Session 4 roles. `--role knock`: `REGISTER_CRID`,
  `KNOCK` (optionally `--token <hex> --platform apns|fcm`,
  both-or-neither), wait for `SESSION_BRIDGED` (default `--wait` 75 s >
  the relay's 60 s knock window; past it silence IS the answer), chat as
  initiator over `--rounds` SESSION_DATA round trips (speaks first,
  mirroring §3.3.1 S1), one WebSocket ping as the keepalive covering
  check (note §12), then `TEARDOWN`, exit 0. `--role answer`:
  `REGISTER_CRID`, wait for `KNOCK_FWD` (delivered live or on register —
  a pending knock reaches a late-connecting answerer), `ACCEPT`, chat as
  responder, exit 0 on the relay `TEARDOWN`. The CRID comes from a
  TEST-ONLY derivation `SHA-256("nimna/testclient/crid/v1|"+code)[0:16]`
  (explicitly NOT spec §3.1.5, which needs pairing statics that don't
  exist until S8/9) or directly via `--crid <32 hex>`.
- `channel_test.go` — pins the test-only CRID derivation against
  independently computed vectors and the canonical-form property.
- `derive.go` — the REAL §3.1.1/§3.1.2 derivation: code canonicalization,
  date-salted SHA-256 → Argon2id (t=3, m=64 MiB, p=1; x/crypto) → stdlib
  HKDF-SHA-256 topic expansion. CLIENT-side logic: it lives here and must
  never leak into relay packages — the relay never derives topics, and
  `cmd/relay`'s import graph stays x/crypto-free.
- `derive_test.go` — vector-locked against the committed
  `docs/test-vectors/topic-derivation.json`: canonicalization (valid and
  reject cases), salts, and seed/topic/psk under both parameter sets —
  reduced-cost always, production-cost skipped under `-short`.

This is a TEST TOOL, not the relay: it prints its own identifiers and
frames freely. The relay side stays provably silent.

```sh
# terminal 1 — the relay
go run ./cmd/relay

# terminal 2 — the creator (waits up to 120s for a joiner)
go run ./cmd/testclient --role create --code 7Q2-M4K-9XV

# terminal 3 — the joiner (any §3.1.1 input form of the same code)
go run ./cmd/testclient --role join --code "7q2 m4k 9xv"

# then the channel plane over the same code:
go run ./cmd/testclient --role answer --code 7Q2-M4K-9XV   # terminal 2
go run ./cmd/testclient --role knock  --code 7Q2-M4K-9XV   # terminal 3

# offline-knock push path (relay started with -push-sink <url>):
go run ./cmd/testclient --role knock --code 7Q2-M4K-9XV \
    --token 8b2ce49e --platform apns    # sink gets ONE content-free POST
go run ./cmd/testclient --role answer --code 7Q2-M4K-9XV   # within 60 s
```
