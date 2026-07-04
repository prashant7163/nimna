# cmd/testclient/

The Session 3 done-check tool: one binary, run twice, that rendezvouses
two connections through the relay and exchanges raw PAIR_DATA frames.
Session 4 extends this same binary for knock/accept/chat.

- `main.go` — `--role create|join`, `--relay` URL, `--code`; the creator
  registers its topic and waits for `TOPIC_BRIDGED`; the joiner probes
  today's topic, then also registers yesterday's (spec §3.1.2 — two
  candidates cover a TTL ≤ 24 h); after the bridge the joiner initiates a
  demo exchange of raw PAIR_DATA frames (arbitrary bytes — real Noise is
  app work, Sessions 8/9; the relay forwards them verbatim). Exits
  non-zero on any failure so QA can script it.
- `derive.go` — the REAL §3.1.1/§3.1.2 derivation: code canonicalization,
  date-salted SHA-256 → Argon2id (t=3, m=64 MiB, p=1; x/crypto) → stdlib
  HKDF-SHA-256 topic expansion. CLIENT-side logic: it lives here and must
  never leak into relay packages — the relay never derives topics, and
  `cmd/relay`'s import graph stays x/crypto-free.
- `derive_test.go` — vector-locked against the committed
  `docs/test-vectors/topic-derivation.json`: canonicalization (valid and
  reject cases), salts, and seed/topic/psk under both parameter sets —
  reduced-cost always, production-cost skipped under `-short`.

This is a TEST TOOL, not the relay: it prints its own topics and frames
freely. The relay side stays provably silent.

```sh
# terminal 1 — the relay
go run ./cmd/relay

# terminal 2 — the creator (waits up to 120s for a joiner)
go run ./cmd/testclient --role create --code 7Q2-M4K-9XV

# terminal 3 — the joiner (any §3.1.1 input form of the same code)
go run ./cmd/testclient --role join --code "7q2 m4k 9xv"
```
