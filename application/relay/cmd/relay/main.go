// Command relay is the Nimna relay: a stateless WebSocket router that
// bridges exactly two live device connections and stores nothing.
//
// The complete at-rest inventory of a running relay is: routing tables in
// memory, TLS certificates, and push credentials supplied as deployment
// configuration (spec §4). This binary is thin wiring around
// internal/server — flags, config, signals; no logic.
//
// Its import graph deliberately contains no protocol crypto: the relay
// never derives topics or touches the x/crypto module (routing_ids are
// opaque 16-byte values). Verified per session with the ANCHORED check
// `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto'` == 0 —
// an unanchored grep false-positives on Go's stdlib-vendored
// vendor/golang.org/x/crypto/... TLS paths, present in any HTTP binary.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"nimna.app/relay/internal/server"
)

const version = "0.1.0-dev"

// defaultListen is a sane localhost default; deployments set -listen or
// NIMNA_RELAY_LISTEN. TLS termination is Session 6.
const defaultListen = "127.0.0.1:9440"

func main() {
	listenDefault := defaultListen
	if v := os.Getenv("NIMNA_RELAY_LISTEN"); v != "" {
		listenDefault = v
	}
	listen := flag.String("listen", listenDefault,
		"TCP listen address (env NIMNA_RELAY_LISTEN)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("nimna-relay %s\n", version)
		return
	}

	// Lifecycle-only logging (started/stopped/config). No identifier —
	// no topic, CRID, IP, or token — is loggable by construction:
	// identifier values live in internal/ident wrapper types that
	// redact on every serialization surface.
	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	logger.Info("nimna-relay starting", "version", version)

	ctx, stop := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := server.New(server.Config{Addr: *listen}, logger)
	if err := srv.Run(ctx); err != nil {
		logger.Error("relay exited", "err", err)
		os.Exit(1)
	}
}
