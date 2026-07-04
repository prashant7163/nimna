// Package server implements the relay's WebSocket accept loop, connection
// lifecycle, and frame router (architecture note §3, §5).
//
// Concurrency model, per connection: one read-loop goroutine plus one
// writer goroutine draining a bounded channel (cap 32). All outbound
// frames pass through that channel; nothing else touches the socket write
// path. Delivery is a non-blocking send: a full buffer closes the peer —
// the relay never queues (spec §4 statelessness), and a slow consumer is
// indistinguishable from a dead one. Teardown runs exactly once
// (sync.Once) from read error, write error, delivery overflow, or server
// shutdown, and unwinds every topic registration the connection holds.
//
// Silence doctrine (scoped to the Nimna layer, where it is absolute —
// architecture note §5.1): structurally malformed traffic (short frame,
// wrong version, unknown frame type, oversize message, non-binary
// WebSocket message) closes the connection via CloseNow, and
// valid-but-unhandled frame types (the Session 4 channel plane) are
// silently dropped. Relay code never sends a close frame carrying reason
// text or a Nimna-state-dependent status; the only close frames with text
// are the WebSocket library's own RFC 6455 transport-compliance closes
// (1002), whose bytes are a fixed function of the sender's malformed
// transport input and carry no Nimna identifier or state.
//
// Logging is lifecycle-only (started/stopped/config) via slog. No topic,
// CRID, IP, or token ever reaches a log: identifier values are wrapped in
// internal/ident types at the boundary where they enter this package.
package server

import (
	"context"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/rendezvous"
	"nimna.app/relay/internal/wire"
)

// sendBuf is the per-connection outbound channel capacity (architecture
// note §3). A peer whose buffer is full is closed, never queued for.
const sendBuf = 32

// Config is the relay's runtime configuration. Spec-verbatim limits and
// TTLs are the defaults; fields exist so deployments can tune what the
// spec marks tunable.
type Config struct {
	// Addr is the TCP listen address (host:port).
	Addr string
	// TopicTTL caps a topic registration's lifetime per connection.
	// Zero means the spec default, 24 h (spec §4).
	TopicTTL time.Duration
}

// frameHandler processes one parsed frame on the receiving connection's
// read goroutine. raw is the exact received frame for verbatim
// forwarding. Session 4 registers its channel-plane handlers on the same
// router without touching the connection lifecycle.
type frameHandler func(c *conn, f wire.Frame, raw []byte)

// Server is the relay. Its complete state is in-memory: the topic
// registry and the live connections' goroutines. Nothing is ever at rest.
type Server struct {
	cfg      Config
	log      *slog.Logger
	topics   *rendezvous.Registry[*conn]
	handlers map[wire.FrameType]frameHandler
}

// New builds a Server. logger may be nil for silent operation (tests).
func New(cfg Config, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	s := &Server{
		cfg:    cfg,
		log:    logger,
		topics: rendezvous.New[*conn](cfg.TopicTTL, nil),
	}
	// Session 3 router: rendezvous plane only. Any other VALID type is
	// absent from this map and silently dropped by route(); Session 4
	// adds the channel plane here.
	s.handlers = map[wire.FrameType]frameHandler{
		wire.RegisterTopic: handleRegisterTopic,
		wire.PairData:      handlePairData,
	}
	return s
}

// Handler returns the WebSocket accept endpoint (any path). Exposed so
// tests can mount it on ephemeral listeners.
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

// Serve serves WebSocket connections on ln until ctx is cancelled.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	hs := &http.Server{
		Handler: s.Handler(),
		// Request contexts derive from ctx: cancelling it propagates
		// into every live connection's read/write loops.
		BaseContext:       func(net.Listener) context.Context { return ctx },
		ReadHeaderTimeout: 10 * time.Second,
		// net/http's fallback error logger writes raw client IPs to
		// stderr ("http: panic serving <addr>", and TLS handshake
		// errors at S6), bypassing internal/ident entirely. Relay
		// logging is lifecycle-only and identifier-free by
		// construction, so this internal surface is discarded.
		ErrorLog: log.New(io.Discard, "", 0),
	}

	go s.topics.RunJanitor(ctx)

	// Lifecycle-only logging: the configured listen address is operator
	// config, not an identifier.
	s.log.Info("relay listening", "addr", ln.Addr().String())

	errc := make(chan error, 1)
	go func() { errc <- hs.Serve(ln) }()

	select {
	case <-ctx.Done():
		// Stop accepting; hijacked WebSocket connections are not
		// tracked by net/http — they die via ctx propagation into
		// their read loops, which runs each teardown.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = hs.Shutdown(shutdownCtx)
		_ = hs.Close()
		<-errc
		s.log.Info("relay stopped")
		return nil
	case err := <-errc:
		return err
	}
}

// handleWS upgrades one connection and runs its read loop to completion.
func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
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

	ctx, cancel := context.WithCancel(r.Context())
	c := &conn{
		srv:    s,
		ws:     ws,
		remote: ident.RemoteAddrFrom(r.RemoteAddr),
		ctx:    ctx,
		cancel: cancel,
		sendCh: make(chan []byte, sendBuf),
		topics: make(map[ident.Topic]struct{}),
	}
	go c.writeLoop()
	c.readLoop()
}

// readFrame reads one WebSocket message, bounded at wire.MaxFrame + 1
// bytes so memory stays bounded without the library's explanatory close.
// ok=false means the connection must be torn down (read error, non-binary
// message, or oversize) — silently, per the doctrine.
func readFrame(ctx context.Context, ws *websocket.Conn) (data []byte, ok bool) {
	typ, r, err := ws.Reader(ctx)
	if err != nil {
		return nil, false
	}
	if typ != websocket.MessageBinary {
		// Non-binary messages are structurally malformed traffic.
		return nil, false
	}
	data, err = io.ReadAll(io.LimitReader(r, wire.MaxFrame+1))
	if err != nil {
		return nil, false
	}
	if len(data) > wire.MaxFrame {
		return nil, false
	}
	return data, true
}
