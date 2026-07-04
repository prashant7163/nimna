package limits

import (
	"context"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
)

// Rate-table defaults: the spec §4 numbers verbatim, plus the pinned
// cardinality guard (architecture note §15).
const (
	// DefaultKnockInterval is the knock collapse window: 1 knock per
	// CRID per 10 s, duplicates inside the window dropped silently.
	DefaultKnockInterval = 10 * time.Second
	// DefaultPushMinInterval is the per-CRID push floor: 1 per 60 s.
	DefaultPushMinInterval = 60 * time.Second
	// DefaultPushPerHour / DefaultPushPerDay are the per-CRID push caps.
	DefaultPushPerHour = 6
	DefaultPushPerDay  = 20
	// DefaultHourWindow / DefaultDayWindow are the fixed windows the
	// hour/day counters run over. Config exists so tests and the soak
	// tool can accelerate (§14: "tests and the soak tool accelerate by
	// shrinking the windows via config"); the defaults stay spec.
	DefaultHourWindow = time.Hour
	DefaultDayWindow  = 24 * time.Hour
	// MaxRateEntries is the pinned hard cap on the per-CRID table
	// (~4 MB worst case) — a memory guard, not a knob, unreachable in
	// legitimate use (§15).
	MaxRateEntries = 65536
)

// RateConfig configures a RateTable. Zero values mean the spec defaults.
// MaxEntries exists for tests only; the relay always runs the pinned cap.
type RateConfig struct {
	KnockInterval   time.Duration
	PushMinInterval time.Duration
	PushPerHour     int
	PushPerDay      int
	HourWindow      time.Duration
	DayWindow       time.Duration
	MaxEntries      int
}

func (c *RateConfig) fill() {
	if c.KnockInterval <= 0 {
		c.KnockInterval = DefaultKnockInterval
	}
	if c.PushMinInterval <= 0 {
		c.PushMinInterval = DefaultPushMinInterval
	}
	if c.PushPerHour <= 0 {
		c.PushPerHour = DefaultPushPerHour
	}
	if c.PushPerDay <= 0 {
		c.PushPerDay = DefaultPushPerDay
	}
	if c.HourWindow <= 0 {
		c.HourWindow = DefaultHourWindow
	}
	if c.DayWindow <= 0 {
		c.DayWindow = DefaultDayWindow
	}
	if c.MaxEntries <= 0 {
		c.MaxEntries = MaxRateEntries
	}
}

// KnockVerdict is the collapse decision for one KNOCK.
type KnockVerdict int

const (
	// KnockAllowed: outside the collapse window; the knock proceeds and
	// anchors a fresh window.
	KnockAllowed KnockVerdict = iota
	// KnockCollapsed: inside the window — the caller drops the knock
	// silently BEFORE any state change: no forward, no push, no pending
	// overwrite, no deadline refresh (§16). The drop does not refresh
	// the window: it anchors on accepted knocks only.
	KnockCollapsed
	// KnockUntracked: the table is at its hard cap and this CRID has no
	// entry — fail-open on the forward (§15): the knock proceeds,
	// uncounted; the caller meters the cap trip. Pushes for untracked
	// CRIDs fail closed (PushDeniedUntracked).
	KnockUntracked
)

// PushVerdict is the dispatch decision for one eligible push.
type PushVerdict int

const (
	// PushAllowed: within all three caps; the budget is charged.
	PushAllowed PushVerdict = iota
	// PushDeniedMin / PushDeniedHour / PushDeniedDay: the named cap
	// suppresses the dispatch, silently — the knock itself was
	// processed normally (§16: the caps limit platform-push
	// forwarding, not knocks).
	PushDeniedMin
	PushDeniedHour
	PushDeniedDay
	// PushDeniedUntracked: at the table cap with no entry — a dispatch
	// that cannot be counted is refused (fail-closed; filling the table
	// must never mint pushes at the platform, §15).
	PushDeniedUntracked
)

// rateEntry holds one CRID's counters and timestamps ONLY — no connection
// references, no tokens, nothing about any user (§15).
type rateEntry struct {
	lastKnock time.Time
	hasKnock  bool
	lastPush  time.Time
	hasPush   bool
	hourStart time.Time
	hourCount int
	dayStart  time.Time
	dayCount  int
	touched   time.Time
}

// RateTable is the single per-CRID rate table (§15): knock collapse
// window + push min-interval/hour/day counters. It deliberately does NOT
// live on the channel registry's entries — those die with their last
// connection, and a counter riding them would reset on reconnect churn
// and structurally could not honor a 20/day cap.
//
// Cardinality stays bounded and stateless: entries idle longer than the
// longest configured window are evicted by the janitor; a hard cap
// backstops abuse, with fail-open-forward / fail-closed-push semantics at
// the cap.
type RateTable struct {
	mu      sync.Mutex
	cfg     RateConfig
	entries map[ident.CRID]*rateEntry
	now     func() time.Time
}

// NewRateTable returns a RateTable. now is the injectable clock (nil =
// time.Now).
func NewRateTable(cfg RateConfig, now func() time.Time) *RateTable {
	cfg.fill()
	if now == nil {
		now = time.Now
	}
	return &RateTable{
		cfg:     cfg,
		entries: make(map[ident.CRID]*rateEntry),
		now:     now,
	}
}

// entry returns crid's entry, creating it if room exists; ok=false means
// the table is at cap and crid is untracked.
func (t *RateTable) entry(crid ident.CRID) (*rateEntry, bool) {
	e, ok := t.entries[crid]
	if ok {
		return e, true
	}
	if len(t.entries) >= t.cfg.MaxEntries {
		return nil, false
	}
	e = &rateEntry{}
	t.entries[crid] = e
	return e, true
}

// Knock applies the collapse window to one KNOCK on crid. Window
// semantics ("1 per 10 s"): a knock at lastKnock+10s is allowed; at
// lastKnock+9.999s it is collapsed.
func (t *RateTable) Knock(crid ident.CRID) KnockVerdict {
	t.mu.Lock()
	defer t.mu.Unlock()

	e, tracked := t.entry(crid)
	if !tracked {
		return KnockUntracked
	}
	now := t.now()
	e.touched = now
	if e.hasKnock && now.Sub(e.lastKnock) < t.cfg.KnockInterval {
		return KnockCollapsed
	}
	e.lastKnock, e.hasKnock = now, true
	return KnockAllowed
}

// Push applies the min-interval and the fixed hour/day windows to one
// eligible dispatch on crid, charging the budget only when allowed (a
// denial charges nothing — the caps are checked atomically). Boundary
// semantics match Knock: a push at lastPush+60s is allowed; the hour/day
// windows are fixed windows anchored at their first counted push and
// restart once their duration has fully elapsed.
func (t *RateTable) Push(crid ident.CRID) PushVerdict {
	t.mu.Lock()
	defer t.mu.Unlock()

	e, tracked := t.entry(crid)
	if !tracked {
		return PushDeniedUntracked
	}
	now := t.now()
	e.touched = now
	if e.hasPush && now.Sub(e.lastPush) < t.cfg.PushMinInterval {
		return PushDeniedMin
	}
	hourCount, dayCount := e.hourCount, e.dayCount
	if e.hourCount == 0 || now.Sub(e.hourStart) >= t.cfg.HourWindow {
		hourCount = 0
	}
	if e.dayCount == 0 || now.Sub(e.dayStart) >= t.cfg.DayWindow {
		dayCount = 0
	}
	if hourCount+1 > t.cfg.PushPerHour {
		return PushDeniedHour
	}
	if dayCount+1 > t.cfg.PushPerDay {
		return PushDeniedDay
	}
	if hourCount == 0 {
		e.hourStart = now
	}
	if dayCount == 0 {
		e.dayStart = now
	}
	e.hourCount, e.dayCount = hourCount+1, dayCount+1
	e.lastPush, e.hasPush = now, true
	return PushAllowed
}

// EvictAfter is the idle-eviction horizon: the longest configured window
// (§15 — 24 h at spec defaults). An entry idle longer carries no
// enforceable information.
func (t *RateTable) EvictAfter() time.Duration {
	horizon := t.cfg.DayWindow
	for _, d := range []time.Duration{t.cfg.HourWindow, t.cfg.PushMinInterval, t.cfg.KnockInterval} {
		if d > horizon {
			horizon = d
		}
	}
	return horizon
}

// Sweep evicts entries idle strictly longer than the horizon.
func (t *RateTable) Sweep() {
	horizon := t.EvictAfter()
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	for crid, e := range t.entries {
		if now.Sub(e.touched) > horizon {
			delete(t.entries, crid)
		}
	}
}

// janitorTick derives the sweep interval: 60 s at spec defaults (§15),
// scaling down with config-accelerated horizons so eviction remains
// observable in tests and soak runs.
func (t *RateTable) janitorTick() time.Duration {
	tick := t.EvictAfter() / 3
	if tick > time.Minute {
		tick = time.Minute
	}
	if tick < 10*time.Millisecond {
		tick = 10 * time.Millisecond
	}
	return tick
}

// RunJanitor sweeps until ctx is done. In-memory only; nothing at rest.
func (t *RateTable) RunJanitor(ctx context.Context) {
	tick := time.NewTicker(t.janitorTick())
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			t.Sweep()
		}
	}
}

// Len reports live rate entries — an identifier-free count (the
// rate_entries gauge).
func (t *RateTable) Len() int {
	t.mu.Lock()
	defer t.mu.Unlock()
	return len(t.entries)
}
