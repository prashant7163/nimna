// Package channel implements the relay's CRID registry: per-CRID
// registration sets, the single pending-knock slot, and the
// knock → accept → bridged session state machine (spec §3.2, §3.3, §4;
// architecture note §§9–10).
//
// Entry invariants, held under the one mutex: an entry exists iff its
// registration set is non-empty (an entry never outlives its last
// registered connection); pending.from is registered; a bridged entry has
// both members registered and no pending (ACCEPT consumes the pending, and
// a KNOCK on a bridged CRID is dropped).
//
// The registration set has NO membership cap: the relay is role-blind and
// cannot authenticate CRID membership — that is Noise KK's job (§3.3.1: a
// squatter who ACCEPTs gets a bridge whose handshake fails at the clients,
// fail-closed). Capping at two would let a squatter or a stale half-dead
// connection lock out the legitimate peer. Memory stays bounded by
// connection count (S5 adds per-IP and frame-rate caps).
//
// Every state-dependent rejection is a SILENT drop (ok=false to the
// caller, nothing on the wire): a close that depended on registry state
// would itself leak that state through an observable close. Pending-knock
// expiry is equally silent — §5.4 defines no lapse frame.
//
// This package is token-free by construction: no ident.DeviceToken ever
// enters it (architecture note §11) — the registry cannot store what it
// never sees. It is a pure in-memory state machine guarded by one plain
// mutex, generic over a comparable endpoint handle, mirroring
// internal/rendezvous: operations return endpoints and the caller
// (internal/server) delivers frames outside the lock. There are no logs in
// this package.
package channel

import (
	"context"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
)

// DefaultPendingTTL is the pending-knock hold: exactly 60 s (spec §3.2
// step 3). Configurable at construction; the spec default stands.
const DefaultPendingTTL = 60 * time.Second

// JanitorInterval is the hygiene sweep tick — 10 s, finer than the topic
// janitor's 1 min because the TTL it polices is 60 s (architecture note
// §10). Correctness never depends on it: every consumer checks the
// deadline itself.
const JanitorInterval = 10 * time.Second

// pendingKnock is the at-most-one held knock on an entry.
type pendingKnock[E comparable] struct {
	from     E
	deadline time.Time
}

// entry is one CRID's state: the registration set, the bridged pair (a =
// knocker, b = accepter, valid iff bridged), and the pending-knock slot.
type entry[E comparable] struct {
	regs    map[E]struct{}
	bridged bool
	a, b    E
	pending *pendingKnock[E]
}

// livePending reports whether the entry holds an unexpired pending knock,
// lazily deleting a lapsed one (valid iff now ≤ deadline — the 60 s hold
// is exact). Callers hold the registry mutex.
func (e *entry[E]) livePending(now time.Time) bool {
	if e.pending == nil {
		return false
	}
	if now.After(e.pending.deadline) {
		e.pending = nil
		return false
	}
	return true
}

// Registry is the CRID registry, generic over a comparable endpoint handle
// (the server registers its connection pointers; tests register stubs).
// Maps key on ident.CRID directly — no identifier bytes are ever exposed.
// The zero value is not usable; call New.
type Registry[E comparable] struct {
	mu      sync.Mutex
	entries map[ident.CRID]*entry[E]
	ttl     time.Duration
	now     func() time.Time
}

// New returns a Registry with the given pending-knock hold (0 means
// DefaultPendingTTL) and clock (nil means time.Now; tests inject a fake).
func New[E comparable](ttl time.Duration, now func() time.Time) *Registry[E] {
	if ttl <= 0 {
		ttl = DefaultPendingTTL
	}
	if now == nil {
		now = time.Now
	}
	return &Registry[E]{
		entries: make(map[ident.CRID]*entry[E]),
		ttl:     ttl,
		now:     now,
	}
}

// Register processes a REGISTER_CRID from ep: add it to the CRID's
// registration set, creating the entry if absent. It never fails and never
// signals the registrant about registry state — with one deliberate
// exception: deliver reports whether an unexpired pending knock from a
// different connection is held, in which case the caller must immediately
// deliver a freshly built KNOCK_FWD to ep (deliver-on-register, note §10 —
// the push is content-free, so without this the pushed-awake peer could
// never learn WHICH CRID to accept). The pending's deadline is NOT
// refreshed. A duplicate registration is a silent idempotent no-op and
// does not re-trigger delivery.
func (r *Registry[E]) Register(crid ident.CRID, ep E) (deliver bool) {
	r.mu.Lock()
	defer r.mu.Unlock()

	e, ok := r.entries[crid]
	if !ok {
		r.entries[crid] = &entry[E]{regs: map[E]struct{}{ep: {}}}
		return false
	}
	if _, dup := e.regs[ep]; dup {
		return false
	}
	e.regs[ep] = struct{}{}
	// pending.from is always registered, and ep was not — the pending
	// cannot be ep's own; the check is kept for the invariant's sake.
	return e.livePending(r.now()) && e.pending.from != ep
}

// Knock processes a KNOCK from ep. Valid iff ep is registered on the CRID
// and the CRID is not bridged; anything else is ok=false — a silent drop.
// On success the pending slot is overwritten ({ep, now + TTL} — a fresh
// deadline, latest knocker wins) and fwd is every OTHER registered
// connection: the caller sends each a freshly built KNOCK_FWD. An empty
// fwd is the peer-offline outcome — the caller may dispatch ONE push iff
// the knock carried a token; the registry never sees tokens.
func (r *Registry[E]) Knock(crid ident.CRID, ep E) (fwd []E, ok bool) {
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.entries[crid]
	if !present || e.bridged {
		return nil, false
	}
	if _, member := e.regs[ep]; !member {
		return nil, false
	}
	e.pending = &pendingKnock[E]{from: ep, deadline: r.now().Add(r.ttl)}
	for m := range e.regs {
		if m != ep {
			fwd = append(fwd, m)
		}
	}
	return fwd, true
}

// Accept processes an ACCEPT from ep. Valid iff ep is registered, an
// unexpired pending knock from a DIFFERENT connection exists (a connection
// never bridges to itself), and the CRID is not bridged; anything else —
// including a lapsed pending, which is lazily deleted here — is ok=false,
// a silent drop. On success the pending is consumed, the entry becomes
// bridged (knocker, ep), and the caller sends SESSION_BRIDGED to both.
// First ACCEPT wins: later ones find no pending.
func (r *Registry[E]) Accept(crid ident.CRID, ep E) (knocker E, ok bool) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.entries[crid]
	if !present || e.bridged {
		return zero, false
	}
	if _, member := e.regs[ep]; !member {
		return zero, false
	}
	if !e.livePending(r.now()) {
		return zero, false
	}
	if e.pending.from == ep {
		return zero, false
	}
	knocker = e.pending.from
	e.pending = nil
	e.bridged, e.a, e.b = true, knocker, ep
	return knocker, true
}

// Forward resolves a SESSION_DATA frame from ep on crid: it returns the
// other bridge member iff the CRID is bridged AND ep is one of the two
// members — byte-identical semantics to the rendezvous Forward. Every
// other case returns ok=false and the caller drops the frame silently.
func (r *Registry[E]) Forward(crid ident.CRID, ep E) (to E, ok bool) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.entries[crid]
	if !present || !e.bridged {
		return zero, false
	}
	switch ep {
	case e.a:
		return e.b, true
	case e.b:
		return e.a, true
	}
	return zero, false
}

// Teardown processes a client→relay TEARDOWN from ep. Valid iff the CRID
// is bridged and ep is a member; anything else is a silent drop — in
// particular, a TEARDOWN never cancels a pending knock (§5.4 defines no
// knock-cancel, so none exists). On success the bridge is cleared,
// registrations survive (§3.3 "forgets the CRID" reads as the session
// state, not the registrations — else a live peer would draw a platform
// push, note §10), and the caller sends the relay TEARDOWN to other only:
// the initiator already knows.
func (r *Registry[E]) Teardown(crid ident.CRID, ep E) (other E, ok bool) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.entries[crid]
	if !present || !e.bridged {
		return zero, false
	}
	switch ep {
	case e.a:
		other = e.b
	case e.b:
		other = e.a
	default:
		return zero, false
	}
	e.bridged, e.a, e.b = false, zero, zero
	return other, true
}

// DropConn unwinds ep's registration on one CRID (connection-death path;
// disconnection is an implicit TEARDOWN, §5.4): ep leaves the registration
// set; a pending knock FROM ep dies silently (an already-delivered
// KNOCK_FWD is not retracted — a late ACCEPT just finds no pending); if ep
// was a bridge member the bridge is cleared and the survivor is returned
// for the relay→client TEARDOWN notify. The entry is deleted when its
// registration set empties — an entry never outlives its last connection.
func (r *Registry[E]) DropConn(crid ident.CRID, ep E) (survivor E, notify bool) {
	var zero E
	r.mu.Lock()
	defer r.mu.Unlock()

	e, present := r.entries[crid]
	if !present {
		return zero, false
	}
	if _, member := e.regs[ep]; !member {
		// Not registered here: by the invariants ep holds neither the
		// pending nor a bridge seat — nothing to unwind.
		return zero, false
	}
	delete(e.regs, ep)
	if e.pending != nil && e.pending.from == ep {
		e.pending = nil
	}
	if e.bridged && (ep == e.a || ep == e.b) {
		if ep == e.a {
			survivor = e.b
		} else {
			survivor = e.a
		}
		e.bridged, e.a, e.b = false, zero, zero
		notify = true
	}
	if len(e.regs) == 0 {
		delete(r.entries, crid)
	}
	return survivor, notify
}

// Sweep is memory hygiene only: it clears lapsed pending knocks sitting
// inside live entries (the entry itself lives with its registrations).
// Correctness never depends on it — Accept and deliver-on-register check
// the deadline themselves. Expiry is silent: §5.4 defines no lapse frame,
// so nothing can be sent.
func (r *Registry[E]) Sweep() {
	now := r.now()
	r.mu.Lock()
	defer r.mu.Unlock()

	for _, e := range r.entries {
		if e.pending != nil && now.After(e.pending.deadline) {
			e.pending = nil
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

// Len reports the number of live CRID entries — an identifier-free count
// (tests and, from S5, aggregate metrics).
func (r *Registry[E]) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.entries)
}

// BridgedCount reports the number of bridged (live-session) entries — the
// same identifier-free class as Len (the session_bridges gauge, note §18).
func (r *Registry[E]) BridgedCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, e := range r.entries {
		if e.bridged {
			n++
		}
	}
	return n
}

// PendingCount reports the number of held pending-knock slots, including
// lapsed ones not yet lazily deleted or swept — an identifier-free count
// (tests and aggregate metrics).
func (r *Registry[E]) PendingCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, e := range r.entries {
		if e.pending != nil {
			n++
		}
	}
	return n
}
