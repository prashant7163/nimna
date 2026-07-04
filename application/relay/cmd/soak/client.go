package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

const dialTimeout = 10 * time.Second

// randID mints an opaque random 16-byte routing id (topic or CRID). The
// relay treats both as opaque; the soak driver derives nothing (§21).
func randID() [16]byte {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err) // crypto/rand never fails on supported platforms
	}
	return b
}

// wsc is a minimal test client: one reader goroutine feeding a frame
// channel, mirroring cmd/testclient's shape.
type wsc struct {
	ws     *websocket.Conn
	frames chan wire.Frame
	done   chan struct{}
}

func dialWS(ctx context.Context, relay string) (*wsc, error) {
	dctx, cancel := context.WithTimeout(ctx, dialTimeout)
	defer cancel()
	ws, _, err := websocket.Dial(dctx, relay, nil)
	if err != nil {
		return nil, err
	}
	ws.SetReadLimit(-1)
	c := &wsc{ws: ws, frames: make(chan wire.Frame, 32), done: make(chan struct{})}
	go func() {
		defer close(c.done)
		for {
			typ, data, err := ws.Read(context.Background())
			if err != nil {
				return
			}
			if typ != websocket.MessageBinary {
				continue
			}
			if f, err := wire.Parse(data); err == nil {
				select {
				case c.frames <- f:
				default: // soak never blocks on its own reader
				}
			}
		}
	}()
	return c, nil
}

func (c *wsc) close() { _ = c.ws.CloseNow() }

func (c *wsc) send(ctx context.Context, t wire.FrameType, rid [16]byte, payload []byte) error {
	wctx, cancel := context.WithTimeout(ctx, dialTimeout)
	defer cancel()
	return c.ws.Write(wctx, websocket.MessageBinary, wire.Encode(t, rid, payload))
}

// await waits up to d for a frame of type t on rid.
func (c *wsc) await(t wire.FrameType, rid [16]byte, d time.Duration) bool {
	deadline := time.After(d)
	for {
		select {
		case f, ok := <-c.frames:
			if !ok {
				return false
			}
			if f.Type == t && f.RoutingID == rid {
				return true
			}
		case <-c.done:
			return false
		case <-deadline:
			return false
		}
	}
}

// awaitPayload waits for a data frame on rid and returns its payload.
func (c *wsc) awaitPayload(t wire.FrameType, rid [16]byte, d time.Duration) ([]byte, bool) {
	deadline := time.After(d)
	for {
		select {
		case f, ok := <-c.frames:
			if !ok {
				return nil, false
			}
			if f.Type == t && f.RoutingID == rid {
				return f.Payload, true
			}
		case <-c.done:
			return nil, false
		case <-deadline:
			return nil, false
		}
	}
}

const flowTimeout = 15 * time.Second

// churnOnce is one dial/register/drop cycle.
func churnOnce(ctx context.Context, cfg config, st *stats) {
	c, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("churn dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer c.close()
	if err := c.send(ctx, wire.RegisterCRID, randID(), nil); err != nil {
		st.inc("churn send error")
		return
	}
	st.inc("churn cycles")
	sleepCtx(ctx, 50*time.Millisecond)
}

// pacer spaces REGISTER_TOPIC frames below the relay's per-IP rendezvous
// throttle so soak load measures the relay, not the throttle (which has
// its own abuse probe). Slightly slower than the limit for margin.
type pacer struct {
	mu       sync.Mutex
	interval time.Duration
	next     time.Time
}

func newPacer(perMin int) *pacer {
	if perMin <= 0 {
		perMin = 6
	}
	return &pacer{interval: time.Duration(float64(time.Minute) / (float64(perMin) * 0.9))}
}

// acquire blocks until one REGISTER_TOPIC slot is free (or ctx ends).
func (p *pacer) acquire(ctx context.Context) bool {
	p.mu.Lock()
	now := time.Now()
	at := p.next
	if at.Before(now) {
		at = now
	}
	p.next = at.Add(p.interval)
	p.mu.Unlock()
	select {
	case <-time.After(time.Until(at)):
		return true
	case <-ctx.Done():
		return false
	}
}

// pairFlowOnce drives one full rendezvous flow: two connections register
// one random topic, bridge, exchange PAIR_DATA rounds, drop.
func pairFlowOnce(ctx context.Context, cfg config, st *stats, pc *pacer) {
	if !pc.acquire(ctx) || ctx.Err() != nil {
		return
	}
	topic := randID()
	a, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("pair dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer a.close()
	b, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("pair dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer b.close()

	if a.send(ctx, wire.RegisterTopic, topic, nil) != nil {
		st.inc("pair send error")
		return
	}
	if !pc.acquire(ctx) {
		return
	}
	if b.send(ctx, wire.RegisterTopic, topic, nil) != nil {
		st.inc("pair send error")
		return
	}
	if !a.await(wire.TopicBridged, topic, flowTimeout) || !b.await(wire.TopicBridged, topic, flowTimeout) {
		st.inc("pair bridge timeout (throttle?)")
		return
	}
	for i := 0; i < cfg.rounds; i++ {
		msg := fmt.Appendf(nil, "pair round %d", i)
		if a.send(ctx, wire.PairData, topic, msg) != nil {
			st.inc("pair send error")
			return
		}
		if _, ok := b.awaitPayload(wire.PairData, topic, flowTimeout); !ok {
			st.inc("pair data timeout")
			return
		}
		if b.send(ctx, wire.PairData, topic, msg) != nil {
			st.inc("pair send error")
			return
		}
		if _, ok := a.awaitPayload(wire.PairData, topic, flowTimeout); !ok {
			st.inc("pair data timeout")
			return
		}
	}
	st.inc("pair flows complete")
}

// sessionFlowOnce drives one full channel flow: register → knock →
// KNOCK_FWD → accept → SESSION_BRIDGED → data rounds → TEARDOWN → relay
// TEARDOWN at the peer. With a sink configured, every fourth flow instead
// exercises the offline-knock-with-token path.
var sessionFlowN int64
var sessionFlowMu sync.Mutex

func sessionFlowOnce(ctx context.Context, cfg config, st *stats, sink *pushSink) {
	sessionFlowMu.Lock()
	sessionFlowN++
	offline := sink != nil && sessionFlowN%4 == 0
	sessionFlowMu.Unlock()
	if offline {
		offlineKnockOnce(ctx, cfg, st)
		return
	}

	crid := randID()
	k, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("session dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer k.close()
	a, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("session dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer a.close()

	if k.send(ctx, wire.RegisterCRID, crid, nil) != nil ||
		a.send(ctx, wire.RegisterCRID, crid, nil) != nil {
		st.inc("session send error")
		return
	}
	if k.send(ctx, wire.Knock, crid, nil) != nil {
		st.inc("session send error")
		return
	}
	if !a.await(wire.KnockFwd, crid, flowTimeout) {
		st.inc("session knock timeout")
		return
	}
	if a.send(ctx, wire.Accept, crid, nil) != nil {
		st.inc("session send error")
		return
	}
	if !k.await(wire.SessionBridged, crid, flowTimeout) || !a.await(wire.SessionBridged, crid, flowTimeout) {
		st.inc("session bridge timeout")
		return
	}
	for i := 0; i < cfg.rounds; i++ {
		msg := fmt.Appendf(nil, "session round %d", i)
		if k.send(ctx, wire.SessionData, crid, msg) != nil {
			st.inc("session send error")
			return
		}
		if _, ok := a.awaitPayload(wire.SessionData, crid, flowTimeout); !ok {
			st.inc("session data timeout")
			return
		}
		if a.send(ctx, wire.SessionData, crid, msg) != nil {
			st.inc("session send error")
			return
		}
		if _, ok := k.awaitPayload(wire.SessionData, crid, flowTimeout); !ok {
			st.inc("session data timeout")
			return
		}
	}
	if k.send(ctx, wire.Teardown, crid, nil) != nil {
		st.inc("session send error")
		return
	}
	if !a.await(wire.Teardown, crid, flowTimeout) {
		st.inc("session teardown timeout")
		return
	}
	st.inc("session flows complete")
}

// offlineKnockOnce: a fresh CRID with no other registrant, knocked with a
// random token — the push path (one sink call per eligible knock).
func offlineKnockOnce(ctx context.Context, cfg config, st *stats) {
	crid := randID()
	c, err := dialWS(ctx, cfg.relay)
	if err != nil {
		st.inc("offline dial error")
		sleepCtx(ctx, time.Second)
		return
	}
	defer c.close()
	token := randID()
	if c.send(ctx, wire.RegisterCRID, crid, nil) != nil ||
		c.send(ctx, wire.Knock, crid, wire.EncodeKnockPayload(wire.PlatformFCM, token[:])) != nil {
		st.inc("offline send error")
		return
	}
	st.inc("offline knocks")
	sleepCtx(ctx, 200*time.Millisecond)
}

func sleepCtx(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(d):
	}
}

// pushSink is the soak-hosted push sink: it stands in for the platform
// (which legitimately receives tokens) and counts content-free POSTs.
type pushSink struct {
	ln    net.Listener
	srv   *http.Server
	mu    sync.Mutex
	count int
}

func startSink(addr string) (*pushSink, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	s := &pushSink{ln: ln}
	s.srv = &http.Server{
		ReadHeaderTimeout: 5 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.Copy(io.Discard, io.LimitReader(r.Body, 4096))
			s.mu.Lock()
			s.count++
			s.mu.Unlock()
		}),
	}
	go func() { _ = s.srv.Serve(ln) }()
	return s, nil
}

func (s *pushSink) calls() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.count
}

func (s *pushSink) close() { _ = s.srv.Close() }
