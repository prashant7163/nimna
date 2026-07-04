package wire

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"strconv"
	"strings"
	"testing"
)

// validHeader returns a minimal valid REGISTER_TOPIC frame (18 bytes).
func validHeader() []byte {
	b := make([]byte, HeaderLen)
	b[0] = Version
	b[1] = byte(RegisterTopic)
	for i := 2; i < HeaderLen; i++ {
		b[i] = byte(i)
	}
	return b
}

// TestParseInvalid covers the invalid-case vectors deferred from Session 2
// (architecture note §7): they live here as table-driven tests, not in
// framing.json.
func TestParseInvalid(t *testing.T) {
	oversize := append(validHeader(), make([]byte, MaxFrame-HeaderLen+1)...)

	cases := []struct {
		name string
		in   []byte
		want error
	}{
		{"empty-frame", []byte{}, ErrShort},
		{"nil-frame", nil, ErrShort},
		{"one-byte", []byte{Version}, ErrShort},
		{"short-header-17", validHeader()[:17], ErrShort},
		{"bad-version-0x00", append([]byte{0x00}, validHeader()[1:]...), ErrVersion},
		{"bad-version-0x02", append([]byte{0x02}, validHeader()[1:]...), ErrVersion},
		{"unknown-type-0x00", frameWithType(0x00), ErrType},
		{"unknown-type-0x06", frameWithType(0x06), ErrType},
		{"unknown-type-0x0f", frameWithType(0x0f), ErrType},
		{"unknown-type-0x13", frameWithType(0x13), ErrType},
		{"unknown-type-0x22", frameWithType(0x22), ErrType},
		{"unknown-type-0xff", frameWithType(0xff), ErrType},
		{"oversize", oversize, ErrOversize},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Parse(c.in)
			if !errors.Is(err, c.want) {
				t.Fatalf("Parse: got err %v, want %v", err, c.want)
			}
		})
	}
}

func frameWithType(ft byte) []byte {
	b := validHeader()
	b[1] = ft
	return b
}

// TestParseValidBounds pins the boundary semantics: an exactly-header
// frame (empty payload), an exactly-MaxFrame frame, and the all-zero
// routing_id (legal and routable — the relay never judges identifier
// bytes).
func TestParseValidBounds(t *testing.T) {
	t.Run("header-only-empty-payload", func(t *testing.T) {
		f, err := Parse(validHeader())
		if err != nil {
			t.Fatalf("Parse: %v", err)
		}
		if f.Type != RegisterTopic {
			t.Fatalf("Type: got %#x, want %#x", byte(f.Type), byte(RegisterTopic))
		}
		if len(f.Payload) != 0 {
			t.Fatalf("Payload: got %d bytes, want 0", len(f.Payload))
		}
	})
	t.Run("max-frame-accepted", func(t *testing.T) {
		b := append(validHeader(), make([]byte, MaxFrame-HeaderLen)...)
		f, err := Parse(b)
		if err != nil {
			t.Fatalf("Parse: %v", err)
		}
		if len(f.Payload) != MaxFrame-HeaderLen {
			t.Fatalf("Payload: got %d bytes, want %d", len(f.Payload), MaxFrame-HeaderLen)
		}
	})
	t.Run("zero-routing-id-routable", func(t *testing.T) {
		b := validHeader()
		for i := 2; i < HeaderLen; i++ {
			b[i] = 0
		}
		f, err := Parse(b)
		if err != nil {
			t.Fatalf("Parse: %v", err)
		}
		if f.RoutingID != [RoutingIDLen]byte{} {
			t.Fatal("routing_id: want all-zero")
		}
	})
}

func TestFrameTypeValid(t *testing.T) {
	valid := []FrameType{
		RegisterTopic, RegisterCRID, Knock, Accept, Teardown,
		TopicBridged, KnockFwd, SessionBridged, PairData, SessionData,
	}
	seen := map[FrameType]bool{}
	for _, ft := range valid {
		if !ft.Valid() {
			t.Errorf("FrameType %#x: Valid() = false, want true", byte(ft))
		}
		seen[ft] = true
	}
	if len(seen) != 10 {
		t.Fatalf("enum: %d distinct types, want 10 (spec §5.4)", len(seen))
	}
	for v := 0; v < 256; v++ {
		ft := FrameType(v)
		if ft.Valid() != seen[ft] {
			t.Errorf("FrameType %#x: Valid() = %v, want %v", v, ft.Valid(), seen[ft])
		}
	}
}

func TestEncodeParseRoundTrip(t *testing.T) {
	var rid [RoutingIDLen]byte
	for i := range rid {
		rid[i] = byte(0xa0 + i)
	}
	payload := []byte{0xde, 0xad, 0xbe, 0xef}
	b := Encode(PairData, rid, payload)
	if len(b) != HeaderLen+len(payload) {
		t.Fatalf("Encode: %d bytes, want %d", len(b), HeaderLen+len(payload))
	}
	f, err := Parse(b)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if f.Type != PairData || f.RoutingID != rid || !bytes.Equal(f.Payload, payload) {
		t.Fatal("round trip: parsed frame does not match encoded inputs")
	}
}

// outerFrameVector mirrors the outer_frames entries of
// testdata/framing.json (read-only conformance fixtures — the committed
// vectors are never regenerated or edited here). The file is a vendored
// byte-identical copy of the monorepo's docs/test-vectors/framing.json
// (see testdata/README.md); monorepo CI cmp-asserts it never drifts.
type outerFrameVector struct {
	Name      string `json:"name"`
	FrameType string `json:"frame_type"` // "0x01 REGISTER_TOPIC"
	RoutingID string `json:"routing_id"` // hex
	Payload   string `json:"payload"`    // hex, may be empty
	Encoded   string `json:"encoded"`    // hex
}

// TestFramingVectors loads the valid outer_frames cases from the committed
// protocol test vectors and asserts byte-exact Parse and Encode agreement.
func TestFramingVectors(t *testing.T) {
	raw, err := os.ReadFile("testdata/framing.json")
	if err != nil {
		t.Fatalf("reading committed vectors: %v", err)
	}
	var doc struct {
		OuterFrames []outerFrameVector `json:"outer_frames"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("decoding vectors: %v", err)
	}
	if len(doc.OuterFrames) == 0 {
		t.Fatal("no outer_frames cases found in framing.json")
	}
	for _, v := range doc.OuterFrames {
		t.Run(v.Name, func(t *testing.T) {
			wantTypeStr, _, ok := strings.Cut(v.FrameType, " ")
			if !ok {
				t.Fatalf("frame_type %q: want \"0xNN NAME\"", v.FrameType)
			}
			wantType64, err := strconv.ParseUint(wantTypeStr, 0, 8)
			if err != nil {
				t.Fatalf("frame_type %q: %v", v.FrameType, err)
			}
			wantType := FrameType(wantType64)
			encoded := mustHex(t, v.Encoded)
			wantRID := mustHex(t, v.RoutingID)
			wantPayload := mustHex(t, v.Payload)

			f, err := Parse(encoded)
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			if f.Type != wantType {
				t.Errorf("Type: got %#x, want %#x", byte(f.Type), byte(wantType))
			}
			if !bytes.Equal(f.RoutingID[:], wantRID) {
				t.Error("routing_id: parsed bytes differ from vector")
			}
			if !bytes.Equal(f.Payload, wantPayload) {
				t.Error("payload: parsed bytes differ from vector")
			}

			var rid [RoutingIDLen]byte
			copy(rid[:], wantRID)
			if got := Encode(wantType, rid, wantPayload); !bytes.Equal(got, encoded) {
				t.Error("Encode: bytes differ from vector encoding")
			}
		})
	}
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex in vector: %v", err)
	}
	return b
}
