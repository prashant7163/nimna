// Package rendezvous implements the relay's topic registry and bridging
// state machine (spec §3.1.6, §4; architecture note §5).
//
// Lifecycle: absent → REGISTER_TOPIC creates waiting(A) → a second
// distinct connection bridges(A,B) → the entry is deleted when either
// member's connection ends or a member's 24 h registration cap fires.
// Deletion IS topic death: the registry keeps no tombstones, so a later
// registration of the same 16 bytes creates a fresh waiting entry — a
// stateless relay cannot distinguish expired from used from never-existed,
// which makes §3.1.6's indistinguishability structural.
//
// Registration is always silent: no ack frame exists in §5.4, so "always
// succeeds silently" is structural. While bridged, further registrants are
// ignored with NO state kept (first-come-wins; indistinguishable from
// acceptance to the sender, memory stays bounded and squatting-free).
//
// The registry is a pure in-memory state machine guarded by one plain
// mutex (single-VPS scale; architecture note §3). It never touches the
// network: Register and Forward return the peer endpoints and the caller
// (internal/server) delivers frames outside the lock.
package rendezvous

import (
	"context"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
)

// DefaultTTL is the per-connection topic-registration cap (spec §4: topic
// registrations live only as long as their connection, additionally capped
// at 24 h). Configurable at construction; the spec default stands.
const DefaultTTL = 24 * time.Hour

// JanitorInterval is the coarse eviction tick (architecture note §5: ~1
// minute is plenty against a 24 h cap).
const JanitorInterval = time.Minute

// Outcome reports what a registration did — to the CALLER only. On the
// wire every outcome is identical silence (§3.1.6): the sender is never
// told which one occurred.
type Outcome int

const (
	// Waiting: first registrant; a fresh entry now waits for a peer.
	Waiting Outcome = iota
	// Bridged: second distinct registrant; the topic is now bridged and
	// the caller must send TOPIC_BRIDGED to both ends.
	Bridged
	// Ignored: third registrant while bridged, or an idempotent
	// re-registration by a current member. NO state was kept.
	Ignored
)

// registration is one endpoint's membership in a topic entry.
type registration[E comparable] struct {
	ep       E
	deadline time.Time
}

// entry is a topic's state: waiting (b unset) or bridged (a and b set).
type entry[E comparable] struct {
	a, b    registration[E]
	bridged bool
}

// Registry is the topic registry, generic over a comparable endpoint
// handle (the server registers its connection pointers; tests register
// stubs). The zero value is not usable; call New.
type Registry[E comparable] struct {
	mu     sync.Mutex
	topics map[ident.Topic]*entry[E]
	ttl    time.Duration
	now    func() time.Time
}

// New returns a Registry with the given registration cap (0 means
// DefaultTTL) and clock (nil means time.Now; tests inject a fake).
func New[E comparable](ttl time.Duration, now func() time.Time) *Registry[E] {
	if ttl <= 0 {
		ttl = DefaultTTL
	}
	if now == nil {
		now = time.Now
	}
	return &Registry[E]{
		topics: make(map[ident.Topic]*entry[E]),
		ttl:    ttl,
		now:    now,
	}
}

// Register processes a REGISTER_TOPIC from ep. It never fails: on the
// wire, registration always succeeds silently (§3.1.6). When the outcome
// is Bridged, peer is the earlier registrant and the caller must send
// TOPIC_BRIDGED to both ep and peer; otherwise peer is the zero E.
//
// A connection never bridges to itself: re-registration by a current
// member is an idempotent no-op (Ignored, original deadline kept).
func (r *Registry[E]) Register(topic ident.Topic, ep E) (peer E, outcome Outcome) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, ok := r.topics[topic]
	if !ok {
		r.topics[topic] = &entry[E]{
			a: registration[E]{ep: ep, deadline: r.now().Add(r.ttl)},
		}
		return zero, Waiting
	}
	if e.a.ep == ep || (e.bridged && e.b.ep == ep) {
		return zero, Ignored
	}
	if e.bridged {
		// First-come-wins: the topic is taken. No state is kept for
		// further registrants — silence is indistinguishable from
		// acceptance to the sender.
		return zero, Ignored
	}
	e.b = registration[E]{ep: ep, deadline: r.now().Add(r.ttl)}
	e.bridged = true
	return e.a.ep, Bridged
}

// Forward resolves a PAIR_DATA frame from ep on topic: it returns the
// other bridged member iff the topic is bridged AND ep is one of its two
// members. Every other case — unknown topic, waiting topic, non-member
// sender — returns ok=false and the caller drops the frame silently.
func (r *Registry[E]) Forward(topic ident.Topic, ep E) (to E, ok bool) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.topics[topic]
	if !present || !e.bridged {
		return zero, false
	}
	switch ep {
	case e.a.ep:
		return e.b.ep, true
	case e.b.ep:
		return e.a.ep, true
	}
	return zero, false
}

// Drop unwinds ep's registration on topic (connection teardown path). If
// ep is a member — waiting or bridged — the ENTIRE entry is deleted: a
// bridged topic dies with either end, and deletion is the only "completed"
// the relay can see (PAIR_DATA is opaque). If ep is not a member of the
// current entry (the entry may already belong to fresh registrants), Drop
// is a no-op.
func (r *Registry[E]) Drop(topic ident.Topic, ep E) {
	r.mu.Lock()
	defer r.mu.Unlock()

	e, ok := r.topics[topic]
	if !ok {
		return
	}
	if e.a.ep == ep || (e.bridged && e.b.ep == ep) {
		delete(r.topics, topic)
	}
}

// Sweep evicts registrations whose 24 h cap has fired: a waiting entry
// with an overdue registration is deleted; a bridged entry is deleted when
// EITHER member is overdue (the bridge dies whole — no half-bridges). No
// signal is sent: §5.4 defines no topic-scoped teardown frame, so clients
// detect via their own handshake timeout, fail-closed (§3.1.6).
func (r *Registry[E]) Sweep() {
	now := r.now()
	r.mu.Lock()
	defer r.mu.Unlock()

	for topic, e := range r.topics {
		if now.After(e.a.deadline) || (e.bridged && now.After(e.b.deadline)) {
			delete(r.topics, topic)
		}
	}
}

// RunJanitor sweeps every JanitorInterval until ctx is done. In-memory
// only; nothing at rest.
func (r *Registry[E]) RunJanitor(ctx context.Context) {
	t := time.NewTicker(JanitorInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.Sweep()
		}
	}
}

// Len reports the number of live topic entries (tests and aggregate
// metrics — a count carries no identifiers).
func (r *Registry[E]) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.topics)
}

// BridgedCount reports the number of bridged topic entries — the same
// identifier-free class as Len (the topic_bridges gauge, note §18).
func (r *Registry[E]) BridgedCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, e := range r.topics {
		if e.bridged {
			n++
		}
	}
	return n
}
