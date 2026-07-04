# cmd/

Go entrypoints, one folder per binary (idiomatic Go layout).

- `relay/` — the single relay binary (`go run ./cmd/relay`): thin wiring
  of `internal/server` — flags/env for every spec §4 limit (spec-verbatim
  defaults), TLS cert/key paths (both-or-neither, boot-fatal one alone),
  the APNs/FCM credential slots (boot-fatal validity rules) and the
  test-only push sink, the ops listener (`/metrics` + `/healthz`), the
  build-stamped version, signals; no logic. Also home of the CI
  log-scrub assertions (`logscrub_test.go` + the TLS extension
  `logscrub_tls_test.go`), which build and drive the real binary.
- `testclient/` — the hands-on test/audit CLI (`go run ./cmd/testclient
  --role create|join|knock|answer --code …`): real §3.1.2 code→topic
  derivation for the rendezvous plane, test-only code→CRID derivation for
  the channel plane; drives rendezvous + PAIR_DATA and knock → accept →
  SESSION_DATA → teardown through a live relay, over `ws://` or `wss://`
  (`-tls-ca` adds a local/QA root; no verify-off switch exists). The
  module's only x/crypto consumer; `cmd/relay` stays x/crypto-free
  (CI-asserted).
- `soak/` — the Session 5 soak & abuse driver: connection churn, full
  flows on both planes, `-abuse` limit probes, metrics sampling, and the
  pinned flat-memory verdict. Stdlib + `coder/websocket` only.
