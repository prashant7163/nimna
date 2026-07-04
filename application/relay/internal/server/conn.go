package server

import (
	"context"
	"sync"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/rendezvous"
	"nimna.app/relay/internal/wire"
)

// conn is one live WebSocket connection: a read loop (runs handleWS's
// goroutine), a writer goroutine draining sendCh, and its own set of topic
// registrations so teardown can unwind them (registrations live only as
// long as their connection, spec §4).
type conn struct {
	srv *Server
	ws  *websocket.Conn

	// remote is held as an unloggable wrapper from the accept boundary
	// on (logging doctrine). Session 5's per-IP limits key on it; it has
	// no other purpose and no way back to the raw address.
	remote ident.RemoteAddr

	ctx    context.Context
	cancel context.CancelFunc
	once   sync.Once

	// sendCh is the bounded outbound queue (cap sendBuf); the writer
	// goroutine is the only code that touches ws write paths.
	sendCh chan []byte

	// mu guards topics; registrations are added on the read goroutine
	// but unwound from whichever goroutine reaches teardown first.
	mu     sync.Mutex
	topics map[ident.Topic]struct{}
}

// readLoop reads, parses, and routes frames until the connection dies.
// Every exit path is a silent teardown: malformed traffic, read errors,
// and context cancellation all look identical from the outside.
func (c *conn) readLoop() {
	defer c.teardown()
	for {
		data, ok := readFrame(c.ctx, c.ws)
		if !ok {
			return
		}
		f, err := wire.Parse(data)
		if err != nil {
			// Structurally malformed (short frame, bad version,
			// unknown type): close, explain nothing.
			return
		}
		c.route(f, data)
	}
}

// route dispatches one valid frame. Types without a registered handler —
// the entire Session 4 channel plane, and relay-emitted types echoed back
// by a client — are silently dropped: valid traffic never closes a
// connection, and the relay never answers what it does not serve.
func (c *conn) route(f wire.Frame, raw []byte) {
	if h, ok := c.srv.handlers[f.Type]; ok {
		h(c, f, raw)
	}
}

// writeLoop is the connection's single writer: it alone drains sendCh
// into the socket. A write error tears the connection down.
func (c *conn) writeLoop() {
	for {
		select {
		case <-c.ctx.Done():
			return
		case frame := <-c.sendCh:
			if err := c.ws.Write(c.ctx, websocket.MessageBinary, frame); err != nil {
				c.teardown()
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
		c.teardown()
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

// teardown ends the connection exactly once, from whichever path gets
// there first: read error, malformed frame, write error, delivery
// overflow, or server shutdown. It unwinds every topic registration the
// connection holds — a bridged topic dies whole with this end; the
// survivor gets no signal because §5.4 defines none (clients detect via
// their own handshake timeout, fail-closed per §3.1.6) — and closes the
// socket with a bare CloseNow. Relay code never sends a close frame
// carrying reason text or a Nimna-state-dependent status; the only close
// frames with text are the WebSocket library's own RFC 6455
// transport-compliance closes (1002), whose bytes are a fixed function of
// the sender's malformed transport input and carry no Nimna identifier or
// state (architecture note §5.1).
func (c *conn) teardown() {
	c.once.Do(func() {
		c.cancel()

		c.mu.Lock()
		held := make([]ident.Topic, 0, len(c.topics))
		for t := range c.topics {
			held = append(held, t)
		}
		c.mu.Unlock()
		for _, t := range held {
			c.srv.topics.Drop(t, c)
		}

		_ = c.ws.CloseNow()
	})
}

// handleRegisterTopic implements REGISTER_TOPIC (0x01). Registration
// always succeeds silently (spec §3.1.6) — there is no ack frame, so
// waiting, bridging-the-peer, and being ignored are indistinguishable to
// the sender. The relay routes on the 18-byte header alone (spec §5.4)
// and never inspects the payload.
func handleRegisterTopic(c *conn, f wire.Frame, _ []byte) {
	topic := ident.TopicFromWire(f.RoutingID)
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
		to.send(raw)
	}
}
