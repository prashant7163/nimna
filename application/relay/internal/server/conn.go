package server

import (
	"context"
	"sync"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/limits"
	"nimna.app/relay/internal/metrics"
	"nimna.app/relay/internal/rendezvous"
	"nimna.app/relay/internal/wire"
)

// conn is one live WebSocket connection: a read loop (runs handleWS's
// goroutine), a writer goroutine draining sendCh, and its own sets of
// topic and CRID registrations so teardown can unwind them (registrations
// live only as long as their connection, spec §4). The planes coexist: a
// connection may hold both kinds at once — an app pairing a new channel
// while its existing channels stay knock-reachable is the normal case.
type conn struct {
	srv *Server
	ws  *websocket.Conn

	// tc is the limit listener's tracked conn (nil on the Handler-only
	// test path): its liveness clock ticks under this connection's
	// reads, and its idle flag attributes idle-reap closes.
	tc *limits.Conn

	// remote is the canonicalized per-IP key, held as an unloggable
	// wrapper from the accept boundary on (logging doctrine). The
	// per-IP limits key on it; it has no other purpose and no way back
	// to the raw address.
	remote ident.RemoteAddr

	// seq is the opaque process-local id for debug tracing (§19) —
	// never an identifier, resets every process.
	seq uint64

	// bucket paces reads: one token per WebSocket message (§15/§16 —
	// backpressure, never an error).
	bucket *limits.Bucket

	ctx    context.Context
	cancel context.CancelFunc
	once   sync.Once

	// sendCh is the bounded outbound queue (cap sendBuf); the writer
	// goroutine is the only code that touches ws write paths.
	sendCh chan []byte

	// mu guards the registration sets; registrations are added on the
	// read goroutine but unwound from whichever goroutine reaches
	// teardown first.
	mu     sync.Mutex
	topics map[ident.Topic]struct{}
	crids  map[ident.CRID]struct{}
}

// readLoop reads, parses, and routes frames until the connection dies.
// Every exit path is a silent teardown: malformed traffic, read errors,
// pacing, and context cancellation all look identical from the outside.
// A panic anywhere on the read path is scrubbed (§19: site + type only)
// and unwinds the connection like any other read-side death.
func (c *conn) readLoop() {
	defer func() {
		if v := recover(); v != nil {
			c.srv.scrubPanic(metrics.SiteRead, v)
		}
		// Backstop class; explicit teardown calls on the paths below
		// won the sync.Once first where they ran.
		c.teardown(metrics.CloseReadError)
	}()
	for {
		// Frame-rate pacing (§16): wait for a token BEFORE reading the
		// next message — zero outcome bytes; the sender experiences
		// throughput, never an error.
		if wait := c.bucket.Reserve(); wait > 0 {
			c.srv.m.Trip(metrics.LimitFrameRate)
			c.srv.trace("frame rate pacing", c, "wait", wait)
			t := time.NewTimer(wait)
			select {
			case <-c.ctx.Done():
				t.Stop()
				c.teardown(metrics.CloseReadError)
				return
			case <-t.C:
			}
		}
		data, res := readFrame(c.ctx, c.ws, c.srv.cfg.MaxFrame)
		switch res {
		case readOK:
		case readOversize:
			c.srv.m.Trip(metrics.LimitFrameSize)
			c.teardown(metrics.CloseOversize)
			return
		case readNonBinary:
			c.teardown(metrics.CloseStructural)
			return
		default: // readErrClosed: peer death, idle reap, or shutdown
			c.teardown(metrics.CloseReadError)
			return
		}
		f, err := wire.Parse(data)
		if err != nil {
			// Structurally malformed (short frame, bad version,
			// unknown type): close, explain nothing.
			c.teardown(metrics.CloseStructural)
			return
		}
		c.srv.trace("frame", c, "type", uint8(f.Type))
		c.route(f, data)
	}
}

// route dispatches one valid frame. Types without a registered handler —
// relay-emitted go-signals (0x10–0x12) echoed back by a client — are
// silently dropped: the relay never answers what it does not serve. Valid
// traffic closes a connection in exactly one case: a structurally
// malformed KNOCK payload, a pure function of the received bytes (§9).
func (c *conn) route(f wire.Frame, raw []byte) {
	if h, ok := c.srv.handlers[f.Type]; ok {
		h(c, f, raw)
	}
}

// writeLoop is the connection's single writer: it alone drains sendCh
// into the socket. A write error tears the connection down; a panic is
// scrubbed (§19) and does the same.
func (c *conn) writeLoop() {
	defer func() {
		if v := recover(); v != nil {
			c.srv.scrubPanic(metrics.SiteWrite, v)
			c.teardown(metrics.CloseWriteError)
		}
	}()
	for {
		select {
		case <-c.ctx.Done():
			return
		case frame := <-c.sendCh:
			if err := c.ws.Write(c.ctx, websocket.MessageBinary, frame); err != nil {
				c.teardown(metrics.CloseWriteError)
				return
			}
		}
	}
}

// send queues an outbound frame without ever blocking. A full buffer
// closes this connection: the relay never queues beyond the fixed cap
// (spec §4 statelessness), and a slow consumer is indistinguishable from
// a dead one. Safe to call from any goroutine.
func (c *conn) send(frame []byte) {
	if c.ctx.Err() != nil {
		return
	}
	select {
	case c.sendCh <- frame:
	default:
		c.teardown(metrics.CloseSendOverflow)
	}
}

// addTopic records a registration for teardown unwind. It returns false
// when the connection lost the race with its own teardown — the caller
// must then drop the registration from the registry itself, because
// teardown's sweep has already run.
func (c *conn) addTopic(t ident.Topic) bool {
	c.mu.Lock()
	c.topics[t] = struct{}{}
	c.mu.Unlock()
	// teardown cancels ctx BEFORE sweeping the set; if ctx is still
	// alive here, the sweep (if any ever runs) is guaranteed to see
	// this entry.
	return c.ctx.Err() == nil
}

// addCRID records a CRID registration for teardown unwind, mirroring
// addTopic: add, then check ctx — on a lost race with teardown the caller
// must unwind via DropConn itself, because teardown's sweep has already
// run.
func (c *conn) addCRID(id ident.CRID) bool {
	c.mu.Lock()
	c.crids[id] = struct{}{}
	c.mu.Unlock()
	return c.ctx.Err() == nil
}

// atRegCap reports whether adding one more registration on the given
// plane's set would exceed the per-conn/per-plane cap (§14, default 256).
// An identifier already held is never capped: re-registration stays the
// idempotent no-op it always was. The over-cap outcome is a silent drop —
// registration has no ack, so the drop is byte-identical to acceptance
// (§16).
func (c *conn) topicAtCap(t ident.Topic) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, held := c.topics[t]; held {
		return false
	}
	return len(c.topics) >= c.srv.cfg.MaxRegsPerConn
}

func (c *conn) cridAtCap(id ident.CRID) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, held := c.crids[id]; held {
		return false
	}
	return len(c.crids) >= c.srv.cfg.MaxRegsPerConn
}

// teardown ends the connection exactly once, from whichever path gets
// there first: read error, malformed frame, oversize, write error,
// delivery overflow, idle reap, or server shutdown. The class parameter
// only attributes the close in the aggregate metrics — on the wire every
// teardown is identical. It unwinds BOTH planes' registrations: a bridged
// topic dies whole with this end, and its survivor gets no signal because
// §5.4 defines none for topics (clients detect via their own handshake
// timeout, fail-closed per §3.1.6); on the CRID plane, disconnection is
// an implicit TEARDOWN (§5.4) — a bridge survivor is notified with the
// relay-built TEARDOWN frame, a pending knock from this connection dies
// silently, and each CRID entry dies when its last registration leaves.
// The socket closes with a bare CloseNow. Relay code never sends a close
// frame carrying reason text or a Nimna-state-dependent status; the only
// close frames with text are the WebSocket library's own RFC 6455
// transport-compliance closes (1002), whose bytes are a fixed function of
// the sender's malformed transport input and carry no Nimna identifier or
// state (architecture note §5.1).
func (c *conn) teardown(class metrics.CloseClass) {
	c.once.Do(func() {
		// Metrics attribution refinements, invisible on the wire: a
		// read error on a connection the liveness janitor flagged is an
		// idle close; a read error whose conn context is ALREADY done
		// is a shutdown close. The shutdown check is race-free: at this
		// point c.cancel() has not yet run (it is called just below,
		// inside this same once), so c.ctx.Err() is non-nil only when a
		// parent was cancelled — and for a hijacked WebSocket conn the
		// only parent is Serve's context, i.e. server shutdown.
		if class == metrics.CloseReadError {
			switch {
			case c.tc != nil && c.tc.IdleClosed():
				class = metrics.CloseIdle
			case c.ctx.Err() != nil:
				class = metrics.CloseShutdown
			}
		}
		c.srv.m.Close(class)

		c.cancel()

		c.mu.Lock()
		heldTopics := make([]ident.Topic, 0, len(c.topics))
		for t := range c.topics {
			heldTopics = append(heldTopics, t)
		}
		heldCRIDs := make([]ident.CRID, 0, len(c.crids))
		for id := range c.crids {
			heldCRIDs = append(heldCRIDs, id)
		}
		c.mu.Unlock()
		for _, t := range heldTopics {
			c.srv.topics.Drop(t, c)
		}
		for _, id := range heldCRIDs {
			if survivor, notify := c.srv.channels.DropConn(id, c); notify {
				// Implicit TEARDOWN to the bridge survivor (§3.3:
				// the relay "notifies the peer"); freshly built,
				// empty payload.
				c.srv.m.TeardownImplicit()
				survivor.send(wire.Encode(wire.Teardown, id.WireBytes(), nil))
			}
		}

		_ = c.ws.CloseNow()
	})
}

// handleRegisterTopic implements REGISTER_TOPIC (0x01). Registration
// always succeeds silently (spec §3.1.6) — there is no ack frame, so
// waiting, bridging-the-peer, being throttled, being capped, and being
// ignored are all indistinguishable to the sender. The relay routes on
// the 18-byte header alone (spec §5.4) and never inspects the payload.
//
// Two silent limits gate it (§16): the per-IP rendezvous window (counting
// REGISTER_TOPIC frames only — the throttle impedes code brute-forcing)
// and the per-conn registration cap.
func handleRegisterTopic(c *conn, f wire.Frame, _ []byte) {
	if !c.srv.rdvz.Allow(c.remote) {
		c.srv.m.Trip(metrics.LimitRendezvous)
		c.srv.trace("rendezvous throttled", c)
		return
	}
	topic := ident.TopicFromWire(f.RoutingID)
	if c.topicAtCap(topic) {
		c.srv.m.Trip(metrics.LimitRegCap)
		c.srv.trace("registration cap", c, "plane", "topic")
		return
	}
	peer, outcome := c.srv.topics.Register(topic, c)
	if outcome == rendezvous.Ignored {
		return
	}
	if !c.addTopic(topic) {
		// Teardown already swept this connection's registrations;
		// unwind the one that just slipped in behind it.
		c.srv.topics.Drop(topic, c)
		return
	}
	if outcome == rendezvous.Bridged {
		// TOPIC_BRIDGED to BOTH ends: empty payload, routing_id =
		// topic (spec §5.4). Queued on each end's channel before any
		// PAIR_DATA can follow it there.
		frame := wire.Encode(wire.TopicBridged, topic.WireBytes(), nil)
		peer.send(frame)
		c.send(frame)
	}
}

// handlePairData implements PAIR_DATA (0x20): forwarded verbatim — the
// exact received bytes — iff the topic is bridged and the sender is one
// of its two members. Anything else (unknown topic, waiting topic,
// non-member sender, dead peer) is a silent drop; the payload is opaque
// and never inspected.
func handlePairData(c *conn, f wire.Frame, raw []byte) {
	topic := ident.TopicFromWire(f.RoutingID)
	if to, ok := c.srv.topics.Forward(topic, c); ok {
		c.srv.m.Forwarded(metrics.PlanePair)
		to.send(raw)
	}
}
