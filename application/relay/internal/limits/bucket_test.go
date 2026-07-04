package limits

import (
	"sync"
	"testing"
	"time"
)

// fakeClock is the injectable test clock, matching the registry tests'
// style: boundary assertions are exact, never sleep-based.
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func newFakeClock() *fakeClock {
	return &fakeClock{t: time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

// TestBucketBurstExact: a full bucket admits exactly burst messages
// instantly; message burst+1 waits exactly 1/rate.
func TestBucketBurstExact(t *testing.T) {
	clk := newFakeClock()
	b := NewBucket(50, 100, clk.now)

	for i := 0; i < 100; i++ {
		if wait := b.Reserve(); wait != 0 {
			t.Fatalf("message %d within burst: wait %v, want 0", i+1, wait)
		}
	}
	if wait := b.Reserve(); wait != 20*time.Millisecond {
		t.Fatalf("message burst+1: wait %v, want exactly 1/rate = 20ms", wait)
	}
}

// TestBucketRefill: elapsed time refills at the configured rate, capped
// at burst.
func TestBucketRefill(t *testing.T) {
	clk := newFakeClock()
	b := NewBucket(10, 5, clk.now)

	for i := 0; i < 5; i++ {
		if wait := b.Reserve(); wait != 0 {
			t.Fatalf("burst message %d: wait %v", i+1, wait)
		}
	}
	// Empty. 100ms refills exactly 1 token.
	clk.advance(100 * time.Millisecond)
	if wait := b.Reserve(); wait != 0 {
		t.Fatalf("after exact single-token refill: wait %v, want 0", wait)
	}
	if wait := b.Reserve(); wait != 100*time.Millisecond {
		t.Fatalf("next message: wait %v, want 100ms", wait)
	}

	// A long idle refills to burst, never beyond: exactly 5 free, the
	// 6th waits. The pending 100ms debt from above is repaid by the
	// hour too.
	clk.advance(time.Hour)
	for i := 0; i < 5; i++ {
		if wait := b.Reserve(); wait != 0 {
			t.Fatalf("post-idle message %d: wait %v, want 0 (refill caps at burst)", i+1, wait)
		}
	}
	if wait := b.Reserve(); wait == 0 {
		t.Fatal("post-idle message burst+1: want a wait — refill must cap at burst")
	}
}

// TestBucketQueuesBackToBack: consecutive over-burst reservations stack
// at exactly the configured rate (the sender experiences throughput,
// never an error — §16).
func TestBucketQueuesBackToBack(t *testing.T) {
	clk := newFakeClock()
	b := NewBucket(10, 1, clk.now)

	if wait := b.Reserve(); wait != 0 {
		t.Fatalf("first: wait %v", wait)
	}
	for i := 1; i <= 3; i++ {
		want := time.Duration(i) * 100 * time.Millisecond
		if wait := b.Reserve(); wait != want {
			t.Fatalf("queued reservation %d: wait %v, want %v", i, wait, want)
		}
	}
}
