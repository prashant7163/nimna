package limits

import (
	"fmt"
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
)

func crid(b byte) ident.CRID {
	var raw [16]byte
	raw[0] = b
	raw[15] = 0xEE
	return ident.CRIDFromWire(raw)
}

func specTable(clk *fakeClock) *RateTable {
	return NewRateTable(RateConfig{}, clk.now)
}

// TestKnockCollapseBoundary pins the spec window semantics exactly: after
// an accepted knock, the collapse is alive at 9.999s and dead at 10s.
func TestKnockCollapseBoundary(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(1)

	if v := rt.Knock(id); v != KnockAllowed {
		t.Fatalf("first knock: %v, want allowed", v)
	}
	clk.advance(10*time.Second - time.Millisecond)
	if v := rt.Knock(id); v != KnockCollapsed {
		t.Fatalf("knock at 9.999s: %v, want collapsed", v)
	}
	clk.advance(time.Millisecond)
	if v := rt.Knock(id); v != KnockAllowed {
		t.Fatalf("knock at exactly 10s: %v, want allowed", v)
	}
}

// TestKnockCollapseDoesNotRefresh: collapsed knocks do not move the
// anchor — the window anchors on accepted knocks only (§15).
func TestKnockCollapseDoesNotRefresh(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(2)

	rt.Knock(id) // accepted at t=0
	clk.advance(5 * time.Second)
	if v := rt.Knock(id); v != KnockCollapsed {
		t.Fatalf("knock at 5s: %v, want collapsed", v)
	}
	clk.advance(5 * time.Second)
	// 10s after the ACCEPTED knock — allowed. If the collapsed knock at
	// 5s had refreshed the anchor, this would still be collapsed.
	if v := rt.Knock(id); v != KnockAllowed {
		t.Fatalf("knock 10s after the accepted one: %v, want allowed", v)
	}
}

// TestKnockPerCRID: windows are per CRID, not global.
func TestKnockPerCRID(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)

	if v := rt.Knock(crid(3)); v != KnockAllowed {
		t.Fatalf("crid A: %v", v)
	}
	if v := rt.Knock(crid(4)); v != KnockAllowed {
		t.Fatalf("crid B must have its own window: %v", v)
	}
}

// TestPushMinIntervalBoundary: 1 push per 60s — refused at 59.999s,
// allowed at exactly 60s.
func TestPushMinIntervalBoundary(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(5)

	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("first push: %v", v)
	}
	clk.advance(time.Minute - time.Millisecond)
	if v := rt.Push(id); v != PushDeniedMin {
		t.Fatalf("push at 59.999s: %v, want denied-min", v)
	}
	clk.advance(time.Millisecond)
	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("push at exactly 60s: %v, want allowed", v)
	}
}

// TestPushDenialDoesNotCharge: a denied push charges no budget — the
// caps are checked atomically, so denials never eat the hour/day counts,
// and a denied-min push does not push the min-interval anchor forward.
func TestPushDenialDoesNotCharge(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(6)

	rt.Push(id) // allowed at t=0
	clk.advance(30 * time.Second)
	if v := rt.Push(id); v != PushDeniedMin {
		t.Fatalf("push at 30s: %v", v)
	}
	clk.advance(30 * time.Second)
	// 60s after the ALLOWED push: allowed. A denial that charged the
	// anchor would refuse this.
	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("push 60s after the allowed one: %v, want allowed", v)
	}
}

// TestPushHourCap: 6 per hour (spec) — the 7th inside the fixed window is
// refused; the window restarts exactly one hour after its first counted
// push.
func TestPushHourCap(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(7)

	for i := 1; i <= 6; i++ {
		if v := rt.Push(id); v != PushAllowed {
			t.Fatalf("push %d within hour cap: %v", i, v)
		}
		clk.advance(time.Minute) // respect the 60s floor
	}
	// 6 minutes in, 6 pushes counted.
	if v := rt.Push(id); v != PushDeniedHour {
		t.Fatalf("7th push in the hour: %v, want denied-hour", v)
	}
	// Just before the window rolls (59:59.999 from the first push):
	// still refused.
	clk.advance(54*time.Minute - time.Millisecond) // now 59:59.999
	if v := rt.Push(id); v != PushDeniedHour {
		t.Fatalf("push at 59:59.999: %v, want denied-hour", v)
	}
	clk.advance(time.Millisecond) // exactly 1h after the first push
	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("push at exactly 1h: %v, want allowed (fresh window)", v)
	}
}

// TestPushDayCap: 20 per day (spec). Driven with an accelerated hour
// window is not possible here — the spec table is used with minute
// spacing across hours via window rolls, so the day cap is exercised
// against real spec windows on the fake clock.
func TestPushDayCap(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	id := crid(8)

	// 20 pushes, one per hour window roll: all allowed, day count 20.
	for i := 1; i <= 20; i++ {
		if v := rt.Push(id); v != PushAllowed {
			t.Fatalf("push %d within day cap: %v", i, v)
		}
		clk.advance(time.Hour)
	}
	// 20 hours in; day window (24h) still open, count exhausted.
	if v := rt.Push(id); v != PushDeniedDay {
		t.Fatalf("21st push in the day: %v, want denied-day", v)
	}
	// Just before the day rolls (24h after the first push): refused.
	clk.advance(4*time.Hour - time.Millisecond)
	if v := rt.Push(id); v != PushDeniedDay {
		t.Fatalf("push at 23:59:59.999: %v, want denied-day", v)
	}
	clk.advance(time.Millisecond) // exactly 24h after the first push
	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("push at exactly 24h: %v, want allowed (fresh day)", v)
	}
}

// TestConfiguredWindows: shrunken hour/day windows (the §14 acceleration
// path for tests and soak) keep the same boundary semantics.
func TestConfiguredWindows(t *testing.T) {
	clk := newFakeClock()
	rt := NewRateTable(RateConfig{
		PushMinInterval: 100 * time.Millisecond,
		PushPerHour:     2,
		PushPerDay:      3,
		HourWindow:      time.Second,
		DayWindow:       2 * time.Second,
	}, clk.now)
	id := crid(9)

	if v := rt.Push(id); v != PushAllowed { // t=0: h1 d1
		t.Fatalf("push 1: %v", v)
	}
	clk.advance(200 * time.Millisecond)
	if v := rt.Push(id); v != PushAllowed { // t=0.2: h2 d2
		t.Fatalf("push 2: %v", v)
	}
	clk.advance(200 * time.Millisecond)
	if v := rt.Push(id); v != PushDeniedHour { // t=0.4: hour cap
		t.Fatalf("push 3: %v, want denied-hour", v)
	}
	clk.advance(600 * time.Millisecond)     // t=1.0: hour window rolls
	if v := rt.Push(id); v != PushAllowed { // h1 d3
		t.Fatalf("push 4: %v, want allowed", v)
	}
	clk.advance(200 * time.Millisecond)
	if v := rt.Push(id); v != PushDeniedDay { // t=1.2: day cap (d would be 4)
		t.Fatalf("push 5: %v, want denied-day", v)
	}
	clk.advance(800 * time.Millisecond) // t=2.0: day window rolls
	if v := rt.Push(id); v != PushAllowed {
		t.Fatalf("push 6: %v, want allowed (fresh day)", v)
	}
}

// TestRateTableCap: at the hard cap, an untracked knock fails open
// (forward proceeds, uncounted) and an untracked push fails closed;
// tracked entries keep enforcing normally (§15).
func TestRateTableCap(t *testing.T) {
	clk := newFakeClock()
	rt := NewRateTable(RateConfig{MaxEntries: 3}, clk.now)

	for i := byte(1); i <= 3; i++ {
		if v := rt.Knock(crid(i)); v != KnockAllowed {
			t.Fatalf("fill knock %d: %v", i, v)
		}
	}
	if got := rt.Len(); got != 3 {
		t.Fatalf("Len at cap: %d", got)
	}

	// Untracked CRID: knock fails open, push fails closed.
	if v := rt.Knock(crid(99)); v != KnockUntracked {
		t.Fatalf("knock at cap: %v, want untracked (fail-open)", v)
	}
	if v := rt.Push(crid(99)); v != PushDeniedUntracked {
		t.Fatalf("push at cap: %v, want denied-untracked (fail-closed)", v)
	}
	if got := rt.Len(); got != 3 {
		t.Fatalf("cap breached: Len %d", got)
	}

	// Tracked entries still enforce.
	if v := rt.Knock(crid(1)); v != KnockCollapsed {
		t.Fatalf("tracked knock inside window at cap: %v, want collapsed", v)
	}

	// Eviction frees room: idle out the tracked entries, sweep, and the
	// formerly untracked CRID gains an entry.
	clk.advance(rt.EvictAfter() + time.Millisecond)
	rt.Sweep()
	if got := rt.Len(); got != 0 {
		t.Fatalf("Len after eviction sweep: %d, want 0", got)
	}
	if v := rt.Knock(crid(99)); v != KnockAllowed {
		t.Fatalf("knock after eviction freed room: %v, want allowed", v)
	}
}

// TestEvictionBoundary: entries idle exactly the horizon survive; idle
// strictly longer are evicted ("idle longer than 24 h", §15). The
// horizon is the longest configured window.
func TestEvictionBoundary(t *testing.T) {
	clk := newFakeClock()
	rt := specTable(clk)
	if got := rt.EvictAfter(); got != 24*time.Hour {
		t.Fatalf("EvictAfter at spec defaults: %v, want 24h", got)
	}

	rt.Knock(crid(1))
	clk.advance(24 * time.Hour)
	rt.Sweep()
	if got := rt.Len(); got != 1 {
		t.Fatalf("entry idle exactly the horizon must survive; Len %d", got)
	}
	clk.advance(time.Millisecond)
	rt.Sweep()
	if got := rt.Len(); got != 0 {
		t.Fatalf("entry idle past the horizon must be evicted; Len %d", got)
	}
}

// TestEvictionKeepsActive: activity (even collapsed knocks) keeps an
// entry warm across sweeps.
func TestEvictionKeepsActive(t *testing.T) {
	clk := newFakeClock()
	rt := NewRateTable(RateConfig{
		HourWindow: time.Second,
		DayWindow:  2 * time.Second, // horizon = PushMinInterval 60s
	}, clk.now)
	if got := rt.EvictAfter(); got != time.Minute {
		t.Fatalf("EvictAfter: %v, want 60s (the longest configured window)", got)
	}
	id := crid(1)
	rt.Knock(id)
	for i := 0; i < 4; i++ {
		clk.advance(45 * time.Second)
		rt.Knock(id) // touches, allowed or collapsed
		rt.Sweep()
		if got := rt.Len(); got != 1 {
			t.Fatalf("active entry evicted at step %d", i)
		}
	}
}

// TestRateTableManyCRIDs: distinct CRIDs get distinct entries up to the
// cap — a sanity pin on map keying by ident.CRID.
func TestRateTableManyCRIDs(t *testing.T) {
	clk := newFakeClock()
	rt := NewRateTable(RateConfig{MaxEntries: 64}, clk.now)
	for i := 0; i < 64; i++ {
		var raw [16]byte
		copy(raw[:], fmt.Sprintf("crid-%03d", i))
		if v := rt.Knock(ident.CRIDFromWire(raw)); v != KnockAllowed {
			t.Fatalf("crid %d: %v", i, v)
		}
	}
	if got := rt.Len(); got != 64 {
		t.Fatalf("Len: %d, want 64", got)
	}
}
