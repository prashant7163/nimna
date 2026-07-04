// Command soak is the Session 5 soak & abuse driver (architecture note
// §21): it holds sustained connection churn and full protocol flows
// against a RUNNING relay, samples the relay's metrics endpoint, probes
// every limit in -abuse mode, and prints a pinned flat-memory verdict.
//
// A third main package beside relay/testclient: a committed deliverable
// under the module's gofmt/vet/test CI, deliberately OUTSIDE the relay
// binary's import graph (coder/websocket + stdlib only — no x/crypto).
// Routing identifiers are opaque random 16-byte values (--crid-style, note
// §21): the relay never derives, so neither does its load driver.
//
// Typical accelerated in-session run (relay windows shrunk via config —
// the §14 acceleration path; defaults stay spec):
//
//	go run ./cmd/relay -push-sink http://127.0.0.1:9470 \
//	    -push-day-window 90s -push-hour-window 60s
//	go run ./cmd/soak -duration 10m -drain 60s -abuse \
//	    -sink-listen 127.0.0.1:9470
//
// True overnight run: -duration 8h against spec-default config (note:
// the rate_entries gauge then only drains after the relay's 24 h idle
// eviction — the zero-verdict on that gauge needs a shortened
// -push-day-window on the relay side; the verdict output says so).
//
// PROGRESS.md reports exactly which run was performed (§21's honest
// evidence standard).
//
// Exit status: 0 = verdict PASS (and all abuse probes passed), 1 = FAIL.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

type config struct {
	relay      string
	metrics    string
	duration   time.Duration
	sample     time.Duration
	drain      time.Duration
	churn      int
	pairFlows  int
	sessFlows  int
	rounds     int
	abuse      bool
	sinkListen string

	// Mirrors of the relay's limit config, used to compute abuse-probe
	// expectations and to pace rendezvous registrations client-side.
	connCap          int
	frameRate        int
	frameBurst       int
	maxFrame         int
	rendezvousPerMin int
	knockInterval    time.Duration
	pushMinInterval  time.Duration
	pushPerHour      int
}

func main() {
	os.Exit(run())
}

func run() int {
	var cfg config
	flag.StringVar(&cfg.relay, "relay", "ws://127.0.0.1:9440", "relay WebSocket URL")
	flag.StringVar(&cfg.metrics, "metrics", "http://127.0.0.1:9441/metrics", "relay metrics URL")
	flag.DurationVar(&cfg.duration, "duration", 30*time.Minute, "load duration (arbitrary; overnight = 8h+)")
	flag.DurationVar(&cfg.sample, "sample", 30*time.Second, "metrics sampling interval")
	flag.DurationVar(&cfg.drain, "drain", 150*time.Second, "post-load settle before the zero check (≥ 2× the relay's janitor ticks)")
	flag.IntVar(&cfg.churn, "churn", 8, "connection-churn workers (dial/register/drop)")
	flag.IntVar(&cfg.pairFlows, "pair-flows", 2, "rendezvous flow workers (register → bridge → PAIR_DATA → drop)")
	flag.IntVar(&cfg.sessFlows, "session-flows", 4, "channel flow workers (register → knock → accept → SESSION_DATA → TEARDOWN)")
	flag.IntVar(&cfg.rounds, "rounds", 4, "data round trips per flow")
	flag.BoolVar(&cfg.abuse, "abuse", false, "run the limit probes before the load")
	flag.StringVar(&cfg.sinkListen, "sink-listen", "", "host a push sink here (point the relay's -push-sink at it); enables the push probes")

	flag.IntVar(&cfg.connCap, "conn-cap", 64, "relay's -max-conns-per-ip (probe expectation)")
	flag.IntVar(&cfg.frameRate, "frame-rate", 50, "relay's -frame-rate (probe expectation)")
	flag.IntVar(&cfg.frameBurst, "frame-burst", 100, "relay's -frame-burst (probe expectation)")
	flag.IntVar(&cfg.maxFrame, "max-frame", 131072, "relay's -max-frame (probe expectation)")
	flag.IntVar(&cfg.rendezvousPerMin, "rendezvous-per-min", 6, "relay's -rendezvous-per-min (probe expectation + client-side pacing)")
	flag.DurationVar(&cfg.knockInterval, "knock-interval", 10*time.Second, "relay's -knock-interval (probe expectation)")
	flag.DurationVar(&cfg.pushMinInterval, "push-min-interval", 60*time.Second, "relay's -push-min-interval (probe expectation)")
	flag.IntVar(&cfg.pushPerHour, "push-per-hour", 6, "relay's -push-per-hour (probe expectation)")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	fmt.Printf("soak: relay=%s metrics=%s duration=%s abuse=%v\n",
		cfg.relay, cfg.metrics, cfg.duration, cfg.abuse)

	// Reachability check + baseline sample.
	base, err := scrape(cfg.metrics)
	if err != nil {
		fmt.Printf("soak: metrics endpoint unreachable: %v\n", err)
		return 1
	}
	fmt.Printf("baseline: %s\n", gaugeRow(base))

	var sink *pushSink
	if cfg.sinkListen != "" {
		sink, err = startSink(cfg.sinkListen)
		if err != nil {
			fmt.Printf("soak: sink listen: %v\n", err)
			return 1
		}
		defer sink.close()
		fmt.Printf("soak: push sink on %s (relay must run with -push-sink http://%s)\n",
			cfg.sinkListen, cfg.sinkListen)
	}

	ok := true
	if cfg.abuse {
		if !runAbuse(ctx, cfg, sink) {
			ok = false
		}
	}

	// ---- Load phase.
	loadCtx, cancelLoad := context.WithTimeout(ctx, cfg.duration)
	defer cancelLoad()
	stats := &stats{}
	pacer := newPacer(cfg.rendezvousPerMin)
	var wg sync.WaitGroup
	worker := func(f func(context.Context)) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for loadCtx.Err() == nil {
				f(loadCtx)
			}
		}()
	}
	for i := 0; i < cfg.churn; i++ {
		worker(func(ctx context.Context) { churnOnce(ctx, cfg, stats) })
	}
	for i := 0; i < cfg.pairFlows; i++ {
		worker(func(ctx context.Context) { pairFlowOnce(ctx, cfg, stats, pacer) })
	}
	for i := 0; i < cfg.sessFlows; i++ {
		worker(func(ctx context.Context) { sessionFlowOnce(ctx, cfg, stats, sink) })
	}

	// Sampling loop.
	var samples []sample
	tick := time.NewTicker(cfg.sample)
	fmt.Printf("%-8s %s\n", "t", gaugeHeader())
sampling:
	for start := time.Now(); ; {
		select {
		case <-loadCtx.Done():
			tick.Stop()
			break sampling
		case <-tick.C:
			m, err := scrape(cfg.metrics)
			if err != nil {
				fmt.Printf("sample failed: %v\n", err)
				continue
			}
			samples = append(samples, sample{at: time.Since(start), m: m})
			fmt.Printf("%-8s %s\n", time.Since(start).Truncate(time.Second), gaugeRow(m))
		}
	}
	wg.Wait()
	stats.print()

	if ctx.Err() != nil {
		fmt.Println("soak: interrupted — no verdict")
		return 1
	}

	// ---- Drain, then the pinned verdict (§21).
	fmt.Printf("load stopped; draining %s before the zero check\n", cfg.drain)
	select {
	case <-time.After(cfg.drain):
	case <-ctx.Done():
		fmt.Println("soak: interrupted — no verdict")
		return 1
	}
	final, err := scrape(cfg.metrics)
	if err != nil {
		fmt.Printf("final scrape failed: %v\n", err)
		return 1
	}
	fmt.Printf("final:   %s\n", gaugeRow(final))

	if !verdict(samples, final) {
		ok = false
	}
	if ok {
		fmt.Println("soak: PASS")
		return 0
	}
	fmt.Println("soak: FAIL")
	return 1
}

type sample struct {
	at time.Duration
	m  map[string]float64
}

// tableGauges is §21's zero list: every table gauge must return to zero
// after load + drain.
var tableGauges = []string{
	"nimna_relay_connections",
	"nimna_relay_topics",
	"nimna_relay_topic_bridges",
	"nimna_relay_crid_entries",
	"nimna_relay_pending_knocks",
	"nimna_relay_session_bridges",
	"nimna_relay_rate_entries",
}

// verdict applies the pinned flat-memory rule (§21): all table gauges
// zero after the drain, and median heap_alloc_bytes of the final quarter
// of load samples ≤ 1.10 × the median of the second quarter.
func verdict(samples []sample, final map[string]float64) bool {
	ok := true
	for _, g := range tableGauges {
		if v := final[g]; v != 0 {
			fmt.Printf("verdict: %s = %v, want 0", g, v)
			if g == "nimna_relay_rate_entries" {
				fmt.Printf(" (rate entries evict after the relay's LONGEST configured window — a spec-default relay holds them 24h; run the relay with a shortened -push-day-window for a drainable soak)")
			}
			fmt.Println()
			ok = false
		}
	}

	heap := seriesOf(samples, "nimna_relay_heap_alloc_bytes")
	if len(heap) < 8 {
		fmt.Printf("verdict: only %d samples — need ≥8 for the quartile heap rule (lengthen -duration or shorten -sample)\n", len(heap))
		return false
	}
	q := len(heap) / 4
	second := median(heap[q : 2*q])
	last := median(heap[3*q:])
	fmt.Printf("verdict: heap median second-quarter=%.0f final-quarter=%.0f (ratio %.3f, limit 1.10)\n",
		second, last, last/second)
	if last > second*1.10 {
		fmt.Println("verdict: heap grows monotonically — FAIL")
		ok = false
	}
	return ok
}

func seriesOf(samples []sample, key string) []float64 {
	out := make([]float64, 0, len(samples))
	for _, s := range samples {
		out = append(out, s.m[key])
	}
	return out
}

func median(xs []float64) float64 {
	if len(xs) == 0 {
		return 0
	}
	sorted := append([]float64(nil), xs...)
	for i := 1; i < len(sorted); i++ { // insertion sort; n is tiny
		for j := i; j > 0 && sorted[j] < sorted[j-1]; j-- {
			sorted[j], sorted[j-1] = sorted[j-1], sorted[j]
		}
	}
	if n := len(sorted); n%2 == 1 {
		return sorted[n/2]
	} else {
		return (sorted[n/2-1] + sorted[n/2]) / 2
	}
}

// stats aggregates worker outcomes (soak-side only, printed at exit).
type stats struct {
	mu       sync.Mutex
	counters map[string]int
}

func (s *stats) inc(key string) {
	s.mu.Lock()
	if s.counters == nil {
		s.counters = map[string]int{}
	}
	s.counters[key]++
	s.mu.Unlock()
}

func (s *stats) print() {
	s.mu.Lock()
	defer s.mu.Unlock()
	fmt.Println("load outcomes:")
	for k, v := range s.counters {
		fmt.Printf("  %-28s %d\n", k, v)
	}
}
