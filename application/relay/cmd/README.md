# cmd/

Go entrypoints, one folder per binary (idiomatic Go layout).

- `relay/` — the single relay binary (`go run ./cmd/relay`). Currently the
  Session 1 scaffold; server internals will live in `internal/` packages
  from Session 3 on.
