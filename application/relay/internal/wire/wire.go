// Package wire implements the Nimna outer frame (spec v0.2 §5.4): the
// fixed 18-byte header [ver:1][frame_type:1][routing_id:16] followed by a
// per-type payload. This package is THE ONLY protocol-parsing surface in
// the relay module; everything else routes on the parsed header and treats
// payloads as opaque bytes.
//
// All validation errors are fixed-text sentinels carrying zero identifier
// bytes. Per the silence doctrine they are internal signals only — the
// relay never explains a malformed frame on the wire.
package wire

import "errors"

const (
	// HeaderLen is the fixed outer-header length in bytes:
	// ver (1) + frame_type (1) + routing_id (16).
	HeaderLen = 18

	// Version is the only protocol version in existence (spec §5.4).
	Version = 0x01

	// RoutingIDLen is the routing_id field length: a rendezvous topic
	// (§3.1.2) or a CRID (§3.1.5), both exactly 16 bytes.
	RoutingIDLen = 16

	// MaxFrame is the maximum total frame size the relay accepts
	// (spec §4 default: 128 KiB). Set as the WebSocket read limit at
	// accept; Parse also enforces it for defense in depth.
	MaxFrame = 128 * 1024
)

// FrameType is the outer frame's type byte (spec §5.4).
type FrameType byte

// Relay-plane frame types (routing; payloads visible to the relay by
// necessity).
const (
	// RegisterTopic (c→r, routing_id = topic, payload empty) registers
	// rendezvous interest. Registration always succeeds silently
	// (§3.1.6): no ack frame exists.
	RegisterTopic FrameType = 0x01
	// RegisterCRID (c→r, routing_id = CRID, payload empty). One frame
	// per CRID. Handled in Session 4.
	RegisterCRID FrameType = 0x02
	// Knock (c→r, routing_id = CRID) initiates a session; the payload
	// is empty (no push) or platform ‖ token_len ‖ token (§3.2.1).
	// Handled in Session 4.
	Knock FrameType = 0x03
	// Accept (c→r, routing_id = CRID, payload empty). Handled in
	// Session 4.
	Accept FrameType = 0x04
	// Teardown (both directions, routing_id = CRID, payload empty).
	// CRID-plane only; disconnection is an implicit TEARDOWN. Handled
	// in Session 4.
	Teardown FrameType = 0x05
)

// Relay→client go-signals.
const (
	// TopicBridged (r→c, routing_id = topic, payload empty) is sent to
	// both ends when a topic's second registrant arrives.
	TopicBridged FrameType = 0x10
	// KnockFwd (r→c, routing_id = CRID, payload empty — any token is
	// stripped before forwarding). Handled in Session 4.
	KnockFwd FrameType = 0x11
	// SessionBridged (r→c, routing_id = CRID, payload empty), sent to
	// both ends on ACCEPT. Handled in Session 4.
	SessionBridged FrameType = 0x12
)

// Data-plane frame types (forwarded verbatim; payload opaque to the relay).
const (
	// PairData (routing_id = topic) carries pairing-handshake bytes
	// M1–M4 (§3.1.3), forwarded verbatim between a bridged topic's two
	// ends.
	PairData FrameType = 0x20
	// SessionData (routing_id = CRID) carries session-handshake and
	// transport ciphertext (§3.3.1). Handled in Session 4.
	SessionData FrameType = 0x21
)

// Valid reports whether t is a defined §5.4 frame type. Anything else is
// structurally malformed traffic (the connection is closed, silently).
func (t FrameType) Valid() bool {
	switch t {
	case RegisterTopic, RegisterCRID, Knock, Accept, Teardown,
		TopicBridged, KnockFwd, SessionBridged,
		PairData, SessionData:
		return true
	}
	return false
}

// Fixed-text sentinel errors. They deliberately carry no frame bytes: the
// silence doctrine forbids explaining failures on the wire, and errors
// must never become an identifier side channel in logs.
var (
	// ErrShort is returned for frames shorter than the 18-byte header
	// (including the empty frame).
	ErrShort = errors.New("wire: frame shorter than outer header")
	// ErrVersion is returned when ver is not 0x01.
	ErrVersion = errors.New("wire: unsupported protocol version")
	// ErrType is returned for frame-type bytes outside the §5.4 enum.
	ErrType = errors.New("wire: unknown frame type")
	// ErrOversize is returned for frames larger than MaxFrame. The
	// WebSocket read limit normally rejects these before Parse runs;
	// this check is defense in depth.
	ErrOversize = errors.New("wire: frame exceeds maximum size")
)

// Frame is a parsed outer frame. RoutingID is plane-dependent raw bytes
// (topic or CRID); callers wrap it in the matching internal/ident type at
// the routing boundary. Payload aliases the input buffer — it is not a
// copy.
type Frame struct {
	Type      FrameType
	RoutingID [RoutingIDLen]byte
	Payload   []byte
}

// Parse validates and splits an outer frame (spec §5.4). It enforces
// exactly: minimum length (18-byte header), ver == 0x01, a defined frame
// type, and the MaxFrame bound. The routing_id is any 16 bytes — an
// all-zero routing_id is a legal, routable value like any other; the relay
// cannot and does not judge identifier bytes. Payload contents are never
// inspected here.
func Parse(b []byte) (Frame, error) {
	if len(b) < HeaderLen {
		return Frame{}, ErrShort
	}
	if len(b) > MaxFrame {
		return Frame{}, ErrOversize
	}
	if b[0] != Version {
		return Frame{}, ErrVersion
	}
	t := FrameType(b[1])
	if !t.Valid() {
		return Frame{}, ErrType
	}
	var f Frame
	f.Type = t
	copy(f.RoutingID[:], b[2:HeaderLen])
	f.Payload = b[HeaderLen:]
	return f, nil
}

// Encode builds an outer frame: [0x01][t][routingID][payload...].
func Encode(t FrameType, routingID [RoutingIDLen]byte, payload []byte) []byte {
	b := make([]byte, HeaderLen+len(payload))
	b[0] = Version
	b[1] = byte(t)
	copy(b[2:HeaderLen], routingID[:])
	copy(b[HeaderLen:], payload)
	return b
}
