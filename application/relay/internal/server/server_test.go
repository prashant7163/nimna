package server

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

func newLocalListener() (net.Listener, error) {
	return net.Listen("tcp", "127.0.0.1:0")
}

const (
	recvTimeout    = 2 * time.Second
	silenceWindow  = 300 * time.Millisecond
	deadTopicPolls = 200 // × 10ms
)

// wsClient wraps a client connection with a reader goroutine so tests can
// wait on channels: expecting silence must not kill the connection (a
// cancelled read context would), and a closed connection is observable.
type wsClient struct {
	t      *testing.T
	ws     *websocket.Conn
	frames chan []byte
	closed chan struct{}
	// readErr is the read loop's terminal error, valid after closed.
	readErr error
}

func dial(t *testing.T, url string) *wsClient {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	ws.SetReadLimit(-1)
	c := &wsClient{t: t, ws: ws, frames: make(chan []byte, 16), closed: make(chan struct{})}
	go func() {
		defer close(c.closed)
		for {
			_, data, err := ws.Read(context.Background())
			if err != nil {
				c.readErr = err
				return
			}
			c.frames <- data
		}
	}()
	t.Cleanup(func() { _ = ws.CloseNow() })
	return c
}

func (c *wsClient) send(raw []byte) {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
	defer cancel()
	if err := c.ws.Write(ctx, websocket.MessageBinary, raw); err != nil {
		c.t.Fatalf("write: %v", err)
	}
}

func (c *wsClient) sendText(s string) {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
	defer cancel()
	if err := c.ws.Write(ctx, websocket.MessageText, []byte(s)); err != nil {
		c.t.Fatalf("write text: %v", err)
	}
}

// expectFrame waits for the next frame from the relay.
func (c *wsClient) expectFrame() []byte {
	c.t.Helper()
	select {
	case f := <-c.frames:
		return f
	case <-c.closed:
		c.t.Fatalf("connection closed while expecting a frame (read err: %v)", c.readErr)
	case <-time.After(recvTimeout):
		c.t.Fatal("timed out expecting a frame")
	}
	return nil
}

// expectSilence asserts that NOTHING arrives and the connection stays
// open for the window — the relay's one answer to everything it ignores.
func (c *wsClient) expectSilence() {
	c.t.Helper()
	select {
	case f := <-c.frames:
		c.t.Fatalf("expected silence, got %d-byte frame % x", len(f), f)
	case <-c.closed:
		c.t.Fatalf("expected silence, connection was closed (read err: %v)", c.readErr)
	case <-time.After(silenceWindow):
	}
}

// expectSilentClose asserts the relay closed the connection WITHOUT a
// close frame: no status, no reason — CloseStatus == -1 proves nothing
// explanatory was sent (silence doctrine).
func (c *wsClient) expectSilentClose() {
	c.t.Helper()
	select {
	case f := <-c.frames:
		c.t.Fatalf("expected close, got %d-byte frame % x", len(f), f)
	case <-c.closed:
		if status := websocket.CloseStatus(c.readErr); status != -1 {
			c.t.Fatalf("relay sent a close frame (status %v) — the silence doctrine forbids explaining", status)
		}
	case <-time.After(recvTimeout):
		c.t.Fatal("timed out waiting for the connection to close")
	}
}

func topicBytes(b byte) [16]byte {
	var rid [16]byte
	rid[0] = b
	rid[15] = 0xEE
	return rid
}

func bridgedFrame(rid [16]byte) []byte {
	return wire.Encode(wire.TopicBridged, rid, nil)
}

// newRelay starts a relay on an ephemeral httptest listener and returns
// the ws URL plus the server for white-box registry polling.
func newRelay(t *testing.T) (string, *Server) {
	return newRelayWith(t, Config{})
}

// newRelayWith is newRelay with explicit config — tests exercising S3/S4
// registry semantics under repeated knocks shrink the S5 windows
// (KnockInterval etc.) so the limiter, which has its own tests, stays out
// of their way. Handler-only: no limit listener, no janitors, no ops
// listener (those run under Serve).
func newRelayWith(t *testing.T, cfg Config) (string, *Server) {
	t.Helper()
	s := New(cfg, nil)
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	return "ws" + strings.TrimPrefix(ts.URL, "http"), s
}

// waitTopicCount polls until the registry holds n entries — the only
// honest way to observe a topic's death, since the relay signals nothing.
func waitTopicCount(t *testing.T, s *Server, n int) {
	t.Helper()
	for i := 0; i < deadTopicPolls; i++ {
		if s.topics.Len() == n {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("registry never reached %d entries (still %d)", n, s.topics.Len())
}

// TestRendezvousEndToEnd is the Session 3 spine: register → bridge →
// verbatim PAIR_DATA both ways → death on disconnect → silent fresh
// re-registration (§3.1.6 structural indistinguishability).
func TestRendezvousEndToEnd(t *testing.T) {
	url, s := newRelay(t)
	rid := topicBytes(1)

	a := dial(t, url)
	b := dial(t, url)

	// First registrant waits in silence: no ack frame exists.
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.expectSilence()

	// Second distinct registrant bridges: TOPIC_BRIDGED to BOTH ends,
	// empty payload, routing_id = topic.
	b.send(wire.Encode(wire.RegisterTopic, rid, nil))
	want := bridgedFrame(rid)
	if got := a.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("A TOPIC_BRIDGED: got % x, want % x", got, want)
	}
	if got := b.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("B TOPIC_BRIDGED: got % x, want % x", got, want)
	}

	// PAIR_DATA A→B and B→A, forwarded verbatim: the exact frame bytes.
	m1 := wire.Encode(wire.PairData, rid, []byte("M1 demo bytes \x00\xff"))
	a.send(m1)
	if got := b.expectFrame(); !bytes.Equal(got, m1) {
		t.Fatalf("A→B: got % x, want verbatim % x", got, m1)
	}
	m2 := wire.Encode(wire.PairData, rid, []byte("M2 demo bytes"))
	b.send(m2)
	if got := a.expectFrame(); !bytes.Equal(got, m2) {
		t.Fatalf("B→A: got % x, want verbatim % x", got, m2)
	}

	// Disconnect one end: the topic entry dies whole. The survivor
	// gets no topic-scoped signal (§5.4 defines none).
	_ = a.ws.CloseNow()
	waitTopicCount(t, s, 0)
	b.expectSilence()

	// Survivor's PAIR_DATA on the dead topic: silent drop.
	b.send(wire.Encode(wire.PairData, rid, []byte("into the void")))
	b.expectSilence()

	// A fresh registrant on the same 16 bytes is re-accepted into a
	// fresh waiting entry — no bridge, no error, no tombstone.
	c := dial(t, url)
	c.send(wire.Encode(wire.RegisterTopic, rid, nil))
	c.expectSilence()
	waitTopicCount(t, s, 1)

	// And it can bridge anew.
	d := dial(t, url)
	d.send(wire.Encode(wire.RegisterTopic, rid, nil))
	if got := c.expectFrame(); !bytes.Equal(got, bridgedFrame(rid)) {
		t.Fatalf("fresh bridge to C: got % x", got)
	}
	if got := d.expectFrame(); !bytes.Equal(got, bridgedFrame(rid)) {
		t.Fatalf("fresh bridge to D: got % x", got)
	}
}

// TestThirdRegistrantIgnored: while bridged, a third registrant gets
// nothing, holds nothing, and cannot inject into the bridge.
func TestThirdRegistrantIgnored(t *testing.T) {
	url, _ := newRelay(t)
	rid := topicBytes(2)

	a := dial(t, url)
	b := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	b.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.expectFrame() // TOPIC_BRIDGED
	b.expectFrame() // TOPIC_BRIDGED

	// Third registrant: silence — indistinguishable from acceptance.
	c := dial(t, url)
	c.send(wire.Encode(wire.RegisterTopic, rid, nil))
	c.expectSilence()

	// Its PAIR_DATA is dropped: it is not a member.
	c.send(wire.Encode(wire.PairData, rid, []byte("interloper")))
	c.expectSilence()

	// The bridge is untouched: A↔B still forwards verbatim, and
	// neither member ever saw the interloper's frame.
	m := wire.Encode(wire.PairData, rid, []byte("still here"))
	a.send(m)
	if got := b.expectFrame(); !bytes.Equal(got, m) {
		t.Fatalf("bridge after third registrant: got % x, want % x", got, m)
	}
	a.expectSilence()

	// The third registrant's death does not disturb the bridge.
	_ = c.ws.CloseNow()
	b.send(m)
	if got := a.expectFrame(); !bytes.Equal(got, m) {
		t.Fatalf("bridge after interloper death: got % x", got)
	}
}

// TestMalformedFrameCloses: every structurally malformed NIMNA frame —
// carried in a well-formed WebSocket message, so relay code decides —
// closes the connection with NO close frame at all: no status, no reason,
// no explanation (the Nimna layer of §5.1, where silence is absolute).
// Transport-layer violations, where the library answers before relay code
// runs, are covered by TestTransportComplianceCloses.
func TestMalformedFrameCloses(t *testing.T) {
	url, _ := newRelay(t)

	cases := []struct {
		name string
		send func(c *wsClient)
	}{
		{"empty-frame", func(c *wsClient) { c.send([]byte{}) }},
		{"short-frame-17", func(c *wsClient) { c.send(make([]byte, 17)) }},
		{"bad-version", func(c *wsClient) {
			f := wire.Encode(wire.RegisterTopic, topicBytes(3), nil)
			f[0] = 0x02
			c.send(f)
		}},
		{"unknown-type", func(c *wsClient) {
			f := wire.Encode(wire.RegisterTopic, topicBytes(3), nil)
			f[1] = 0x99
			c.send(f)
		}},
		{"non-binary-message", func(c *wsClient) { c.sendText("hello") }},
		{"oversize-frame", func(c *wsClient) {
			c.send(wire.Encode(wire.PairData, topicBytes(3), make([]byte, wire.MaxFrame-wire.HeaderLen+1)))
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := dial(t, url)
			tc.send(c)
			c.expectSilentClose()
		})
	}
}

// TestUnhandledValidTypeDropped: valid §5.4 traffic never closes a
// connection. Relay-emitted go-signals (0x10–0x12) echoed back by a client
// are unhandled and silently dropped; the channel-plane frames sent here
// are handled since Session 4 but land on state that makes each a silent
// drop (or, for REGISTER_CRID and this conn's own KNOCK, silent
// acceptance) — on the wire every one is identical silence, exactly as in
// Session 3. The connection stays fully usable.
func TestUnhandledValidTypeDropped(t *testing.T) {
	url, _ := newRelay(t)
	rid := topicBytes(4)

	a := dial(t, url)
	for _, ft := range []wire.FrameType{
		wire.RegisterCRID, wire.Knock, wire.Accept, wire.Teardown,
		wire.TopicBridged, wire.KnockFwd, wire.SessionBridged, wire.SessionData,
	} {
		a.send(wire.Encode(ft, rid, nil))
	}
	a.expectSilence()

	// Still alive and serving: the same connection can register and
	// bridge.
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	b := dial(t, url)
	b.send(wire.Encode(wire.RegisterTopic, rid, nil))
	if got := a.expectFrame(); !bytes.Equal(got, bridgedFrame(rid)) {
		t.Fatalf("bridge after dropped frames: got % x", got)
	}
	b.expectFrame()
}

// TestPairDataBeforeBridgeDropped: PAIR_DATA on a waiting or unknown
// topic is silently dropped, even from the waiting registrant.
func TestPairDataBeforeBridgeDropped(t *testing.T) {
	url, _ := newRelay(t)
	rid := topicBytes(5)

	a := dial(t, url)
	// Unknown topic.
	a.send(wire.Encode(wire.PairData, rid, []byte("early")))
	a.expectSilence()
	// Waiting topic, from its own registrant.
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.send(wire.Encode(wire.PairData, rid, []byte("still early")))
	a.expectSilence()
}

// TestRegisterTopicIdempotent: re-registration by the same connection is
// a no-op — a connection never bridges to itself.
func TestRegisterTopicIdempotent(t *testing.T) {
	url, s := newRelay(t)
	rid := topicBytes(6)

	a := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.send(wire.Encode(wire.RegisterTopic, rid, nil))
	a.expectSilence()
	waitTopicCount(t, s, 1)

	// A second connection still bridges normally.
	b := dial(t, url)
	b.send(wire.Encode(wire.RegisterTopic, rid, nil))
	if got := a.expectFrame(); !bytes.Equal(got, bridgedFrame(rid)) {
		t.Fatalf("bridge after idempotent re-register: got % x", got)
	}
	b.expectFrame()
}

// TestDisconnectUnwindsAllRegistrations: a connection registered on many
// topics takes every registration with it.
func TestDisconnectUnwindsAllRegistrations(t *testing.T) {
	url, s := newRelay(t)

	a := dial(t, url)
	for i := byte(10); i < 15; i++ {
		a.send(wire.Encode(wire.RegisterTopic, topicBytes(i), nil))
	}
	waitTopicCount(t, s, 5)

	_ = a.ws.CloseNow()
	waitTopicCount(t, s, 0)
}

// TestServeShutdown: cancelling the serve context stops the relay and
// tears down live connections.
func TestServeShutdown(t *testing.T) {
	s := New(Config{Addr: "127.0.0.1:0"}, nil)
	ctx, cancel := context.WithCancel(context.Background())

	ln, err := newLocalListener()
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()

	url := "ws://" + ln.Addr().String()
	c := dial(t, url)
	c.send(wire.Encode(wire.RegisterTopic, topicBytes(7), nil))
	waitTopicCount(t, s, 1)

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Serve: %v", err)
		}
	case <-time.After(recvTimeout):
		t.Fatal("Serve did not stop on context cancel")
	}
	// The live connection was torn down and unwound.
	select {
	case <-c.closed:
	case <-time.After(recvTimeout):
		t.Fatal("connection not torn down on shutdown")
	}
	waitTopicCount(t, s, 0)
}

// --- Transport-boundary probes (architecture note §5.1) ---------------------
//
// coder/websocket itself emits RFC 6455 compliance closes (status 1002 +
// generic English text) on transport-layer violations — RSV bits set,
// unknown opcode — from internal paths that fire before relay code runs.
// §5.1 accepts these iff they are library-emitted, triggered strictly
// below the Nimna outer frame, and a pure function of the sender's own
// offending transport bytes: INDEPENDENT of all relay state and free of
// identifier bytes. These tests pin every leg of that carve-out.

// patternedTopic returns a distinctive 16-byte routing_id whose bytes (or
// hex) would be recognizable if they ever leaked into a close payload.
func patternedTopic(seed byte) [16]byte {
	var rid [16]byte
	for i := range rid {
		rid[i] = seed + byte(i)*7
	}
	return rid
}

// wsRawHandshake completes a real WebSocket client handshake over raw TCP
// and returns the connection plus a buffered reader positioned after the
// 101 response.
func wsRawHandshake(t *testing.T, addr string) (net.Conn, *bufio.Reader) {
	t.Helper()
	tcp, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("tcp dial: %v", err)
	}
	t.Cleanup(func() { _ = tcp.Close() })
	_ = tcp.SetDeadline(time.Now().Add(recvTimeout))

	_, err = fmt.Fprintf(tcp, "GET / HTTP/1.1\r\n"+
		"Host: %s\r\n"+
		"Connection: Upgrade\r\n"+
		"Upgrade: websocket\r\n"+
		"Sec-WebSocket-Version: 13\r\n"+
		"Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n\r\n", addr)
	if err != nil {
		t.Fatalf("handshake write: %v", err)
	}
	br := bufio.NewReader(tcp)
	status, err := br.ReadString('\n')
	if err != nil {
		t.Fatalf("handshake response: %v", err)
	}
	if !strings.Contains(status, "101") {
		t.Fatalf("handshake: got %q, want 101", strings.TrimSpace(status))
	}
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			t.Fatalf("handshake headers: %v", err)
		}
		if line == "\r\n" {
			return tcp, br
		}
	}
}

// wsProbeClose completes a WebSocket handshake, writes one raw probe
// frame, and returns the server's complete close frame bytes (header +
// payload; server frames are unmasked).
func wsProbeClose(t *testing.T, addr string, probe []byte) []byte {
	t.Helper()
	tcp, br := wsRawHandshake(t, addr)
	if _, err := tcp.Write(probe); err != nil {
		t.Fatalf("probe write: %v", err)
	}
	hdr := make([]byte, 2)
	if _, err := io.ReadFull(br, hdr); err != nil {
		t.Fatalf("reading close header: %v", err)
	}
	if hdr[0] != 0x88 { // FIN + close opcode
		t.Fatalf("response frame: got first byte %#x, want 0x88 (close)", hdr[0])
	}
	if hdr[1]&0x80 != 0 {
		t.Fatal("server close frame must be unmasked")
	}
	n := int(hdr[1] & 0x7f)
	if n >= 126 {
		t.Fatalf("close payload length %d: extended lengths unexpected", n)
	}
	payload := make([]byte, n)
	if _, err := io.ReadFull(br, payload); err != nil {
		t.Fatalf("reading close payload: %v", err)
	}
	return append(hdr, payload...)
}

// TestTransportComplianceCloses drives the §5.1 covering-test spec: raw
// probes with RSV bits set and with an unknown opcode, after a completed
// WebSocket handshake. For each probe it asserts status 1002 with the
// known generic library text and no identifier bytes — and the
// load-bearing assertion: the close bytes are BYTE-IDENTICAL against an
// empty relay and against one holding registered AND bridged topics.
// State-independence is what proves this is not a response surface.
func TestTransportComplianceCloses(t *testing.T) {
	probes := []struct {
		name       string
		frame      []byte
		wantReason string
	}{
		{
			// FIN|RSV1 + binary opcode, masked, empty payload.
			name:       "rsv-bit-set",
			frame:      []byte{0xc2, 0x80, 0x00, 0x00, 0x00, 0x00},
			wantReason: "received header with unexpected rsv bits set: true:false:false",
		},
		{
			// FIN + reserved opcode 0x3, masked, empty payload.
			name:       "unknown-opcode",
			frame:      []byte{0x83, 0x80, 0x00, 0x00, 0x00, 0x00},
			wantReason: "received unknown opcode opcode(3)",
		},
	}

	// Relay 1: empty — no topics, no connections.
	urlEmpty, _ := newRelay(t)
	addrEmpty := strings.TrimPrefix(urlEmpty, "ws://")

	// Relay 2: populated — one waiting registration AND one bridged
	// pair, all on distinctive routing_ids, live through the probes.
	urlBusy, sBusy := newRelay(t)
	addrBusy := strings.TrimPrefix(urlBusy, "ws://")
	waitingRID := patternedTopic(0x35)
	bridgedRID := patternedTopic(0x9c)
	w := dial(t, urlBusy)
	w.send(wire.Encode(wire.RegisterTopic, waitingRID, nil))
	a := dial(t, urlBusy)
	b := dial(t, urlBusy)
	a.send(wire.Encode(wire.RegisterTopic, bridgedRID, nil))
	b.send(wire.Encode(wire.RegisterTopic, bridgedRID, nil))
	a.expectFrame() // TOPIC_BRIDGED
	b.expectFrame() // TOPIC_BRIDGED
	waitTopicCount(t, sBusy, 2)

	for _, p := range probes {
		t.Run(p.name, func(t *testing.T) {
			closeEmpty := wsProbeClose(t, addrEmpty, p.frame)
			closeBusy := wsProbeClose(t, addrBusy, p.frame)

			// Library compliance close: status 1002 + the known
			// generic text, nothing else.
			status := binary.BigEndian.Uint16(closeEmpty[2:4])
			if status != 1002 {
				t.Errorf("close status: got %d, want 1002", status)
			}
			if reason := string(closeEmpty[4:]); reason != p.wantReason {
				t.Errorf("close reason: got %q, want %q", reason, p.wantReason)
			}

			// State-independence — the load-bearing §5.1 property:
			// identical bytes whether the relay is empty or holds
			// registered and bridged topics.
			if !bytes.Equal(closeEmpty, closeBusy) {
				t.Errorf("close bytes depend on relay state:\n empty: % x\n  busy: % x",
					closeEmpty, closeBusy)
			}

			// No identifier bytes in the close payload, raw or hex.
			for _, rid := range [][16]byte{waitingRID, bridgedRID} {
				if bytes.Contains(closeBusy, rid[:]) {
					t.Error("close payload contains raw routing_id bytes")
				}
				h := hex.EncodeToString(rid[:])
				if strings.Contains(string(closeBusy), h) ||
					strings.Contains(string(closeBusy), strings.ToUpper(h)) {
					t.Error("close payload contains hex routing_id")
				}
			}
		})
	}

	// The probes must not have disturbed relay state: the waiting and
	// bridged entries survive, and the bridge still forwards verbatim.
	waitTopicCount(t, sBusy, 2)
	m := wire.Encode(wire.PairData, bridgedRID, []byte("still bridged"))
	a.send(m)
	if got := b.expectFrame(); !bytes.Equal(got, m) {
		t.Fatalf("bridge after transport probes: got % x, want % x", got, m)
	}
}
