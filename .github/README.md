# .github/

CI skeletons (GitHub Actions), path-filtered per stack:

- `workflows/relay.yml` — Go relay: gofmt / vet / build / test
  (Go version pinned via `go.mod`).
- `workflows/mobile.yml` — Flutter app: format / analyze / test
  (Flutter pinned to 3.44.2 via `subosito/flutter-action@v2`, the standard
  community action for Flutter CI — the one third-party action in use).
