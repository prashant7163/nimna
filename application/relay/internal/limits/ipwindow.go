package limits

import (
	"context"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
)

// IPWindow is the per-IP rendezvous throttle (spec §4 "single-digit
// attempts per minute"; architecture note §15): a fixed 60 s window
// counter per canonical IP key, counting REGISTER_TOPIC frames only — the
// throttle exists to impede code brute-forcing; REGISTER_CRID is not a
// guessing surface (128-bit identifiers) and is bounded by the frame-rate
// and registration caps instead.
//
// Every frame counts against the window, allowed or not; a frame is
// allowed while the window's count is within the limit. A throttled
// REGISTER_TOPIC is silently dropped by the caller — registration has no
// ack (§3.1.6), so the drop is byte-identical to acceptance and the
// prober cannot even tell which probes counted (§16).
type IPWindow struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	wins   map[ident.RemoteAddr]*ipWin
	now    func() time.Time
}

type ipWin struct {
	start time.Time
	count int
}

// DefaultRendezvousPerMin is the spec-shaped default: 6 = three code
// entries a minute (a joiner costs two registrations, today+yesterday) —
// typo-friendly, brute-force-hostile (§14).
const DefaultRendezvousPerMin = 6

// NewIPWindow returns a throttle allowing limit frames per fixed window
// per IP key. Zero/negative limit means DefaultRendezvousPerMin; zero
// window means one minute. now is the injectable clock (nil = time.Now).
func NewIPWindow(limit int, window time.Duration, now func() time.Time) *IPWindow {
	if limit <= 0 {
		limit = DefaultRendezvousPerMin
	}
	if window <= 0 {
		window = time.Minute
	}
	if now == nil {
		now = time.Now
	}
	return &IPWindow{
		limit:  limit,
		window: window,
		wins:   make(map[ident.RemoteAddr]*ipWin),
		now:    now,
	}
}

// Allow counts one REGISTER_TOPIC from key and reports whether it is
// within the window's limit. A lapsed window restarts at this frame
// (lazy expiry).
func (w *IPWindow) Allow(key ident.RemoteAddr) bool {
	w.mu.Lock()
	defer w.mu.Unlock()

	now := w.now()
	win, ok := w.wins[key]
	if !ok || now.Sub(win.start) >= w.window {
		w.wins[key] = &ipWin{start: now, count: 1}
		return w.limit >= 1
	}
	win.count++
	return win.count <= w.limit
}

// Sweep drops lapsed windows (memory hygiene; correctness is lazy).
func (w *IPWindow) Sweep() {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := w.now()
	for key, win := range w.wins {
		if now.Sub(win.start) >= w.window {
			delete(w.wins, key)
		}
	}
}

// RunJanitor sweeps once per window until ctx is done.
func (w *IPWindow) RunJanitor(ctx context.Context) {
	t := time.NewTicker(w.window)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			w.Sweep()
		}
	}
}

// Len reports live window entries — an identifier-free count.
func (w *IPWindow) Len() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.wins)
}
