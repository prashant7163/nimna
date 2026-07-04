// Command testclient is the Session 3/4 done-check tool: one binary
// covering both relay planes.
//
// Rendezvous plane (Session 3) — run twice, real §3.1.2 code→topic
// derivation, raw PAIR_DATA exchange:
//
//	go run ./cmd/testclient --role create --code 7Q2-M4K-9XV
//	go run ./cmd/testclient --role join   --code 7Q2-M4K-9XV
//
// The creator derives the topic from its code-creation date (today by
// default), registers, and waits for TOPIC_BRIDGED. The joiner derives
// today's topic and registers; if no bridge forms after a short probe
// window it also derives and registers yesterday's (spec §3.1.2 — two
// candidates always cover a TTL ≤ 24 h). After the bridge, the joiner
// initiates a demo exchange of raw PAIR_DATA frames.
//
// Channel plane (Session 4) — knock → accept → SESSION_DATA chat:
//
//	go run ./cmd/testclient --role answer --code 7Q2-M4K-9XV
//	go run ./cmd/testclient --role knock  --code 7Q2-M4K-9XV \
//	    [--token <hex> --platform apns|fcm]
//
// Both roles register a CRID derived from the shared code by a TEST-ONLY
// derivation (see deriveCRID; explicitly NOT spec §3.1.5) or given
// directly via --crid. The knocker sends KNOCK (with the optional push
// token), waits for SESSION_BRIDGED, chats as initiator (speaks first,
// mirroring §3.3.1 S1), sends one WebSocket ping as the keepalive
// covering check (note §12), then TEARDOWN. The answerer waits for
// KNOCK_FWD — delivered live or on register (a knock pending at the relay
// reaches a late-connecting answerer) — ACCEPTs, chats as responder, and
// exits on the relay's TEARDOWN. Payload bytes are arbitrary demo content
// in both planes — real Noise handshaking is app work (Sessions 8+), and
// the relay forwards data frames verbatim without ever parsing them.
//
// This is a TEST TOOL, not the relay: it prints its own identifiers and
// frames freely. The relay side stays provably silent — it never sends
// anything beyond the §5.4 go-signals and forwarded data frames, and
// never explains failures.
//
// Exit status: 0 on a completed exchange, non-zero on any failure, so QA
// can script it.
package main

import (
	"context"
	"encoding/hex"
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
	role := flag.String("role", "", "create | join | knock | answer (required)")
	relayURL := flag.String("relay", "ws://127.0.0.1:9440", "relay WebSocket URL")
	code := flag.String("code", "", "pairing code, e.g. 7Q2-M4K-9XV (required unless --crid)")
	date := flag.String("date", "", "creator only: code-creation date YYYY-MM-DD (default: today UTC)")
	wait := flag.Duration("wait", 0, "max wait for the bridge go-signal (defaults: create 120s, join 30s, knock 75s, answer 120s)")
	probe := flag.Duration("probe", 5*time.Second, "joiner: wait on today's topic before also registering yesterday's")
	rounds := flag.Int("rounds", 2, "demo data round trips after the bridge (must match on both ends)")
	cridHex := flag.String("crid", "", "knock/answer: 32-hex CRID override (skips the code derivation)")
	tokenHex := flag.String("token", "", "knock only: push device-token hex (with --platform)")
	platformName := flag.String("platform", "", "knock only: apns | fcm (with --token)")
	flag.Parse()

	channelRole := *role == "knock" || *role == "answer"
	if *role != "create" && *role != "join" && !channelRole {
		return fail("--role must be create, join, knock or answer")
	}
	if *role != "knock" && (*tokenHex != "" || *platformName != "") {
		return fail("--token/--platform apply to --role knock only")
	}
	if (*tokenHex == "") != (*platformName == "") {
		return fail("--token and --platform go together (both or neither)")
	}
	var token []byte
	var platform wire.Platform
	if *tokenHex != "" {
		var err error
		token, err = hex.DecodeString(*tokenHex)
		if err != nil || len(token) == 0 {
			return fail("--token must be non-empty hex")
		}
		switch *platformName {
		case "apns":
			platform = wire.PlatformAPNs
		case "fcm":
			platform = wire.PlatformFCM
		default:
			return fail("--platform must be apns or fcm")
		}
	}

	// Resolve the routing identifier for the chosen plane.
	var canonical string
	var crid [16]byte
	switch {
	case channelRole && *cridHex != "":
		b, err := hex.DecodeString(*cridHex)
		if err != nil || len(b) != 16 {
			return fail("--crid must be exactly 32 hex characters")
		}
		copy(crid[:], b)
	case *code == "":
		return fail("--code is required (or --crid for knock/answer)")
	default:
		var err error
		canonical, err = canonicalize(*code)
		if err != nil {
			return fail("%v", err)
		}
		if channelRole {
			crid = deriveCRID(canonical)
		}
	}

	if *wait == 0 {
		switch *role {
		case "create", "answer":
			*wait = 120 * time.Second
		case "join":
			*wait = 30 * time.Second
		case "knock":
			// 75 s > the relay's 60 s pending-knock window: past it,
			// silence is the answer (§3.2 — ACCEPT or nothing).
			*wait = 75 * time.Second
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
	case "join":
		return cl.runJoin(ctx, canonical, *wait, *probe, *rounds)
	case "knock":
		return cl.runKnock(ctx, crid, token, platform, *wait, *rounds)
	default:
		return cl.runAnswer(ctx, crid, *wait, *rounds)
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

func (c *client) send(ctx context.Context, t wire.FrameType, rid [16]byte, payload []byte) error {
	frame := wire.Encode(t, rid, payload)
	fmt.Printf("[%s] send %s rid=%x payload=%s\n", c.role, frameName(t), rid, printable(payload))
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
	case wire.RegisterCRID:
		return "REGISTER_CRID"
	case wire.Knock:
		return "KNOCK"
	case wire.Accept:
		return "ACCEPT"
	case wire.Teardown:
		return "TEARDOWN"
	case wire.TopicBridged:
		return "TOPIC_BRIDGED"
	case wire.KnockFwd:
		return "KNOCK_FWD"
	case wire.SessionBridged:
		return "SESSION_BRIDGED"
	case wire.PairData:
		return "PAIR_DATA"
	case wire.SessionData:
		return "SESSION_DATA"
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
