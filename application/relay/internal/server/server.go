// Package server implements the relay's WebSocket accept loop, connection
// lifecycle, and frame router (architecture note §3, §5), plus the
// Session 5 hardening: limit enforcement wiring, the liveness/per-IP limit
// listener, identifier-free metrics, and the panic recover-and-scrub
// discipline (note §§14–22).
//
// Concurrency model, per connection: one read-loop goroutine plus one
// writer goroutine draining a bounded channel (cap 32). All outbound
// frames pass through that channel; nothing else touches the socket write
// path. Delivery is a non-blocking send: a full buffer closes the peer —
// the relay never queues (spec §4 statelessness), and a slow consumer is
// indistinguishable from a dead one. Teardown runs exactly once
// (sync.Once) from read error, write error, delivery overflow, idle reap,
// or server shutdown, and unwinds every registration the connection holds.
//
// Silence doctrine (scoped to the Nimna layer, where it is absolute —
// architecture note §5.1): structurally malformed traffic (short frame,
// wrong version, unknown frame type, oversize message, non-binary
// WebSocket message, malformed KNOCK payload) closes the connection via
// CloseNow; valid-but-unhandled frame types (relay-emitted go-signals
// echoed back by a client) and every state-dependent rejection are
// silently dropped — a close that depended on registry state would leak
// that state. Every rate-limit outcome is byte-identical silence, a bare
// CloseNow, or a zero-byte accept refusal per note §16's adjudication.
// Relay code never sends a close frame carrying reason text or a
// Nimna-state-dependent status; the only close frames with text are the
// WebSocket library's own RFC 6455 transport-compliance closes (1002),
// whose bytes are a fixed function of the sender's malformed transport
// input and carry no Nimna identifier or state.
//
// Logging is lifecycle-only (started/stopped/config, panic scrubs, push
// transport status) via slog. No topic, CRID, IP, or token ever reaches a
// log: identifier values are wrapped in internal/ident types at the
// boundary where they enter this package. Debug tracing (-debug-trace,
// never in production) keys per-connection events by an opaque
// process-local sequence number only.
package server

import (
	"context"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/channel"
	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/limits"
	"nimna.app/relay/internal/metrics"
	"nimna.app/relay/internal/push"
	"nimna.app/relay/internal/rendezvous"
	"nimna.app/relay/internal/wire"
)

// sendBuf is the per-connection outbound channel capacity (architecture
// note §3). A peer whose buffer is full is closed, never queued for.
const sendBuf = 32

// Frame-plane defaults (architecture note §14; spec-named numbers are
// spec-verbatim, the rest are CODE-pinned boring defaults).
const (
	DefaultFrameRate      = 50  // frames/second, sustained
	DefaultFrameBurst     = 100 // covers a full 5 MB attachment burst
	DefaultMaxRegsPerConn = 256 // per plane; the §10-flagged candidate, decided
)

// Config is the relay's runtime configuration. Spec-verbatim limits and
// TTLs are the defaults; fields exist so deployments can tune what the
// spec marks tunable, and so tests and the soak tool can accelerate by
// shrinking windows (note §14). Zero values mean the defaults.
type Config struct {
	// Addr is the TCP listen address (host:port).
	Addr string
	// TopicTTL caps a topic registration's lifetime per connection.
	// Zero means the spec default, 24 h (spec §4).
	TopicTTL time.Duration
	// PendingKnockTTL is the pending-knock hold. Zero means the spec
	// default, exactly 60 s (spec §3.2 step 3).
	PendingKnockTTL time.Duration
	// Push delivers content-free wakes for offline knocks that carry a
	// token (spec §3.2.1). Nil is the spec-sanctioned push-less mode:
	// such knocks hold their pending and nothing else happens.
	Push push.Sender

	// MaxConnsPerIP caps live connections per canonical IP key
	// (IPv4 exact, IPv6 /64). Default 64.
	MaxConnsPerIP int
	// FrameRate / FrameBurst shape the per-connection frame-rate token
	// bucket: one token per WebSocket message, read-paced (§16 —
	// backpressure, never an error). Defaults 50/s and 100.
	FrameRate  int
	FrameBurst int
	// MaxFrame is the maximum accepted WebSocket message size in bytes.
	// Default 131072 (spec §4: 128 KiB). Values above wire.MaxFrame are
	// still bounded by the wire constant — raising the protocol bound
	// is a wire change, not configuration.
	MaxFrame int
	// RendezvousPerMin caps REGISTER_TOPIC frames per IP key per fixed
	// minute (spec §4 "single-digit attempts per minute"). Default 6.
	RendezvousPerMin int
	// MaxRegsPerConn caps registrations per connection, per plane.
	// Default 256.
	MaxRegsPerConn int
	// KnockInterval is the per-CRID knock collapse window (spec §4:
	// 10 s, duplicates dropped silently). PushMinInterval, PushPerHour,
	// PushPerDay are the per-CRID push caps (spec §4: 60 s / 6 / 20).
	KnockInterval   time.Duration
	PushMinInterval time.Duration
	PushPerHour     int
	PushPerDay      int
	// PushHourWindow / PushDayWindow are the fixed windows behind the
	// hour/day caps — acceleration knobs for tests and soak (§14:
	// "tests and the soak tool accelerate by shrinking the windows via
	// config"); the defaults stay spec (1 h / 24 h).
	PushHourWindow time.Duration
	PushDayWindow  time.Duration
	// IdleTimeout reaps connections with no inbound bytes (WS pings
	// count structurally). Default 90 s = three missed 30 s client
	// pings (§17).
	IdleTimeout time.Duration
	// MetricsAddr is the ops listener address serving GET /metrics
	// (§18). Empty disables. cmd/relay defaults it to 127.0.0.1:9441.
	MetricsAddr string
	// DebugTrace enables per-connection debug tracing (§19). NEVER in
	// production: even structurally identifier-free traces map activity
	// over time.
	DebugTrace bool
}

// frameHandler processes one parsed frame on the receiving connection's
// read goroutine. raw is the exact received frame for verbatim forwarding.
type frameHandler func(c *conn, f wire.Frame, raw []byte)

// Server is the relay. Its complete state is in-memory: the registries,
// the limit tables, the metrics counters, and the live connections'
// goroutines. Nothing is ever at rest.
type Server struct {
	cfg      Config
	log      *slog.Logger
	topics   *rendezvous.Registry[*conn]
	channels *channel.Registry[*conn]
	// push is the bounded dispatcher around cfg.Push; nil in push-less
	// mode. Its worker runs under Serve's context.
	push     *push.Dispatcher
	handlers map[wire.FrameType]frameHandler

	m *metrics.Metrics
	// rates is the per-CRID knock/push rate table; rdvz the per-IP
	// rendezvous window (note §15).
	rates *limits.RateTable
	rdvz  *limits.IPWindow

	// connCount feeds the connections gauge; connSeq mints the opaque
	// per-connection debug-trace ids; opsAddr publishes the bound
	// metrics listener address (tests bind port 0). Shutdown-close
	// attribution needs no server-side flag: each conn reads its own
	// parent-derived context at teardown (see conn.teardown).
	connCount atomic.Int64
	connSeq   atomic.Uint64
	opsAddr   atomic.Value // string
}

// New builds a Server. logger may be nil for silent operation (tests).
func New(cfg Config, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	if cfg.FrameRate <= 0 {
		cfg.FrameRate = DefaultFrameRate
	}
	if cfg.FrameBurst <= 0 {
		cfg.FrameBurst = DefaultFrameBurst
	}
	if cfg.MaxFrame <= 0 {
		cfg.MaxFrame = wire.MaxFrame
	}
	if cfg.MaxRegsPerConn <= 0 {
		cfg.MaxRegsPerConn = DefaultMaxRegsPerConn
	}
	if cfg.IdleTimeout <= 0 {
		cfg.IdleTimeout = limits.DefaultIdleTimeout
	}
	if cfg.MaxConnsPerIP <= 0 {
		cfg.MaxConnsPerIP = limits.DefaultMaxConnsPerIP
	}
	m := metrics.New()
	s := &Server{
		cfg:      cfg,
		log:      logger,
		topics:   rendezvous.New[*conn](cfg.TopicTTL, nil),
		channels: channel.New[*conn](cfg.PendingKnockTTL, nil),
		m:        m,
		rates: limits.NewRateTable(limits.RateConfig{
			KnockInterval:   cfg.KnockInterval,
			PushMinInterval: cfg.PushMinInterval,
			PushPerHour:     cfg.PushPerHour,
			PushPerDay:      cfg.PushPerDay,
			HourWindow:      cfg.PushHourWindow,
			DayWindow:       cfg.PushDayWindow,
		}, nil),
		rdvz: limits.NewIPWindow(cfg.RendezvousPerMin, time.Minute, nil),
	}
	if cfg.Push != nil {
		s.push = push.NewDispatcher(cfg.Push, m, logger)
	}
	// The full §5.4 router: rendezvous plane (S3) + channel plane (S4).
	// The remaining VALID types — relay-emitted go-signals 0x10–0x12
	// echoed back by a client — are absent from this map and silently
	// dropped by route().
	s.handlers = map[wire.FrameType]frameHandler{
		wire.RegisterTopic: handleRegisterTopic,
		wire.PairData:      handlePairData,
		wire.RegisterCRID:  handleRegisterCRID,
		wire.Knock:         handleKnock,
		wire.Accept:        handleAccept,
		wire.Teardown:      handleTeardown,
		wire.SessionData:   handleSessionData,
	}
	return s
}

// Metrics returns the server's instrument (the ops listener scrapes it;
// tests assert on it via the exposition).
func (s *Server) Metrics() *metrics.Metrics { return s.m }

// Gauges snapshots the live identifier-free counts for one scrape.
func (s *Server) Gauges() metrics.Gauges {
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	return metrics.Gauges{
		Connections:    int(s.connCount.Load()),
		Topics:         s.topics.Len(),
		TopicBridges:   s.topics.BridgedCount(),
		CRIDEntries:    s.channels.Len(),
		PendingKnocks:  s.channels.PendingCount(),
		SessionBridges: s.channels.BridgedCount(),
		RateEntries:    s.rates.Len(),
		Goroutines:     runtime.NumGoroutine(),
		HeapAllocBytes: ms.HeapAlloc,
		HeapSysBytes:   ms.HeapSys,
	}
}

// Handler returns the WebSocket accept endpoint (any path). Exposed so
// tests can mount it on ephemeral listeners. Note the janitors, the limit
// listener, the ops listener, and the push worker run only under Serve.
func (s *Server) Handler() http.Handler {
	return http.HandlerFunc(s.handleWS)
}

// Run listens on cfg.Addr and serves until ctx is cancelled, then shuts
// down: no new connections, and every live connection's context is
// cancelled so its teardown runs.
func (s *Server) Run(ctx context.Context) error {
	ln, err := net.Listen("tcp", s.cfg.Addr)
	if err != nil {
		return err
	}
	return s.Serve(ctx, ln)
}

// connKey stashes the limit listener's tracked conn in the request
// context so handleWS reuses its canonical IP key and, at teardown, its
// idle-close attribution.
type connKey struct{}

// Serve serves WebSocket connections on ln until ctx is cancelled. ln is
// wrapped in the limit listener (§17): per-IP cap at the TCP accept
// boundary, liveness deadline, TCP keepalive backstop. S6 ordering,
// pinned: raw TCP → limit listener → tls.NewListener → HTTP.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	lim := limits.NewListener(ln, limits.ListenerConfig{
		MaxConnsPerIP: s.cfg.MaxConnsPerIP,
		IdleTimeout:   s.cfg.IdleTimeout,
		Metrics:       s.m,
	})

	hs := &http.Server{
		Handler: s.Handler(),
		// Request contexts derive from ctx: cancelling it propagates
		// into every live connection's read/write loops.
		BaseContext:       func(net.Listener) context.Context { return ctx },
		ReadHeaderTimeout: 10 * time.Second,
		// The tracked conn rides the request context (idle attribution
		// + canonical IP key). At S6 the TLS conn wraps it; unwrap via
		// NetConn.
		ConnContext: func(cctx context.Context, c net.Conn) context.Context {
			for {
				switch tc := c.(type) {
				case *limits.Conn:
					return context.WithValue(cctx, connKey{}, tc)
				case interface{ NetConn() net.Conn }:
					c = tc.NetConn()
				default:
					return cctx
				}
			}
		},
		// net/http's fallback error logger writes raw client IPs to
		// stderr ("http: panic serving <addr>", and TLS handshake
		// errors at S6), bypassing internal/ident entirely. Relay
		// logging is lifecycle-only and identifier-free by
		// construction, so this internal surface is discarded; our own
		// handler-level recover scrubs and counts panics instead.
		ErrorLog: log.New(io.Discard, "", 0),
	}

	// Long-lived goroutines run under the recover-and-scrub discipline
	// (§19): a panic logs site + panic type only, is counted, and the
	// loop restarts (janitors, push worker) — identifiers can never
	// escape through a panic value's rendering or a stack trace.
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() { s.topics.RunJanitor(ctx) })
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() { s.channels.RunJanitor(ctx) })
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() { s.rates.RunJanitor(ctx) })
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() { s.rdvz.RunJanitor(ctx) })
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() { lim.RunJanitor(ctx) })
	if s.push != nil {
		s.goRecoverLoop(ctx, metrics.SitePush, func() { s.push.Run(ctx) })
	}

	// The ops listener (§18): GET /metrics, everything else 404, plain
	// HTTP, operator-local by default. It shuts down alongside the main
	// listener (§22).
	var ops *http.Server
	var opsLn net.Listener
	if s.cfg.MetricsAddr != "" {
		var err error
		opsLn, err = net.Listen("tcp", s.cfg.MetricsAddr)
		if err != nil {
			return fmt.Errorf("metrics listener: %w", err)
		}
		// The ops handler joins the §19 recover set like every other
		// HTTP surface we own: without this, net/http's own recovery
		// would swallow a scrape-path panic uncounted (its ErrorLog is
		// discarded). Same fixed site label as the WS handler — both
		// are relay-owned HTTP handlers; the enum stays pinned.
		opsHandler := metrics.Handler(s.m, s.Gauges)
		ops = &http.Server{
			Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				defer func() {
					if v := recover(); v != nil {
						s.scrubPanic(metrics.SiteHTTP, v)
					}
				}()
				opsHandler.ServeHTTP(w, r)
			}),
			ReadHeaderTimeout: 10 * time.Second,
			ErrorLog:          log.New(io.Discard, "", 0),
		}
		go func() { _ = ops.Serve(opsLn) }()
		s.opsAddr.Store(opsLn.Addr().String())
		s.log.Info("metrics listening", "addr", opsLn.Addr().String())
	}

	// Lifecycle-only logging: the configured listen address is operator
	// config, not an identifier.
	s.log.Info("relay listening", "addr", lim.Addr().String())

	errc := make(chan error, 1)
	go func() { errc <- hs.Serve(lim) }()

	select {
	case <-ctx.Done():
		// Stop accepting; hijacked WebSocket connections are not
		// tracked by net/http — they die via ctx propagation into
		// their read loops, which runs each teardown (attributed as a
		// shutdown close: the conn's parent-derived context is already
		// done, see conn.teardown — no flag, no ordering race). NO
		// drain: pending knocks and queued pushes are the
		// dies-with-process class (§22).
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = hs.Shutdown(shutdownCtx)
		_ = hs.Close()
		if ops != nil {
			_ = ops.Shutdown(shutdownCtx)
			_ = ops.Close()
		}
		<-errc
		s.log.Info("relay stopped")
		return nil
	case err := <-errc:
		if ops != nil {
			_ = ops.Close()
		}
		return err
	}
}

// OpsAddr reports the bound metrics listener address, empty until Serve
// binds it (tests bind port 0).
func (s *Server) OpsAddr() string {
	if v := s.opsAddr.Load(); v != nil {
		return v.(string)
	}
	return ""
}

// handleWS upgrades one connection and runs its read loop to completion.
func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	defer func() {
		if v := recover(); v != nil {
			s.scrubPanic(metrics.SiteHTTP, v)
		}
	}()

	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		// Not a WebSocket upgrade; Accept already replied at the
		// HTTP layer. Never logged: the request carries an IP.
		return
	}
	// The frame-size limit is a relay-decided policy, so its close must
	// be Nimna-layer silent (§5.1): it is enforced in readFrame with a
	// bare CloseNow. The library's own limiter would send an explanatory
	// close frame (StatusMessageTooBig + reason) from a RELAY policy
	// decision — outside the §5.1 transport carve-out — so it is
	// disabled here.
	ws.SetReadLimit(-1)

	// The canonical IP key comes from the limit listener's tracked conn
	// when present (Serve path — one canonicalization, one key), else
	// from the request address (Handler-only test path).
	tc, _ := r.Context().Value(connKey{}).(*limits.Conn)
	remote := ident.RemoteAddrFrom(r.RemoteAddr)
	if tc != nil {
		remote = tc.RemoteKey()
	}

	ctx, cancel := context.WithCancel(r.Context())
	c := &conn{
		srv:    s,
		ws:     ws,
		tc:     tc,
		remote: remote,
		seq:    s.connSeq.Add(1),
		bucket: limits.NewBucket(float64(s.cfg.FrameRate), s.cfg.FrameBurst, nil),
		ctx:    ctx,
		cancel: cancel,
		sendCh: make(chan []byte, sendBuf),
		topics: make(map[ident.Topic]struct{}),
		crids:  make(map[ident.CRID]struct{}),
	}
	s.m.Conn()
	s.connCount.Add(1)
	defer s.connCount.Add(-1)
	s.trace("conn open", c)
	go c.writeLoop()
	c.readLoop()
	s.trace("conn closed", c)
}

// scrubPanic is §19's recover discipline, concretely: the fixed log line
// carries the component site and the panic value's Go TYPE only — never
// the value's rendering and never a stack trace at production level. The
// ident types redact themselves, but a panic value can carry raw bytes
// from ANY type; the scrub rule assumes nothing about what panicked.
func (s *Server) scrubPanic(site metrics.Site, v any) {
	s.m.Panic(site)
	s.log.Warn("panic recovered", "site", siteName(site), "type", fmt.Sprintf("%T", v))
	if s.cfg.DebugTrace {
		// Debug config may additionally log the stack (§19).
		buf := make([]byte, 8192)
		s.log.Debug("panic stack", "stack", string(buf[:runtime.Stack(buf, false)]))
	}
}

func siteName(site metrics.Site) string {
	switch site {
	case metrics.SiteRead:
		return "read"
	case metrics.SiteWrite:
		return "write"
	case metrics.SiteJanitor:
		return "janitor"
	case metrics.SitePush:
		return "push"
	default:
		return "http"
	}
}

// goRecoverLoop runs f under recover, restarting it after a panic until
// ctx ends (janitors and the push worker must survive a poisoned cycle).
func (s *Server) goRecoverLoop(ctx context.Context, site metrics.Site, f func()) {
	go func() {
		for ctx.Err() == nil {
			func() {
				defer func() {
					if v := recover(); v != nil {
						s.scrubPanic(site, v)
					}
				}()
				f()
			}()
		}
	}()
}

// trace emits one flag-gated debug-trace event (§19): keyed by the opaque
// per-process connection sequence number, never an identifier. The gate
// is the config flag, not the log level, so production builds pay one
// boolean test.
func (s *Server) trace(msg string, c *conn, args ...any) {
	if !s.cfg.DebugTrace {
		return
	}
	s.log.Debug(msg, append([]any{"conn", c.seq}, args...)...)
}

// readResult classifies one readFrame outcome so teardown can attribute
// the close (metrics only — on the wire every close is identical).
type readResult int

const (
	readOK        readResult = iota
	readErrClosed            // transport read error (peer gone, idle reap, shutdown)
	readNonBinary            // structurally malformed: non-binary message
	readOversize             // over the configured frame bound
)

// readFrame reads one WebSocket message, bounded at maxFrame + 1 bytes so
// memory stays bounded without the library's explanatory close.
func readFrame(ctx context.Context, ws *websocket.Conn, maxFrame int) ([]byte, readResult) {
	typ, r, err := ws.Reader(ctx)
	if err != nil {
		return nil, readErrClosed
	}
	if typ != websocket.MessageBinary {
		// Non-binary messages are structurally malformed traffic.
		return nil, readNonBinary
	}
	data, err := io.ReadAll(io.LimitReader(r, int64(maxFrame)+1))
	if err != nil {
		return nil, readErrClosed
	}
	if len(data) > maxFrame {
		return nil, readOversize
	}
	return data, readOK
}
