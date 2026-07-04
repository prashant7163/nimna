// Channel-plane roles (Session 4 done-check): knock and answer — register
// a CRID, knock/accept, exchange raw SESSION_DATA, tear down. CLIENT-side
// logic: it lives inside cmd/testclient and never leaks into relay
// packages — the relay treats CRIDs as opaque 16 bytes.
package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

// deriveCRID is a TEST-ONLY deterministic CRID source:
// SHA-256("nimna/testclient/crid/v1|" + canonical_code)[0:16].
//
// It is explicitly NOT the spec §3.1.5 CRID derivation — that is a PRF
// over the channel's paired static keys, which do not exist until the app
// implements pairing (Sessions 8/9). This stand-in only needs the property
// the done-check needs: both ends of a test pair derive the same 16 bytes
// from the shared code. --crid overrides it entirely.
func deriveCRID(canonical string) [16]byte {
	sum := sha256.Sum256([]byte("nimna/testclient/crid/v1|" + canonical))
	var crid [16]byte
	copy(crid[:], sum[:16])
	return crid
}

// chatTimeout bounds each wait inside an established session.
const chatTimeout = 30 * time.Second

// waitFrame waits up to d for a frame of type t on rid. Any other frame
// arriving meanwhile is printed and skipped.
func (c *client) waitFrame(d time.Duration, t wire.FrameType, rid [16]byte) (wire.Frame, bool) {
	deadline := time.After(d)
	for {
		select {
		case f, ok := <-c.frames:
			if !ok {
				return wire.Frame{}, false
			}
			fmt.Printf("[%s] recv %s rid=%x payload=%s\n", c.role, frameName(f.Type), f.RoutingID, printable(f.Payload))
			if f.Type == t && f.RoutingID == rid {
				return f, true
			}
		case <-deadline:
			return wire.Frame{}, false
		}
	}
}

// runKnock is the session initiator: REGISTER_CRID, KNOCK (optionally
// carrying the peer's push token), wait for SESSION_BRIDGED, chat first
// (mirroring §3.3.1 — the knocker is the Noise initiator and sends S1),
// one WebSocket ping (the §12 keepalive covering check), then TEARDOWN.
func (c *client) runKnock(ctx context.Context, crid [16]byte, token []byte, platform wire.Platform, wait time.Duration, rounds int) int {
	if err := c.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return fail("register: %v", err)
	}
	var payload []byte
	if len(token) > 0 {
		payload = wire.EncodeKnockPayload(platform, token)
		fmt.Printf("[knock] knocking with a %d-byte push token (the relay forwards it to the platform once, or discards it if the peer is online)\n", len(token))
	}
	if err := c.send(ctx, wire.Knock, crid, payload); err != nil {
		return fail("knock: %v", err)
	}

	fmt.Printf("[knock] waiting for SESSION_BRIDGED (up to %s — ACCEPT or silence is all a knocker ever sees)\n", wait)
	if _, ok := c.waitFrame(wait, wire.SessionBridged, crid); !ok {
		return fail("no answer — no SESSION_BRIDGED within %s", wait)
	}

	// Chat, initiator side: the knocker speaks first. Payload bytes are
	// arbitrary demo content; the relay forwards them verbatim.
	for i := 1; i <= rounds; i++ {
		ping := fmt.Appendf(nil, "demo-ping %d/%d from knocker", i, rounds)
		if err := c.send(ctx, wire.SessionData, crid, ping); err != nil {
			return fail("round %d: send: %v", i, err)
		}
		if _, ok := c.waitFrame(chatTimeout, wire.SessionData, crid); !ok {
			return fail("round %d: no SESSION_DATA reply from answerer", i)
		}
	}

	// Keepalive covering check (note §12): the relay adds no keepalive
	// code — the library auto-pongs while its read loop is in Read.
	// Ping blocks until the pong arrives, so success IS the check.
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	err := c.ws.Ping(pingCtx)
	cancel()
	if err != nil {
		return fail("ws ping: no pong from the relay: %v", err)
	}
	fmt.Printf("[knock] ws ping acknowledged — relay keepalive OK\n")

	if err := c.send(ctx, wire.Teardown, crid, nil); err != nil {
		return fail("teardown: %v", err)
	}
	fmt.Printf("[knock] SUCCESS — %d SESSION_DATA round trips, ping, TEARDOWN sent\n", rounds)
	c.ws.Close(websocket.StatusNormalClosure, "")
	return 0
}

// runAnswer is the session responder: REGISTER_CRID, wait for KNOCK_FWD —
// delivered live, or immediately on register when a knock is already
// pending at the relay (deliver-on-register makes the push → reconnect
// path work) — then ACCEPT, wait for SESSION_BRIDGED, chat as responder,
// and exit 0 on the relay's TEARDOWN.
func (c *client) runAnswer(ctx context.Context, crid [16]byte, wait time.Duration, rounds int) int {
	if err := c.send(ctx, wire.RegisterCRID, crid, nil); err != nil {
		return fail("register: %v", err)
	}

	fmt.Printf("[answer] waiting for KNOCK_FWD (up to %s — delivered live or on register)\n", wait)
	if _, ok := c.waitFrame(wait, wire.KnockFwd, crid); !ok {
		return fail("no KNOCK_FWD within %s", wait)
	}

	if err := c.send(ctx, wire.Accept, crid, nil); err != nil {
		return fail("accept: %v", err)
	}
	if _, ok := c.waitFrame(chatTimeout, wire.SessionBridged, crid); !ok {
		return fail("no SESSION_BRIDGED after ACCEPT (the knock may have lapsed — 60 s window)")
	}

	// Chat, responder side: reply to each knocker frame.
	for i := 1; i <= rounds; i++ {
		in, ok := c.waitFrame(chatTimeout, wire.SessionData, crid)
		if !ok {
			return fail("round %d: no SESSION_DATA from knocker", i)
		}
		reply := fmt.Appendf(nil, "demo-pong %d/%d from answerer (echo %q)", i, rounds, in.Payload)
		if err := c.send(ctx, wire.SessionData, crid, reply); err != nil {
			return fail("round %d: send: %v", i, err)
		}
	}

	fmt.Printf("[answer] waiting for the relay TEARDOWN\n")
	if _, ok := c.waitFrame(chatTimeout, wire.Teardown, crid); !ok {
		return fail("no TEARDOWN after the chat")
	}
	fmt.Printf("[answer] SUCCESS — %d SESSION_DATA round trips, TEARDOWN received\n", rounds)
	c.ws.Close(websocket.StatusNormalClosure, "")
	return 0
}
