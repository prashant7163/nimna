// Package ident provides the relay's unloggable identifier wrapper types
// (logging doctrine; architecture note §4). A Topic, CRID, RemoteAddr or
// DeviceToken can never reach a log, an error string, or any serialized
// form as identifier bytes: every rendering surface — fmt (all verbs, via
// fmt.Formatter), encoding/text, encoding/json, and log/slog — emits a
// fixed tag such as "topic[redacted]" with zero identifier bytes. There is
// deliberately no truncated-hex form: partial values still correlate.
//
// The ONLY raw accessor is the greppable WireBytes(), used solely to build
// outbound frames at the wire boundary; every call site is audited in
// review. The underlying bytes live in unexported fields so no other
// access path exists.
//
// Topic and CRID are comparable value types: registries key maps on them
// directly without ever exposing bytes.
package ident

import (
	"fmt"
	"log/slog"
	"net/netip"
)

// redact implements every rendering surface for a fixed tag.
func redactFormat(f fmt.State, tag string) {
	// All verbs, all flags: the tag and nothing else. Implementing
	// fmt.Formatter covers %v %s %q %x %X %d %+v %#v alike.
	f.Write([]byte(tag))
}

// Topic is a 16-byte rendezvous topic (spec §3.1.2). It IS the code-hash:
// the HKDF expansion of the Argon2id-stretched pairing code — the closest
// thing to the code the relay ever sees, which is why it is unloggable.
type Topic struct{ b [16]byte }

// TopicFromWire wraps 16 routing_id bytes parsed off the wire.
func TopicFromWire(b [16]byte) Topic { return Topic{b: b} }

// WireBytes returns the raw bytes for building outbound frames. The only
// raw accessor; every call site is review-audited.
func (t Topic) WireBytes() [16]byte { return t.b }

const topicTag = "topic[redacted]"

func (t Topic) String() string                { return topicTag }
func (t Topic) GoString() string              { return topicTag }
func (t Topic) Format(f fmt.State, verb rune) { redactFormat(f, topicTag) }
func (t Topic) MarshalText() ([]byte, error)  { return []byte(topicTag), nil }
func (t Topic) MarshalJSON() ([]byte, error)  { return []byte(`"` + topicTag + `"`), nil }
func (t Topic) LogValue() slog.Value          { return slog.StringValue(topicTag) }

// CRID is a 16-byte channel routing identifier (spec §3.1.5): a PRF output
// both ends derive from their static keys. The relay routes on it and must
// never log it — it links a channel across sessions.
type CRID struct{ b [16]byte }

// CRIDFromWire wraps 16 routing_id bytes parsed off the wire.
func CRIDFromWire(b [16]byte) CRID { return CRID{b: b} }

// WireBytes returns the raw bytes for building outbound frames. The only
// raw accessor; every call site is review-audited.
func (c CRID) WireBytes() [16]byte { return c.b }

const cridTag = "crid[redacted]"

func (c CRID) String() string                { return cridTag }
func (c CRID) GoString() string              { return cridTag }
func (c CRID) Format(f fmt.State, verb rune) { redactFormat(f, cridTag) }
func (c CRID) MarshalText() ([]byte, error)  { return []byte(cridTag), nil }
func (c CRID) MarshalJSON() ([]byte, error)  { return []byte(`"` + cridTag + `"`), nil }
func (c CRID) LogValue() slog.Value          { return slog.StringValue(cridTag) }

// RemoteAddr is a connection's CANONICALIZED remote address key. IPs are
// unloggable (spec §4 "necessarily sees" — never at rest, never in logs).
// Comparable; the per-IP limits key on it without exposing the address. It
// has no raw accessor: the canonical key is the only address form held
// anywhere in the relay, and it never round-trips to a dialable address.
type RemoteAddr struct{ s string }

// RemoteAddrFrom canonicalizes a transport-layer address string (e.g.
// http.Request.RemoteAddr or a net.Addr's String()) at the accept boundary
// (architecture note §15): the port is stripped; an IPv4 address (including
// the IPv4-mapped ::ffff: form) keys as the exact address; an IPv6 address
// keys as its /64 prefix — a single v6 host owns a /64, so exact-address v6
// keying would be a free per-IP-cap bypass. An unparseable input (never a
// real TCP peer) keys as its whole string, still unloggable.
func RemoteAddrFrom(s string) RemoteAddr {
	var addr netip.Addr
	if ap, err := netip.ParseAddrPort(s); err == nil {
		addr = ap.Addr()
	} else if a, err := netip.ParseAddr(s); err == nil {
		addr = a
	} else {
		return RemoteAddr{s: s}
	}
	addr = addr.Unmap().WithZone("")
	if addr.Is4() {
		return RemoteAddr{s: addr.String()}
	}
	prefix, err := addr.Prefix(64)
	if err != nil {
		// Unreachable for a zone-stripped address; key exactly.
		return RemoteAddr{s: addr.String()}
	}
	return RemoteAddr{s: prefix.String()}
}

const addrTag = "addr[redacted]"

func (a RemoteAddr) String() string                { return addrTag }
func (a RemoteAddr) GoString() string              { return addrTag }
func (a RemoteAddr) Format(f fmt.State, verb rune) { redactFormat(f, addrTag) }
func (a RemoteAddr) MarshalText() ([]byte, error)  { return []byte(addrTag), nil }
func (a RemoteAddr) MarshalJSON() ([]byte, error)  { return []byte(`"` + addrTag + `"`), nil }
func (a RemoteAddr) LogValue() slog.Value          { return slog.StringValue(addrTag) }

// DeviceToken is a platform push token carried in a KNOCK payload
// (spec §3.2.1). Used once per knock to address a push, then discarded —
// never stored, never logged.
type DeviceToken struct{ b []byte }

// DeviceTokenFrom wraps raw token bytes parsed off a KNOCK payload.
func DeviceTokenFrom(b []byte) DeviceToken {
	cp := make([]byte, len(b))
	copy(cp, b)
	return DeviceToken{b: cp}
}

// WireBytes returns the raw token bytes for the single push call that
// consumes them. The only raw accessor; every call site is review-audited.
func (d DeviceToken) WireBytes() []byte { return d.b }

const tokenTag = "device-token[redacted]"

func (d DeviceToken) String() string                { return tokenTag }
func (d DeviceToken) GoString() string              { return tokenTag }
func (d DeviceToken) Format(f fmt.State, verb rune) { redactFormat(f, tokenTag) }
func (d DeviceToken) MarshalText() ([]byte, error)  { return []byte(tokenTag), nil }
func (d DeviceToken) MarshalJSON() ([]byte, error)  { return []byte(`"` + tokenTag + `"`), nil }
func (d DeviceToken) LogValue() slog.Value          { return slog.StringValue(tokenTag) }

// Interface conformance, compile-time checked.
var (
	_ fmt.Stringer   = Topic{}
	_ fmt.GoStringer = Topic{}
	_ fmt.Formatter  = Topic{}
	_ slog.LogValuer = Topic{}
	_ fmt.Stringer   = CRID{}
	_ fmt.GoStringer = CRID{}
	_ fmt.Formatter  = CRID{}
	_ slog.LogValuer = CRID{}
	_ fmt.Stringer   = RemoteAddr{}
	_ fmt.GoStringer = RemoteAddr{}
	_ fmt.Formatter  = RemoteAddr{}
	_ slog.LogValuer = RemoteAddr{}
	_ fmt.Stringer   = DeviceToken{}
	_ fmt.GoStringer = DeviceToken{}
	_ fmt.Formatter  = DeviceToken{}
	_ slog.LogValuer = DeviceToken{}
)
