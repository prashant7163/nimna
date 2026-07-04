# .github/

CI skeletons (GitHub Actions), path-filtered per stack:

- `workflows/relay.yml` — Go relay: gofmt / vet / build / test
  (Go version pinned via `go.mod`).
- `workflows/mobile.yml` — Flutter app: format / analyze / test
  (Flutter pinned to 3.44.2 via `subosito/flutter-action@v2`, the standard
  community action for Flutter CI — the one third-party action in use).
- `workflows/test-vectors.yml` — protocol test vectors: gofmt / vet /
  build / test of the committed generator, then regenerate + drift guard
  (`git diff --exit-code` + clean `git status`) so the vectors can never
  silently diverge from the generator.
