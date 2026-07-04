package push

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
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

const testTimeout = 2 * time.Second

// mockSender records calls and can be gated to simulate a slow transport.
type mockSender struct {
	mu    sync.Mutex
	calls []mockCall
	// gate, when non-nil, blocks every Send until it is closed.
	gate chan struct{}
	// sent signals once per completed Send.
	sent chan struct{}
}

type mockCall struct {
	platform    wire.Platform
	tokenHex    string
	hadDeadline bool
	deadlineIn  time.Duration
}

func newMockSender(gated bool) *mockSender {
	m := &mockSender{sent: make(chan struct{}, 256)}
	if gated {
		m.gate = make(chan struct{})
	}
	return m
}

func (m *mockSender) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	if m.gate != nil {
		select {
		case <-m.gate:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	dl, ok := ctx.Deadline()
	m.mu.Lock()
	m.calls = append(m.calls, mockCall{
		platform:    platform,
		tokenHex:    hex.EncodeToString(token.WireBytes()),
		hadDeadline: ok,
		deadlineIn:  time.Until(dl),
	})
	m.mu.Unlock()
	m.sent <- struct{}{}
	return nil
}

func (m *mockSender) snapshot() []mockCall {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]mockCall(nil), m.calls...)
}

func (m *mockSender) waitSends(t *testing.T, n int) {
	t.Helper()
	for i := 0; i < n; i++ {
		select {
		case <-m.sent:
		case <-time.After(testTimeout):
			t.Fatalf("timed out waiting for send %d of %d", i+1, n)
		}
	}
}

func token(b byte, n int) ident.DeviceToken {
	return ident.DeviceTokenFrom(bytes.Repeat([]byte{b}, n))
}

func runDispatcher(t *testing.T, d *Dispatcher) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		d.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

// TestDispatcherDeliversExactlyOncePerEnqueue: one Enqueue is one Send —
// no duplication, addressing preserved, and each attempt runs under the
// 10 s per-send deadline.
func TestDispatcherDeliversExactlyOncePerEnqueue(t *testing.T) {
	m := newMockSender(false)
	d := NewDispatcher(m, nil, nil)
	runDispatcher(t, d)

	d.Enqueue(wire.PlatformAPNs, token(0xA1, 32))
	d.Enqueue(wire.PlatformFCM, token(0xB2, 64))
	m.waitSends(t, 2)

	// Nothing further arrives: exactly one Send per Enqueue.
	select {
	case <-m.sent:
		t.Fatal("unexpected extra Send")
	case <-time.After(100 * time.Millisecond):
	}

	calls := m.snapshot()
	if len(calls) != 2 {
		t.Fatalf("calls: got %d, want 2", len(calls))
	}
	if calls[0].platform != wire.PlatformAPNs || calls[0].tokenHex != strings.Repeat("a1", 32) {
		t.Fatalf("call 0: got platform %#x token %s", byte(calls[0].platform), calls[0].tokenHex)
	}
	if calls[1].platform != wire.PlatformFCM || calls[1].tokenHex != strings.Repeat("b2", 64) {
		t.Fatalf("call 1: got platform %#x token %s", byte(calls[1].platform), calls[1].tokenHex)
	}
	for i, c := range calls {
		if !c.hadDeadline || c.deadlineIn > sendTimeout {
			t.Fatalf("call %d: want a per-send deadline within %s, got (%v, %s)",
				i, sendTimeout, c.hadDeadline, c.deadlineIn)
		}
	}
}

// TestDispatcherOverflowDropsSilently: with the worker wedged on one send
// and the queue full, further enqueues are dropped — Enqueue never blocks
// and nothing is ever queued beyond the fixed cap.
func TestDispatcherOverflowDropsSilently(t *testing.T) {
	m := newMockSender(true)
	d := NewDispatcher(m, nil, nil)
	runDispatcher(t, d)

	// One job wedges the worker on the gate...
	d.Enqueue(wire.PlatformAPNs, token(0x01, 4))
	// ...then fill the queue to its cap, plus overflow that must drop.
	const overflow = 5
	for i := 0; i < queueCap+overflow; i++ {
		done := make(chan struct{})
		go func() {
			d.Enqueue(wire.PlatformAPNs, token(0x02, 4))
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(testTimeout):
			t.Fatal("Enqueue blocked — it must never block the read goroutine")
		}
	}

	close(m.gate)
	// The wedged job + the full queue drain; the overflow was dropped.
	m.waitSends(t, 1+queueCap)
	select {
	case <-m.sent:
		t.Fatal("overflowed jobs must be dropped, not delivered late")
	case <-time.After(100 * time.Millisecond):
	}
	if got := len(m.snapshot()); got != 1+queueCap {
		t.Fatalf("delivered: got %d, want %d", got, 1+queueCap)
	}
}

// TestDispatcherStopsOnContextCancel: Run returns when its context ends.
func TestDispatcherStopsOnContextCancel(t *testing.T) {
	d := NewDispatcher(newMockSender(false), nil, nil)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		d.Run(ctx)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(testTimeout):
		t.Fatal("Run did not stop on context cancel")
	}
}

// failingSender always fails with the configured error.
type failingSender struct {
	mu   sync.Mutex
	err  error
	sent chan struct{}
}

func (f *failingSender) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	f.mu.Lock()
	err := f.err
	f.mu.Unlock()
	f.sent <- struct{}{}
	return err
}

func (f *failingSender) setErr(err error) {
	f.mu.Lock()
	f.err = err
	f.mu.Unlock()
}

// pushCount reads one pushes_total series through the public exposition
// (the counters are deliberately unexported).
func pushCount(m *metrics.Metrics, outcome string) string {
	var buf bytes.Buffer
	metrics.Write(&buf, m, metrics.Gauges{})
	prefix := `nimna_relay_pushes_total{outcome="` + outcome + `"} `
	for _, line := range strings.Split(buf.String(), "\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimPrefix(line, prefix)
		}
	}
	return "missing"
}

// waitFor polls cond briefly — worker-side counting is asynchronous to
// the test goroutine.
func waitFor(t *testing.T, cond func() bool, msg string) {
	t.Helper()
	for i := 0; i < 200; i++ {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal(msg)
}

// syncBuf is a goroutine-safe log capture target: the worker goroutine
// writes while the test reads.
type syncBuf struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuf) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuf) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func (b *syncBuf) Reset() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.buf.Reset()
}

// TestDispatcherCountsOutcomes: failed attempts are metered, and each
// failure logs ONE fixed-field Warn line carrying platform and HTTP
// status only — no token bytes, no error rendering (note §19).
func TestDispatcherCountsOutcomes(t *testing.T) {
	mtr := metrics.New()
	logBuf := &syncBuf{}
	logger := slog.New(slog.NewTextHandler(logBuf, nil))

	fail := &failingSender{err: &StatusError{Code: 500}, sent: make(chan struct{}, 8)}
	d := NewDispatcher(fail, mtr, logger)
	runDispatcher(t, d)

	d.Enqueue(wire.PlatformAPNs, token(0xC3, 32))
	select {
	case <-fail.sent:
	case <-time.After(testTimeout):
		t.Fatal("no send attempt")
	}
	waitFor(t, func() bool { return pushCount(mtr, "failed") == "1" },
		"failed counter never reached 1")
	waitFor(t, func() bool { return strings.Contains(logBuf.String(), "push transport failure") },
		"failure log line never appeared")

	out := logBuf.String()
	if !strings.Contains(out, "push transport failure") ||
		!strings.Contains(out, "platform=apns") || !strings.Contains(out, "status=500") {
		t.Fatalf("failure log missing fixed fields: %q", out)
	}
	tokenHex := strings.Repeat("c3", 32)
	if strings.Contains(strings.ToLower(out), tokenHex) {
		t.Fatal("failure log leaks token bytes")
	}
	if strings.Contains(out, "transport status") {
		t.Fatalf("failure log carries the error rendering, not fixed fields: %q", out)
	}

	// A non-status transport error (dial-failure class) logs status=0
	// and never its own text.
	logBuf.Reset()
	fail.setErr(context.DeadlineExceeded)
	d.Enqueue(wire.PlatformFCM, token(0x11, 4))
	select {
	case <-fail.sent:
	case <-time.After(testTimeout):
		t.Fatal("no second send attempt")
	}
	waitFor(t, func() bool { return pushCount(mtr, "failed") == "2" },
		"failed counter never reached 2")
	waitFor(t, func() bool { return strings.Contains(logBuf.String(), "platform=fcm") },
		"second failure log line never appeared")
	out = logBuf.String()
	if !strings.Contains(out, "platform=fcm") || !strings.Contains(out, "status=0") {
		t.Fatalf("non-status failure log missing fixed fields: %q", out)
	}
	if strings.Contains(out, "deadline exceeded") {
		t.Fatalf("failure log leaks the error's own rendering: %q", out)
	}
}

// TestDispatcherCountsSentAndDropped: a successful attempt counts sent;
// queue overflow counts dropped at Enqueue time.
func TestDispatcherCountsSentAndDropped(t *testing.T) {
	mtr := metrics.New()
	m := newMockSender(true)
	d := NewDispatcher(m, mtr, nil)
	runDispatcher(t, d)

	d.Enqueue(wire.PlatformAPNs, token(0x01, 4)) // wedges the worker
	// Wait until the worker holds the wedged job (queue drained) so the
	// flood below deterministically fills all queueCap slots.
	waitFor(t, func() bool { return len(d.queue) == 0 },
		"worker never picked up the wedge job")
	for i := 0; i < queueCap+3; i++ {
		d.Enqueue(wire.PlatformAPNs, token(0x02, 4))
	}
	waitFor(t, func() bool { return pushCount(mtr, "dropped") == "3" },
		"dropped counter never reached 3")
	close(m.gate)
	m.waitSends(t, 1+queueCap)
	want := fmt.Sprintf("%d", 1+queueCap)
	waitFor(t, func() bool { return pushCount(mtr, "sent") == want },
		"sent counter never reached 1+queueCap")
}

// TestHTTPSinkStatusError: a non-2xx sink response surfaces as
// *StatusError carrying the code and nothing else — the only push error
// detail the operational log may ever carry.
func TestHTTPSinkStatusError(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(ts.Close)

	err := NewHTTPSink(ts.URL).Send(context.Background(), wire.PlatformAPNs, token(0x01, 4))
	var se *StatusError
	if !errors.As(err, &se) || se.Code != 500 {
		t.Fatalf("Send: got %v, want *StatusError{500}", err)
	}
	if s := se.Error(); strings.Contains(s, ts.URL) {
		t.Fatal("StatusError must not carry the URL")
	}
}

// sinkRecorder captures every request the HTTPSink makes.
type sinkRecorder struct {
	mu   sync.Mutex
	reqs []sinkReq
}

type sinkReq struct {
	method   string
	platform string
	tokenHex string
	ctype    string
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
			ctype:    req.Header.Get("Content-Type"),
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

// TestHTTPSinkContentFreeConstantBody drives the sink directly: per-call
// POST with the addressing headers, the pinned constant body per platform,
// byte-identical bodies across calls, and no token bytes anywhere in the
// body — the auditable content-freeness claim.
func TestHTTPSinkContentFreeConstantBody(t *testing.T) {
	rec := &sinkRecorder{}
	ts := httptest.NewServer(rec.handler())
	t.Cleanup(ts.Close)
	sink := NewHTTPSink(ts.URL)
	ctx := context.Background()

	tok1 := token(0x5A, 32)
	tok2 := token(0x77, 32)
	tokFCM := ident.DeviceTokenFrom([]byte("fcm-token-string-form"))
	if err := sink.Send(ctx, wire.PlatformAPNs, tok1); err != nil {
		t.Fatalf("Send 1: %v", err)
	}
	if err := sink.Send(ctx, wire.PlatformAPNs, tok2); err != nil {
		t.Fatalf("Send 2: %v", err)
	}
	if err := sink.Send(ctx, wire.PlatformFCM, tokFCM); err != nil {
		t.Fatalf("Send 3: %v", err)
	}

	reqs := rec.snapshot()
	if len(reqs) != 3 {
		t.Fatalf("requests: got %d, want 3", len(reqs))
	}
	for i, r := range reqs {
		if r.method != http.MethodPost {
			t.Errorf("request %d: method %s, want POST", i, r.method)
		}
		if r.ctype != "application/json" {
			t.Errorf("request %d: content-type %q", i, r.ctype)
		}
	}

	// Addressing travels ONLY in headers.
	if reqs[0].platform != "apns" || reqs[1].platform != "apns" || reqs[2].platform != "fcm" {
		t.Fatalf("platform headers: %q %q %q", reqs[0].platform, reqs[1].platform, reqs[2].platform)
	}
	if reqs[0].tokenHex != strings.Repeat("5a", 32) || reqs[1].tokenHex != strings.Repeat("77", 32) {
		t.Fatal("token header must be the exact hex of the dispatched token")
	}
	if reqs[2].tokenHex != hex.EncodeToString([]byte("fcm-token-string-form")) {
		t.Fatal("FCM token header must be the exact hex of the dispatched token")
	}

	// Bodies: the pinned constants, byte-identical across pushes.
	if string(reqs[0].body) != apnsBody {
		t.Fatalf("APNs body: got %q, want the pinned constant", reqs[0].body)
	}
	if !bytes.Equal(reqs[0].body, reqs[1].body) {
		t.Fatal("APNs bodies must be byte-identical across pushes")
	}
	if string(reqs[2].body) != fcmBody {
		t.Fatalf("FCM body: got %q, want the pinned constant", reqs[2].body)
	}

	// No token leaks into any body, raw or hex.
	for i, r := range reqs {
		if bytes.Contains(bytes.ToLower(r.body), []byte(strings.ToLower(r.tokenHex))) {
			t.Errorf("request %d: body contains the token hex", i)
		}
	}
	if bytes.Contains(reqs[2].body, []byte("fcm-token-string-form")) {
		t.Error("body contains raw token bytes")
	}
}

// TestBodiesAreContentFreeConstants pins the exact §11 constants: a single
// localization key, no channel, sender, count, or timestamp fields.
func TestBodiesAreContentFreeConstants(t *testing.T) {
	if apnsBody != `{"aps":{"alert":{"loc-key":"NEW_ACTIVITY"}}}` {
		t.Fatal("APNs body drifted from the note §11 pin")
	}
	if fcmBody != `{"message":{"android":{"priority":"high","ttl":"60s","notification":{"title_loc_key":"NEW_ACTIVITY"}}}}` {
		t.Fatal("FCM body drifted from the note §11 pin")
	}
}

// TestHTTPSinkTimeoutRespectsContext: a wedged sink endpoint cannot hold a
// Send past its context.
func TestHTTPSinkTimeoutRespectsContext(t *testing.T) {
	release := make(chan struct{})
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		<-release
	}))
	t.Cleanup(func() {
		close(release)
		ts.Close()
	})

	sink := NewHTTPSink(ts.URL)
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- sink.Send(ctx, wire.PlatformAPNs, token(0x01, 4)) }()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("Send against a wedged endpoint must fail once the context ends")
		}
	case <-time.After(testTimeout):
		t.Fatal("Send did not honor its context")
	}
}
