package limits

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"nimna.app/relay/internal/metrics"
)

// tripCount reads one limit_trips_total series through the public
// exposition (the counters are deliberately unexported).
func tripCount(m *metrics.Metrics, limit string) string {
	var buf bytes.Buffer
	metrics.Write(&buf, m, metrics.Gauges{})
	for _, line := range strings.Split(buf.String(), "\n") {
		if strings.HasPrefix(line, `nimna_relay_limit_trips_total{limit="`+limit+`"} `) {
			return strings.TrimPrefix(line, `nimna_relay_limit_trips_total{limit="`+limit+`"} `)
		}
	}
	return "missing"
}

// echoAccept runs an accept loop that just holds accepted conns (and
// reads from them so the liveness clock ticks), returning a stop func.
func acceptLoop(t *testing.T, ln net.Listener) {
	t.Helper()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				buf := make([]byte, 256)
				for {
					if _, err := c.Read(buf); err != nil {
						_ = c.Close()
						return
					}
				}
			}()
		}
	}()
}

func newLimitListener(t *testing.T, cfg ListenerConfig) *Listener {
	t.Helper()
	raw, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ln := NewListener(raw, cfg)
	t.Cleanup(func() { _ = ln.Close() })
	return ln
}

func dialTCP(t *testing.T, addr string) net.Conn {
	t.Helper()
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })
	return c
}

// TestPerIPCapZeroBytes: the over-cap connect is closed with ZERO bytes
// received — the §16 refusal shape — while under-cap connects live; a
// freed slot re-admits.
func TestPerIPCapZeroBytes(t *testing.T) {
	m := metrics.New()
	ln := newLimitListener(t, ListenerConfig{MaxConnsPerIP: 2, Metrics: m})
	acceptLoop(t, ln)
	addr := ln.Addr().String()

	c1 := dialTCP(t, addr)
	c2 := dialTCP(t, addr)
	waitLen(t, ln, 2)

	// Third connect from the same IP: closed with zero bytes.
	over := dialTCP(t, addr)
	_ = over.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 64)
	n, err := over.Read(buf)
	if n != 0 {
		t.Fatalf("over-cap connect received %d bytes, want 0", n)
	}
	if err != io.EOF {
		t.Fatalf("over-cap connect: read err %v, want EOF (clean zero-byte close)", err)
	}

	if got := tripCount(m, "conn_ip"); got != "1" {
		t.Errorf("conn_ip trips: got %s, want 1", got)
	}

	// The two under-cap connections are untouched: they can still write
	// (reads on the server side keep succeeding — no error surfaces).
	if _, err := c1.Write([]byte("still alive")); err != nil {
		t.Fatalf("under-cap conn 1 disturbed: %v", err)
	}

	// Freeing a slot re-admits the same IP.
	_ = c2.Close()
	waitLen(t, ln, 1)
	c4 := dialTCP(t, addr)
	if _, err := c4.Write([]byte("readmitted")); err != nil {
		t.Fatalf("re-admitted conn: %v", err)
	}
	waitLen(t, ln, 2)
}

// waitLen polls the listener's tracked-conn count (accept and close are
// asynchronous to the dialer's view).
func waitLen(t *testing.T, ln *Listener, n int) {
	t.Helper()
	for i := 0; i < 200; i++ {
		if ln.Len() == n {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("listener never reached %d tracked conns (at %d)", n, ln.Len())
}

// TestLivenessReap: a silent connection is reaped once its last inbound
// byte is older than the deadline; a connection with inbound traffic
// (any bytes — WS pings are inbound bytes, §17) survives.
func TestLivenessReap(t *testing.T) {
	clk := newFakeClock()
	m := metrics.New()
	ln := newLimitListener(t, ListenerConfig{
		IdleTimeout: 90 * time.Second,
		Metrics:     m,
		Now:         clk.now,
	})
	acceptLoop(t, ln)
	addr := ln.Addr().String()

	silent := dialTCP(t, addr)
	chatty := dialTCP(t, addr)
	waitLen(t, ln, 2)

	// 60s in: chatty sends bytes (a ping stand-in); its clock bumps
	// when the server-side read completes.
	clk.advance(60 * time.Second)
	if _, err := chatty.Write([]byte("ping")); err != nil {
		t.Fatalf("chatty write: %v", err)
	}
	waitTouched(t, ln, clk.now().UnixNano())

	// 90.001s in: silent's last inbound is 90.001s old (> deadline);
	// chatty's is 30.001s old.
	clk.advance(30*time.Second + time.Millisecond)
	ln.sweep()

	_ = silent.SetReadDeadline(time.Now().Add(2 * time.Second))
	if _, err := silent.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("silent conn: read err %v, want EOF (reaped)", err)
	}
	waitLen(t, ln, 1)

	// Chatty survives the same sweep.
	if _, err := chatty.Write([]byte("still here")); err != nil {
		t.Fatalf("chatty disturbed by sweep: %v", err)
	}
	if got := tripCount(m, "idle"); got != "1" {
		t.Errorf("idle trips: got %s, want 1", got)
	}
}

// waitTouched waits until some tracked conn's liveness clock reaches ts —
// i.e. the server-side read of the client's bytes completed.
func waitTouched(t *testing.T, ln *Listener, ts int64) {
	t.Helper()
	for i := 0; i < 200; i++ {
		ln.mu.Lock()
		var newest int64
		for c := range ln.conns {
			if v := c.last.Load(); v > newest {
				newest = v
			}
		}
		ln.mu.Unlock()
		if newest >= ts {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("liveness clock never advanced past the write")
}

// TestLivenessBoundary: a connection idle EXACTLY the deadline is not
// reaped; strictly older is. Pins the sweep comparison.
func TestLivenessBoundary(t *testing.T) {
	clk := newFakeClock()
	ln := newLimitListener(t, ListenerConfig{
		IdleTimeout: 90 * time.Second,
		Now:         clk.now,
	})
	acceptLoop(t, ln)

	c := dialTCP(t, ln.Addr().String())
	waitLen(t, ln, 1)

	clk.advance(90 * time.Second)
	ln.sweep()
	if ln.Len() != 1 {
		t.Fatal("conn idle exactly the deadline must survive")
	}
	clk.advance(time.Millisecond)
	ln.sweep()
	waitLen(t, ln, 0)
	_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
	if _, err := c.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("read err %v, want EOF", err)
	}
}

// TestJanitorTick pins the §17 derivation: 30s at the 90s default,
// scaling down for accelerated configs, floored for sanity.
func TestJanitorTick(t *testing.T) {
	cases := []struct {
		idle time.Duration
		want time.Duration
	}{
		{90 * time.Second, 30 * time.Second},  // §17 verbatim
		{300 * time.Second, 30 * time.Second}, // capped at 30s
		{900 * time.Millisecond, 300 * time.Millisecond},
		{3 * time.Millisecond, 10 * time.Millisecond}, // floored
	}
	for _, tc := range cases {
		ln := Listener{idle: tc.idle}
		if got := ln.janitorTick(); got != tc.want {
			t.Errorf("janitorTick(idle=%v): got %v, want %v", tc.idle, got, tc.want)
		}
	}
}
