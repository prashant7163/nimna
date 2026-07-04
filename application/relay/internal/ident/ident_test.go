package ident

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"testing"
)

// Distinctive raw values: any leak — full hex, truncated hex, raw bytes,
// or decimal renderings — is caught by scanning outputs for fragments.
var rawID = [16]byte{
	0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xf0, 0x0d,
	0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
}

var rawToken = []byte("apns-token-EXTREMELY-SECRET-0123456789")

const rawAddr = "203.0.113.77:54321"

// leakFragments returns substrings whose presence in any rendering would
// mean identifier bytes escaped (full or partial).
func leakFragments(raw []byte) []string {
	h := hex.EncodeToString(raw)
	frags := []string{
		h,                  // full lowercase hex
		strings.ToUpper(h), // full uppercase hex
		h[:8],              // truncated hex (partial values still correlate)
		strings.ToUpper(h[:8]),
	}
	if s := string(raw); isMostlyPrintable(raw) {
		frags = append(frags, s, s[:8])
	}
	return frags
}

func isMostlyPrintable(b []byte) bool {
	for _, c := range b {
		if c < 0x20 || c > 0x7e {
			return false
		}
	}
	return len(b) > 0
}

func assertRedacted(t *testing.T, surface, out, wantTag string, raw []byte) {
	t.Helper()
	if !strings.Contains(out, wantTag) {
		t.Errorf("%s: output %q does not carry the fixed tag %q", surface, out, wantTag)
	}
	for _, frag := range leakFragments(raw) {
		if strings.Contains(out, frag) {
			t.Errorf("%s: output %q leaks identifier fragment %q", surface, out, frag)
		}
	}
	// Decimal byte renderings (e.g. a %d or %v fallthrough on an array)
	// would contain sequences like "222 173 190" — catch the first raw
	// byte rendered in decimal next to the second.
	if len(raw) >= 2 {
		dec := fmt.Sprintf("%d %d", raw[0], raw[1])
		if strings.Contains(out, dec) {
			t.Errorf("%s: output %q leaks decimal byte rendering %q", surface, out, dec)
		}
	}
}

// each subject under test: value, its fixed tag, and its raw bytes.
type subject struct {
	name string
	val  any
	tag  string
	raw  []byte
}

func subjects() []subject {
	return []subject{
		{"Topic", TopicFromWire(rawID), "topic[redacted]", rawID[:]},
		{"CRID", CRIDFromWire(rawID), "crid[redacted]", rawID[:]},
		{"RemoteAddr", RemoteAddrFrom(rawAddr), "addr[redacted]", []byte(rawAddr)},
		{"DeviceToken", DeviceTokenFrom(rawToken), "device-token[redacted]", rawToken},
	}
}

// TestFmtRedaction drives every practically reachable fmt path: the plain
// verbs, the hex verbs (the classic leak), quoting, flags, pointers to the
// value, and values nested inside structs/slices/maps.
func TestFmtRedaction(t *testing.T) {
	verbs := []string{"%v", "%+v", "%#v", "%s", "%q", "%x", "%X", "%d"}
	for _, s := range subjects() {
		for _, verb := range verbs {
			out := fmt.Sprintf(verb, s.val)
			assertRedacted(t, s.name+" fmt "+verb, out, s.tag, s.raw)
		}
		// Nested renderings walk into the value and must hit the
		// Formatter, not reflection.
		assertRedacted(t, s.name+" nested-slice", fmt.Sprintf("%v", []any{s.val}), s.tag, s.raw)
		assertRedacted(t, s.name+" nested-struct", fmt.Sprintf("%+v", struct{ ID any }{s.val}), s.tag, s.raw)
		assertRedacted(t, s.name+" nested-map", fmt.Sprintf("%v", map[string]any{"id": s.val}), s.tag, s.raw)
		assertRedacted(t, s.name+" Sprint", fmt.Sprint(s.val), s.tag, s.raw)
		assertRedacted(t, s.name+" errorf", fmt.Errorf("ctx: %v", s.val).Error(), s.tag, s.raw)
	}
}

func TestStringAndGoString(t *testing.T) {
	for _, s := range subjects() {
		str := s.val.(fmt.Stringer).String()
		assertRedacted(t, s.name+" String()", str, s.tag, s.raw)
		gostr := s.val.(fmt.GoStringer).GoString()
		assertRedacted(t, s.name+" GoString()", gostr, s.tag, s.raw)
	}
}

func TestJSONRedaction(t *testing.T) {
	for _, s := range subjects() {
		direct, err := json.Marshal(s.val)
		if err != nil {
			t.Fatalf("%s: json.Marshal: %v", s.name, err)
		}
		assertRedacted(t, s.name+" json direct", string(direct), s.tag, s.raw)

		wrapped, err := json.Marshal(map[string]any{"id": s.val})
		if err != nil {
			t.Fatalf("%s: json.Marshal wrapped: %v", s.name, err)
		}
		assertRedacted(t, s.name+" json wrapped", string(wrapped), s.tag, s.raw)
	}
}

func TestMarshalText(t *testing.T) {
	type textMarshaler interface {
		MarshalText() ([]byte, error)
	}
	for _, s := range subjects() {
		out, err := s.val.(textMarshaler).MarshalText()
		if err != nil {
			t.Fatalf("%s: MarshalText: %v", s.name, err)
		}
		assertRedacted(t, s.name+" MarshalText", string(out), s.tag, s.raw)
	}
}

// TestSlogRedaction proves redaction through log/slog with both the text
// and JSON handlers capturing real handler output, plus a direct
// LogValue() check.
func TestSlogRedaction(t *testing.T) {
	for _, s := range subjects() {
		var text, jsonBuf bytes.Buffer
		slog.New(slog.NewTextHandler(&text, nil)).Info("event", "id", s.val)
		assertRedacted(t, s.name+" slog text", text.String(), s.tag, s.raw)

		slog.New(slog.NewJSONHandler(&jsonBuf, nil)).Info("event", slog.Any("id", s.val))
		assertRedacted(t, s.name+" slog json", jsonBuf.String(), s.tag, s.raw)

		lv := s.val.(slog.LogValuer).LogValue()
		assertRedacted(t, s.name+" LogValue", lv.String(), s.tag, s.raw)
	}
}

// TestWireBytesRoundTrip pins the single sanctioned raw path.
func TestWireBytesRoundTrip(t *testing.T) {
	if got := TopicFromWire(rawID).WireBytes(); got != rawID {
		t.Error("Topic.WireBytes: round trip lost bytes")
	}
	if got := CRIDFromWire(rawID).WireBytes(); got != rawID {
		t.Error("CRID.WireBytes: round trip lost bytes")
	}
	if got := DeviceTokenFrom(rawToken).WireBytes(); !bytes.Equal(got, rawToken) {
		t.Error("DeviceToken.WireBytes: round trip lost bytes")
	}
}

// TestComparability pins that Topic and CRID work as map keys (registries
// depend on it) and that equality follows the wrapped bytes.
func TestComparability(t *testing.T) {
	a := TopicFromWire(rawID)
	b := TopicFromWire(rawID)
	other := TopicFromWire([16]byte{1})
	if a != b {
		t.Error("Topic: identical bytes must compare equal")
	}
	if a == other {
		t.Error("Topic: distinct bytes must compare unequal")
	}
	m := map[Topic]int{a: 1}
	if m[b] != 1 {
		t.Error("Topic: map lookup by equal value failed")
	}
	c1 := CRIDFromWire(rawID)
	c2 := CRIDFromWire(rawID)
	if c1 != c2 {
		t.Error("CRID: identical bytes must compare equal")
	}
	if RemoteAddrFrom(rawAddr) != RemoteAddrFrom(rawAddr) {
		t.Error("RemoteAddr: identical addresses must compare equal")
	}
}

// TestRemoteAddrCanonicalization pins the §15 per-IP key: port stripped,
// IPv4 exact (incl. the IPv4-mapped form), IPv6 keyed by /64 prefix with
// any zone stripped. The key is what the per-IP limits count on, so getting
// two-hosts-one-key (v6 /64) and one-host-two-keys (ports) right is
// load-bearing.
func TestRemoteAddrCanonicalization(t *testing.T) {
	cases := []struct {
		name string
		a, b string
		same bool
	}{
		{"v4 ports irrelevant", "203.0.113.77:54321", "203.0.113.77:12345", true},
		{"v4 distinct hosts distinct", "203.0.113.77:1", "203.0.113.78:1", false},
		{"v4 with and without port", "203.0.113.77:54321", "203.0.113.77", true},
		{"v4-mapped v6 keys as the v4", "[::ffff:203.0.113.77]:99", "203.0.113.77:1", true},
		{"v6 same /64 same key", "[2001:db8:1:2:aaaa::1]:443", "[2001:db8:1:2::ffff]:80", true},
		{"v6 different /64 distinct", "[2001:db8:1:2::1]:443", "[2001:db8:1:3::1]:443", false},
		{"v6 interface IDs collapse", "[2001:db8::1]:1", "[2001:db8::2]:2", true},
		{"v6 zone stripped", "[fe80::1%eth0]:1", "[fe80::1%eth1]:2", true},
		{"garbage keys as itself", "not-an-address", "not-an-address", true},
		{"distinct garbage distinct", "not-an-address", "other-garbage", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ka, kb := RemoteAddrFrom(tc.a), RemoteAddrFrom(tc.b)
			if (ka == kb) != tc.same {
				t.Errorf("RemoteAddrFrom(%q) == RemoteAddrFrom(%q): got %v, want %v",
					tc.a, tc.b, ka == kb, tc.same)
			}
		})
	}
}

// TestRemoteAddrCanonicalStillRedacts proves canonicalization gained no
// leak: every rendering surface of a canonicalized key stays the fixed tag,
// with neither the raw input nor the canonical form visible.
func TestRemoteAddrCanonicalStillRedacts(t *testing.T) {
	for _, raw := range []string{
		"203.0.113.77:54321",
		"[2001:db8:1:2:aaaa::1]:443",
		"[fe80::1%eth0]:8080",
	} {
		v := RemoteAddrFrom(raw)
		for _, out := range []string{
			fmt.Sprintf("%v", v), fmt.Sprintf("%+v", v), fmt.Sprintf("%#v", v),
			fmt.Sprintf("%s", v), fmt.Sprintf("%q", v), fmt.Sprintf("%x", v),
			v.String(), v.GoString(),
		} {
			assertRedacted(t, "RemoteAddr canonical "+raw, out, "addr[redacted]", []byte(raw))
			// The canonical (post-strip) forms must not leak either.
			for _, frag := range []string{"203.0.113", "2001:db8", "fe80::"} {
				if strings.Contains(out, frag) {
					t.Errorf("rendering %q leaks canonical fragment %q", out, frag)
				}
			}
		}
	}
}

// TestDeviceTokenCopies pins that DeviceTokenFrom copies its input: a
// caller mutating the source buffer must not reach into the token.
func TestDeviceTokenCopies(t *testing.T) {
	src := []byte{1, 2, 3}
	tok := DeviceTokenFrom(src)
	src[0] = 99
	if tok.WireBytes()[0] != 1 {
		t.Error("DeviceTokenFrom must copy, not alias, its input")
	}
}
