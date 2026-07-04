package limits

import (
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
)

func ipKey(s string) ident.RemoteAddr { return ident.RemoteAddrFrom(s) }

// TestIPWindowLimit: exactly limit frames pass per window; further ones
// are denied but still counted (denial is invisible on the wire — the
// caller drops silently).
func TestIPWindowLimit(t *testing.T) {
	clk := newFakeClock()
	w := NewIPWindow(6, time.Minute, clk.now)
	key := ipKey("203.0.113.7:1")

	for i := 1; i <= 6; i++ {
		if !w.Allow(key) {
			t.Fatalf("frame %d within limit denied", i)
		}
	}
	for i := 7; i <= 9; i++ {
		if w.Allow(key) {
			t.Fatalf("frame %d over limit allowed", i)
		}
	}
}

// TestIPWindowBoundary: the fixed window restarts at exactly its
// duration — denied at 59.999s, fresh at 60s.
func TestIPWindowBoundary(t *testing.T) {
	clk := newFakeClock()
	w := NewIPWindow(1, time.Minute, clk.now)
	key := ipKey("203.0.113.7:1")

	if !w.Allow(key) {
		t.Fatal("first frame denied")
	}
	clk.advance(time.Minute - time.Millisecond)
	if w.Allow(key) {
		t.Fatal("frame at 59.999s allowed — window must still be closed")
	}
	clk.advance(time.Millisecond)
	if !w.Allow(key) {
		t.Fatal("frame at exactly 60s denied — window must have restarted")
	}
}

// TestIPWindowPerKey: windows are independent per canonical IP key; the
// same host's ports share one window (canonicalization strips ports).
func TestIPWindowPerKey(t *testing.T) {
	clk := newFakeClock()
	w := NewIPWindow(1, time.Minute, clk.now)

	if !w.Allow(ipKey("203.0.113.7:1111")) {
		t.Fatal("first key denied")
	}
	if w.Allow(ipKey("203.0.113.7:2222")) {
		t.Fatal("same host, different port: must share the window")
	}
	if !w.Allow(ipKey("203.0.113.8:1111")) {
		t.Fatal("different host: must have its own window")
	}
	// Two v6 hosts in one /64 share a window (§15: a single v6 host
	// owns a /64).
	if !w.Allow(ipKey("[2001:db8:1:2::1]:1")) {
		t.Fatal("first /64 frame denied")
	}
	if w.Allow(ipKey("[2001:db8:1:2::2]:1")) {
		t.Fatal("same /64: must share the window")
	}
}

// TestIPWindowSweep: lapsed windows are evicted; live ones survive.
func TestIPWindowSweep(t *testing.T) {
	clk := newFakeClock()
	w := NewIPWindow(6, time.Minute, clk.now)

	w.Allow(ipKey("203.0.113.7:1"))
	clk.advance(30 * time.Second)
	w.Allow(ipKey("203.0.113.8:1"))
	if got := w.Len(); got != 2 {
		t.Fatalf("Len: got %d, want 2", got)
	}
	clk.advance(30 * time.Second) // first window now exactly lapsed
	w.Sweep()
	if got := w.Len(); got != 1 {
		t.Fatalf("Len after sweep: got %d, want 1 (only the live window)", got)
	}
}
