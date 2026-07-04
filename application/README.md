# application/

All product code. Two independent projects:

- [`relay/`](relay/) — the Go relay (stateless WebSocket router; will be
  open-sourced under AGPL-3.0 at Session 6). Module `nimna.app/relay`.
- [`mobile/`](mobile/) — the Flutter app for iOS + Android (closed source).
  Package `nimna`, identifiers `app.nimna`.

Both are governed by [`docs/nimna-protocol-spec-v0.1.1.md`](../docs/nimna-protocol-spec-v0.1.1.md)
(the single source of truth), the session plan in
[`nimna-build-plan-v2-sessions.md`](../nimna-build-plan-v2-sessions.md), and
the standing rules in the repo-root [`CLAUDE.md`](../CLAUDE.md). UI work is
additionally bound by the design artifacts in [`designs/`](../designs/).

CI for both stacks lives in `.github/workflows/`.
