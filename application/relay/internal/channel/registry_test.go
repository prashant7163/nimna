package channel

import (
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
)

// Tests are named TestRowNN… after the normative edge-semantics table in
// architecture note §10, so the reviewer can map every row to its covering
// test. Rows whose observable behavior is wire-level (4, 7, and the
// forward/push/verbatim legs of 8–10, 18, 20–23) have their authoritative
// wire assertions in internal/server; the state transitions behind them
// are pinned here.

// fakeClock is an injectable clock: tests never sleep.
type fakeClock struct{ t time.Time }

func newFakeClock() *fakeClock {
	return &fakeClock{t: time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) now() time.Time          { return c.t }
func (c *fakeClock) advance(d time.Duration) { c.t = c.t.Add(d) }

func crid(b byte) ident.CRID {
	var raw [16]byte
	raw[0] = b
	return ident.CRIDFromWire(raw)
}

// Endpoints are plain strings in tests — the registry is generic over any
// comparable handle.
func newRegistry(clk *fakeClock) *Registry[string] {
	return New[string](0, clk.now)
}

// bridge builds the standard fixture: A and B registered, A knocked,
// B accepted — bridged (A, B).
func bridge(t *testing.T, r *Registry[string], id ident.CRID) {
	t.Helper()
	r.Register(id, "A")
	r.Register(id, "B")
	if _, ok := r.Knock(id, "A"); !ok {
		t.Fatal("fixture: knock failed")
	}
	if knocker, ok := r.Accept(id, "B"); !ok || knocker != "A" {
		t.Fatal("fixture: accept failed")
	}
}

// Row 1: a duplicate REGISTER_CRID from the same connection is a silent
// idempotent no-op and does NOT re-trigger pending delivery.
func TestRow01DuplicateRegistrationIdempotentNoRedelivery(t *testing.T) {
	r := newRegistry(newFakeClock())
	if deliver := r.Register(crid(1), "A"); deliver {
		t.Fatal("first registration: nothing pending, deliver must be false")
	}
	if deliver := r.Register(crid(1), "A"); deliver {
		t.Fatal("duplicate registration must not deliver")
	}
	if r.Len() != 1 {
		t.Fatalf("Len: got %d, want 1", r.Len())
	}

	// With a live pending held, a duplicate registration still must not
	// re-trigger delivery.
	r.Register(crid(1), "B")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	if deliver := r.Register(crid(1), "B"); deliver {
		t.Fatal("duplicate registration with live pending must not re-deliver")
	}
}

// Row 2: a third (and further) connection is added to the registration
// set — no cap at S4, no signal.
func TestRow02ThirdConnectionAddedToRegs(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if deliver := r.Register(crid(1), "C"); deliver {
		t.Fatal("no pending: third registrant must get no delivery")
	}
	if r.Len() != 1 {
		t.Fatalf("Len: got %d, want 1 (one entry, three members)", r.Len())
	}

	// All three are members: a knock from A forwards to both others.
	fwd, ok := r.Knock(crid(1), "A")
	if !ok || len(fwd) != 2 {
		t.Fatalf("knock forward set: got %v (ok=%v), want B and C", fwd, ok)
	}
	seen := map[string]bool{}
	for _, m := range fwd {
		seen[m] = true
	}
	if !seen["B"] || !seen["C"] {
		t.Fatalf("forward set %v must be exactly {B, C}", fwd)
	}
}

// Row 3: registering a CRID that holds an unexpired pending knock from a
// different connection reports deliver=true (deliver-on-register); the
// deadline is NOT refreshed.
func TestRow03DeliverOnRegisterUnexpiredPending(t *testing.T) {
	clk := newFakeClock()
	r := newRegistry(clk)
	r.Register(crid(1), "A")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}

	clk.advance(30 * time.Second)
	if deliver := r.Register(crid(1), "B"); !deliver {
		t.Fatal("registrant must be told to deliver the held KNOCK_FWD")
	}

	// The deadline was not refreshed by B's delivery: 31 s later the
	// original 60 s window has lapsed and a further registrant gets
	// nothing (and the lapsed pending is lazily deleted).
	clk.advance(31 * time.Second)
	if deliver := r.Register(crid(1), "C"); deliver {
		t.Fatal("lapsed pending must not deliver — deadline must not refresh on register")
	}
	if r.PendingCount() != 0 {
		t.Fatal("lapsed pending must be lazily deleted on the register path")
	}
}

// Row 5: a KNOCK from a connection not registered on the CRID is a silent
// drop — including on a CRID with no entry at all (nothing is created).
func TestRow05KnockFromUnregisteredDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	if _, ok := r.Knock(crid(9), "A"); ok {
		t.Fatal("knock on an absent CRID must be dropped")
	}
	if r.Len() != 0 {
		t.Fatal("a dropped knock must not create an entry")
	}

	r.Register(crid(1), "A")
	if _, ok := r.Knock(crid(1), "B"); ok {
		t.Fatal("knock from a non-member must be dropped")
	}
	if r.PendingCount() != 0 {
		t.Fatal("a dropped knock must not set a pending")
	}
}

// Row 6: a KNOCK on a bridged CRID is a silent drop — member or not.
func TestRow06KnockOnBridgedDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))
	r.Register(crid(1), "C") // registered third party

	for _, ep := range []string{"A", "B", "C", "D"} {
		if _, ok := r.Knock(crid(1), ep); ok {
			t.Fatalf("knock from %q on a bridged CRID must be dropped", ep)
		}
	}
	if r.PendingCount() != 0 {
		t.Fatal("bridged entry must hold no pending")
	}
}

// Row 8 (state leg): a valid KNOCK returns every registered connection
// except the knocker, and overwrites the pending slot.
func TestRow08KnockForwardSetExcludesKnocker(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	fwd, ok := r.Knock(crid(1), "A")
	if !ok || len(fwd) != 1 || fwd[0] != "B" {
		t.Fatalf("forward set: got %v (ok=%v), want [B]", fwd, ok)
	}
	if r.PendingCount() != 1 {
		t.Fatal("a forwarded knock still sets the pending (the peer may reconnect to ACCEPT)")
	}
}

// Row 9 (state leg): a valid KNOCK with an empty forward set — the
// peer-offline outcome — holds the pending and nothing else.
func TestRow09OfflineKnockPendingOnly(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	fwd, ok := r.Knock(crid(1), "A")
	if !ok {
		t.Fatal("knock from the sole registrant must be valid")
	}
	if len(fwd) != 0 {
		t.Fatalf("forward set: got %v, want empty (peer offline)", fwd)
	}
	if r.PendingCount() != 1 {
		t.Fatal("pending must be held for the 60 s window")
	}
}

// Row 11: a second KNOCK while one is pending overwrites it — latest
// knocker, fresh 60 s deadline.
func TestRow11SecondKnockOverwritesPendingFreshDeadline(t *testing.T) {
	clk := newFakeClock()
	r := newRegistry(clk)
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	r.Register(crid(1), "C")

	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("first knock failed")
	}
	clk.advance(40 * time.Second)
	if _, ok := r.Knock(crid(1), "B"); !ok {
		t.Fatal("second knock failed")
	}
	if r.PendingCount() != 1 {
		t.Fatal("the pending slot is single: overwrite, not accumulate")
	}

	// 30 s later the FIRST knock's window (60 s) has lapsed but the
	// second's (fresh deadline) has not: the accept bridges to B.
	clk.advance(30 * time.Second)
	knocker, ok := r.Accept(crid(1), "C")
	if !ok || knocker != "B" {
		t.Fatalf("accept: got (%q, %v), want (B, true) — latest knocker wins", knocker, ok)
	}
}

// Row 12: an ACCEPT with no pending, or with an expired pending, is a
// silent drop; the lapsed pending is lazily deleted.
func TestRow12AcceptNoPendingOrExpiredDropped(t *testing.T) {
	clk := newFakeClock()
	r := newRegistry(clk)
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")

	if _, ok := r.Accept(crid(1), "B"); ok {
		t.Fatal("accept with no pending must be dropped")
	}

	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	clk.advance(DefaultPendingTTL + time.Nanosecond)
	if _, ok := r.Accept(crid(1), "B"); ok {
		t.Fatal("accept after the 60 s window must be dropped")
	}
	if r.PendingCount() != 0 {
		t.Fatal("the lapsed pending must be lazily deleted by the accept path")
	}
}

// Row 13: an ACCEPT from the pending knocker's own connection is a silent
// drop — a connection never bridges to itself; the pending survives.
func TestRow13AcceptFromKnockerDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	if _, ok := r.Accept(crid(1), "A"); ok {
		t.Fatal("self-accept must be dropped")
	}
	// The pending is untouched: B can still accept.
	if knocker, ok := r.Accept(crid(1), "B"); !ok || knocker != "A" {
		t.Fatal("pending must survive a dropped self-accept")
	}
}

// Row 14: an ACCEPT from a connection not registered on the CRID is a
// silent drop.
func TestRow14AcceptFromUnregisteredDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	if _, ok := r.Accept(crid(1), "C"); ok {
		t.Fatal("accept from a non-member must be dropped")
	}
	if _, ok := r.Accept(crid(9), "C"); ok {
		t.Fatal("accept on an absent CRID must be dropped")
	}
}

// Row 15: an ACCEPT on an already-bridged CRID is a silent drop (the
// pending was consumed at bridge; the guard holds anyway).
func TestRow15AcceptOnBridgedDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))
	r.Register(crid(1), "C")
	for _, ep := range []string{"A", "B", "C"} {
		if _, ok := r.Accept(crid(1), ep); ok {
			t.Fatalf("accept from %q on a bridged CRID must be dropped", ep)
		}
	}
}

// Row 16: a valid ACCEPT consumes the pending, bridges (knocker,
// accepter), and first ACCEPT wins — a later one finds no pending (row
// 12).
func TestRow16AcceptBridgesFirstWins(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	r.Register(crid(1), "C")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}

	knocker, ok := r.Accept(crid(1), "B")
	if !ok || knocker != "A" {
		t.Fatalf("accept: got (%q, %v), want (A, true)", knocker, ok)
	}
	if r.PendingCount() != 0 {
		t.Fatal("the pending must be consumed at bridge")
	}
	// Second ACCEPT loses: no pending remains.
	if _, ok := r.Accept(crid(1), "C"); ok {
		t.Fatal("second accept must be dropped — first ACCEPT wins")
	}
	// The bridge is (A, B).
	if to, ok := r.Forward(crid(1), "A"); !ok || to != "B" {
		t.Fatal("bridge must resolve A→B")
	}
}

// Row 17: SESSION_DATA resolution on an unbridged CRID, or from a
// non-member, is a silent drop.
func TestRow17ForwardUnbridgedOrNonMemberDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	if _, ok := r.Forward(crid(9), "A"); ok {
		t.Fatal("forward on an absent CRID must be dropped")
	}
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if _, ok := r.Forward(crid(1), "A"); ok {
		t.Fatal("forward on an unbridged CRID must be dropped, even from a member")
	}
	bridge(t, r, crid(2))
	r.Register(crid(2), "C")
	if _, ok := r.Forward(crid(2), "C"); ok {
		t.Fatal("forward from a registered non-bridge-member must be dropped")
	}
	if _, ok := r.Forward(crid(2), "D"); ok {
		t.Fatal("forward from a stranger must be dropped")
	}
}

// Row 18 (state leg): from a bridge member, Forward resolves the OTHER
// member, both directions. (Verbatim byte forwarding is asserted at the
// wire in internal/server.)
func TestRow18ForwardResolvesOtherMember(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))
	if to, ok := r.Forward(crid(1), "A"); !ok || to != "B" {
		t.Fatalf("Forward A: got (%q, %v), want (B, true)", to, ok)
	}
	if to, ok := r.Forward(crid(1), "B"); !ok || to != "A" {
		t.Fatalf("Forward B: got (%q, %v), want (A, true)", to, ok)
	}
}

// Row 19: a client TEARDOWN on an unbridged CRID, or from a non-member,
// is a silent drop — and a TEARDOWN never cancels a pending knock (§5.4
// defines no knock-cancel, so none exists).
func TestRow19TeardownUnbridgedOrNonMemberDroppedPendingSurvives(t *testing.T) {
	r := newRegistry(newFakeClock())
	if _, ok := r.Teardown(crid(9), "A"); ok {
		t.Fatal("teardown on an absent CRID must be dropped")
	}

	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	// TEARDOWN while pending, even from the knocker: dropped, pending
	// survives.
	if _, ok := r.Teardown(crid(1), "A"); ok {
		t.Fatal("teardown on an unbridged CRID must be dropped")
	}
	if r.PendingCount() != 1 {
		t.Fatal("a TEARDOWN must never cancel a pending knock")
	}
	if knocker, ok := r.Accept(crid(1), "B"); !ok || knocker != "A" {
		t.Fatal("the pending must still bridge after the dropped teardown")
	}

	// Bridged now: a registered non-member's TEARDOWN is dropped and the
	// bridge is untouched.
	r.Register(crid(1), "C")
	if _, ok := r.Teardown(crid(1), "C"); ok {
		t.Fatal("teardown from a non-bridge-member must be dropped")
	}
	if to, ok := r.Forward(crid(1), "A"); !ok || to != "B" {
		t.Fatal("bridge must survive a non-member teardown")
	}
}

// Row 20: a TEARDOWN from a bridge member clears the bridge, returns the
// OTHER member for the notify, and leaves every registration in place —
// re-knock without re-register is legal and expected.
func TestRow20TeardownClearsBridgeRegistrationsSurvive(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))

	other, ok := r.Teardown(crid(1), "A")
	if !ok || other != "B" {
		t.Fatalf("teardown: got (%q, %v), want (B, true)", other, ok)
	}
	if _, ok := r.Forward(crid(1), "A"); ok {
		t.Fatal("bridge must be cleared")
	}
	if r.Len() != 1 {
		t.Fatal("the entry must survive: registrations outlive the bridge")
	}
	// Both members are still registered: a fresh knock forwards to B.
	fwd, ok := r.Knock(crid(1), "A")
	if !ok || len(fwd) != 1 || fwd[0] != "B" {
		t.Fatalf("re-knock after teardown: got %v (ok=%v), want [B]", fwd, ok)
	}
}

// Row 21: connection death of a bridge member is an implicit TEARDOWN —
// bridge cleared, survivor returned for the notify, survivor's
// registration untouched.
func TestRow21BridgeMemberDeathReturnsSurvivor(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))

	survivor, notify := r.DropConn(crid(1), "A")
	if !notify || survivor != "B" {
		t.Fatalf("DropConn: got (%q, %v), want (B, true)", survivor, notify)
	}
	if r.Len() != 1 {
		t.Fatal("B's registration must keep the entry alive")
	}
	// The survivor is still registered: it can knock again.
	if _, ok := r.Knock(crid(1), "B"); !ok {
		t.Fatal("survivor must remain registered after the implicit teardown")
	}
}

// Row 22: connection death of the pending knocker deletes the pending
// silently; a late ACCEPT then finds nothing (row 12).
func TestRow22PendingKnockerDeathDeletesPending(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}

	survivor, notify := r.DropConn(crid(1), "A")
	if notify || survivor != "" {
		t.Fatal("no bridge existed: nothing to notify")
	}
	if r.PendingCount() != 0 {
		t.Fatal("the knocker's pending must die with its connection")
	}
	if _, ok := r.Accept(crid(1), "B"); ok {
		t.Fatal("a late ACCEPT after the knocker's death must be dropped")
	}
}

// Row 23: on simultaneous TEARDOWNs, the first clears and notifies; the
// second finds no bridge (row 19).
func TestRow23SecondTeardownDropped(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))

	if other, ok := r.Teardown(crid(1), "A"); !ok || other != "B" {
		t.Fatal("first teardown must clear and notify")
	}
	if _, ok := r.Teardown(crid(1), "B"); ok {
		t.Fatal("second teardown must find no bridge")
	}
}

// --- Entry lifetime & pending TTL -------------------------------------------

// TestEntryDeletedWhenRegsEmpty pins the entry invariant: an entry exists
// iff its registration set is non-empty.
func TestEntryDeletedWhenRegsEmpty(t *testing.T) {
	r := newRegistry(newFakeClock())

	r.Register(crid(1), "A")
	r.DropConn(crid(1), "A")
	if r.Len() != 0 {
		t.Fatal("sole registrant's death must delete the entry")
	}

	// Bridged pair: both die, entry dies with the second.
	bridge(t, r, crid(2))
	r.DropConn(crid(2), "A")
	if r.Len() != 1 {
		t.Fatal("survivor must keep the entry alive")
	}
	r.DropConn(crid(2), "B")
	if r.Len() != 0 {
		t.Fatal("the entry must die with its last registration")
	}

	// DropConn for a stranger or on an absent CRID is a no-op.
	r.Register(crid(3), "A")
	r.DropConn(crid(3), "X")
	r.DropConn(crid(9), "A")
	if r.Len() != 1 {
		t.Fatal("a stranger's DropConn must not delete another's entry")
	}
}

// TestPendingTTLExactBoundary pins the exact 60 s hold with the fake
// clock: alive strictly inside the window, alive at exactly now ==
// deadline (note §10: valid iff now ≤ deadline), dead the instant after.
func TestPendingTTLExactBoundary(t *testing.T) {
	setup := func() (*fakeClock, *Registry[string]) {
		clk := newFakeClock()
		r := newRegistry(clk)
		r.Register(crid(1), "A")
		r.Register(crid(1), "B")
		if _, ok := r.Knock(crid(1), "A"); !ok {
			t.Fatal("knock failed")
		}
		return clk, r
	}

	t.Run("alive-at-60s-minus-1", func(t *testing.T) {
		clk, r := setup()
		clk.advance(DefaultPendingTTL - time.Second)
		if _, ok := r.Accept(crid(1), "B"); !ok {
			t.Fatal("pending must survive inside the 60 s window")
		}
	})
	t.Run("alive-at-exactly-60s", func(t *testing.T) {
		clk, r := setup()
		clk.advance(DefaultPendingTTL)
		if _, ok := r.Accept(crid(1), "B"); !ok {
			t.Fatal("pending is valid at now == deadline (now ≤ deadline, note §10)")
		}
	})
	t.Run("dead-just-after-60s", func(t *testing.T) {
		clk, r := setup()
		clk.advance(DefaultPendingTTL + time.Nanosecond)
		if _, ok := r.Accept(crid(1), "B"); ok {
			t.Fatal("pending must be dead past the 60 s window")
		}
	})
	t.Run("deliver-on-register-same-boundary", func(t *testing.T) {
		clk, r := setup()
		clk.advance(DefaultPendingTTL)
		if deliver := r.Register(crid(1), "C"); !deliver {
			t.Fatal("deliver-on-register must honor now == deadline as alive")
		}
		clk.advance(time.Nanosecond)
		if deliver := r.Register(crid(1), "D"); deliver {
			t.Fatal("deliver-on-register must treat now > deadline as no-pending")
		}
	})
}

// TestPendingConsumedOnBridge: the pending never coexists with a bridge.
func TestPendingConsumedOnBridge(t *testing.T) {
	r := newRegistry(newFakeClock())
	bridge(t, r, crid(1))
	if r.PendingCount() != 0 {
		t.Fatal("bridging must consume the pending")
	}
	r.Sweep() // and the sweep finds nothing to do
	if r.Len() != 1 {
		t.Fatal("sweep must not disturb a live entry")
	}
}

// TestSweepClearsLapsedPendingKeepsEntry: the 10 s janitor sweep is memory
// hygiene only — it clears lapsed pendings inside live entries and never
// touches the entry itself (which lives with its registrations).
func TestSweepClearsLapsedPendingKeepsEntry(t *testing.T) {
	clk := newFakeClock()
	r := newRegistry(clk)
	r.Register(crid(1), "A")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}

	clk.advance(DefaultPendingTTL - time.Second)
	r.Sweep()
	if r.PendingCount() != 1 {
		t.Fatal("sweep must keep an unexpired pending")
	}

	clk.advance(2 * time.Second) // now past the deadline
	r.Sweep()
	if r.PendingCount() != 0 {
		t.Fatal("sweep must clear the lapsed pending")
	}
	if r.Len() != 1 {
		t.Fatal("sweep must never delete the entry — it lives with its registrations")
	}
}

// TestCustomPendingTTLHonored: the hold is config with the spec default.
func TestCustomPendingTTLHonored(t *testing.T) {
	clk := newFakeClock()
	r := New[string](5*time.Second, clk.now)
	r.Register(crid(1), "A")
	r.Register(crid(1), "B")
	if _, ok := r.Knock(crid(1), "A"); !ok {
		t.Fatal("knock failed")
	}
	clk.advance(5*time.Second + time.Nanosecond)
	if _, ok := r.Accept(crid(1), "B"); ok {
		t.Fatal("custom TTL must drive the pending deadline")
	}
}

// TestIndependentCRIDs: entries are independent; one connection may hold
// many CRIDs.
func TestIndependentCRIDs(t *testing.T) {
	r := newRegistry(newFakeClock())
	r.Register(crid(1), "A")
	r.Register(crid(2), "A")
	r.Register(crid(1), "B")

	r.DropConn(crid(1), "A")
	if r.Len() != 2 {
		t.Fatalf("Len: got %d, want 2 (crid 1 lives with B, crid 2 with A)", r.Len())
	}
	if _, ok := r.Knock(crid(2), "A"); !ok {
		t.Fatal("crid 2 must be untouched by the crid 1 unwind")
	}
}
