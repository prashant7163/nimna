#!/bin/sh
# Release build for the nimna relay (architecture note §28).
#
# Best-effort reproducibility (spec §4): pinned toolchain (go.mod),
# -trimpath, CGO off — the same toolchain on the same commit produces a
# byte-identical binary, so third parties can verify a deployed binary
# against the repository (RUNBOOK.md §9).
#
# Output: dist/nimna-relay-linux-amd64, dist/nimna-relay-linux-arm64
# (dist/ is git-ignored). The version stamp (git describe) surfaces in
# the boot log, `nimna-relay -version`, and the /healthz body.
set -eu

cd "$(dirname "$0")/.."

VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
mkdir -p dist

for ARCH in amd64 arm64; do
    OUT="dist/nimna-relay-linux-${ARCH}"
    echo "building ${OUT} (version ${VERSION})"
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" \
        go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
        -o "${OUT}" ./cmd/relay
done

echo
ls -l dist/nimna-relay-linux-*
