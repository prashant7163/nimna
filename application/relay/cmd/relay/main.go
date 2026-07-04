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
// opaque 16-byte values). CI-asserted with the ANCHORED check
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
	"strconv"
	"syscall"
	"time"

	"nimna.app/relay/internal/push"
	"nimna.app/relay/internal/server"
)

const version = "0.1.0-dev"

// defaultListen is a sane localhost default; deployments set -listen or
// NIMNA_RELAY_LISTEN. TLS termination is Session 6.
const defaultListen = "127.0.0.1:9440"

// defaultMetricsListen is the ops listener (architecture note §18):
// operator-eyes-only by default; GET /metrics, everything else 404.
const defaultMetricsListen = "127.0.0.1:9441"

// Push configuration (spec §3.2.1; architecture note §11). All slots
// default empty; with nothing set the relay runs push-less — the
// spec-sanctioned mode where offline knocks hold their pending and
// coordination is out-of-band.
//
// Real APNs/FCM transports land in Session 6 (deploy) behind the same
// push.Sender interface, consuming these config slots — names pinned now:
//
//	NIMNA_RELAY_APNS_KEY_FILE  APNs .p8 signing-key path
//	NIMNA_RELAY_APNS_KEY_ID    APNs key id
//	NIMNA_RELAY_APNS_TEAM_ID   Apple developer team id
//	NIMNA_RELAY_APNS_TOPIC     app bundle id (apns-topic)
//	NIMNA_RELAY_FCM_SA_FILE    FCM service-account JSON path
//
// Credentials are deployment configuration — file paths and env only,
// never repository content (spec §4); the config.example and .gitignore
// guard land in Session 6.
//
// envPushSink (-push-sink) selects the TEST-ONLY HTTP sink that stands in
// for the push platforms during done-checks: it receives each dispatch as
// one content-free POST. Never a production transport.
const envPushSink = "NIMNA_RELAY_PUSH_SINK"

// Flag defaults are seeded from NIMNA_RELAY_* env vars; the flag wins
// (architecture note §14). Malformed env values fall back to the coded
// default: config errors must never pick a different limit silently, and
// the boot log prints every effective value for the operator to verify.

func envStr(key, def string) string {
	if v := os.Getenv("NIMNA_RELAY_" + key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv("NIMNA_RELAY_" + key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func envDur(key string, def time.Duration) time.Duration {
	if v := os.Getenv("NIMNA_RELAY_" + key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

func envBool(key string, def bool) bool {
	if v := os.Getenv("NIMNA_RELAY_" + key); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			return b
		}
	}
	return def
}

func main() {
	listen := flag.String("listen", envStr("LISTEN", defaultListen),
		"TCP listen address (env NIMNA_RELAY_LISTEN)")
	pushSink := flag.String("push-sink", os.Getenv(envPushSink),
		"test-only HTTP push-sink URL (env "+envPushSink+"); empty = push-less")

	// Limits & observability (architecture note §14; spec §4 numbers
	// are spec-verbatim defaults).
	maxConnsPerIP := flag.Int("max-conns-per-ip", envInt("MAX_CONNS_PER_IP", 64),
		"live-connection cap per IP key: IPv4 exact, IPv6 /64 (env NIMNA_RELAY_MAX_CONNS_PER_IP)")
	frameRate := flag.Int("frame-rate", envInt("FRAME_RATE", server.DefaultFrameRate),
		"per-connection sustained frames/second, read-paced (env NIMNA_RELAY_FRAME_RATE)")
	frameBurst := flag.Int("frame-burst", envInt("FRAME_BURST", server.DefaultFrameBurst),
		"per-connection frame burst (env NIMNA_RELAY_FRAME_BURST)")
	maxFrame := flag.Int("max-frame", envInt("MAX_FRAME", 131072),
		"max frame size in bytes, spec default 128 KiB; raising past 131072 is a wire-constant change, not config (env NIMNA_RELAY_MAX_FRAME)")
	rendezvousPerMin := flag.Int("rendezvous-per-min", envInt("RENDEZVOUS_PER_MIN", 6),
		"REGISTER_TOPIC frames per IP key per minute (env NIMNA_RELAY_RENDEZVOUS_PER_MIN)")
	maxRegsPerConn := flag.Int("max-regs-per-conn", envInt("MAX_REGS_PER_CONN", server.DefaultMaxRegsPerConn),
		"registrations per connection, per plane (env NIMNA_RELAY_MAX_REGS_PER_CONN)")
	knockInterval := flag.Duration("knock-interval", envDur("KNOCK_INTERVAL", 10*time.Second),
		"per-CRID knock collapse window, spec 10s (env NIMNA_RELAY_KNOCK_INTERVAL)")
	pushMinInterval := flag.Duration("push-min-interval", envDur("PUSH_MIN_INTERVAL", 60*time.Second),
		"per-CRID push floor, spec 60s (env NIMNA_RELAY_PUSH_MIN_INTERVAL)")
	pushPerHour := flag.Int("push-per-hour", envInt("PUSH_PER_HOUR", 6),
		"per-CRID pushes per hour window, spec 6 (env NIMNA_RELAY_PUSH_PER_HOUR)")
	pushPerDay := flag.Int("push-per-day", envInt("PUSH_PER_DAY", 20),
		"per-CRID pushes per day window, spec 20 (env NIMNA_RELAY_PUSH_PER_DAY)")
	pushHourWindow := flag.Duration("push-hour-window", envDur("PUSH_HOUR_WINDOW", time.Hour),
		"hour-cap window; test/soak acceleration knob, defaults spec (env NIMNA_RELAY_PUSH_HOUR_WINDOW)")
	pushDayWindow := flag.Duration("push-day-window", envDur("PUSH_DAY_WINDOW", 24*time.Hour),
		"day-cap window; test/soak acceleration knob, defaults spec (env NIMNA_RELAY_PUSH_DAY_WINDOW)")
	idleTimeout := flag.Duration("idle-timeout", envDur("IDLE_TIMEOUT", 90*time.Second),
		"reap connections with no inbound bytes for this long; WS pings count as liveness (env NIMNA_RELAY_IDLE_TIMEOUT)")
	metricsListen := flag.String("metrics-listen", envStr("METRICS_LISTEN", defaultMetricsListen),
		"ops listener for GET /metrics; empty disables (env NIMNA_RELAY_METRICS_LISTEN)")
	debugTrace := flag.Bool("debug-trace", envBool("DEBUG_TRACE", false),
		"per-connection debug tracing — NEVER in production (env NIMNA_RELAY_DEBUG_TRACE)")

	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("nimna-relay %s\n", version)
		return
	}

	// Operational logging (note §19): process lifecycle, config summary,
	// panic scrubs, push transport status — internal slog only, never a
	// wire surface. No identifier — no topic, CRID, IP, or token — is
	// loggable by construction: identifier values live in internal/ident
	// wrapper types that redact on every serialization surface.
	// -debug-trace raises the level; production stays Info.
	level := slog.LevelInfo
	if *debugTrace {
		level = slog.LevelDebug
	}
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	logger.Info("nimna-relay starting", "version", version)

	ctx, stop := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := server.Config{
		Addr:             *listen,
		MaxConnsPerIP:    *maxConnsPerIP,
		FrameRate:        *frameRate,
		FrameBurst:       *frameBurst,
		MaxFrame:         *maxFrame,
		RendezvousPerMin: *rendezvousPerMin,
		MaxRegsPerConn:   *maxRegsPerConn,
		KnockInterval:    *knockInterval,
		PushMinInterval:  *pushMinInterval,
		PushPerHour:      *pushPerHour,
		PushPerDay:       *pushPerDay,
		PushHourWindow:   *pushHourWindow,
		PushDayWindow:    *pushDayWindow,
		IdleTimeout:      *idleTimeout,
		MetricsAddr:      *metricsListen,
		DebugTrace:       *debugTrace,
	}
	if *pushSink != "" {
		cfg.Push = push.NewHTTPSink(*pushSink)
	}

	// Boot config summary (note §19): limit values and listener
	// addresses — never credentials, never file contents.
	logger.Info("config",
		"listen", *listen,
		"metrics_listen", *metricsListen,
		"max_conns_per_ip", *maxConnsPerIP,
		"frame_rate", *frameRate,
		"frame_burst", *frameBurst,
		"max_frame", *maxFrame,
		"rendezvous_per_min", *rendezvousPerMin,
		"max_regs_per_conn", *maxRegsPerConn,
		"knock_interval", *knockInterval,
		"push_min_interval", *pushMinInterval,
		"push_per_hour", *pushPerHour,
		"push_per_day", *pushPerDay,
		"push_hour_window", *pushHourWindow,
		"push_day_window", *pushDayWindow,
		"idle_timeout", *idleTimeout,
		"push_mode", pushMode(*pushSink),
		"debug_trace", *debugTrace,
	)

	srv := server.New(cfg, logger)
	if err := srv.Run(ctx); err != nil {
		logger.Error("relay exited", "err", err)
		os.Exit(1)
	}
}

// pushMode names the push configuration class for the boot log. The
// class name, not the sink URL: the config summary stays fixed-shape
// (note §19 — fixed fields only, no free-form values).
func pushMode(sink string) string {
	if sink != "" {
		return "sink"
	}
	return "push-less"
}
