// Package limits implements the relay's transport-boundary and per-key
// rate enforcement (spec §4; architecture note §§14–17): the per-conn
// frame-rate token bucket, the per-IP rendezvous window, the bounded
// per-CRID knock/push rate table, and the limit listener (per-IP
// connection cap + liveness deadline).
//
// Every table here is spec §4's own named "rate/push counters" transient
// class — in-memory, user-anonymous, reset on restart, dies with the
// process. Maps key on internal/ident wrapper types only; no identifier
// bytes are exposed, logged, or reachable from this package's API.
//
// Enforcement outcomes are returned to the caller as verdicts; the caller
// (internal/server, or the listener itself at the accept boundary) applies
// §16's silence adjudication: silent drops or bare closes, never a
// response surface. This package sends no frames and writes no logs.
package limits

import (
	"sync"
	"time"
)

// Bucket is a hand-rolled token bucket (architecture note §15: rate
// arithmetic, not crypto — no x/time/rate dependency for a fmt-sized
// loop). One token is charged per WebSocket message read, before parse.
// The read loop calls Reserve and sleeps out the returned wait, so the
// sender experiences throughput shaping, never an error (§16: dropping
// would break the per-message rekey chain; closing would kill a
// legitimate media send).
//
// A Bucket is used by a single reader goroutine but is mutex-guarded so
// nothing depends on that.
type Bucket struct {
	mu     sync.Mutex
	rate   float64 // tokens per second
	burst  float64
	tokens float64
	last   time.Time
	now    func() time.Time
}

// NewBucket returns a full bucket refilling at rate tokens/second up to
// burst. now is the injectable clock (nil means time.Now).
func NewBucket(rate float64, burst int, now func() time.Time) *Bucket {
	if now == nil {
		now = time.Now
	}
	b := &Bucket{rate: rate, burst: float64(burst), now: now}
	b.tokens = b.burst
	b.last = now()
	return b
}

// Reserve spends one token and returns how long the caller must wait
// before acting on it: zero while the bucket has tokens, else the exact
// refill time for the deficit. The token is committed either way (the
// caller sleeps, it does not retry), so consecutive reservations queue
// up back-to-back at the configured rate.
func (b *Bucket) Reserve() time.Duration {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := b.now()
	b.tokens += now.Sub(b.last).Seconds() * b.rate
	if b.tokens > b.burst {
		b.tokens = b.burst
	}
	b.last = now
	b.tokens--
	if b.tokens >= 0 {
		return 0
	}
	return time.Duration(-b.tokens / b.rate * float64(time.Second))
}
