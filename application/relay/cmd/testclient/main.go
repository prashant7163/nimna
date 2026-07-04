// Command testclient is the Session 3 done-check tool: one binary, run
// twice, that rendezvouses two connections through the relay via the real
// §3.1.2 code→topic derivation and exchanges raw PAIR_DATA frames.
//
//	go run ./cmd/testclient --role create --code 7Q2-M4K-9XV
//	go run ./cmd/testclient --role join   --code 7Q2-M4K-9XV
//
// The creator derives the topic from its code-creation date (today by
// default), registers, and waits for TOPIC_BRIDGED. The joiner derives
// today's topic and registers; if no bridge forms after a short probe
// window it also derives and registers yesterday's (spec §3.1.2 — two
// candidates always cover a TTL ≤ 24 h). After the bridge, the joiner
// initiates a demo exchange of raw PAIR_DATA frames; the payload bytes
// are arbitrary — real Noise handshaking is app work (Sessions 8/9), and
// the relay forwards these frames verbatim without ever parsing them.
//
// This is a TEST TOOL, not the relay: it prints its own topics and frames
// freely. The relay side stays provably silent — it never sends anything
// but TOPIC_BRIDGED and forwarded PAIR_DATA, and never explains failures.
//
// Exit status: 0 on a completed exchange, non-zero on any failure, so QA
// can script it.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

func main() {
	os.Exit(run())
}

func fail(format string, a ...any) int {
	fmt.Fprintf(os.Stderr, "testclient: "+format+"\n", a...)
	return 1
}

func run() int {
	role := flag.String("role", "", "create | join (required)")
	relayURL := flag.String("relay", "ws://127.0.0.1:9440", "relay WebSocket URL")
	code := flag.String("code", "", "pairing code, e.g. 7Q2-M4K-9XV (required)")
	date := flag.String("date", "", "creator only: code-creation date YYYY-MM-DD (default: today UTC)")
	wait := flag.Duration("wait", 0, "max wait for TOPIC_BRIDGED (default: create 120s, join 30s)")
	probe := flag.Duration("probe", 5*time.Second, "joiner: wait on today's topic before also registering yesterday's")
	rounds := flag.Int("rounds", 2, "demo PAIR_DATA round trips after the bridge")
	flag.Parse()

	if *role != "create" && *role != "join" {
		return fail("--role must be create or join")
	}
	if *code == "" {
		return fail("--code is required")
	}
	canonical, err := canonicalize(*code)
	if err != nil {
		return fail("%v", err)
	}
	if *wait == 0 {
		if *role == "create" {
			*wait = 120 * time.Second
		} else {
			*wait = 30 * time.Second
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	fmt.Printf("[%s] dialing %s\n", *role, *relayURL)
	ws, _, err := websocket.Dial(ctx, *relayURL, nil)
	if err != nil {
		return fail("dial: %v", err)
	}
	defer ws.CloseNow()
	ws.SetReadLimit(wire.MaxFrame)

	cl := &client{role: *role, ws: ws, frames: make(chan wire.Frame, 8)}
	go cl.readLoop(ctx)

	switch *role {
	case "create":
		return cl.runCreate(ctx, canonical, *date, *wait, *rounds)
	default:
		return cl.runJoin(ctx, canonical, *wait, *probe, *rounds)
	}
}

// client wraps the WebSocket with a reader goroutine so waits are plain
// channel selects — per-read deadlines would close the connection in
// coder/websocket.
type client struct {
	role   string
	ws     *websocket.Conn
	frames chan wire.Frame
}

func (c *client) readLoop(ctx context.Context) {
	for {
		typ, data, err := c.ws.Read(ctx)
		if err != nil {
			close(c.frames)
			return
		}
		if typ != websocket.MessageBinary {
			continue
		}
		f, err := wire.Parse(data)
		if err != nil {
			fmt.Printf("[%s] recv unparseable frame (%d bytes) — ignoring\n", c.role, len(data))
			continue
		}
		c.frames <- f
	}
}

func (c *client) send(ctx context.Context, t wire.FrameType, topic [16]byte, payload []byte) error {
	frame := wire.Encode(t, topic, payload)
	fmt.Printf("[%s] send %s topic=%x payload=%s\n", c.role, frameName(t), topic, printable(payload))
	return c.ws.Write(ctx, websocket.MessageBinary, frame)
}

// waitBridged waits up to d for TOPIC_BRIDGED on one of topics. Any other
// frame arriving meanwhile is printed and skipped.
func (c *client) waitBridged(d time.Duration, topics ...[16]byte) ([16]byte, bool) {
	deadline := time.After(d)
	for {
		select {
		case f, ok := <-c.frames:
			if !ok {
				return [16]byte{}, false
			}
			fmt.Printf("[%s] recv %s topic=%x payload=%s\n", c.role, frameName(f.Type), f.RoutingID, printable(f.Payload))
			if f.Type != wire.TopicBridged {
				continue
			}
			for _, t := range topics {
				if f.RoutingID == t {
					return t, true
				}
			}
		case <-deadline:
			return [16]byte{}, false
		}
	}
}

// waitPairData waits up to d for a PAIR_DATA frame on topic.
func (c *client) waitPairData(d time.Duration, topic [16]byte) ([]byte, bool) {
	deadline := time.After(d)
	for {
		select {
		case f, ok := <-c.frames:
			if !ok {
				return nil, false
			}
			fmt.Printf("[%s] recv %s topic=%x payload=%s\n", c.role, frameName(f.Type), f.RoutingID, printable(f.Payload))
			if f.Type == wire.PairData && f.RoutingID == topic {
				return f.Payload, true
			}
		case <-deadline:
			return nil, false
		}
	}
}

func (c *client) runCreate(ctx context.Context, canonical, date string, wait time.Duration, rounds int) int {
	if date == "" {
		date = time.Now().UTC().Format("2006-01-02")
	}
	fmt.Printf("[create] deriving topic for code date %s (Argon2id t=3 m=64MiB — takes a moment)\n", date)
	topic := deriveTopic(canonical, date, productionParams)
	fmt.Printf("[create] topic=%x\n", topic)

	if err := c.send(ctx, wire.RegisterTopic, topic, nil); err != nil {
		return fail("register: %v", err)
	}
	fmt.Printf("[create] waiting for TOPIC_BRIDGED (up to %s)\n", wait)
	bridged, ok := c.waitBridged(wait, topic)
	if !ok {
		return fail("no TOPIC_BRIDGED within %s", wait)
	}
	fmt.Printf("[create] bridged on topic=%x\n", bridged)

	// Demo exchange, responder side: the joiner speaks first (§3.1.3 —
	// the joiner sends M1). Payload bytes are arbitrary demo content.
	for i := 1; i <= rounds; i++ {
		in, ok := c.waitPairData(30*time.Second, bridged)
		if !ok {
			return fail("round %d: no PAIR_DATA from joiner", i)
		}
		reply := fmt.Appendf(nil, "demo-pong %d/%d from creator (echo %q)", i, rounds, in)
		if err := c.send(ctx, wire.PairData, bridged, reply); err != nil {
			return fail("round %d: send: %v", i, err)
		}
	}
	fmt.Printf("[create] SUCCESS — %d PAIR_DATA round trips complete\n", rounds)
	c.ws.Close(websocket.StatusNormalClosure, "")
	return 0
}

func (c *client) runJoin(ctx context.Context, canonical string, wait, probe time.Duration, rounds int) int {
	today := time.Now().UTC().Format("2006-01-02")
	fmt.Printf("[join] deriving today's topic (%s) (Argon2id t=3 m=64MiB — takes a moment)\n", today)
	topicToday := deriveTopic(canonical, today, productionParams)
	fmt.Printf("[join] topic(today)=%x\n", topicToday)

	if err := c.send(ctx, wire.RegisterTopic, topicToday, nil); err != nil {
		return fail("register today: %v", err)
	}

	candidates := [][16]byte{topicToday}
	fmt.Printf("[join] probing today's topic for %s\n", probe)
	bridged, ok := c.waitBridged(probe, candidates...)
	if !ok {
		// No bridge yet: also register yesterday's candidate — two
		// candidates always cover a TTL ≤ 24 h (spec §3.1.2).
		yesterday := time.Now().UTC().AddDate(0, 0, -1).Format("2006-01-02")
		fmt.Printf("[join] no bridge yet; deriving yesterday's topic (%s)\n", yesterday)
		topicYesterday := deriveTopic(canonical, yesterday, productionParams)
		fmt.Printf("[join] topic(yesterday)=%x\n", topicYesterday)
		if err := c.send(ctx, wire.RegisterTopic, topicYesterday, nil); err != nil {
			return fail("register yesterday: %v", err)
		}
		candidates = append(candidates, topicYesterday)
		fmt.Printf("[join] waiting on both candidates (up to %s)\n", wait)
		bridged, ok = c.waitBridged(wait, candidates...)
	}
	if !ok {
		return fail("no TOPIC_BRIDGED — that code didn't match anything")
	}
	fmt.Printf("[join] bridged on topic=%x\n", bridged)

	// Demo exchange, initiator side (the joiner sends first, §3.1.3).
	for i := 1; i <= rounds; i++ {
		ping := fmt.Appendf(nil, "demo-ping %d/%d from joiner", i, rounds)
		if err := c.send(ctx, wire.PairData, bridged, ping); err != nil {
			return fail("round %d: send: %v", i, err)
		}
		if _, ok := c.waitPairData(30*time.Second, bridged); !ok {
			return fail("round %d: no PAIR_DATA reply from creator", i)
		}
	}
	fmt.Printf("[join] SUCCESS — %d PAIR_DATA round trips complete\n", rounds)
	c.ws.Close(websocket.StatusNormalClosure, "")
	return 0
}

func frameName(t wire.FrameType) string {
	switch t {
	case wire.RegisterTopic:
		return "REGISTER_TOPIC"
	case wire.TopicBridged:
		return "TOPIC_BRIDGED"
	case wire.PairData:
		return "PAIR_DATA"
	default:
		return fmt.Sprintf("frame(0x%02x)", byte(t))
	}
}

// printable renders demo payload bytes for the console.
func printable(p []byte) string {
	if len(p) == 0 {
		return "(empty)"
	}
	for _, b := range p {
		if b < 0x20 || b > 0x7e {
			return fmt.Sprintf("%x", p)
		}
	}
	return fmt.Sprintf("%q", p)
}
