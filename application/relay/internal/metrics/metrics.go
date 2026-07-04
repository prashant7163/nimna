// Package metrics implements the relay's identifier-free aggregate
// instrument (architecture note §18; work-loop logging doctrine): a struct
// of sync/atomic counters incremented at event sites, plus a scrape-time
// exposition in hand-rolled Prometheus text format (version 0.0.4). No
// background aggregation goroutine exists; gauges are read live at scrape
// time from the registries' identifier-free counts and runtime stats.
//
// Label values are FIXED COMPILE-TIME ENUMERATIONS ONLY (plane, limit,
// class, outcome, cause, site) — never free-form strings — so every
// series' cardinality is fixed at build time and no identifier can ever
// become a label by construction. The exposition therefore cannot carry a
// CRID, topic, IP, device token, or code hash no matter what the caller
// does: there is no API surface that accepts a string.
//
// prometheus/client_golang was considered and not taken (§18): it is a
// dependency tree for what hand-writes as a ~30-line fmt.Fprintf loop.
package metrics

import (
	"fmt"
	"io"
	"net/http"
	"sync/atomic"
)

// Plane labels frames_forwarded_total: the rendezvous data plane
// (PAIR_DATA) or the channel data plane (SESSION_DATA).
type Plane int

const (
	PlanePair Plane = iota
	PlaneSession
	numPlanes
)

var planeNames = [numPlanes]string{"pair", "session"}

// Limit labels limit_trips_total: one value per enforced limit class
// (architecture note §§14–16). Collapsed knocks are knock_collapse trips —
// there is deliberately no duplicate series for them.
type Limit int

const (
	LimitConnIP Limit = iota
	LimitFrameRate
	LimitFrameSize
	LimitRendezvous
	LimitRegCap
	LimitKnockCollapse
	LimitPushMin
	LimitPushHour
	LimitPushDay
	LimitRateTableCap
	LimitIdle
	numLimits
)

var limitNames = [numLimits]string{
	"conn_ip", "frame_rate", "frame_size", "rendezvous", "reg_cap",
	"knock_collapse", "push_min", "push_hour", "push_day",
	"rate_table_cap", "idle",
}

// CloseClass labels closes_total: why the relay ended a connection. One
// close event is counted per connection, attributed to whichever cause
// reached teardown first.
type CloseClass int

const (
	CloseStructural CloseClass = iota
	CloseOversize
	CloseIdle
	CloseReadError
	CloseWriteError
	CloseSendOverflow
	CloseShutdown
	numCloseClasses
)

var closeNames = [numCloseClasses]string{
	"structural", "oversize", "idle", "read_error", "write_error",
	"send_overflow", "shutdown",
}

// PushOutcome labels pushes_total. Attempted = the sum across outcomes,
// not a separate series (§18): sent (transport accepted), failed
// (transport error or non-2xx status), dropped (dispatch queue overflow),
// refused (per-CRID caps or the rate-table-cap fail-closed arm suppressed
// the dispatch before it was queued).
type PushOutcome int

const (
	PushSent PushOutcome = iota
	PushFailed
	PushDropped
	PushRefused
	numPushOutcomes
)

var pushNames = [numPushOutcomes]string{"sent", "failed", "dropped", "refused"}

// Site labels panics_total: which recovered long-lived goroutine class
// panicked (architecture note §19).
type Site int

const (
	SiteRead Site = iota
	SiteWrite
	SiteJanitor
	SitePush
	SiteHTTP
	numSites
)

var siteNames = [numSites]string{"read", "write", "janitor", "push", "http"}

// Metrics is the counter set. The zero value is ready to use; all methods
// are safe on a nil receiver (a nil *Metrics is a no-op instrument, so
// leaf packages never need nil checks at event sites).
type Metrics struct {
	connectionsTotal atomic.Uint64
	framesForwarded  [numPlanes]atomic.Uint64
	knocksForwarded  atomic.Uint64
	pushes           [numPushOutcomes]atomic.Uint64
	limitTrips       [numLimits]atomic.Uint64
	closes           [numCloseClasses]atomic.Uint64
	teardownExplicit atomic.Uint64
	teardownImplicit atomic.Uint64
	panics           [numSites]atomic.Uint64
}

// New returns a fresh Metrics.
func New() *Metrics { return &Metrics{} }

// Conn counts one accepted (upgraded) connection.
func (m *Metrics) Conn() {
	if m != nil {
		m.connectionsTotal.Add(1)
	}
}

// Forwarded counts one verbatim data frame forwarded on plane p.
func (m *Metrics) Forwarded(p Plane) {
	if m != nil {
		m.framesForwarded[p].Add(1)
	}
}

// KnockForwarded counts one relay-built KNOCK_FWD delivered (live forward
// or deliver-on-register).
func (m *Metrics) KnockForwarded() {
	if m != nil {
		m.knocksForwarded.Add(1)
	}
}

// Push counts one push dispatch outcome.
func (m *Metrics) Push(o PushOutcome) {
	if m != nil {
		m.pushes[o].Add(1)
	}
}

// Trip counts one limit enforcement event.
func (m *Metrics) Trip(l Limit) {
	if m != nil {
		m.limitTrips[l].Add(1)
	}
}

// Close counts one connection close, by cause class.
func (m *Metrics) Close(c CloseClass) {
	if m != nil {
		m.closes[c].Add(1)
	}
}

// TeardownExplicit counts one client-initiated session teardown.
func (m *Metrics) TeardownExplicit() {
	if m != nil {
		m.teardownExplicit.Add(1)
	}
}

// TeardownImplicit counts one disconnect-driven implicit session teardown.
func (m *Metrics) TeardownImplicit() {
	if m != nil {
		m.teardownImplicit.Add(1)
	}
}

// Panic counts one recovered panic at site s.
func (m *Metrics) Panic(s Site) {
	if m != nil {
		m.panics[s].Add(1)
	}
}

// Gauges is a scrape-time snapshot of the live identifier-free counts: the
// registries' Len/PendingCount/BridgedCount values, the rate-table size,
// and runtime stats. The collector fills it fresh per scrape; tests fill
// it with fixed values for the golden exposition.
type Gauges struct {
	Connections    int
	Topics         int
	TopicBridges   int
	CRIDEntries    int
	PendingKnocks  int
	SessionBridges int
	RateEntries    int
	Goroutines     int
	HeapAllocBytes uint64
	HeapSysBytes   uint64
}

// prefix is the pinned series prefix (§18).
const prefix = "nimna_relay_"

// Write renders the complete pinned inventory — every series, including
// zero-valued ones, in a fixed order — in Prometheus text format 0.0.4.
func Write(w io.Writer, m *Metrics, g Gauges) {
	gauge := func(name string, v uint64) {
		fmt.Fprintf(w, "# TYPE %s%s gauge\n%s%s %d\n", prefix, name, prefix, name, v)
	}
	gauge("connections", uint64(g.Connections))
	gauge("topics", uint64(g.Topics))
	gauge("topic_bridges", uint64(g.TopicBridges))
	gauge("crid_entries", uint64(g.CRIDEntries))
	gauge("pending_knocks", uint64(g.PendingKnocks))
	gauge("session_bridges", uint64(g.SessionBridges))
	gauge("rate_entries", uint64(g.RateEntries))
	gauge("goroutines", uint64(g.Goroutines))
	gauge("heap_alloc_bytes", g.HeapAllocBytes)
	gauge("heap_sys_bytes", g.HeapSysBytes)

	fmt.Fprintf(w, "# TYPE %sconnections_total counter\n%sconnections_total %d\n",
		prefix, prefix, m.connectionsTotal.Load())

	fmt.Fprintf(w, "# TYPE %sframes_forwarded_total counter\n", prefix)
	for p := Plane(0); p < numPlanes; p++ {
		fmt.Fprintf(w, "%sframes_forwarded_total{plane=%q} %d\n",
			prefix, planeNames[p], m.framesForwarded[p].Load())
	}

	fmt.Fprintf(w, "# TYPE %sknocks_forwarded_total counter\n%sknocks_forwarded_total %d\n",
		prefix, prefix, m.knocksForwarded.Load())

	fmt.Fprintf(w, "# TYPE %spushes_total counter\n", prefix)
	for o := PushOutcome(0); o < numPushOutcomes; o++ {
		fmt.Fprintf(w, "%spushes_total{outcome=%q} %d\n",
			prefix, pushNames[o], m.pushes[o].Load())
	}

	fmt.Fprintf(w, "# TYPE %slimit_trips_total counter\n", prefix)
	for l := Limit(0); l < numLimits; l++ {
		fmt.Fprintf(w, "%slimit_trips_total{limit=%q} %d\n",
			prefix, limitNames[l], m.limitTrips[l].Load())
	}

	fmt.Fprintf(w, "# TYPE %scloses_total counter\n", prefix)
	for c := CloseClass(0); c < numCloseClasses; c++ {
		fmt.Fprintf(w, "%scloses_total{class=%q} %d\n",
			prefix, closeNames[c], m.closes[c].Load())
	}

	fmt.Fprintf(w, "# TYPE %steardowns_total counter\n", prefix)
	fmt.Fprintf(w, "%steardowns_total{cause=\"explicit\"} %d\n", prefix, m.teardownExplicit.Load())
	fmt.Fprintf(w, "%steardowns_total{cause=\"implicit\"} %d\n", prefix, m.teardownImplicit.Load())

	fmt.Fprintf(w, "# TYPE %spanics_total counter\n", prefix)
	for s := Site(0); s < numSites; s++ {
		fmt.Fprintf(w, "%spanics_total{site=%q} %d\n",
			prefix, siteNames[s], m.panics[s].Load())
	}
}

// Handler serves GET /metrics on the ops listener; everything else — every
// other path AND every other method — 404s (§18: the ops port speaks
// exactly one thing). gauges is called once per scrape.
func Handler(m *Metrics, gauges func() Gauges) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/metrics" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		Write(w, m, gauges())
	})
}
