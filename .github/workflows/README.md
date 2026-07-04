# workflows/

GitHub Actions workflow definitions (GitHub parses only `.yml`/`.yaml` here).

- `relay.yml` — Go relay checks: gofmt clean / vet / build / test.
- `mobile.yml` — Flutter app checks: format / analyze / test.
- `test-vectors.yml` — protocol vector generator checks + regeneration
  drift guard.

All are path-filtered to their stack; details in [`../README.md`](../README.md).
