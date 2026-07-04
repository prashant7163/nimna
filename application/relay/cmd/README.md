# cmd/

Go entrypoints, one folder per binary (idiomatic Go layout).

- `relay/` — the single relay binary (`go run ./cmd/relay`): thin wiring
  of `internal/server` — flags/env for every spec §4 limit (spec-verbatim
  defaults), the ops metrics listener, the test-only push sink and the S6
  push-credential slots, signals; no logic. Also home of the CI
  log-scrub assertion (`logscrub_test.go`), which builds and drives the
  real binary.
- `testclient/` — the Session 3/4 done-check CLI (`go run ./cmd/testclient
  --role create|join|knock|answer --code …`): real §3.1.2 code→topic
  derivation for the rendezvous plane, test-only code→CRID derivation for
  the channel plane; drives rendezvous + PAIR_DATA and knock → accept →
  SESSION_DATA → teardown through a live relay. The module's only
  x/crypto consumer; `cmd/relay` stays x/crypto-free (CI-asserted).
- `soak/` — the Session 5 soak & abuse driver: connection churn, full
  flows on both planes, `-abuse` limit probes, metrics sampling, and the
  pinned flat-memory verdict. Stdlib + `coder/websocket` only.
