# cmd/

Go entrypoints, one folder per binary (idiomatic Go layout).

- `relay/` — the single relay binary (`go run ./cmd/relay`): thin wiring
  of `internal/server` — flags, config (incl. the test-only push sink and
  the S6 push-credential slots), signals; no logic.
- `testclient/` — the Session 3/4 done-check CLI (`go run ./cmd/testclient
  --role create|join|knock|answer --code …`): real §3.1.2 code→topic
  derivation for the rendezvous plane, test-only code→CRID derivation for
  the channel plane; drives rendezvous + PAIR_DATA and knock → accept →
  SESSION_DATA → teardown through a live relay. The module's only
  x/crypto consumer; `cmd/relay` stays x/crypto-free.
