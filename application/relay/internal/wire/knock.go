package wire

import (
	"encoding/binary"
	"errors"
)

// KNOCK payload (spec §5.4, §5.7): the one relay-plane frame whose payload
// the relay must parse. Exactly two well-formed shapes exist:
//
//	empty                                     — no push
//	platform (1) ‖ token_len (2, BE) ‖ token  — the peer's push token
//
// There is no presence byte on the relay plane (§5.7): presence is
// signaled by a non-empty payload. Anything that is neither shape is
// structurally malformed traffic — a pure function of the received bytes,
// independent of all relay state — and the caller closes the connection
// (architecture note §9).

// Platform is the KNOCK payload's push-platform byte (spec §5.4).
type Platform byte

const (
	// PlatformAPNs addresses an Apple push token.
	PlatformAPNs Platform = 0x01
	// PlatformFCM addresses a Google push token.
	PlatformFCM Platform = 0x02
)

// knockTokenHeaderLen is platform (1) + token_len (2).
const knockTokenHeaderLen = 3

// ErrKnockPayload is the fixed-text sentinel for a malformed KNOCK
// payload. Like every wire error it carries zero frame bytes: the silence
// doctrine forbids explaining failures on the wire, and errors must never
// become an identifier side channel in logs.
var ErrKnockPayload = errors.New("wire: malformed KNOCK payload")

// KnockPayload is a parsed KNOCK payload. Token aliases the input buffer —
// the caller wraps it in ident.DeviceToken (which copies) immediately at
// the parse boundary; raw token bytes must not travel further.
type KnockPayload struct {
	HasToken bool
	Platform Platform
	Token    []byte
}

// ParseKnockPayload validates and splits a KNOCK payload (spec §5.4).
// Well-formed means: empty; or platform ∈ {0x01 APNs, 0x02 FCM},
// token_len ≥ 1, and token_len exactly equal to the remaining payload
// length. No token cap is invented beyond the structural bounds (the
// two-byte length field, and MaxFrame enforced upstream): a garbage token
// dies at the push platform — spec §3.2.1's stale-token semantics.
func ParseKnockPayload(p []byte) (KnockPayload, error) {
	if len(p) == 0 {
		return KnockPayload{}, nil
	}
	if len(p) < knockTokenHeaderLen {
		return KnockPayload{}, ErrKnockPayload
	}
	platform := Platform(p[0])
	if platform != PlatformAPNs && platform != PlatformFCM {
		return KnockPayload{}, ErrKnockPayload
	}
	tokenLen := binary.BigEndian.Uint16(p[1:knockTokenHeaderLen])
	if tokenLen == 0 || int(tokenLen) != len(p)-knockTokenHeaderLen {
		return KnockPayload{}, ErrKnockPayload
	}
	return KnockPayload{
		HasToken: true,
		Platform: platform,
		Token:    p[knockTokenHeaderLen:],
	}, nil
}

// EncodeKnockPayload builds the non-empty KNOCK payload form:
// platform (1) ‖ token_len (2, big-endian) ‖ token. Used by clients (the
// test client) and tests; the relay itself never builds a KNOCK payload —
// its relay-emitted KNOCK_FWD is empty by construction. Panics on a token
// outside the structural uint16 form: that is a caller bug, never wire
// input.
func EncodeKnockPayload(platform Platform, token []byte) []byte {
	if len(token) == 0 || len(token) > 0xFFFF {
		panic("wire: token length outside the uint16 KNOCK form")
	}
	b := make([]byte, knockTokenHeaderLen+len(token))
	b[0] = byte(platform)
	binary.BigEndian.PutUint16(b[1:knockTokenHeaderLen], uint16(len(token)))
	copy(b[knockTokenHeaderLen:], token)
	return b
}
