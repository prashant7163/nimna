package server

import (
	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

// Channel-plane handlers (spec §3.2, §3.3, §5.4; architecture note §§9–10).
//
// The silence rule that shapes every path here: a state-dependent
// rejection is always a silent drop — a close that depended on registry
// state would itself leak that state through an observable close. Only
// state-independent structural malformation (a pure function of the
// received bytes: the malformed KNOCK payload) ever closes the connection.
//
// Relay-emitted frames (KNOCK_FWD, SESSION_BRIDGED, relay→client TEARDOWN)
// are always freshly built with empty payloads — never a forwarded client
// frame — so KNOCK_FWD's token strip is structural, not a filtering step.

// handleRegisterCRID implements REGISTER_CRID (0x02). Registration is
// silent — no ack frame exists — with one §5.4-defined exception: when the
// CRID holds an unexpired pending knock from another connection, the
// registrant immediately gets KNOCK_FWD (deliver-on-register, note §10 —
// the push is content-free, so a pushed-awake peer can only learn WHICH
// CRID to accept from this delivery). The payload is ignored: the relay
// routes on the 18-byte header alone (§5.4).
func handleRegisterCRID(c *conn, f wire.Frame, _ []byte) {
	crid := ident.CRIDFromWire(f.RoutingID)
	deliver := c.srv.channels.Register(crid, c)
	if !c.addCRID(crid) {
		// Lost the race with this connection's own teardown: unwind the
		// registration ourselves, because teardown's sweep may already
		// have run. The notify branch is load-bearing: a DUPLICATE
		// REGISTER_CRID from a connection already bridged on this CRID
		// takes this path too, and its DropConn then legitimately
		// returns the bridge survivor for the implicit-TEARDOWN notify.
		// The survivor is notified exactly once — the registry mutex
		// serializes this DropConn against teardown's sweep, and
		// whichever runs second finds the conn already out of the
		// registration set and is a no-op.
		if survivor, notify := c.srv.channels.DropConn(crid, c); notify {
			survivor.send(wire.Encode(wire.Teardown, crid.WireBytes(), nil))
		}
		return
	}
	if deliver {
		c.send(wire.Encode(wire.KnockFwd, crid.WireBytes(), nil))
	}
}

// handleKnock implements KNOCK (0x03), the one relay-plane frame whose
// payload the relay parses. A malformed payload is structurally malformed
// traffic and closes the connection — state-independent, so it is the one
// valid-frame close the silence doctrine permits (the close itself is
// teardown's bare CloseNow, note §5.1). Everything state-dependent is a
// silent drop.
//
// Push evaluation (§3.2 step 2): forward and push are mutually exclusive.
// A non-empty forward set means the peer is online — KNOCK_FWD to every
// registered connection except the knocker, and any token is discarded
// unused. An empty forward set with a token means exactly ONE dispatch.
// The knocker receives nothing back in any case: its visible surface is
// ACCEPT or silence.
func handleKnock(c *conn, f wire.Frame, _ []byte) {
	kp, err := wire.ParseKnockPayload(f.Payload)
	if err != nil {
		c.teardown()
		return
	}
	// The token is wrapped at the parse boundary and lives only on this
	// stack and in at most one dispatch queue entry — it never enters
	// internal/channel and is never stored (spec §3.2.1).
	var token ident.DeviceToken
	if kp.HasToken {
		token = ident.DeviceTokenFrom(kp.Token)
	}

	crid := ident.CRIDFromWire(f.RoutingID)
	fwd, ok := c.srv.channels.Knock(crid, c)
	if !ok {
		return
	}
	if len(fwd) > 0 {
		// Freshly built, empty payload: the token strip is structural.
		frame := wire.Encode(wire.KnockFwd, crid.WireBytes(), nil)
		for _, to := range fwd {
			to.send(frame)
		}
		return
	}
	if kp.HasToken && c.srv.push != nil {
		c.srv.push.Enqueue(kp.Platform, token)
	}
}

// handleAccept implements ACCEPT (0x04): first ACCEPT wins the pending,
// the CRID bridges (knocker, accepter), and both ends get a freshly built
// SESSION_BRIDGED — the knocker then speaks first (§3.3.1 S1). Every
// invalid case is a silent drop. The payload is ignored (§5.4: empty).
// Per-conn sendCh FIFO guarantees the accepter saw its KNOCK_FWD queued
// before this SESSION_BRIDGED.
func handleAccept(c *conn, f wire.Frame, _ []byte) {
	crid := ident.CRIDFromWire(f.RoutingID)
	knocker, ok := c.srv.channels.Accept(crid, c)
	if !ok {
		return
	}
	frame := wire.Encode(wire.SessionBridged, crid.WireBytes(), nil)
	knocker.send(frame)
	c.send(frame)
}

// handleTeardown implements client→relay TEARDOWN (0x05): a bridge member
// clears the bridge and the relay notifies the OTHER member only (§3.3 —
// the initiator already knows). Registrations survive; re-knock without
// re-register is legal. Anything else — unbridged CRID, non-member, a
// pending knock (no knock-cancel exists in §5.4) — is a silent drop. The
// payload is ignored (§5.4: empty).
func handleTeardown(c *conn, f wire.Frame, _ []byte) {
	crid := ident.CRIDFromWire(f.RoutingID)
	if other, ok := c.srv.channels.Teardown(crid, c); ok {
		other.send(wire.Encode(wire.Teardown, crid.WireBytes(), nil))
	}
}

// handleSessionData implements SESSION_DATA (0x21): forwarded verbatim —
// the exact received bytes — iff the CRID is bridged and the sender is one
// of its two members. Anything else is a silent drop; the payload is
// opaque ciphertext and never inspected (handshake and transport frames
// look identical here).
func handleSessionData(c *conn, f wire.Frame, raw []byte) {
	crid := ident.CRIDFromWire(f.RoutingID)
	if to, ok := c.srv.channels.Forward(crid, c); ok {
		to.send(raw)
	}
}
