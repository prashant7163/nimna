# nimna relay — deployment runbook

Target shape: one small VPS, one binary, one systemd unit. The relay is
**stateless** — at rest it holds only its TLS certificate pair and push
credentials, both read-only deployment config (spec §4). That fact drives
every operational answer below.

## 1. Provision

- Debian stable, minimal install (or any systemd distribution).
- **Clock: ensure `systemd-timesyncd` (or equivalent NTP) is enabled and
  synchronized** — `timedatectl` must say so. The push transports sign
  time-boxed JWTs (`iat`/`exp`) and TLS validates certificate windows:
  **a skewed clock is a push outage** and, badly enough, a TLS outage.
- Firewall: inbound 22 (SSH), 80 (certbot renewal only), 443 (the relay).
  Nothing else. The ops listener (9441) binds 127.0.0.1 and must never be
  exposed.

## 2. DNS

A/AAAA record for `relay.nimna.app` pointing at the host. Wait for
propagation before step 5 (certbot's http-01 must reach the host by
name).

## 3. User, directories, permissions

```sh
useradd --system --home /nonexistent --shell /usr/sbin/nologin nimna-relay
mkdir -p /etc/nimna-relay/tls /etc/nimna-relay/credentials
chown root:nimna-relay /etc/nimna-relay /etc/nimna-relay/tls /etc/nimna-relay/credentials
chmod 0750 /etc/nimna-relay /etc/nimna-relay/tls /etc/nimna-relay/credentials
```

## 4. Binary

Build on any machine with the repo checked out (Go pinned by go.mod):

```sh
deploy/build.sh          # → dist/nimna-relay-linux-{amd64,arm64}
```

Copy the right arch to the host as `/usr/local/bin/nimna-relay`, mode
0755, owner root. `nimna-relay -version` must print the stamped version.

## 5. Certificates — certbot standalone + deploy hook

The relay owns :443 and serves no files, so certbot runs `--standalone`
on :80 (http-01); :80 stays otherwise unbound — the relay is not a
website and nothing legitimate speaks plain HTTP to it.

```sh
apt install certbot
install -m 0755 deploy/certbot-deploy-hook.sh \
    /etc/letsencrypt/renewal-hooks/deploy/nimna-relay.sh
certbot certonly --standalone -d relay.nimna.app
```

Hooks installed in `/etc/letsencrypt/renewal-hooks/deploy/` run
automatically after every successful issuance and renewal — that one
`install` is the whole registration; do **not** also pass
`--deploy-hook` (it would record a second, duplicate hook in the
renewal config). After `certonly` completes, verify the pair landed:

```sh
ls -l /etc/nimna-relay/tls/   # fullchain.pem + privkey.pem, root:nimna-relay 0640
```

The hook copies `fullchain.pem`/`privkey.pem` into `/etc/nimna-relay/tls/`
(group-readable by nimna-relay) — **a pure file copy, no restart**: the
relay hot-reloads the pair within ~60 s of the cert file's mtime moving,
and live sessions survive renewal.

## 6. Configuration

```sh
install -o root -g nimna-relay -m 0640 deploy/relay.env.example /etc/nimna-relay/relay.env
```

Edit `/etc/nimna-relay/relay.env`: set the two TLS paths
(`/etc/nimna-relay/tls/fullchain.pem`, `/etc/nimna-relay/tls/privkey.pem`)
and, when they exist, the push credential slots (files under
`/etc/nimna-relay/credentials/`, root:nimna-relay 0640). Push slots left
empty = push-less, which is a legal mode. Misconfiguration is loud:
half a TLS pair, a partial APNs quad, an unparseable credential file, or
a test sink beside real credentials all refuse to boot.

## 7. Enable and start

```sh
install -m 0644 deploy/nimna-relay.service /etc/systemd/system/nimna-relay.service
systemctl daemon-reload
systemctl enable --now nimna-relay
```

## 8. Verify

- `journalctl -u nimna-relay -f` — expect `nimna-relay starting` with the
  stamped version, the `config` summary (check `tls=on`, the cert paths,
  and `push_mode`), and `relay listening`.
- On-host health: `curl http://127.0.0.1:9441/healthz` →
  `ok nimna-relay <version>`.
- TLS from outside:
  `openssl s_client -connect relay.nimna.app:443 -brief` — expect a
  TLS 1.3 session and the Let's Encrypt chain.
- End-to-end from a second machine (repo checkout):

  ```sh
  go run ./cmd/testclient --role create --code 7Q2-M4K-9XV --relay wss://relay.nimna.app
  go run ./cmd/testclient --role join   --code 7Q2-M4K-9XV --relay wss://relay.nimna.app
  ```

  Both exit 0 after the bridged PAIR_DATA exchange. Repeat with
  `--role answer` / `--role knock` for the channel plane.
- Metrics scrape via tunnel (below): `nimna_relay_connections` moves while
  the testclients run.

## 9. Operate

- **Metrics: SSH tunnel only, never exposed.**
  `ssh -L 9441:127.0.0.1:9441 host` then scrape
  `http://127.0.0.1:9441/metrics`. The exposition is identifier-free by
  construction (aggregate counters, compile-time label sets).
- **Certificate renewal:** automatic (certbot timer + deploy hook + the
  relay's hot reload). Test it: `certbot renew --dry-run`. Watch for the
  relay's `tls certificate reloaded` line (carries the new expiry) after
  a real renewal.
- **Upgrade:** replace `/usr/local/bin/nimna-relay`, then
  `systemctl restart nimna-relay`. Verify with `/healthz` (version) and
  journalctl.
- **Binary verification:** rebuild at the deployed commit with
  `deploy/build.sh` (same pinned toolchain) and compare checksums against
  the deployed binary — the build is reproducible best-effort
  (`-trimpath`, CGO off, pinned Go).
- **Clock:** keep `systemd-timesyncd` healthy (`timedatectl`). Clock skew
  is a push outage.
- **Logs:** identifier-free by construction (lifecycle, config summary,
  scrubbed panic lines, push status codes, TLS reload events) — journalctl
  output is shareable in incident notes as-is.
- **Incident doctrine, verbatim:** **restart is always safe — the relay
  is stateless; the entire recovery procedure is
  `systemctl restart nimna-relay`; live pairs re-knock.** There is no
  state to rescue, drain, or replay — by design there never will be.
