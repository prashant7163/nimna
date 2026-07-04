# internal/metrics/

Identifier-free aggregate metrics — the relay's production instrument
(architecture note §18; logging doctrine):

- `metrics.go` — a struct of `sync/atomic` counters incremented at event
  sites plus a scrape-time gauge snapshot; no background aggregation
  goroutine. Label values are fixed compile-time enumerations only
  (`plane`, `limit`, `class`, `outcome`, `cause`, `site`) — there is no
  API surface that accepts a string, so no identifier can ever become a
  label by construction. Exposition is hand-rolled Prometheus text format
  0.0.4 (`prometheus/client_golang` is a dependency tree for a ~30-line
  `fmt.Fprintf` loop and is not taken). `Handler` serves `GET /metrics`
  and 404s everything else — the ops port speaks exactly one thing.
  Pinned inventory, prefix `nimna_relay_`: gauges `connections`, `topics`,
  `topic_bridges`, `crid_entries`, `pending_knocks`, `session_bridges`,
  `rate_entries`, `goroutines`, `heap_alloc_bytes`, `heap_sys_bytes`;
  counters `connections_total`, `frames_forwarded_total{plane}`,
  `knocks_forwarded_total`, `pushes_total{outcome}` (attempted = the sum,
  not a series), `limit_trips_total{limit}`, `closes_total{class}`,
  `teardowns_total{cause}`, `panics_total{site}`.
- `metrics_test.go` — golden exposition (exact bytes, full inventory,
  fixed order), line-format parseability, identifier-freeness (every
  label value ∈ the compile-time sets; no hex runs, no address-shaped
  strings), nil-instrument safety, and the GET-/metrics-else-404 surface.

The ops listener that serves this (default `127.0.0.1:9441`, `-metrics-
listen`, empty disables) lives in `internal/server`; S6's `/healthz`
lands on that same listener.
