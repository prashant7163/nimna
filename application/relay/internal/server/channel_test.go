package server

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/push"
	"nimna.app/relay/internal/wire"
)

// Wire-level coverage of the architecture note §10 edge table (rows named
// TestRowNN…); the state-machine legs live in internal/channel. These
// tests drive real WebSocket connections against an in-process Server.

func cridBytes(b byte) [16]byte {
	var rid [16]byte
	rid[0] = b
	rid[15] = 0xCC
	return rid
}

func knockFwdFrame(rid [16]byte) []byte       { return wire.Encode(wire.KnockFwd, rid, nil) }
func sessionBridgedFrame(rid [16]byte) []byte { return wire.Encode(wire.SessionBridged, rid, nil) }
func teardownFrame(rid [16]byte) []byte       { return wire.Encode(wire.Teardown, rid, nil) }

// countingSender is an in-process push.Sender recording every dispatch.
type countingSender struct {
	mu    sync.Mutex
	calls []wire.Platform
	sent  chan struct{}
}

func newCountingSender() *countingSender {
	return &countingSender{sent: make(chan struct{}, 64)}
}

func (s *countingSender) Send(_ context.Context, platform wire.Platform, _ ident.DeviceToken) error {
	s.mu.Lock()
	s.calls = append(s.calls, platform)
	s.mu.Unlock()
	s.sent <- struct{}{}
	return nil
}

func (s *countingSender) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.calls)
}

// waitPush waits for the next asynchronous dispatch to complete.
func (s *countingSender) waitPush(t *testing.T) {
	t.Helper()
	select {
	case <-s.sent:
	case <-time.After(recvTimeout):
		t.Fatal("timed out waiting for a push dispatch")
	}
}

// newRelayServe starts a full relay via Serve on an ephemeral listener —
// unlike newRelay it also runs the registry janitors and the push
// dispatcher worker.
func newRelayServe(t *testing.T, cfg Config) (string, *Server) {
	t.Helper()
	s := New(cfg, nil)
	ln, err := newLocalListener()
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(recvTimeout):
			t.Error("Serve did not stop on context cancel")
		}
	})
	return "ws://" + ln.Addr().String(), s
}

// waitChannelCount polls the CRID registry's identifier-free entry count.
func waitChannelCount(t *testing.T, s *Server, n int) {
	t.Helper()
	for i := 0; i < deadTopicPolls; i++ {
		if s.channels.Len() == n {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("CRID registry never reached %d entries (still %d)", n, s.channels.Len())
}

// waitPendingCount polls the identifier-free pending-knock count.
func waitPendingCount(t *testing.T, s *Server, n int) {
	t.Helper()
	for i := 0; i < deadTopicPolls; i++ {
		if s.channels.PendingCount() == n {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("pending count never reached %d (still %d)", n, s.channels.PendingCount())
}

// register sends REGISTER_CRID and, where the caller needs ordering
// against another connection's traffic, the registry counts provide the
// synchronization points (registration itself is silent).
func registerCRID(c *wsClient, rid [16]byte) {
	c.send(wire.Encode(wire.RegisterCRID, rid, nil))
}

// bridgeCRID drives knocker → KNOCK_FWD → ACCEPT → SESSION_BRIDGED for
// two already-registered clients and asserts every relay frame byte-exact.
func bridgeCRID(t *testing.T, knocker, answerer *wsClient, rid [16]byte) {
	t.Helper()
	knocker.send(wire.Encode(wire.Knock, rid, nil))
	if got := answerer.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("KNOCK_FWD: got % x, want % x", got, knockFwdFrame(rid))
	}
	answerer.send(wire.Encode(wire.Accept, rid, nil))
	want := sessionBridgedFrame(rid)
	if got := knocker.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("knocker SESSION_BRIDGED: got % x, want % x", got, want)
	}
	if got := answerer.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("answerer SESSION_BRIDGED: got % x, want % x", got, want)
	}
}

// TestRow04PayloadIgnoredOnHeaderOnlyTypes: REGISTER_CRID, ACCEPT, and
// TEARDOWN with non-empty payloads are processed on their headers alone —
// exactly as shipped for REGISTER_TOPIC.
func TestRow04PayloadIgnoredOnHeaderOnlyTypes(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(1)
	junk := []byte("ignored payload bytes \x00\xff")

	b := dial(t, url)
	b.send(wire.Encode(wire.RegisterCRID, rid, junk)) // row 4: register with payload
	waitChannelCount(t, s, 1)

	a := dial(t, url)
	registerCRID(a, rid)
	a.send(wire.Encode(wire.Knock, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("KNOCK_FWD after payload-carrying register: got % x", got)
	}

	b.send(wire.Encode(wire.Accept, rid, junk)) // row 4: accept with payload
	want := sessionBridgedFrame(rid)
	if got := a.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("SESSION_BRIDGED: got % x", got)
	}
	if got := b.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("SESSION_BRIDGED: got % x", got)
	}

	a.send(wire.Encode(wire.Teardown, rid, junk)) // row 4: teardown with payload
	if got := b.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("TEARDOWN: got % x", got)
	}
}

// TestRow07MalformedKnockPayloadCloses: a KNOCK payload that is neither
// empty nor a well-formed platform ‖ token_len ‖ token is structurally
// malformed traffic — the connection closes with NO close frame at all
// (bare CloseNow; the silence doctrine's Nimna layer, §5.1). Registration
// state does not matter: the close is a pure function of the bytes.
func TestRow07MalformedKnockPayloadCloses(t *testing.T) {
	url, _ := newRelay(t)
	rid := cridBytes(2)

	cases := []struct {
		name    string
		payload []byte
	}{
		{"platform-only", []byte{0x01}},
		{"platform-plus-one-length-byte", []byte{0x01, 0x00}},
		{"token-len-zero", []byte{0x01, 0x00, 0x00}},
		{"token-shorter-than-len", []byte{0x01, 0x00, 0x05, 0xAA}},
		{"token-longer-than-len", []byte{0x01, 0x00, 0x01, 0xAA, 0xBB}},
		{"platform-0x00", []byte{0x00, 0x00, 0x01, 0xAA}},
		{"platform-0x03", []byte{0x03, 0x00, 0x01, 0xAA}},
	}
	for _, tc := range cases {
		t.Run(tc.name+"-unregistered", func(t *testing.T) {
			c := dial(t, url)
			c.send(wire.Encode(wire.Knock, rid, tc.payload))
			c.expectSilentClose()
		})
		t.Run(tc.name+"-registered", func(t *testing.T) {
			// State-independence: same close whether or not the
			// sender is registered on the CRID.
			c := dial(t, url)
			registerCRID(c, rid)
			c.send(wire.Encode(wire.Knock, rid, tc.payload))
			c.expectSilentClose()
		})
	}
}

// TestRow08OnlineKnockForwardsStripsTokenNoPush: with the peer online, a
// token-carrying KNOCK produces KNOCK_FWD frames with EMPTY payloads (the
// strip is structural — the relay builds the frame fresh) to every other
// registrant, the knocker hears nothing, and the push sender is never
// called (forward and push are mutually exclusive).
func TestRow08OnlineKnockForwardsStripsTokenNoPush(t *testing.T) {
	sender := newCountingSender()
	url, s := newRelayServe(t, Config{Push: sender})
	rid := cridBytes(3)

	b := dial(t, url)
	registerCRID(b, rid)
	c2 := dial(t, url)
	registerCRID(c2, rid)
	waitChannelCount(t, s, 1)

	a := dial(t, url)
	registerCRID(a, rid)
	token := bytes.Repeat([]byte{0xEE}, 32)
	a.send(wire.Encode(wire.Knock, rid, wire.EncodeKnockPayload(wire.PlatformAPNs, token)))

	// Every registrant except the knocker gets the tokenless KNOCK_FWD.
	for _, cl := range []*wsClient{b, c2} {
		got := cl.expectFrame()
		if !bytes.Equal(got, knockFwdFrame(rid)) {
			t.Fatalf("KNOCK_FWD: got % x, want % x (empty payload)", got, knockFwdFrame(rid))
		}
		if bytes.Contains(got, token) {
			t.Fatal("KNOCK_FWD contains token bytes — the strip must be structural")
		}
	}
	// The knocker hears nothing, and no push was dispatched.
	a.expectSilence()
	if n := sender.count(); n != 0 {
		t.Fatalf("push calls: got %d, want 0 (peer online)", n)
	}
}

// TestRow09OfflineKnockNoTokenTotalSilence: sole registrant knocks with no
// token — the pending is held and NOTHING else happens: no frame to
// anyone, no push, no close. There is no PEER_OFFLINE (§5.4).
func TestRow09OfflineKnockNoTokenTotalSilence(t *testing.T) {
	sender := newCountingSender()
	url, s := newRelayServe(t, Config{Push: sender})
	rid := cridBytes(4)

	a := dial(t, url)
	registerCRID(a, rid)
	a.send(wire.Encode(wire.Knock, rid, nil))
	waitPendingCount(t, s, 1)
	a.expectSilence()
	if n := sender.count(); n != 0 {
		t.Fatalf("push calls: got %d, want 0 (no token)", n)
	}
}

// TestRow10OfflineKnockWithTokenExactlyOnePush: peer offline + token =
// exactly ONE dispatch per knock; the knocker still hears nothing. A
// second valid knock is processed independently at S4 — two knocks are two
// pushes (the 1/10 s collapse is S5).
func TestRow10OfflineKnockWithTokenExactlyOnePush(t *testing.T) {
	sender := newCountingSender()
	url, s := newRelayServe(t, Config{Push: sender})
	rid := cridBytes(5)

	a := dial(t, url)
	registerCRID(a, rid)
	payload := wire.EncodeKnockPayload(wire.PlatformFCM, []byte("device-token-bytes"))
	a.send(wire.Encode(wire.Knock, rid, payload))
	sender.waitPush(t)
	a.expectSilence()
	if n := sender.count(); n != 1 {
		t.Fatalf("push calls: got %d, want exactly 1", n)
	}

	// Row 11 at the wire, S4 semantics: each knock evaluated
	// independently.
	a.send(wire.Encode(wire.Knock, rid, payload))
	sender.waitPush(t)
	if n := sender.count(); n != 2 {
		t.Fatalf("push calls after second knock: got %d, want 2", n)
	}
	waitPendingCount(t, s, 1) // still one pending slot: overwritten, not stacked
}

// TestRow03DeliverOnRegisterAndRow01NoRedelivery: a connection registering
// a CRID that holds an unexpired pending knock immediately receives
// KNOCK_FWD; a duplicate registration delivers nothing again.
func TestRow03DeliverOnRegisterAndRow01NoRedelivery(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(6)

	a := dial(t, url)
	registerCRID(a, rid)
	a.send(wire.Encode(wire.Knock, rid, nil))
	waitPendingCount(t, s, 1)

	// Row 3: deliver-on-register.
	b := dial(t, url)
	registerCRID(b, rid)
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("deliver-on-register KNOCK_FWD: got % x", got)
	}
	// Row 1: duplicate registration is a silent no-op — no re-delivery.
	registerCRID(b, rid)
	b.expectSilence()

	// The delivered knock is fully acceptable.
	b.send(wire.Encode(wire.Accept, rid, nil))
	want := sessionBridgedFrame(rid)
	if got := a.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("knocker SESSION_BRIDGED: got % x", got)
	}
	if got := b.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("registrant SESSION_BRIDGED: got % x", got)
	}
}

// TestRow05KnockFromUnregisteredSilentDrop: a KNOCK (well-formed) from a
// connection not registered on the CRID is silently dropped — the
// connection stays open and usable.
func TestRow05KnockFromUnregisteredSilentDrop(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(7)

	a := dial(t, url)
	a.send(wire.Encode(wire.Knock, rid, nil))
	a.expectSilence()
	if s.channels.Len() != 0 || s.channels.PendingCount() != 0 {
		t.Fatal("a dropped knock must leave no state")
	}
}

// TestRow17And18SessionDataSemantics: SESSION_DATA on an unbridged CRID or
// from a non-member is silently dropped; between bridge members the exact
// received bytes are forwarded verbatim, both directions.
func TestRow17And18SessionDataSemantics(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(8)

	// Unbridged: silent drop, even from a registrant.
	a := dial(t, url)
	registerCRID(a, rid)
	a.send(wire.Encode(wire.SessionData, rid, []byte("early")))
	a.expectSilence()

	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)
	bridgeCRID(t, a, b, rid)

	// Row 18: verbatim both ways — the exact frame bytes.
	s1 := wire.Encode(wire.SessionData, rid, []byte("S1 demo \x00\xff\x01"))
	a.send(s1)
	if got := b.expectFrame(); !bytes.Equal(got, s1) {
		t.Fatalf("A→B: got % x, want verbatim % x", got, s1)
	}
	s2 := wire.Encode(wire.SessionData, rid, []byte("S2 demo"))
	b.send(s2)
	if got := a.expectFrame(); !bytes.Equal(got, s2) {
		t.Fatalf("B→A: got % x, want verbatim % x", got, s2)
	}

	// Row 17: a registered non-member cannot inject into the bridge.
	c := dial(t, url)
	registerCRID(c, rid)
	c.send(wire.Encode(wire.SessionData, rid, []byte("interloper")))
	c.expectSilence()
	a.expectSilence()
	b.expectSilence()
}

// TestRow20TeardownNotifiesOtherOnlyRegsSurvive: a member's TEARDOWN sends
// the relay TEARDOWN to the OTHER member only; both stay registered, so a
// re-knock without re-register still forwards.
func TestRow20TeardownNotifiesOtherOnlyRegsSurvive(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(9)

	a := dial(t, url)
	registerCRID(a, rid)
	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)
	bridgeCRID(t, a, b, rid)

	a.send(wire.Encode(wire.Teardown, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("TEARDOWN to other member: got % x", got)
	}
	a.expectSilence() // the initiator already knows

	// Registrations survived: re-knock without re-register.
	a.send(wire.Encode(wire.Knock, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("re-knock KNOCK_FWD: got % x", got)
	}
}

// TestRow21DisconnectIsImplicitTeardown: a bridge member's death sends the
// survivor the relay TEARDOWN; the survivor's registration survives.
func TestRow21DisconnectIsImplicitTeardown(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(10)

	a := dial(t, url)
	registerCRID(a, rid)
	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)
	bridgeCRID(t, a, b, rid)

	_ = a.ws.CloseNow()
	if got := b.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("implicit TEARDOWN: got % x", got)
	}
	// B's registration survives: its knock is valid and holds a pending.
	b.send(wire.Encode(wire.Knock, rid, nil))
	waitPendingCount(t, s, 1)
	waitChannelCount(t, s, 1)
}

// TestRow22KnockerDeathDeletesPendingLateAcceptSilent: the pending dies
// with the knocker's connection; the already-delivered KNOCK_FWD is not
// retracted, and the late ACCEPT is silently dropped (row 12) — the
// answerer's client times out on its own ("No answer." is client work).
func TestRow22KnockerDeathDeletesPendingLateAcceptSilent(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(11)

	a := dial(t, url)
	registerCRID(a, rid)
	a.send(wire.Encode(wire.Knock, rid, nil))
	waitPendingCount(t, s, 1)

	b := dial(t, url)
	registerCRID(b, rid)
	if got := b.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("KNOCK_FWD: got % x", got)
	}

	_ = a.ws.CloseNow()
	waitPendingCount(t, s, 0)

	b.send(wire.Encode(wire.Accept, rid, nil))
	b.expectSilence()
}

// TestRow23SimultaneousTeardown: after A's TEARDOWN clears the bridge and
// notifies B, B's own TEARDOWN (sent before it could know) is a silent
// drop — tolerating the crossed TEARDOWN is client work.
func TestRow23SimultaneousTeardown(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(12)

	a := dial(t, url)
	registerCRID(a, rid)
	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)
	bridgeCRID(t, a, b, rid)

	a.send(wire.Encode(wire.Teardown, rid, nil))
	if got := b.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("TEARDOWN: got % x", got)
	}
	b.send(wire.Encode(wire.Teardown, rid, nil))
	a.expectSilence()
	b.expectSilence()
}

// TestKeepalivePingMidSession is the §12 covering check at the test level:
// the library auto-pongs while the relay's read loop is in Read, so a
// client Ping completes mid-session with zero relay code — and the bridge
// keeps forwarding afterwards.
func TestKeepalivePingMidSession(t *testing.T) {
	url, s := newRelay(t)
	rid := cridBytes(13)

	a := dial(t, url)
	registerCRID(a, rid)
	b := dial(t, url)
	registerCRID(b, rid)
	waitChannelCount(t, s, 1)
	bridgeCRID(t, a, b, rid)

	for _, cl := range []*wsClient{a, b} {
		ctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
		err := cl.ws.Ping(ctx)
		cancel()
		if err != nil {
			t.Fatalf("ws ping: no pong: %v", err)
		}
	}

	m := wire.Encode(wire.SessionData, rid, []byte("after ping"))
	a.send(m)
	if got := b.expectFrame(); !bytes.Equal(got, m) {
		t.Fatalf("bridge after ping: got % x", got)
	}
}

// TestChannelPlaneEndToEnd is the in-process done-check mirror (note §13):
// pair over the rendezvous plane, disconnect, then the four knock
// scenarios against a real HTTPSink — online knock without token (zero
// sink calls), implicit teardown on disconnect, offline knock with token
// (exactly ONE content-free POST), deliver-on-register, accept, chat,
// explicit teardown, online knock WITH token (still zero further calls) —
// and afterwards the relay's memory is empty: topic entries, CRID
// entries, and pending count all zero.
//
// Connections: k1 knocks online at step 2 and dies; a1 answers step 2,
// survives, and is the knocker for steps 3–4 (either side may knock,
// §3.2); a2 answers step 3 via deliver-on-register. k1's implicit
// TEARDOWN to a1 doubles as the synchronization point proving k1 left the
// registration set — so step 3's knock deterministically finds the CRID
// offline.
func TestChannelPlaneEndToEnd(t *testing.T) {
	rec := &sinkRecorder{}
	sink := httptest.NewServer(rec.handler())
	t.Cleanup(sink.Close)

	url, s := newRelayServe(t, Config{Push: push.NewHTTPSink(sink.URL)})
	topicRID := topicBytes(0x51)
	rid := cridBytes(0x52)

	// Step 1 — pair over the rendezvous plane, then disconnect.
	a := dial(t, url)
	b := dial(t, url)
	a.send(wire.Encode(wire.RegisterTopic, topicRID, nil))
	b.send(wire.Encode(wire.RegisterTopic, topicRID, nil))
	if got := a.expectFrame(); !bytes.Equal(got, bridgedFrame(topicRID)) {
		t.Fatalf("TOPIC_BRIDGED: got % x", got)
	}
	b.expectFrame()
	m4 := wire.Encode(wire.PairData, topicRID, []byte("M4 demo"))
	a.send(m4)
	if got := b.expectFrame(); !bytes.Equal(got, m4) {
		t.Fatalf("PAIR_DATA: got % x", got)
	}
	_ = a.ws.CloseNow()
	_ = b.ws.CloseNow()
	waitTopicCount(t, s, 0)

	// Step 2 — online knock, no token: forward path, zero sink calls.
	a1 := dial(t, url)
	registerCRID(a1, rid)
	waitChannelCount(t, s, 1)
	k1 := dial(t, url)
	registerCRID(k1, rid)
	bridgeCRID(t, k1, a1, rid)
	chat := wire.Encode(wire.SessionData, rid, []byte("hello there"))
	k1.send(chat)
	if got := a1.expectFrame(); !bytes.Equal(got, chat) {
		t.Fatalf("chat: got % x", got)
	}
	reply := wire.Encode(wire.SessionData, rid, []byte("hello back"))
	a1.send(reply)
	if got := k1.expectFrame(); !bytes.Equal(got, reply) {
		t.Fatalf("chat reply: got % x", got)
	}
	// k1 hangs up by disconnecting: implicit TEARDOWN to the survivor —
	// received only after k1 is out of the registration set.
	_ = k1.ws.CloseNow()
	if got := a1.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("implicit TEARDOWN: got % x", got)
	}
	if got := len(rec.snapshot()); got != 0 {
		t.Fatalf("sink calls after online knock: got %d, want 0", got)
	}

	// Step 3 — offline knock with token: a1 (sole registrant now) knocks
	// and draws exactly ONE content-free POST; deliver-on-register then
	// completes the flow.
	token := bytes.Repeat([]byte{0x42}, 32)
	a1.send(wire.Encode(wire.Knock, rid, wire.EncodeKnockPayload(wire.PlatformAPNs, token)))
	waitSinkCalls(t, rec, 1)
	a1.expectSilence()

	a2 := dial(t, url)
	registerCRID(a2, rid)
	if got := a2.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("deliver-on-register KNOCK_FWD: got % x", got)
	}
	a2.send(wire.Encode(wire.Accept, rid, nil))
	want := sessionBridgedFrame(rid)
	if got := a1.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("SESSION_BRIDGED: got % x", got)
	}
	if got := a2.expectFrame(); !bytes.Equal(got, want) {
		t.Fatalf("SESSION_BRIDGED: got % x", got)
	}
	a1.send(chat)
	if got := a2.expectFrame(); !bytes.Equal(got, chat) {
		t.Fatalf("chat: got % x", got)
	}
	// Hang up explicitly: relay TEARDOWN to the other member only.
	a1.send(wire.Encode(wire.Teardown, rid, nil))
	if got := a2.expectFrame(); !bytes.Equal(got, teardownFrame(rid)) {
		t.Fatalf("TEARDOWN: got % x", got)
	}
	a1.expectSilence()

	// Step 4 — online knock WITH token: forwarded (registrations
	// survived the teardown), token discarded, no further sink call.
	a1.send(wire.Encode(wire.Knock, rid, wire.EncodeKnockPayload(wire.PlatformFCM, token)))
	if got := a2.expectFrame(); !bytes.Equal(got, knockFwdFrame(rid)) {
		t.Fatalf("KNOCK_FWD: got % x", got)
	}
	a1.expectSilence()

	// Everyone hangs up: the relay's memory must be EMPTY.
	_ = a1.ws.CloseNow()
	_ = a2.ws.CloseNow()
	waitChannelCount(t, s, 0)
	waitPendingCount(t, s, 0)
	waitTopicCount(t, s, 0)

	// The sink saw exactly one call total — content-free, token only in
	// the addressing header.
	reqs := rec.snapshot()
	if len(reqs) != 1 {
		t.Fatalf("sink calls: got %d, want exactly 1", len(reqs))
	}
	r := reqs[0]
	if r.method != http.MethodPost || r.platform != "apns" {
		t.Fatalf("sink call: method %s platform %q", r.method, r.platform)
	}
	if r.tokenHex != strings.Repeat("42", 32) {
		t.Fatalf("sink token header: got %q", r.tokenHex)
	}
	if !bytes.Equal(r.body, []byte(`{"aps":{"alert":{"loc-key":"NEW_ACTIVITY"}}}`)) {
		t.Fatalf("sink body: got %q, want the pinned content-free constant", r.body)
	}
	if bytes.Contains(r.body, token) || bytes.Contains(r.body, []byte(r.tokenHex)) {
		t.Fatal("sink body contains token bytes")
	}
}

// sinkRecorder captures the HTTPSink's POSTs for the integration test.
type sinkRecorder struct {
	mu   sync.Mutex
	reqs []sinkReq
}

type sinkReq struct {
	method   string
	platform string
	tokenHex string
	body     []byte
}

func (r *sinkRecorder) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		body, _ := io.ReadAll(req.Body)
		r.mu.Lock()
		r.reqs = append(r.reqs, sinkReq{
			method:   req.Method,
			platform: req.Header.Get("Nimna-Push-Platform"),
			tokenHex: req.Header.Get("Nimna-Push-Token"),
			body:     body,
		})
		r.mu.Unlock()
	})
}

func (r *sinkRecorder) snapshot() []sinkReq {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]sinkReq(nil), r.reqs...)
}

func waitSinkCalls(t *testing.T, r *sinkRecorder, n int) {
	t.Helper()
	for i := 0; i < deadTopicPolls; i++ {
		if len(r.snapshot()) == n {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("sink never reached %d calls (still %d)", n, len(r.snapshot()))
}
