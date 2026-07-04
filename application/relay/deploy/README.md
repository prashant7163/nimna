# deploy/

The relay's complete deployment story, shipped inside the audited tree
(spec §4's reproducible-deployment claim is only auditable if the unit
file and build script live in the repository everyone reads).

- `RUNBOOK.md` — provision → DNS → user → binary → certs → config →
  start → verify → operate, end to end.
- `nimna-relay.service` — hardened systemd unit. Statelessness as a unit
  property: `ProtectSystem=strict` with no writable paths — the service
  structurally cannot write to the filesystem.
- `relay.env.example` — every `NIMNA_RELAY_*` slot in systemd
  `EnvironmentFile` syntax; TLS and push credential slots ship empty
  (credentials are deployment configuration, never repository content).
- `build.sh` — reproducible-best-effort release build (CGO off,
  `-trimpath`, pinned toolchain, git-describe version stamp) for
  linux/amd64 + linux/arm64 into git-ignored `dist/`.
- `certbot-deploy-hook.sh` — pure cert copy into `/etc/nimna-relay/tls/`,
  no restart: the relay hot-reloads renewed certificates in-process.
