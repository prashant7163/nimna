// The CI log-scrub assertion (architecture note §20): build the REAL
// relay binary, run it in PRODUCTION config (no debug flag; limit windows
// shortened via config so every limit path is reachable in seconds),
// drive identifier-bearing traffic through both planes and every limit,
// capture ALL of the process's stdout+stderr, and assert that no known
// identifier — in hex (both cases), base64 (std/URL, padded/raw), or raw
// byte form — and no client address ever appears, plus coarse sweeps for
// anything identifier-shaped. Runs under the plain `go test ./...` CI
// step; never skipped under -short (seconds-fast; the relay derives
// nothing).
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

const scrubTimeout = 10 * time.Second

// --- process harness ---------------------------------------------------

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

// buildRelay compiles the real binary once per test process.
var (
	buildOnce sync.Once
	relayBin  string
	buildErr  error
)

func builtRelay(t *testing.T) string {
	t.Helper()
	buildOnce.Do(func() {
		dir, err := os.MkdirTemp("", "nimna-logscrub-*")
		if err != nil {
			buildErr = err
			return
		}
		relayBin = filepath.Join(dir, "relay")
		cmd := exec.Command("go", "build", "-o", relayBin, ".")
		out, err := cmd.CombinedOutput()
		if err != nil {
			buildErr = fmt.Errorf("go build: %v\n%s", err, out)
		}
	})
	if buildErr != nil {
		t.Fatalf("building relay: %v", buildErr)
	}
	return relayBin
}

type relayProc struct {
	t    *testing.T
	cmd  *exec.Cmd
	out  *lockedBuf
	addr string // bound ws listen address
	ops  string // bound metrics listen address
}

var (
	listenRe  = regexp.MustCompile(`msg="relay listening" addr=([0-9.:]+)`)
	metricsRe = regexp.MustCompile(`msg="metrics listening" addr=([0-9.:]+)`)
)

// startRelay launches the built binary in production config with the
// given extra flags, capturing all stdout+stderr, and waits for both
// listeners to bind.
func startRelay(t *testing.T, extra ...string) *relayProc {
	t.Helper()
	args := append([]string{
		"-listen", "127.0.0.1:0",
		"-metrics-listen", "127.0.0.1:0",
	}, extra...)
	p := &relayProc{t: t, out: &lockedBuf{}}
	p.cmd = exec.Command(builtRelay(t), args...)
	p.cmd.Stdout = p.out
	p.cmd.Stderr = p.out
	if err := p.cmd.Start(); err != nil {
		t.Fatalf("starting relay: %v", err)
	}
	t.Cleanup(func() {
		if p.cmd.ProcessState == nil {
			_ = p.cmd.Process.Kill()
			_, _ = p.cmd.Process.Wait()
		}
	})
	p.addr = p.waitOutputMatch(listenRe)
	p.ops = p.waitOutputMatch(metricsRe)
	return p
}

func (p *relayProc) waitOutputMatch(re *regexp.Regexp) string {
	deadline := time.Now().Add(scrubTimeout)
	for time.Now().Before(deadline) {
		if m := re.FindStringSubmatch(p.out.String()); m != nil {
			return m[1]
		}
		time.Sleep(10 * time.Millisecond)
	}
	p.t.Fatalf("relay output never matched %v; output:\n%s", re, p.out.String())
	return ""
}

// terminate SIGTERMs the relay and waits for the shutdown log lines.
func (p *relayProc) terminate() {
	p.t.Helper()
	if err := p.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		p.t.Fatalf("SIGTERM: %v", err)
	}
	done := make(chan error, 1)
	go func() { done <- p.cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(scrubTimeout):
		p.t.Fatal("relay did not exit on SIGTERM")
	}
}

// scrape GETs one metrics exposition from the ops listener.
func (p *relayProc) scrape() string {
	p.t.Helper()
	resp, err := http.Get("http://" + p.ops + "/metrics")
	if err != nil {
		p.t.Fatalf("scrape: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return string(body)
}

// --- ws driver with local-address recording ------------------------------

// addrRecorder collects every local address our clients used, so the
// scrub can assert none appears in relay output.
type addrRecorder struct {
	mu    sync.Mutex
	addrs []string
}

func (r *addrRecorder) record(c net.Conn) {
	r.mu.Lock()
	r.addrs = append(r.addrs, c.LocalAddr().String())
	r.mu.Unlock()
}

func (r *addrRecorder) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.addrs...)
}

type scrubClient struct {
	t  *testing.T
	ws *websocket.Conn
}

func (p *relayProc) dialWS(rec *addrRecorder) *scrubClient {
	p.t.Helper()
	hc := &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			c, err := net.Dial(network, addr)
			if err == nil {
				rec.record(c)
			}
			return c, err
		},
	}}
	ctx, cancel := context.WithTimeout(context.Background(), scrubTimeout)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, "ws://"+p.addr, &websocket.DialOptions{HTTPClient: hc})
	if err != nil {
		p.t.Fatalf("ws dial: %v", err)
	}
	ws.SetReadLimit(-1)
	c := &scrubClient{t: p.t, ws: ws}
	p.t.Cleanup(func() { _ = ws.CloseNow() })
	return c
}

func (c *scrubClient) send(frame []byte) {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), scrubTimeout)
	defer cancel()
	if err := c.ws.Write(ctx, websocket.MessageBinary, frame); err != nil {
		c.t.Fatalf("ws write: %v", err)
	}
}

func (c *scrubClient) expect(frame []byte) {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), scrubTimeout)
	defer cancel()
	_, got, err := c.ws.Read(ctx)
	if err != nil {
		c.t.Fatalf("ws read: %v", err)
	}
	if !bytes.Equal(got, frame) {
		c.t.Fatalf("frame: got % x, want % x", got, frame)
	}
}

// waitClosed blocks until the relay closes the connection.
func (c *scrubClient) waitClosed() {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), scrubTimeout)
	defer cancel()
	for {
		if _, _, err := c.ws.Read(ctx); err != nil {
			return
		}
	}
}

// --- known identifiers ---------------------------------------------------

func patterned(seed byte) [16]byte {
	var b [16]byte
	for i := range b {
		b[i] = seed + byte(i)*13
	}
	return b
}

// identifier forms per §20: lower/upper hex, std/URL base64 padded and
// raw, and the raw bytes themselves.
func leakForms(raw []byte) [][]byte {
	h := hex.EncodeToString(raw)
	return [][]byte{
		[]byte(h),
		[]byte(strings.ToUpper(h)),
		[]byte(base64.StdEncoding.EncodeToString(raw)),
		[]byte(base64.RawStdEncoding.EncodeToString(raw)),
		[]byte(base64.URLEncoding.EncodeToString(raw)),
		[]byte(base64.RawURLEncoding.EncodeToString(raw)),
		raw,
	}
}

var (
	hexRunRe    = regexp.MustCompile(`[0-9a-fA-F]{32,}`)
	dottedQuad  = regexp.MustCompile(`\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b`)
	metricDelta = regexp.MustCompile(`nimna_relay_limit_trips_total\{limit="([a-z_]+)"\} ([0-9]+)`)
)

func assertScrubbed(t *testing.T, surface, output string, ids map[string][]byte, clientAddrs []string) {
	t.Helper()
	for name, raw := range ids {
		for _, form := range leakForms(raw) {
			if bytes.Contains([]byte(output), form) {
				t.Errorf("%s leaks %s as %q", surface, name, form)
			}
		}
	}
	for _, addr := range clientAddrs {
		if strings.Contains(output, addr) {
			t.Errorf("%s leaks client address %s", surface, addr)
		}
	}
	if m := hexRunRe.FindString(output); m != "" {
		t.Errorf("%s contains a 32+ char hex run %q", surface, m)
	}
	for _, ip := range dottedQuad.FindAllString(output, -1) {
		if ip != "127.0.0.1" {
			t.Errorf("%s contains dotted-quad %s (only the configured listen host is allowed)", surface, ip)
		}
	}
}

func tripCounts(exposition string) map[string]string {
	out := map[string]string{}
	for _, m := range metricDelta.FindAllStringSubmatch(exposition, -1) {
		out[m[1]] = m[2]
	}
	return out
}

// --- the test ------------------------------------------------------------

// TestLogScrub is §20(1). Phase A exercises both planes and every limit
// reachable under one config (per-IP cap, frame rate, oversize,
// rendezvous throttle, reg cap, knock collapse, push min + hour, idle),
// with the push sink returning 500 so the transport-status Warn line
// fires; phase B (separate config) exercises the day cap. All process
// output and the metrics exposition are scanned for every known
// identifier form.
func TestLogScrub(t *testing.T) {
	// The sink stands in for the push platform (it legitimately
	// receives the token) and returns 500 to force the transport-status
	// log line.
	var sinkCalls sync.Mutex
	sinkCount := 0
	sink := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sinkCalls.Lock()
		sinkCount++
		sinkCalls.Unlock()
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(sink.Close)

	// Known identifier bytes for the leak scan.
	topicBridged := patterned(0x11)
	topicThrottled := patterned(0x22)
	cridSession := patterned(0x33)
	cridPush := patterned(0x44)
	cridCapA, cridCapB, cridCapC := patterned(0x55), patterned(0x66), patterned(0x77)
	token := bytes.Repeat([]byte{0xD7, 0x35}, 16) // 32 bytes
	ids := map[string][]byte{
		"bridged topic":   topicBridged[:],
		"throttled topic": topicThrottled[:],
		"session crid":    cridSession[:],
		"push crid":       cridPush[:],
		"cap crid A":      cridCapA[:],
		"cap crid B":      cridCapB[:],
		"cap crid C":      cridCapC[:],
		"device token":    token[:],
	}
	rec := &addrRecorder{}
	// The push-sink URL is operator config the relay must never log —
	// only its CLASS appears (push_mode=sink). Forbid the URL and its
	// host:port explicitly: the sink's host 127.0.0.1 is whitelisted by
	// the dotted-quad sweep and its port would otherwise go unchecked.
	sinkAddr := strings.TrimPrefix(sink.URL, "http://")
	forbiddenAddrs := func() []string {
		return append(rec.snapshot(), sink.URL, sinkAddr)
	}

	// ---- Phase A: production config, shortened windows (§14: tests
	// accelerate via config; the defaults stay spec).
	p := startRelay(t,
		"-push-sink", sink.URL,
		"-max-conns-per-ip", "6",
		"-frame-rate", "30",
		"-frame-burst", "5",
		"-max-frame", "4096",
		"-rendezvous-per-min", "2",
		"-max-regs-per-conn", "2",
		"-knock-interval", "150ms",
		"-push-min-interval", "2s",
		"-push-per-hour", "1",
		"-idle-timeout", "700ms",
	)

	// (1) Per-IP cap: fill to 6 raw conns, the 7th sees a zero-byte
	// close; then release. (Cap 6 leaves headroom for the flows below,
	// whose closes decrement asynchronously.)
	var fillers []net.Conn
	for i := 0; i < 6; i++ {
		c, err := net.Dial("tcp", p.addr)
		if err != nil {
			t.Fatalf("filler dial: %v", err)
		}
		rec.record(c)
		fillers = append(fillers, c)
	}
	over, err := net.Dial("tcp", p.addr)
	if err != nil {
		t.Fatalf("over-cap dial: %v", err)
	}
	rec.record(over)
	_ = over.SetReadDeadline(time.Now().Add(scrubTimeout))
	if n, err := over.Read(make([]byte, 16)); n != 0 || err != io.EOF {
		t.Fatalf("over-cap connect: got %d bytes, err %v; want 0, EOF", n, err)
	}
	_ = over.Close()
	for _, c := range fillers {
		_ = c.Close()
	}

	// (2) An idle WS connection, reaped while the rest of the phase
	// runs (idle 700ms, tick ~233ms).
	idler := p.dialWS(rec)

	// (3) Rendezvous plane: bridge on known-byte topic (2 registrations
	// = the whole per-minute budget), verbatim PAIR_DATA, then a third
	// REGISTER_TOPIC → rendezvous throttle trip.
	a := p.dialWS(rec)
	b := p.dialWS(rec)
	a.send(wire.Encode(wire.RegisterTopic, topicBridged, nil))
	b.send(wire.Encode(wire.RegisterTopic, topicBridged, nil))
	bridged := wire.Encode(wire.TopicBridged, topicBridged, nil)
	a.expect(bridged)
	b.expect(bridged)
	pd := wire.Encode(wire.PairData, topicBridged, []byte("pairing bytes"))
	a.send(pd)
	b.expect(pd)
	a.send(wire.Encode(wire.RegisterTopic, topicThrottled, nil)) // throttled, silent

	// (4) Channel plane on the same two conns: register, knock (a
	// second knock collapses), accept, SESSION_DATA, explicit TEARDOWN.
	a.send(wire.Encode(wire.RegisterCRID, cridSession, nil))
	b.send(wire.Encode(wire.RegisterCRID, cridSession, nil))
	a.send(wire.Encode(wire.Knock, cridSession, nil))
	b.expect(wire.Encode(wire.KnockFwd, cridSession, nil))
	a.send(wire.Encode(wire.Knock, cridSession, nil)) // collapse trip
	b.send(wire.Encode(wire.Accept, cridSession, nil))
	sb := wire.Encode(wire.SessionBridged, cridSession, nil)
	a.expect(sb)
	b.expect(sb)
	sd := wire.Encode(wire.SessionData, cridSession, []byte("ciphertext bytes"))
	a.send(sd)
	b.expect(sd)
	a.send(wire.Encode(wire.Teardown, cridSession, nil))
	b.expect(wire.Encode(wire.Teardown, cridSession, nil))
	_ = a.ws.CloseNow()
	_ = b.ws.CloseNow()

	// (5) Registration cap (CRID plane, cap 2): third register dropped.
	capper := p.dialWS(rec)
	capper.send(wire.Encode(wire.RegisterCRID, cridCapA, nil))
	capper.send(wire.Encode(wire.RegisterCRID, cridCapB, nil))
	capper.send(wire.Encode(wire.RegisterCRID, cridCapC, nil)) // reg_cap trip
	_ = capper.ws.CloseNow()

	// (6) Push path with the known token: sent (sink 500 → Warn line),
	// then past-collapse-inside-min → push_min trip, then past-min with
	// the hour budget (1) exhausted → push_hour trip.
	pusher := p.dialWS(rec)
	pusher.send(wire.Encode(wire.RegisterCRID, cridPush, nil))
	kp := wire.EncodeKnockPayload(wire.PlatformAPNs, token)
	pusher.send(wire.Encode(wire.Knock, cridPush, kp)) // push #1: sent
	time.Sleep(300 * time.Millisecond)                 // > collapse 150ms, < min 2s
	pusher.send(wire.Encode(wire.Knock, cridPush, kp)) // push_min trip
	// Wait out the 2s push floor WITHOUT going idle (the 700ms liveness
	// deadline would reap a silent pusher): benign frames — silently
	// dropped PAIR_DATA on an unregistered topic — are inbound bytes
	// and keep the connection alive, which also exercises §17's
	// "activity counts as liveness" through the real binary.
	for i := 0; i < 7; i++ {
		time.Sleep(300 * time.Millisecond)
		pusher.send(wire.Encode(wire.PairData, topicThrottled, nil))
	}
	pusher.send(wire.Encode(wire.Knock, cridPush, kp)) // push_hour trip (cap 1)

	// (7) Frame flood: over-burst frames are paced, never errored. Keep
	// the connection open until the pacing trip is visible in the
	// metrics — the server reads at its own pace.
	flooder := p.dialWS(rec)
	for i := 0; i < 12; i++ {
		flooder.send(wire.Encode(wire.PairData, topicThrottled, []byte{byte(i)}))
	}
	waitTrip := func(limit string) {
		t.Helper()
		deadline := time.Now().Add(scrubTimeout)
		for time.Now().Before(deadline) {
			if v := tripCounts(p.scrape())[limit]; v != "" && v != "0" {
				return
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("limit %q never tripped", limit)
	}
	waitTrip("frame_rate")
	_ = flooder.ws.CloseNow()

	// (8) Oversize frame: bare close.
	big := p.dialWS(rec)
	big.send(wire.Encode(wire.PairData, topicThrottled, make([]byte, 4096-wire.HeaderLen+1)))
	big.waitClosed()

	// (9) Structurally malformed frame: bare close.
	mal := p.dialWS(rec)
	mal.send([]byte{0x01, 0x02, 0x03})
	mal.waitClosed()

	// (10) The idler from (2) has long exceeded 700ms: reaped.
	idler.waitClosed()
	_ = pusher.ws.CloseNow()

	// Every limit path verifiably tripped (the §20 point: trips were
	// EXERCISED while output was captured).
	exposition := p.scrape()
	trips := tripCounts(exposition)
	for _, limit := range []string{
		"conn_ip", "frame_rate", "frame_size", "rendezvous", "reg_cap",
		"knock_collapse", "push_min", "push_hour", "idle",
	} {
		if trips[limit] == "" || trips[limit] == "0" {
			t.Errorf("phase A: limit %q never tripped (trips: %v)", limit, trips)
		}
	}
	sinkCalls.Lock()
	if sinkCount != 1 {
		t.Errorf("sink calls: got %d, want exactly 1 (caps suppressed the rest)", sinkCount)
	}
	sinkCalls.Unlock()

	// SIGTERM for the shutdown lines.
	p.terminate()
	outA := p.out.String()

	// Positive controls: the operational log surface actually fired.
	for _, want := range []string{
		"relay listening", "metrics listening", "config",
		"push transport failure", "status=500", "relay stopped",
	} {
		if !strings.Contains(outA, want) {
			t.Errorf("phase A output missing %q — the surface under scrub never fired", want)
		}
	}
	if strings.Contains(outA, "level=DEBUG") {
		t.Error("phase A ran with debug output in production config")
	}

	// The scrub itself: process output and metrics exposition.
	assertScrubbed(t, "phase A output", outA, ids, forbiddenAddrs())
	assertScrubbed(t, "phase A metrics", exposition, ids, forbiddenAddrs())

	// ---- Phase B: day cap (per-hour 5 > per-day 1, so the day window
	// binds; unreachable under one config beside the hour trip above).
	p2 := startRelay(t,
		"-push-sink", sink.URL,
		"-knock-interval", "100ms",
		"-push-min-interval", "300ms",
		"-push-per-hour", "5",
		"-push-per-day", "1",
	)
	cridDay := patterned(0x88)
	ids2 := map[string][]byte{"day crid": cridDay[:], "device token": token[:]}

	d := p2.dialWS(rec)
	d.send(wire.Encode(wire.RegisterCRID, cridDay, nil))
	d.send(wire.Encode(wire.Knock, cridDay, kp)) // sent (day budget spent)
	time.Sleep(450 * time.Millisecond)           // > min 300ms, > collapse 100ms
	d.send(wire.Encode(wire.Knock, cridDay, kp)) // push_day trip
	expo2 := p2.scrape()
	if trips := tripCounts(expo2); trips["push_day"] == "" || trips["push_day"] == "0" {
		t.Errorf("phase B: push_day never tripped (trips: %v)", trips)
	}
	_ = d.ws.CloseNow()
	p2.terminate()
	outB := p2.out.String()
	assertScrubbed(t, "phase B output", outB, ids2, forbiddenAddrs())
	assertScrubbed(t, "phase B metrics", expo2, ids2, forbiddenAddrs())
}
