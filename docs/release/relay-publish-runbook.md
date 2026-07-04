# Relay publish runbook (private side)

Monorepo-only document — **not part of the split**. Governs turning
`application/relay/` into the public AGPL-3.0 repository. Prepared at
Session 6 (repo made publishable, dry-run split verified); the publish
click itself is **launch step 1 at Session 19** ("repo public → site
live → store release" — USER decision, 2026-07-04 21:59 +0200).

## 1. Produce the split tree

**Default: subtree split WITH HISTORY** (CODE decision, 2026-07-04
22:09 +0200 — the commit trail is auditability evidence: the invariants
visibly held over time):

```sh
git subtree split --prefix=application/relay HEAD -b relay-public
```

**Documented S19 alternative — squash to a single commit** (revisitable
at the publish click with zero rework; choose it if history is judged to
carry anything not worth publishing):

```sh
git checkout --orphan relay-public-squash
git rm -rf .
git checkout main -- application/relay
git mv application/relay/* application/relay/.g* .   # move subtree to root
git commit -s -m "nimna relay — initial public release"
```

Either way, verify against a **fresh clone** of the branch, never the
working tree. `--single-branch` is load-bearing: a default clone
fetches every monorepo ref, so the §2 history scan would walk
`origin/main` and self-match the documentation that quotes the scan
patterns (this runbook, the architecture note) — a guaranteed false
LEAK (observed at the S6 wrap verification). The public repo will
contain only the split branch, so the verification clone must too:

```sh
git clone --branch relay-public --single-branch "$(pwd)" /tmp/relay-split-check
cd /tmp/relay-split-check
```

## 2. Split-tree verification list (all must pass, standalone)

- [ ] `go build ./...`
- [ ] `go test ./...` — includes the real-binary log-scrub assertions
      (`cmd/relay/logscrub_test.go`, `logscrub_tls_test.go`) and the
      vendored-vector conformance tests (no path may escape the repo)
- [ ] `go vet ./...`
- [ ] `gofmt -l .` prints nothing
- [ ] Anchored x/crypto check:
      `test "$(go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/')" -eq 0`
- [ ] Presence: `LICENSE` (full AGPL-3.0), `README.md`,
      `CONTRIBUTING.md`, `docs/nimna-protocol-spec-v0.2.md`, `deploy/`
      (unit, env example, build.sh, certbot hook, RUNBOOK),
      `.github/workflows/ci.yml`, `internal/wire/testdata/framing.json`,
      `cmd/testclient/testdata/topic-derivation.json`, `.gitignore`
- [ ] `deploy/build.sh` cross-compiles both linux binaries
- [ ] **History-wide secret scan** (history ships, so history is
      scanned; on the squash alternative it still runs, trivially):

      ```sh
      # key material in any historical blob
      git log -p --all | grep -nE 'BEGIN( [A-Z0-9]+)? PRIVATE KEY|private_key_id' && echo LEAK || echo clean
      # credential-shaped filenames ever added
      git log --diff-filter=A --name-only --all --pretty=format: | sort -u \
        | grep -E '\.p8$|\.pem$|\.key$|\.crt$|\.env$|service-account.*\.json$' \
        && echo LEAK || echo clean
      ```

      Both must print `clean`. Any hit = stop; the squash alternative
      (or history surgery + re-verification) becomes mandatory.

## 3. S19 trigger sequence

Publishing is launch-sequence **step 1**; do not run early.

1. Re-run §1–§2 at the launch commit (the split is cheap and
   deterministic; never publish a stale branch).
2. Create the public repository; push `relay-public` as `main`.
3. Branch protection on `main` (PRs only, CI required).
4. Confirm the public CI (`ci.yml`) runs green on the public repo.
5. Continue the launch sequence: site live → store release. S19 website
   items that unlock relay conveniences: go-import meta tags on
   nimna.app (enables `go install nimna.app/relay/cmd/relay@latest`),
   README links to the live site.

## 4. USER items timed to S19 (do not resolve earlier)

1. **History vs squash — final confirm.** Default is
   history-preserved; USER confirms (or flips to squash) at the publish
   click. Zero rework either way.
2. **Security-contact mailbox.** CONTRIBUTING.md carries a placeholder;
   a dedicated mailbox on the project domain (e.g. security@nimna.app)
   needs the domain mail setup — create it and replace the placeholder
   before the repo goes public.
