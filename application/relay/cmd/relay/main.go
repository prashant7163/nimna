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
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"nimna.app/relay/internal/push"
	"nimna.app/relay/internal/server"
)

// version is stamped at build time by deploy/build.sh via
// `-ldflags "-X main.version=<git describe --tags --always>"`. It
// surfaces in the boot log, the -version flag, and the /healthz body —
// the three places an operator verifies a deployed binary.
var version = "dev"

// defaultListen is a sane localhost default; deployments set -listen or
// NIMNA_RELAY_LISTEN (the deploy kit listens on :443 with TLS).
const defaultListen = "127.0.0.1:9440"

// defaultMetricsListen is the ops listener (architecture note §18):
// operator-eyes-only by default; GET /metrics, everything else 404.
const defaultMetricsListen = "127.0.0.1:9441"

// TLS configuration (architecture note §§24–25): -tls-cert/-tls-key
// (env NIMNA_RELAY_TLS_CERT / NIMNA_RELAY_TLS_KEY) name the PEM chain
// and key paths (certbot fullchain.pem/privkey.pem). Both-or-neither:
// one alone is a config error, boot-fatal; neither is the first-class
// plain listener (dev, tunnel/LB-terminated deployments). The relay
// hot-reloads a renewed certificate in-process (mtime-checked, ≤ 60 s) —
// certbot renewal never restarts the service.
//
// Push configuration (spec §3.2.1; architecture note §11, §27). All
// slots default empty; with nothing set the relay runs push-less — the
// spec-sanctioned mode where offline knocks hold their pending and
// coordination is out-of-band. The real transports consume the pinned
// slots (flags mirror the env names):
//
//	NIMNA_RELAY_APNS_KEY_FILE  APNs .p8 signing-key path
//	NIMNA_RELAY_APNS_KEY_ID    APNs key id
//	NIMNA_RELAY_APNS_TEAM_ID   Apple developer team id
//	NIMNA_RELAY_APNS_TOPIC     app bundle id (apns-topic)
//	NIMNA_RELAY_FCM_SA_FILE    FCM service-account JSON path
//
// The four APNs slots are all-or-nothing (a partial set is boot-fatal;
// the error names the missing slot names only, never values). The FCM
// file must parse at boot. Credentials are deployment configuration —
// file paths and env only, never repository content (spec §4);
// deploy/relay.env.example ships the slots empty and .gitignore guards
// the file shapes.
//
// envPushSink (-push-sink) selects the TEST-ONLY HTTP sink that stands in
// for the push platforms during done-checks: it receives each dispatch as
// one content-free POST. Never a production transport. Setting it
// together with ANY real credential slot is boot-fatal (§24: a
// contradictory transport config has no safe default).
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
	tlsCert := flag.String("tls-cert", envStr("TLS_CERT", ""),
		"TLS certificate chain PEM path, e.g. certbot fullchain.pem; requires -tls-key (env NIMNA_RELAY_TLS_CERT)")
	tlsKey := flag.String("tls-key", envStr("TLS_KEY", ""),
		"TLS private key PEM path, e.g. certbot privkey.pem; requires -tls-cert (env NIMNA_RELAY_TLS_KEY)")
	pushSink := flag.String("push-sink", os.Getenv(envPushSink),
		"test-only HTTP push-sink URL (env "+envPushSink+"); empty = push-less; boot-fatal with any real push credential")
	apnsKeyFile := flag.String("apns-key-file", envStr("APNS_KEY_FILE", ""),
		"APNs .p8 signing-key path; all four apns-* slots go together (env NIMNA_RELAY_APNS_KEY_FILE)")
	apnsKeyID := flag.String("apns-key-id", envStr("APNS_KEY_ID", ""),
		"APNs key id (env NIMNA_RELAY_APNS_KEY_ID)")
	apnsTeamID := flag.String("apns-team-id", envStr("APNS_TEAM_ID", ""),
		"Apple developer team id (env NIMNA_RELAY_APNS_TEAM_ID)")
	apnsTopic := flag.String("apns-topic", envStr("APNS_TOPIC", ""),
		"apns-topic header: the app bundle id (env NIMNA_RELAY_APNS_TOPIC)")
	apnsSandbox := flag.Bool("apns-sandbox", envBool("APNS_SANDBOX", false),
		"route APNs to the sandbox host for dev-build (aps-environment=development) tokens; never in production (env NIMNA_RELAY_APNS_SANDBOX)")
	fcmSAFile := flag.String("fcm-sa-file", envStr("FCM_SA_FILE", ""),
		"FCM service-account JSON path (env NIMNA_RELAY_FCM_SA_FILE)")

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
		"ops listener for GET /metrics and GET /healthz; empty disables (env NIMNA_RELAY_METRICS_LISTEN)")
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

	// Config validity (note §24) — all violations boot-fatal and loud:
	// a contradictory or half-configured transport has no safe default,
	// and silently running push-less against operator intent (or
	// swallowing production pushes into a test sink) is exactly the
	// quiet misbehavior the boot log exists to prevent. §14's
	// malformed-env fallback covers VALUES of limits with safe defaults;
	// these are transport modes.
	fatal := func(msg string, args ...any) {
		logger.Error(msg, args...)
		os.Exit(1)
	}
	if (*tlsCert == "") != (*tlsKey == "") {
		fatal("tls config invalid: -tls-cert and -tls-key go together (both or neither)")
	}
	apnsSlots := map[string]string{
		"apns-key-file": *apnsKeyFile,
		"apns-key-id":   *apnsKeyID,
		"apns-team-id":  *apnsTeamID,
		"apns-topic":    *apnsTopic,
	}
	var apnsMissing []string
	apnsSet := 0
	for name, v := range apnsSlots {
		if v == "" {
			apnsMissing = append(apnsMissing, name)
		} else {
			apnsSet++
		}
	}
	if apnsSet > 0 && apnsSet < len(apnsSlots) {
		// The error names the missing SLOT NAMES only — never values.
		sort.Strings(apnsMissing)
		fatal("apns config invalid: all four apns slots go together",
			"missing", strings.Join(apnsMissing, ","))
	}
	apnsOn := apnsSet == len(apnsSlots)
	fcmOn := *fcmSAFile != ""
	if *pushSink != "" && (apnsOn || fcmOn) {
		fatal("push config invalid: -push-sink is test-only and cannot be combined with real push credentials")
	}

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
		TLSCert:          *tlsCert,
		TLSKey:           *tlsKey,
		Version:          version,
	}

	// Push transport selection (§27): the test sink, or the Router over
	// whichever real transports are configured (one-platform deployments
	// are legal — the missing platform's dispatches drop silently), or
	// push-less. Credential files must parse at boot: a relay that
	// discovers its key is garbage at first dispatch has been silently
	// push-less all along.
	switch {
	case *pushSink != "":
		cfg.Push = push.NewHTTPSink(*pushSink)
	case apnsOn || fcmOn:
		var apnsSender, fcmSender push.Sender
		if apnsOn {
			// -apns-sandbox overrides the production host so dev-build
			// (aps-environment=development) tokens route to Apple's sandbox
			// (S15). Empty BaseURL keeps the production default.
			apnsBaseURL := ""
			if *apnsSandbox {
				apnsBaseURL = push.APNsSandboxBaseURL
			}
			s, err := push.NewAPNs(push.APNsConfig{
				KeyFile: *apnsKeyFile,
				KeyID:   *apnsKeyID,
				TeamID:  *apnsTeamID,
				Topic:   *apnsTopic,
				BaseURL: apnsBaseURL,
			})
			if err != nil {
				// The error may name the configured path (operator
				// config) — never key material.
				fatal("apns config invalid", "err", err.Error())
			}
			apnsSender = s
		}
		if fcmOn {
			s, err := push.NewFCM(push.FCMConfig{SAFile: *fcmSAFile})
			if err != nil {
				fatal("fcm config invalid", "err", err.Error())
			}
			fcmSender = s
		}
		cfg.Push = push.NewRouter(apnsSender, fcmSender)
	}

	// Boot config summary (note §19, §24): limit values, listener
	// addresses, TLS on/off with the configured PATHS (config values,
	// never file contents), and the push mode class — never credentials.
	tlsMode := "off"
	if *tlsCert != "" {
		tlsMode = "on"
	}
	logger.Info("config",
		"listen", *listen,
		"metrics_listen", *metricsListen,
		"tls", tlsMode,
		"tls_cert", *tlsCert,
		"tls_key", *tlsKey,
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
		"push_mode", pushMode(*pushSink != "", apnsOn, fcmOn),
		"debug_trace", *debugTrace,
	)

	srv := server.New(cfg, logger)
	if err := srv.Run(ctx); err != nil {
		logger.Error("relay exited", "err", err)
		os.Exit(1)
	}
}

// pushMode names the push configuration class for the boot log — the
// fixed §24 enumeration push-less|sink|apns|fcm|apns+fcm, never a URL or
// path: the config summary stays fixed-shape (note §19 — fixed fields
// only, no free-form values). Sink + credentials is boot-fatal before
// this runs, so the arms are exclusive.
func pushMode(sink, apns, fcm bool) string {
	switch {
	case sink:
		return "sink"
	case apns && fcm:
		return "apns+fcm"
	case apns:
		return "apns"
	case fcm:
		return "fcm"
	}
	return "push-less"
}
