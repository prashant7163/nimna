package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"strings"
	"time"

	"nimna.app/relay/internal/wire"
)

// runAbuse probes every limit (§21): each probe asserts the relay's
// BEHAVIOR (zero-byte close, pacing-not-errors, silent non-bridge, one
// KNOCK_FWD, the sink-count floor) plus the limit_trips_total delta where
// one exists. Probes run before the load so the per-IP accounting is
// ours alone. Returns false if any probe failed.
func runAbuse(ctx context.Context, cfg config, sink *pushSink) bool {
	fmt.Println("abuse: probing every limit (this takes ~1–3 min at spec windows)")
	before, err := scrape(cfg.metrics)
	if err != nil {
		fmt.Printf("abuse: baseline scrape: %v\n", err)
		return false
	}
	host := strings.TrimPrefix(cfg.relay, "ws://")

	ok := true
	step := func(name string, f func() error) {
		if ctx.Err() != nil {
			return
		}
		if err := f(); err != nil {
			fmt.Printf("abuse: %-22s FAIL: %v\n", name, err)
			ok = false
		} else {
			fmt.Printf("abuse: %-22s ok\n", name)
		}
	}

	step("conn cap", func() error { return probeConnCap(host, cfg.connCap) })
	step("frame flood", func() error { return probeFrameFlood(ctx, cfg) })
	step("oversize frame", func() error { return probeOversize(ctx, cfg) })
	step("duplicate knocks", func() error { return probeDuplicateKnocks(ctx, cfg) })
	if sink != nil {
		step("push over-cap", func() error { return probePushCaps(ctx, cfg, sink) })
	} else {
		fmt.Println("abuse: push over-cap        skipped (no -sink-listen)")
	}
	step("rendezvous throttle", func() error { return probeRendezvous(ctx, cfg) })

	after, err := scrape(cfg.metrics)
	if err != nil {
		fmt.Printf("abuse: final scrape: %v\n", err)
		return false
	}
	for _, limit := range []string{"conn_ip", "frame_rate", "frame_size", "rendezvous", "knock_collapse"} {
		delta := trips(after, limit) - trips(before, limit)
		fmt.Printf("abuse: limit_trips{%s} delta %+.0f\n", limit, delta)
		if delta <= 0 {
			fmt.Printf("abuse: limit %q never tripped\n", limit)
			ok = false
		}
	}
	return ok
}

// probeConnCap fills the per-IP cap with raw TCP connects and asserts the
// over-cap connect is closed with ZERO bytes (§16's refusal shape).
func probeConnCap(host string, cap_ int) error {
	var fillers []net.Conn
	defer func() {
		for _, c := range fillers {
			_ = c.Close()
		}
	}()
	for i := 0; i < cap_; i++ {
		c, err := net.DialTimeout("tcp", host, dialTimeout)
		if err != nil {
			return fmt.Errorf("filler %d: %w", i, err)
		}
		fillers = append(fillers, c)
	}
	over, err := net.DialTimeout("tcp", host, dialTimeout)
	if err != nil {
		return fmt.Errorf("over-cap dial: %w", err)
	}
	defer over.Close()
	_ = over.SetReadDeadline(time.Now().Add(dialTimeout))
	n, err := over.Read(make([]byte, 16))
	if n != 0 {
		return fmt.Errorf("over-cap connect received %d bytes, want 0", n)
	}
	if err != io.EOF {
		return fmt.Errorf("over-cap connect: %v, want EOF", err)
	}
	return nil
}

// probeFrameFlood floods one connection and asserts PACING, not errors:
// every frame is processed in order (proven by a knock round trip queued
// behind the flood), the connection survives, and the measured ceiling is
// near the configured rate.
func probeFrameFlood(ctx context.Context, cfg config) error {
	crid := randID()
	flooder, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer flooder.close()
	peer, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer peer.close()
	if err := flooder.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return err
	}
	if err := peer.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return err
	}

	n := cfg.frameBurst + 2*cfg.frameRate // ~2s of pacing beyond the burst
	junk := randID()
	start := time.Now()
	for i := 0; i < n; i++ {
		if err := flooder.send(ctx, wire.PairData, junk, nil); err != nil {
			return fmt.Errorf("flood frame %d: %w (pacing must never error)", i, err)
		}
	}
	// The knock is read AFTER the flood frames (per-conn ordering): its
	// arrival proves every flood frame was processed and the conn lives.
	if err := flooder.send(ctx, wire.Knock, crid, nil); err != nil {
		return err
	}
	if !peer.await(wire.KnockFwd, crid, time.Duration(n/cfg.frameRate+15)*time.Second) {
		return fmt.Errorf("knock behind the flood never forwarded — flooded conn dead or frames dropped")
	}
	elapsed := time.Since(start)
	ceiling := float64(n+1) / elapsed.Seconds()
	fmt.Printf("abuse:   flood: %d frames in %s → ceiling %.1f/s (configured %d/s + burst %d)\n",
		n+1, elapsed.Truncate(time.Millisecond), ceiling, cfg.frameRate, cfg.frameBurst)
	minElapsed := time.Duration(float64(n-cfg.frameBurst)/float64(cfg.frameRate)*0.5) * time.Second
	if elapsed < minElapsed {
		return fmt.Errorf("flood of %d frames finished in %s — pacing did not engage", n+1, elapsed)
	}
	return nil
}

// probeOversize sends one frame over the configured bound and expects a
// bare close.
func probeOversize(ctx context.Context, cfg config) error {
	c, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer c.close()
	payload := make([]byte, cfg.maxFrame-wire.HeaderLen+1)
	if err := c.send(ctx, wire.PairData, randID(), payload); err == nil {
		select {
		case <-c.done:
		case <-time.After(dialTimeout):
			return fmt.Errorf("oversize frame did not close the connection")
		}
	}
	return nil
}

// probeDuplicateKnocks sends two knocks inside the collapse window and
// asserts exactly ONE KNOCK_FWD arrives.
func probeDuplicateKnocks(ctx context.Context, cfg config) error {
	crid := randID()
	k, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer k.close()
	a, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer a.close()
	if err := k.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return err
	}
	if err := a.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return err
	}
	if err := k.send(ctx, wire.Knock, crid, nil); err != nil {
		return err
	}
	if err := k.send(ctx, wire.Knock, crid, nil); err != nil { // duplicate: collapsed
		return err
	}
	if !a.await(wire.KnockFwd, crid, flowTimeout) {
		return fmt.Errorf("first knock never forwarded")
	}
	if a.await(wire.KnockFwd, crid, 2*time.Second) {
		return fmt.Errorf("duplicate knock inside the window was forwarded")
	}
	return nil
}

// probePushCaps knocks an offline CRID with a token past the push caps
// and asserts the sink-count floor: dispatches ≤ the binding cap, ≥ 1.
func probePushCaps(ctx context.Context, cfg config, sink *pushSink) error {
	crid := randID()
	c, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer c.close()
	if err := c.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return err
	}
	baseline := sink.calls()
	knocks := cfg.pushPerHour + 2
	token := randID()
	payload := wire.EncodeKnockPayload(wire.PlatformAPNs, token[:])
	spacing := cfg.knockInterval + 500*time.Millisecond
	fmt.Printf("abuse:   push probe: %d knocks spaced %s (floor from min-interval %s, hour cap %d)\n",
		knocks, spacing, cfg.pushMinInterval, cfg.pushPerHour)
	for i := 0; i < knocks; i++ {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := c.send(ctx, wire.Knock, crid, payload); err != nil {
			return err
		}
		if i < knocks-1 {
			sleepCtx(ctx, spacing)
		}
	}
	sleepCtx(ctx, 2*time.Second) // let the last dispatch land
	got := sink.calls() - baseline

	// Expected floor: pushes permitted by the min-interval across the
	// knock timeline, capped by the hour budget.
	elapsed := time.Duration(knocks-1) * spacing
	byMin := int(elapsed/cfg.pushMinInterval) + 1
	want := byMin
	if want > cfg.pushPerHour {
		want = cfg.pushPerHour
	}
	fmt.Printf("abuse:   push probe: sink saw %d dispatches (floor %d, hour cap %d)\n",
		got, want, cfg.pushPerHour)
	if got < 1 || got > cfg.pushPerHour || got > byMin {
		return fmt.Errorf("sink count %d outside the cap floor (want 1..min(%d,%d))", got, byMin, cfg.pushPerHour)
	}
	return nil
}

// probeRendezvous registers one past the per-minute window, then after
// the window rolls proves BEHAVIORALLY that the over-limit registration
// took no state: a fresh partner bridges the last in-limit topic but not
// the throttled one. Takes ~65s: the rendezvous window is pinned at one
// minute.
func probeRendezvous(ctx context.Context, cfg config) error {
	a, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer a.close()
	topics := make([][16]byte, cfg.rendezvousPerMin+1)
	for i := range topics {
		topics[i] = randID()
		if err := a.send(ctx, wire.RegisterTopic, topics[i], nil); err != nil {
			return err
		}
	}
	inLimit := topics[cfg.rendezvousPerMin-1] // last accepted
	throttled := topics[cfg.rendezvousPerMin] // dropped silently
	fmt.Printf("abuse:   rendezvous probe: waiting 65s for the window to roll\n")
	sleepCtx(ctx, 65*time.Second)
	if ctx.Err() != nil {
		return ctx.Err()
	}

	b, err := dialWS(ctx, cfg.relay)
	if err != nil {
		return err
	}
	defer b.close()
	if err := b.send(ctx, wire.RegisterTopic, inLimit, nil); err != nil {
		return err
	}
	if !b.await(wire.TopicBridged, inLimit, flowTimeout) {
		return fmt.Errorf("in-limit topic did not bridge — probe conn dead?")
	}
	if err := b.send(ctx, wire.RegisterTopic, throttled, nil); err != nil {
		return err
	}
	if b.await(wire.TopicBridged, throttled, 3*time.Second) {
		return fmt.Errorf("throttled REGISTER_TOPIC left state — it bridged")
	}
	return nil
}
