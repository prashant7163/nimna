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
