package metrics

import (
	"bytes"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

// populated returns a Metrics with every counter class touched, plus a
// fully non-zero gauge snapshot — so the golden test proves the complete
// inventory renders, not just the zero paths.
func populated() (*Metrics, Gauges) {
	m := New()
	m.Conn()
	m.Conn()
	m.Forwarded(PlanePair)
	m.Forwarded(PlaneSession)
	m.Forwarded(PlaneSession)
	m.KnockForwarded()
	m.Push(PushSent)
	m.Push(PushFailed)
	m.Push(PushDropped)
	m.Push(PushRefused)
	for l := Limit(0); l < numLimits; l++ {
		m.Trip(l)
	}
	m.Trip(LimitKnockCollapse)
	for c := CloseClass(0); c < numCloseClasses; c++ {
		m.Close(c)
	}
	m.TeardownExplicit()
	m.TeardownImplicit()
	m.TeardownImplicit()
	for s := Site(0); s < numSites; s++ {
		m.Panic(s)
	}
	g := Gauges{
		Connections: 3, Topics: 4, TopicBridges: 1, CRIDEntries: 5,
		PendingKnocks: 2, SessionBridges: 1, RateEntries: 7,
		Goroutines: 21, HeapAllocBytes: 1048576, HeapSysBytes: 8388608,
	}
	return m, g
}

// TestExpositionGolden pins the exact exposition bytes for a populated
// instrument: the full fixed inventory, fixed order, Prometheus text
// format 0.0.4. Any inventory or format drift fails here first.
func TestExpositionGolden(t *testing.T) {
	m, g := populated()
	var buf bytes.Buffer
	Write(&buf, m, g)

	want := `# TYPE nimna_relay_connections gauge
nimna_relay_connections 3
# TYPE nimna_relay_topics gauge
nimna_relay_topics 4
# TYPE nimna_relay_topic_bridges gauge
nimna_relay_topic_bridges 1
# TYPE nimna_relay_crid_entries gauge
nimna_relay_crid_entries 5
# TYPE nimna_relay_pending_knocks gauge
nimna_relay_pending_knocks 2
# TYPE nimna_relay_session_bridges gauge
nimna_relay_session_bridges 1
# TYPE nimna_relay_rate_entries gauge
nimna_relay_rate_entries 7
# TYPE nimna_relay_goroutines gauge
nimna_relay_goroutines 21
# TYPE nimna_relay_heap_alloc_bytes gauge
nimna_relay_heap_alloc_bytes 1048576
# TYPE nimna_relay_heap_sys_bytes gauge
nimna_relay_heap_sys_bytes 8388608
# TYPE nimna_relay_connections_total counter
nimna_relay_connections_total 2
# TYPE nimna_relay_frames_forwarded_total counter
nimna_relay_frames_forwarded_total{plane="pair"} 1
nimna_relay_frames_forwarded_total{plane="session"} 2
# TYPE nimna_relay_knocks_forwarded_total counter
nimna_relay_knocks_forwarded_total 1
# TYPE nimna_relay_pushes_total counter
nimna_relay_pushes_total{outcome="sent"} 1
nimna_relay_pushes_total{outcome="failed"} 1
nimna_relay_pushes_total{outcome="dropped"} 1
nimna_relay_pushes_total{outcome="refused"} 1
# TYPE nimna_relay_limit_trips_total counter
nimna_relay_limit_trips_total{limit="conn_ip"} 1
nimna_relay_limit_trips_total{limit="frame_rate"} 1
nimna_relay_limit_trips_total{limit="frame_size"} 1
nimna_relay_limit_trips_total{limit="rendezvous"} 1
nimna_relay_limit_trips_total{limit="reg_cap"} 1
nimna_relay_limit_trips_total{limit="knock_collapse"} 2
nimna_relay_limit_trips_total{limit="push_min"} 1
nimna_relay_limit_trips_total{limit="push_hour"} 1
nimna_relay_limit_trips_total{limit="push_day"} 1
nimna_relay_limit_trips_total{limit="rate_table_cap"} 1
nimna_relay_limit_trips_total{limit="idle"} 1
# TYPE nimna_relay_closes_total counter
nimna_relay_closes_total{class="structural"} 1
nimna_relay_closes_total{class="oversize"} 1
nimna_relay_closes_total{class="idle"} 1
nimna_relay_closes_total{class="read_error"} 1
nimna_relay_closes_total{class="write_error"} 1
nimna_relay_closes_total{class="send_overflow"} 1
nimna_relay_closes_total{class="shutdown"} 1
# TYPE nimna_relay_teardowns_total counter
nimna_relay_teardowns_total{cause="explicit"} 1
nimna_relay_teardowns_total{cause="implicit"} 2
# TYPE nimna_relay_panics_total counter
nimna_relay_panics_total{site="read"} 1
nimna_relay_panics_total{site="write"} 1
nimna_relay_panics_total{site="janitor"} 1
nimna_relay_panics_total{site="push"} 1
nimna_relay_panics_total{site="http"} 1
`
	if got := buf.String(); got != want {
		t.Errorf("exposition drifted from golden.\ngot:\n%s\nwant:\n%s", got, want)
	}
}

// Prometheus text format 0.0.4, as this exposition uses it: a # TYPE line
// or a sample line with an optional single fixed label and an unsigned
// integer value.
var (
	typeLine   = regexp.MustCompile(`^# TYPE nimna_relay_[a-z_]+ (counter|gauge)$`)
	sampleLine = regexp.MustCompile(`^nimna_relay_[a-z_]+(\{[a-z]+="[a-z_]+"\})? [0-9]+$`)
)

// TestExpositionParseable asserts every emitted line matches the format —
// nothing free-form can appear, in names, labels, or values.
func TestExpositionParseable(t *testing.T) {
	m, g := populated()
	var buf bytes.Buffer
	Write(&buf, m, g)

	for _, line := range strings.Split(strings.TrimRight(buf.String(), "\n"), "\n") {
		if !typeLine.MatchString(line) && !sampleLine.MatchString(line) {
			t.Errorf("line %q is neither a TYPE line nor a fixed-label sample", line)
		}
	}
}

// TestExpositionIdentifierFree pins the by-construction claim: every label
// value in the output belongs to the compile-time enumerations, and no
// hex-run or address-shaped string appears anywhere. The gauge/counter
// VALUES are aggregate integers; the assertion here is about names and
// labels, where an identifier would have to live.
func TestExpositionIdentifierFree(t *testing.T) {
	m, g := populated()
	var buf bytes.Buffer
	Write(&buf, m, g)
	out := buf.String()

	fixed := map[string]bool{"explicit": true, "implicit": true}
	for _, n := range planeNames {
		fixed[n] = true
	}
	for _, n := range limitNames {
		fixed[n] = true
	}
	for _, n := range closeNames {
		fixed[n] = true
	}
	for _, n := range pushNames {
		fixed[n] = true
	}
	for _, n := range siteNames {
		fixed[n] = true
	}
	label := regexp.MustCompile(`\{[a-z]+="([^"]*)"\}`)
	for _, match := range label.FindAllStringSubmatch(out, -1) {
		if !fixed[match[1]] {
			t.Errorf("label value %q is not in the compile-time enumerations", match[1])
		}
	}
	if hexRun := regexp.MustCompile(`[0-9a-fA-F]{16,}`).FindString(out); hexRun != "" {
		t.Errorf("exposition contains a hex run %q — identifier-shaped", hexRun)
	}
	if addr := regexp.MustCompile(`[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+`).FindString(out); addr != "" {
		t.Errorf("exposition contains an address-shaped string %q", addr)
	}
}

// TestNilMetricsSafe pins that a nil *Metrics is a no-op instrument: leaf
// packages call event methods without nil checks.
func TestNilMetricsSafe(t *testing.T) {
	var m *Metrics
	m.Conn()
	m.Forwarded(PlanePair)
	m.KnockForwarded()
	m.Push(PushSent)
	m.Trip(LimitIdle)
	m.Close(CloseIdle)
	m.TeardownExplicit()
	m.TeardownImplicit()
	m.Panic(SiteRead)
}

// TestHandler pins the ops surface: GET /metrics serves the exposition
// with the 0.0.4 content type; every other path and method 404s.
func TestHandler(t *testing.T) {
	m, g := populated()
	h := Handler(m, func() Gauges { return g })

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	if rec.Code != 200 {
		t.Fatalf("GET /metrics: got %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "text/plain; version=0.0.4; charset=utf-8" {
		t.Errorf("content type: got %q", ct)
	}
	if !strings.Contains(rec.Body.String(), "nimna_relay_connections 3") {
		t.Error("exposition body missing expected gauge")
	}

	for _, probe := range []struct{ method, path string }{
		{"GET", "/"}, {"GET", "/healthz"}, {"GET", "/metrics/x"},
		{"POST", "/metrics"}, {"HEAD", "/metrics"}, {"PUT", "/"},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(probe.method, probe.path, nil))
		if rec.Code != 404 {
			t.Errorf("%s %s: got %d, want 404", probe.method, probe.path, rec.Code)
		}
	}
}
