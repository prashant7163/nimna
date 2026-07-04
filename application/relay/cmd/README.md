# cmd/

Go entrypoints, one folder per binary (idiomatic Go layout).

- `relay/` — the single relay binary (`go run ./cmd/relay`): thin wiring
  of `internal/server` — flags, config, signals; no logic.
- `testclient/` — the Session 3/4 done-check CLI (`go run ./cmd/testclient
  --role create|join --code …`): real §3.1.2 code→topic derivation, drives
  rendezvous + PAIR_DATA through a live relay. The module's only
  x/crypto consumer; `cmd/relay` stays x/crypto-free.
