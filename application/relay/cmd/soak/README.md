# cmd/soak/

Soak & abuse driver for the Session 5 done-check and overnight runs
(architecture note §21). A third main package beside `relay`/`testclient`
— a committed deliverable under the same gofmt/vet/test CI, deliberately
outside the relay binary's import graph (`coder/websocket` + stdlib only;
no x/crypto). Routing identifiers are opaque random 16 bytes — the relay
never derives, so neither does its load driver.

**Drives** (against a RUNNING relay): connection churn
(dial/register/drop), full rendezvous flows (register → bridge →
`PAIR_DATA` → drop; client-side paced under the relay's rendezvous
throttle so load measures the relay, not the throttle), full channel
flows (register → knock → accept → `SESSION_DATA` → `TEARDOWN`), and —
with `-sink-listen` hosting a push sink — offline knocks with tokens.

**`-abuse`** probes every limit before the load, asserting behavior plus
`limit_trips_total` deltas: over-cap connects (zero-byte close), frame
flood (pacing, not errors — measured throughput ceiling; a knock queued
behind the flood proves nothing dropped), oversize frame (close),
duplicate knocks (exactly one `KNOCK_FWD`), push over-cap (sink-count
floor), rendezvous over-throttle (behavioral: the throttled registration
must NOT bridge after the window rolls — takes ~65 s, the window is
pinned at one minute).

**Measures:** samples the metrics endpoint (`-sample`, default 30 s) for
heap, goroutines, and all table gauges; prints the time series and the
pinned verdict (§21): after load + `-drain`, ALL table gauges return to
zero and median `heap_alloc_bytes` of the final quarter ≤ 1.10 × the
second quarter. Note: `rate_entries` drains only after the relay's
longest configured window (24 h at spec defaults) — run the relay with a
shortened `-push-day-window` for a drainable accelerated soak; the
verdict output says so when it bites.

```sh
# accelerated in-session soak (relay windows shrunk via config):
go run ./cmd/relay -push-sink http://127.0.0.1:9470 \
    -push-day-window 90s -push-hour-window 60s
go run ./cmd/soak -duration 10m -drain 60s -abuse \
    -sink-listen 127.0.0.1:9470

# true overnight run:
go run ./cmd/soak -duration 8h
```

Flags mirror the relay's limit config (`-conn-cap`, `-frame-rate`,
`-knock-interval`, …) so probe expectations match the deployment under
test. Exit 0 = PASS. PROGRESS.md reports exactly which run was performed
(§21's honest evidence standard).
