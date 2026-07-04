package main

import (
	"bufio"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// scrape GETs and parses one Prometheus-text exposition into a flat map
// keyed by the full series name including labels, e.g.
// `nimna_relay_limit_trips_total{limit="idle"}`.
func scrape(url string) (map[string]float64, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("metrics: status %d", resp.StatusCode)
	}
	out := map[string]float64{}
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.LastIndexByte(line, ' ')
		if idx < 0 {
			continue
		}
		v, err := strconv.ParseFloat(line[idx+1:], 64)
		if err != nil {
			continue
		}
		out[line[:idx]] = v
	}
	return out, sc.Err()
}

// tripDelta reads one limit_trips_total series.
func trips(m map[string]float64, limit string) float64 {
	return m[`nimna_relay_limit_trips_total{limit="`+limit+`"}`]
}

func gaugeHeader() string {
	return fmt.Sprintf("%-12s %-10s %-6s %-6s %-6s %-6s %-6s %-6s %-6s",
		"heap", "goroutine", "conns", "topics", "tbrdg", "crids", "pend", "sbrdg", "rate")
}

func gaugeRow(m map[string]float64) string {
	return fmt.Sprintf("%-12.0f %-10.0f %-6.0f %-6.0f %-6.0f %-6.0f %-6.0f %-6.0f %-6.0f",
		m["nimna_relay_heap_alloc_bytes"],
		m["nimna_relay_goroutines"],
		m["nimna_relay_connections"],
		m["nimna_relay_topics"],
		m["nimna_relay_topic_bridges"],
		m["nimna_relay_crid_entries"],
		m["nimna_relay_pending_knocks"],
		m["nimna_relay_session_bridges"],
		m["nimna_relay_rate_entries"])
}
