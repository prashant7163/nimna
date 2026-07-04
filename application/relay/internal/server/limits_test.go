package server

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/metrics"
	"nimna.app/relay/internal/wire"
)

// series reads one exposition line's value through the public metrics
// surface (counters are deliberately unexported). key is the full series
// name incl. any label, e.g. `limit_trips_total{limit="idle"}`.
func series(t *testing.T, s *Server, key string) string {
	t.Helper()
	var buf bytes.Buffer
	metrics.Write(&buf, s.Metrics(), s.Gauges())
	prefix := "nimna_relay_" + key + " "
	for _, line := range strings.Split(buf.String(), "\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimPrefix(line, prefix)
		}
	}
	t.Fatalf("series %q missing from exposition", key)
	return ""
}

func waitSeries(t *testing.T, s *Server, key, want string) {
	t.Helper()
	for i := 0; i < deadTopicPolls; i++ {
		if series(t, s, key) == want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("series %q never reached %s (at %s)", key, want, series(t, s, key))
}

// rawZeroByteProbe dials addr and asserts the §16 refusal shape: the
// connection closes with ZERO bytes received.
func rawZeroByteProbe(t *testing.T, addr string) {
	t.Helper()
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	_ = c.SetReadDeadline(time.Now().Add(recvTimeout))
	n, err := c.Read(make([]byte, 64))
	if n != 0 {
		t.Fatalf("over-cap connect received %d bytes, want 0", n)
	}
	if err != io.EOF {
		t.Fatalf("over-cap connect: read err %v, want EOF", err)
	}
}

// TestPerIPCapCoveringEmptyVsLoaded is note §16's covering test: drive an
// IP to cap against an empty relay and against one holding registered
// topics, a bridged pair, and a pending knock; the over-cap connect sees
// a connection close with zero bytes received in BOTH worlds — the
// refusal is a pure function of the IP key's live-connection count and no
// Nimna registry state — and under-cap connects are unaffected.
func TestPerIPCapCoveringEmptyVsLoaded(t *testing.T) {
	// World 1: empty relay at cap 3 — three idle TCP conns, nothing
	// registered.
	urlEmpty, _ := newRelayServe(t, Config{MaxConnsPerIP: 3})
	addrEmpty := strings.TrimPrefix(urlEmpty, "ws://")
	for i := 0; i < 3; i++ {
		c, err := net.Dial("tcp", addrEmpty)
		if err != nil {
			t.Fatalf("filler dial %d: %v", i, err)
		}
		t.Cleanup(func() { _ = c.Close() })
	}
	rawZeroByteProbe(t, addrEmpty)

	// World 2: loaded relay at cap 3 — a waiting topic, a bridged
	// topic, a registered CRID with a pending knock, all live.
	urlBusy, sBusy := newRelayServe(t, Config{MaxConnsPerIP: 3})
	addrBusy := strings.TrimPrefix(urlBusy, "ws://")
	w := dial(t, urlBusy)
	w.send(wire.Encode(wire.RegisterTopic, topicBytes(0x71), nil))
	a := dial(t, urlBusy)
	b := dial(t, urlBusy)
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x72), nil))
	b.send(wire.Encode(wire.RegisterTopic, topicBytes(0x72), nil))
	a.expectFrame() // TOPIC_BRIDGED
	b.expectFrame()
	rid := cridBytes(0x73)
	registerCRID(a, rid)
	registerCRID(b, rid)
	a.send(wire.Encode(wire.Knock, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("KNOCK_FWD: got % x", got)
	}
	waitTopicCount(t, sBusy, 2)
	waitPendingCount(t, sBusy, 1)

	// The over-cap probe sees the identical zero-byte close.
	rawZeroByteProbe(t, addrBusy)

	// Relay state undisturbed; under-cap connects unaffected: freeing a
	// slot admits a fresh connection that serves normally.
	waitTopicCount(t, sBusy, 2)
	_ = w.ws.CloseNow()
	waitTopicCount(t, sBusy, 1)
	c := dial(t, urlBusy)
	c.send(wire.Encode(wire.RegisterTopic, topicBytes(0x74), nil))
	waitTopicCount(t, sBusy, 2)
	if got := series(t, sBusy, `limit_trips_total{limit="conn_ip"}`); got != "1" {
		t.Errorf("conn_ip trips: got %s, want 1", got)
	}
}

// TestFrameRatePacing pins §16's frame-rate outcome: BACKPRESSURE — every
// frame of an over-burst burst is delivered (no drop, no close, no error
// bytes), just paced at the configured rate.
func TestFrameRatePacing(t *testing.T) {
	url, s := newRelayWith(t, Config{FrameRate: 20, FrameBurst: 2})
	rid := topicBytes(0x75)

	a := dial(t, url)
	b := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	b.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.expectFrame()
	b.expectFrame()

	// 6 back-to-back PAIR_DATA on top of the REGISTER already read: at
	// burst 2 and 20/s the tail is paced ~50ms per frame.
	start := time.Now()
	var want [][]byte
	for i := 0; i < 6; i++ {
		f := wire.Encode(wire.PairData, rid, []byte(fmt.Sprintf("paced %d", i)))
		want = append(want, f)
		a.send(f)
	}
	for i, w := range want {
		if got := b.expectFrame(); !bytes.Equal(got, w) {
			t.Fatalf("frame %d: got % x, want % x (pacing must not drop or reorder)", i, got, w)
		}
	}
	if elapsed := time.Since(start); elapsed < 150*time.Millisecond {
		t.Fatalf("6 over-burst frames delivered in %v — pacing did not engage", elapsed)
	}
	if got := series(t, s, `limit_trips_total{limit="frame_rate"}`); got == "0" {
		t.Error("frame_rate trips: got 0, want >0")
	}
	// The sender's connection is alive and unharmed.
	a.send(wire.Encode(wire.PairData, rid, []byte("alive")))
	b.expectFrame()
}

// TestConfiguredMaxFrame pins the configurable frame bound: a message at
// exactly the bound passes (valid frame, silently dropped on unbridged
// state); one byte over closes bare (§16: pure function of the received
// bytes).
func TestConfiguredMaxFrame(t *testing.T) {
	url, s := newRelayWith(t, Config{MaxFrame: 1024})

	a := dial(t, url)
	at := wire.Encode(wire.PairData, topicBytes(0x76), make([]byte, 1024-wire.HeaderLen))
	if len(at) != 1024 {
		t.Fatalf("fixture: frame is %d bytes", len(at))
	}
	a.send(at)
	a.expectSilence()

	over := wire.Encode(wire.PairData, topicBytes(0x76), make([]byte, 1024-wire.HeaderLen+1))
	a.send(over)
	a.expectSilentClose()
	waitSeries(t, s, `limit_trips_total{limit="frame_size"}`, "1")
	waitSeries(t, s, `closes_total{class="oversize"}`, "1")
}

// TestRendezvousThrottle pins the §16 rendezvous outcome behaviorally: a
// throttled REGISTER_TOPIC is byte-identical silence AND takes no state —
// the would-be bridge never fires. Limit 3/min for the shared test IP:
// A's two registrations plus B's first fit; B's second frame is dropped.
func TestRendezvousThrottle(t *testing.T) {
	url, s := newRelayWith(t, Config{RendezvousPerMin: 3})
	t1, t2 := topicBytes(0x77), topicBytes(0x78)

	a := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, t1, nil))
	a.send(wire.Encode(wire.RegisterTopic, t2, nil))
	waitTopicCount(t, s, 2)

	b := dial(t, url)
	// Frame 3 within the limit: bridges t1 normally.
	b.send(wire.Encode(wire.RegisterTopic, t1, nil))
	if got := b.expectFrame(); !bytes.Equal(got, bridgedFrame(t1)) {
		t.Fatalf("in-limit bridge: got % x", got)
	}
	a.expectFrame()

	// Frame 4 over the limit: dropped BEFORE the registry — t2 has a
	// waiting registrant, so an accepted registration would bridge;
	// silence proves the drop, and the registrant hears nothing either.
	b.send(wire.Encode(wire.RegisterTopic, t2, nil))
	b.expectSilence()
	a.expectSilence()
	if got := series(t, s, `limit_trips_total{limit="rendezvous"}`); got != "1" {
		t.Errorf("rendezvous trips: got %s, want 1", got)
	}
}

// TestRegistrationCapBothPlanes pins the per-conn/per-plane cap (§14
// default 256, here 2): over-cap registrations are silently dropped with
// no state kept; re-registration of a held identifier stays idempotent;
// deliver-on-register does NOT fire for a dropped REGISTER_CRID (§16).
func TestRegistrationCapBothPlanes(t *testing.T) {
	url, s := newRelayWith(t, Config{MaxRegsPerConn: 2})

	// Topic plane.
	a := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x79), nil))
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x7A), nil))
	waitTopicCount(t, s, 2)
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x7B), nil)) // over cap: dropped
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x79), nil)) // held: idempotent, not capped
	a.expectSilence()
	if got := s.topics.Len(); got != 2 {
		t.Fatalf("topic Len: got %d, want 2 (over-cap registration kept no state)", got)
	}

	// CRID plane, including the deliver-on-register leg: k holds a
	// pending knock on c3; a is at cap, so its REGISTER_CRID for c3 is
	// dropped and no KNOCK_FWD arrives.
	c1, c2, c3 := cridBytes(0x7C), cridBytes(0x7D), cridBytes(0x7E)
	k := dial(t, url)
	registerCRID(k, c3)
	k.send(wire.Encode(wire.Knock, c3, nil))
	waitPendingCount(t, s, 1)

	registerCRID(a, c1)
	registerCRID(a, c2)
	waitChannelCount(t, s, 3)
	a.send(wire.Encode(wire.RegisterCRID, c3, nil)) // over cap: dropped
	a.expectSilence()                               // in particular: no KNOCK_FWD
	waitChannelCount(t, s, 3)
	if got := series(t, s, `limit_trips_total{limit="reg_cap"}`); got != "2" {
		t.Errorf("reg_cap trips: got %s, want 2 (one per plane)", got)
	}
}

// TestKnockCollapseAtWire drives spec §4's knock collapse over real
// WebSockets: duplicates inside the window are dropped silently — no
// KNOCK_FWD, no error, the pending untouched — and the window reopens
// after the interval.
func TestKnockCollapseAtWire(t *testing.T) {
	const window = 1500 * time.Millisecond
	url, s := newRelayWith(t, Config{KnockInterval: window})
	rid := cridBytes(0x80)

	a := dial(t, url)
	registerCRID(a, rid)
	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)

	start := time.Now()
	a.send(wire.Encode(wire.Knock, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("first knock KNOCK_FWD: got % x", got)
	}

	// Duplicate inside the window: silence on every wire, pending
	// still held from the first knock.
	a.send(wire.Encode(wire.Knock, rid, nil))
	b.expectSilence()
	a.expectSilence()
	if got := s.channels.PendingCount(); got != 1 {
		t.Fatalf("pending count after collapsed knock: got %d, want 1", got)
	}
	if got := series(t, s, `limit_trips_total{limit="knock_collapse"}`); got != "1" {
		t.Errorf("knock_collapse trips: got %s, want 1", got)
	}

	// Past the window: the knock forwards again.
	time.Sleep(window - time.Since(start) + 100*time.Millisecond)
	a.send(wire.Encode(wire.Knock, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("post-window knock: got % x", got)
	}
}

// TestPushMinIntervalAtWire drives spec §4's push floor over real
// WebSockets: the second eligible offline knock inside the 60s push
// window is processed normally — pending set, total silence — but the
// dispatch is suppressed (§16: the caps limit platform-push forwarding,
// not knocks).
func TestPushMinIntervalAtWire(t *testing.T) {
	sender := newCountingSender()
	url, s := newRelayServe(t, Config{
		Push:            sender,
		KnockInterval:   time.Nanosecond, // collapse out of the way
		PushMinInterval: time.Hour,       // unreachable in-test
	})
	rid := cridBytes(0x81)

	a := dial(t, url)
	registerCRID(a, rid)
	payload := wire.EncodeKnockPayload(wire.PlatformAPNs, []byte{0xAA, 0xBB})
	a.send(wire.Encode(wire.Knock, rid, payload))
	sender.waitPush(t)

	a.send(wire.Encode(wire.Knock, rid, payload))
	a.expectSilence() // knock processed, dispatch suppressed, nothing said
	waitPendingCount(t, s, 1)
	if n := sender.count(); n != 1 {
		t.Fatalf("push calls: got %d, want 1 (second suppressed by the 60s floor)", n)
	}
	waitSeries(t, s, `limit_trips_total{limit="push_min"}`, "1")
	waitSeries(t, s, `pushes_total{outcome="refused"}`, "1")
	waitSeries(t, s, `pushes_total{outcome="sent"}`, "1")
}

// TestLivenessAtServer drives §17 end-to-end through Serve with an
// accelerated deadline: WS ping traffic keeps a connection alive well
// past the deadline (pings are inbound bytes — liveness is structural);
// a silent connection is reaped, its registrations unwound, and the
// close is attributed to the idle class.
func TestLivenessAtServer(t *testing.T) {
	const idle = 600 * time.Millisecond // janitor tick = 200ms
	url, s := newRelayServe(t, Config{IdleTimeout: idle})

	silent := dial(t, url)
	silent.send(wire.Encode(wire.RegisterTopic, topicBytes(0x82), nil))
	chatty := dial(t, url)
	chatty.send(wire.Encode(wire.RegisterTopic, topicBytes(0x83), nil))
	waitTopicCount(t, s, 2)

	// Ping every 150ms for 4× the deadline: chatty must survive.
	deadline := time.Now().Add(4 * idle)
	for time.Now().Before(deadline) {
		pctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
		err := chatty.ws.Ping(pctx)
		cancel()
		if err != nil {
			t.Fatalf("ping traffic did not keep the connection alive: %v", err)
		}
		select {
		case <-chatty.closed:
			t.Fatal("pinging connection was reaped")
		case <-time.After(150 * time.Millisecond):
		}
	}

	// The silent connection was reaped meanwhile: closed, unwound,
	// attributed idle. (It sent one frame at t=0 and nothing since —
	// well past 600ms by now.)
	select {
	case <-silent.closed:
	case <-time.After(recvTimeout):
		t.Fatal("silent connection was not reaped")
	}
	waitTopicCount(t, s, 1)
	if got := series(t, s, `limit_trips_total{limit="idle"}`); got != "1" {
		t.Errorf("idle trips: got %s, want 1", got)
	}
	waitSeries(t, s, `closes_total{class="idle"}`, "1")

	// Silence-reap boundary: once chatty stops pinging, it too is
	// reaped — between deadline and deadline+tick.
	select {
	case <-chatty.closed:
	case <-time.After(idle + idle/3 + recvTimeout):
		t.Fatal("idle chatty connection was not reaped after pings stopped")
	}
	waitTopicCount(t, s, 0)
}

// lockedBuf is a goroutine-safe log capture target.
type lockedBuf struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuf) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuf) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// TestPanicRecoverScrub pins §19's scrub concretely: a handler that
// panics with an identifier-bearing value produces ONE log line carrying
// the site and the panic value's Go TYPE only — no identifier bytes, no
// stack, no value rendering — the panic is counted, and the connection
// unwinds through the normal teardown.
func TestPanicRecoverScrub(t *testing.T) {
	logBuf := &lockedBuf{}
	logger := slog.New(slog.NewTextHandler(logBuf, nil))
	s := New(Config{}, logger)
	// A poisoned handler, installed before any connection exists: the
	// panic value CARRIES the identifier wrapper — the scrub must
	// print its type, never its bytes.
	s.handlers[wire.SessionData] = func(c *conn, f wire.Frame, raw []byte) {
		panic(ident.CRIDFromWire(f.RoutingID))
	}
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	url := "ws" + strings.TrimPrefix(ts.URL, "http")

	a := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, topicBytes(0x84), nil))
	waitTopicCount(t, s, 1)

	rid := patternedTopic(0x9D) // distinctive bytes for the leak scan
	a.send(wire.Encode(wire.SessionData, rid, nil))
	a.expectSilentClose()
	waitTopicCount(t, s, 0) // teardown unwound the registration

	out := logBuf.String()
	if !strings.Contains(out, "panic recovered") ||
		!strings.Contains(out, "site=read") ||
		!strings.Contains(out, "type=ident.CRID") {
		t.Fatalf("scrub line missing fixed fields: %q", out)
	}
	hexRID := fmt.Sprintf("%x", rid[:])
	if strings.Contains(strings.ToLower(out), hexRID) {
		t.Fatal("panic log leaks identifier hex")
	}
	if strings.Contains(out, "goroutine") || strings.Contains(out, ".go:") {
		t.Fatal("panic log carries a stack trace at production level")
	}
	if got := series(t, s, `panics_total{site="read"}`); got != "1" {
		t.Errorf("panics{read}: got %s, want 1", got)
	}
	waitSeries(t, s, "connections", "0")
}

// TestGoRecoverLoopRestarts: a panicking janitor/push-worker body is
// scrubbed, counted, and restarted; the loop stops with its context.
func TestGoRecoverLoopRestarts(t *testing.T) {
	s := New(Config{}, nil)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	runs := make(chan struct{}, 16)
	s.goRecoverLoop(ctx, metrics.SiteJanitor, func() {
		runs <- struct{}{}
		panic("poisoned cycle")
	})
	for i := 0; i < 3; i++ {
		select {
		case <-runs:
		case <-time.After(recvTimeout):
			t.Fatalf("loop did not restart after panic %d", i)
		}
	}
	cancel()
	if got := series(t, s, `panics_total{site="janitor"}`); got == "0" {
		t.Error("janitor panics not counted")
	}
}

// TestOpsListener drives §18 through Serve: GET /metrics on the separate
// ops listener serves the identifier-free exposition; every other path
// 404s; the listener dies with the serve context (§22).
func TestOpsListener(t *testing.T) {
	s := New(Config{MetricsAddr: "127.0.0.1:0"}, nil)
	ln, err := newLocalListener()
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()

	var opsAddr string
	for i := 0; i < deadTopicPolls; i++ {
		if opsAddr = s.OpsAddr(); opsAddr != "" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if opsAddr == "" {
		t.Fatal("ops listener never bound")
	}

	resp, err := http.Get("http://" + opsAddr + "/metrics")
	if err != nil {
		t.Fatalf("GET /metrics: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("GET /metrics: status %d", resp.StatusCode)
	}
	if !strings.Contains(string(body), "nimna_relay_connections") ||
		!strings.Contains(string(body), `nimna_relay_limit_trips_total{limit="conn_ip"} 0`) {
		t.Fatalf("exposition missing pinned inventory:\n%s", body)
	}

	for _, path := range []string{"/", "/healthz", "/metrics/sub"} {
		resp, err := http.Get("http://" + opsAddr + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		resp.Body.Close()
		if resp.StatusCode != 404 {
			t.Fatalf("GET %s: status %d, want 404", path, resp.StatusCode)
		}
	}

	// §22: the ops listener shuts down alongside the main one.
	cancel()
	select {
	case <-done:
	case <-time.After(recvTimeout):
		t.Fatal("Serve did not stop")
	}
	if _, err := http.Get("http://" + opsAddr + "/metrics"); err == nil {
		t.Fatal("ops listener survived shutdown")
	}
}
