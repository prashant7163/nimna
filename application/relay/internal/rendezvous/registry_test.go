package rendezvous

import (
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
)

// fakeClock is an injectable clock: tests never sleep.
type fakeClock struct{ t time.Time }

func newFakeClock() *fakeClock {
	return &fakeClock{t: time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) now() time.Time          { return c.t }
func (c *fakeClock) advance(d time.Duration) { c.t = c.t.Add(d) }

func topic(b byte) ident.Topic {
	var raw [16]byte
	raw[0] = b
	return ident.TopicFromWire(raw)
}

// Endpoints are plain strings in tests — the registry is generic over any
// comparable handle.
func newRegistry(clk *fakeClock) *Registry[string] {
	return New[string](0, clk.now)
}

func TestFirstRegistrantWaits(t *testing.T) {
	r := newRegistry(newFakeClock())
	peer, out := r.Register(topic(1), "A")
	if out != Waiting {
		t.Fatalf("outcome: got %v, want Waiting", out)
	}
	if peer != "" {
		t.Fatalf("peer: got %q, want zero", peer)
	}
	if r.Len() != 1 {
		t.Fatalf("Len: got %d, want 1", r.Len())
	}
}

func TestSecondDistinctRegistrantBridges(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	peer, out := r.Register(topic(1), "B")
	if out != Bridged {
		t.Fatalf("outcome: got %v, want Bridged", out)
	}
	if peer != "A" {
		t.Fatalf("peer: got %q, want A", peer)
	}
}

func TestReRegistrationIsIdempotent(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	peer, out := r.Register(topic(1), "A")
	if out != Ignored || peer != "" {
		t.Fatalf("waiting re-registration: got (%q, %v), want (\"\", Ignored)", peer, out)
	}
	// A connection never bridges to itself: still one waiting entry.
	if _, ok := r.Forward(topic(1), "A"); ok {
		t.Fatal("topic must not be bridged by a self re-registration")
	}

	r.Register(topic(1), "B")
	for _, ep := range []string{"A", "B"} {
		peer, out := r.Register(topic(1), ep)
		if out != Ignored || peer != "" {
			t.Fatalf("bridged member %q re-registration: got (%q, %v), want (\"\", Ignored)", ep, peer, out)
		}
	}
	// The bridge is untouched.
	if to, ok := r.Forward(topic(1), "A"); !ok || to != "B" {
		t.Fatal("bridge must survive member re-registrations")
	}
}

func TestThirdRegistrantIgnoredNoState(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	r.Register(topic(1), "B")
	peer, out := r.Register(topic(1), "C")
	if out != Ignored || peer != "" {
		t.Fatalf("third registrant: got (%q, %v), want (\"\", Ignored)", peer, out)
	}
	// No state kept: C is not a member and cannot forward.
	if _, ok := r.Forward(topic(1), "C"); ok {
		t.Fatal("third registrant must not become a forwarding member")
	}
	// C's death must not disturb the bridge (no state to unwind).
	r.Drop(topic(1), "C")
	if to, ok := r.Forward(topic(1), "A"); !ok || to != "B" {
		t.Fatal("bridge must survive a third registrant's Drop")
	}
}

func TestForward(t *testing.T) {
	r := newRegistry(newFakeClock())

	// Unknown topic: silent drop.
	if _, ok := r.Forward(topic(9), "A"); ok {
		t.Fatal("Forward on unknown topic must be ok=false")
	}

	// Waiting topic: silent drop, even for the member.
	r.Register(topic(1), "A")
	if _, ok := r.Forward(topic(1), "A"); ok {
		t.Fatal("Forward on waiting topic must be ok=false")
	}

	// Bridged: both directions resolve to the other member.
	r.Register(topic(1), "B")
	if to, ok := r.Forward(topic(1), "A"); !ok || to != "B" {
		t.Fatalf("Forward A: got (%q, %v), want (B, true)", to, ok)
	}
	if to, ok := r.Forward(topic(1), "B"); !ok || to != "A" {
		t.Fatalf("Forward B: got (%q, %v), want (A, true)", to, ok)
	}

	// Non-member sender on a bridged topic: silent drop.
	if _, ok := r.Forward(topic(1), "C"); ok {
		t.Fatal("Forward from non-member must be ok=false")
	}
}

func TestDropDeletesWholeEntry(t *testing.T) {
	r := newRegistry(newFakeClock())

	// Waiting entry dies with its registrant.
	r.Register(topic(1), "A")
	r.Drop(topic(1), "A")
	if r.Len() != 0 {
		t.Fatal("waiting entry must be deleted on Drop")
	}

	// A bridged topic loses its ENTIRE entry when either end dies.
	r.Register(topic(2), "A")
	r.Register(topic(2), "B")
	r.Drop(topic(2), "A")
	if r.Len() != 0 {
		t.Fatal("bridged entry must be deleted whole when one end drops")
	}
	if _, ok := r.Forward(topic(2), "B"); ok {
		t.Fatal("survivor must not forward on a dead topic")
	}
}

// TestNoTombstones pins the §3.1.6 structural indistinguishability: after
// a topic dies, a fresh registration of the same 16 bytes creates a fresh
// waiting entry — re-accepted, no bridge, no error, no memory of the past.
func TestNoTombstones(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	r.Register(topic(1), "B")
	r.Drop(topic(1), "A")

	peer, out := r.Register(topic(1), "C")
	if out != Waiting || peer != "" {
		t.Fatalf("fresh registrant on dead topic: got (%q, %v), want (\"\", Waiting)", peer, out)
	}
	// And it can bridge anew.
	peer, out = r.Register(topic(1), "D")
	if out != Bridged || peer != "C" {
		t.Fatalf("second fresh registrant: got (%q, %v), want (C, Bridged)", peer, out)
	}
}

func TestDropIsMembershipChecked(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	r.Drop(topic(1), "A")
	// A fresh entry now belongs to C; the late unwind of a long-dead
	// registration must not delete it.
	r.Register(topic(1), "C")
	r.Drop(topic(1), "A")
	if r.Len() != 1 {
		t.Fatal("Drop by a non-member must not delete another's entry")
	}
	// Drop on an absent topic is a no-op.
	r.Drop(topic(9), "A")
}

// TestSweep24hCap exercises the registration cap with the injectable
// clock — no sleeping tests.
func TestSweep24hCap(t *testing.T) {
	t.Run("waiting-entry-evicted", func(t *testing.T) {
		clk := newFakeClock()
		r := newRegistry(clk)
		r.Register(topic(1), "A")

		clk.advance(24*time.Hour - time.Second)
		r.Sweep()
		if r.Len() != 1 {
			t.Fatal("entry must survive inside the 24h cap")
		}

		clk.advance(2 * time.Second) // now past the deadline
		r.Sweep()
		if r.Len() != 0 {
			t.Fatal("waiting entry must be evicted past the 24h cap")
		}
	})

	t.Run("bridged-entry-dies-whole-on-either-deadline", func(t *testing.T) {
		clk := newFakeClock()
		r := newRegistry(clk)
		r.Register(topic(1), "A") // A's deadline: T+24h
		clk.advance(1 * time.Hour)
		r.Register(topic(1), "B") // B's deadline: T+25h

		// Past A's cap but not B's: the bridge dies whole.
		clk.advance(23*time.Hour + time.Minute)
		r.Sweep()
		if r.Len() != 0 {
			t.Fatal("bridged entry must die whole when EITHER member's cap fires")
		}
	})

	t.Run("fresh-registration-after-eviction-waits", func(t *testing.T) {
		clk := newFakeClock()
		r := newRegistry(clk)
		r.Register(topic(1), "A")
		clk.advance(25 * time.Hour)
		r.Sweep()

		// No tombstone: same topic bytes, fresh entry.
		_, out := r.Register(topic(1), "B")
		if out != Waiting {
			t.Fatalf("post-eviction registration: got %v, want Waiting", out)
		}
	})

	t.Run("custom-ttl-honored", func(t *testing.T) {
		clk := newFakeClock()
		r := New[string](time.Hour, clk.now)
		r.Register(topic(1), "A")
		clk.advance(time.Hour + time.Second)
		r.Sweep()
		if r.Len() != 0 {
			t.Fatal("custom TTL must drive the eviction deadline")
		}
	})
}

func TestIndependentTopics(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(topic(1), "A")
	r.Register(topic(2), "A") // same connection, second topic
	r.Register(topic(1), "B")

	// Dropping A's registration on topic 1 must not touch topic 2.
	r.Drop(topic(1), "A")
	if r.Len() != 1 {
		t.Fatalf("Len: got %d, want 1 (topic 2 must survive)", r.Len())
	}
	_, out := r.Register(topic(2), "C")
	if out != Bridged {
		t.Fatal("topic 2 must still be waiting for its bridge")
	}
}
