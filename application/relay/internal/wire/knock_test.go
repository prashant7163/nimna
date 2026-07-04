package wire

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"testing"
)

// knockPayload assembles platform ‖ token_len(2, BE) ‖ token with an
// arbitrary (possibly lying) length field, for invalid-case construction.
func knockPayload(platform byte, tokenLen uint16, token []byte) []byte {
	b := []byte{platform, byte(tokenLen >> 8), byte(tokenLen)}
	return append(b, token...)
}

// TestParseKnockPayloadInvalid is the table-driven invalid-case suite
// (architecture note §9): every case is structurally malformed traffic
// that must close the connection — asserted here as ErrKnockPayload, and
// at the wire in internal/server's TestRow07MalformedKnockPayloadCloses.
func TestParseKnockPayloadInvalid(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
	}{
		{"platform-only", []byte{0x01}},
		{"platform-plus-one-length-byte", []byte{0x01, 0x00}},
		{"token-len-zero", knockPayload(0x01, 0, nil)},
		{"token-len-zero-with-trailing", knockPayload(0x01, 0, []byte{0xAA})},
		{"token-shorter-than-len", knockPayload(0x01, 5, []byte{1, 2, 3, 4})},
		{"token-longer-than-len", knockPayload(0x01, 1, []byte{1, 2})},
		{"platform-0x00", knockPayload(0x00, 1, []byte{0xAA})},
		{"platform-0x03", knockPayload(0x03, 1, []byte{0xAA})},
		{"platform-0xff", knockPayload(0xFF, 1, []byte{0xAA})},
		// A little-endian length field for a 1-byte token reads as
		// 0x0100 big-endian: the mismatch must be rejected (the field
		// is big-endian, pinned by the committed vectors).
		{"token-len-little-endian", knockPayload(0x01, 1<<8, []byte{0xAA})},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := ParseKnockPayload(tc.in); !errors.Is(err, ErrKnockPayload) {
				t.Fatalf("ParseKnockPayload: got err %v, want ErrKnockPayload", err)
			}
		})
	}
}

func TestParseKnockPayloadValid(t *testing.T) {
	t.Run("empty-means-no-push", func(t *testing.T) {
		for _, in := range [][]byte{nil, {}} {
			kp, err := ParseKnockPayload(in)
			if err != nil {
				t.Fatalf("ParseKnockPayload: %v", err)
			}
			if kp.HasToken {
				t.Fatal("empty payload must parse as no-token")
			}
		}
	})
	t.Run("minimal-one-byte-token", func(t *testing.T) {
		kp, err := ParseKnockPayload(knockPayload(0x02, 1, []byte{0x7F}))
		if err != nil {
			t.Fatalf("ParseKnockPayload: %v", err)
		}
		if !kp.HasToken || kp.Platform != PlatformFCM || !bytes.Equal(kp.Token, []byte{0x7F}) {
			t.Fatalf("parsed %+q platform %#x", kp.Token, byte(kp.Platform))
		}
	})
	t.Run("both-platforms", func(t *testing.T) {
		token := bytes.Repeat([]byte{0xA5}, 32)
		for _, p := range []Platform{PlatformAPNs, PlatformFCM} {
			kp, err := ParseKnockPayload(knockPayload(byte(p), 32, token))
			if err != nil {
				t.Fatalf("platform %#x: %v", byte(p), err)
			}
			if kp.Platform != p || !bytes.Equal(kp.Token, token) {
				t.Fatalf("platform %#x: bad parse", byte(p))
			}
		}
	})
	t.Run("big-endian-length-pinned", func(t *testing.T) {
		// token_len 0x0102 = 258: only a big-endian read matches the
		// 258 token bytes that follow.
		token := bytes.Repeat([]byte{0xC3}, 258)
		kp, err := ParseKnockPayload(knockPayload(0x01, 258, token))
		if err != nil {
			t.Fatalf("ParseKnockPayload: %v", err)
		}
		if len(kp.Token) != 258 {
			t.Fatalf("token length: got %d, want 258", len(kp.Token))
		}
	})
	t.Run("max-uint16-token", func(t *testing.T) {
		token := bytes.Repeat([]byte{0x11}, 0xFFFF)
		kp, err := ParseKnockPayload(knockPayload(0x01, 0xFFFF, token))
		if err != nil {
			t.Fatalf("ParseKnockPayload: %v", err)
		}
		if len(kp.Token) != 0xFFFF {
			t.Fatalf("token length: got %d, want %d", len(kp.Token), 0xFFFF)
		}
	})
}

func TestEncodeKnockPayloadRoundTrip(t *testing.T) {
	token := []byte{0xDE, 0xAD, 0xBE, 0xEF}
	enc := EncodeKnockPayload(PlatformAPNs, token)
	if want := append([]byte{0x01, 0x00, 0x04}, token...); !bytes.Equal(enc, want) {
		t.Fatalf("EncodeKnockPayload: got % x, want % x", enc, want)
	}
	kp, err := ParseKnockPayload(enc)
	if err != nil {
		t.Fatalf("ParseKnockPayload: %v", err)
	}
	if !kp.HasToken || kp.Platform != PlatformAPNs || !bytes.Equal(kp.Token, token) {
		t.Fatal("round trip: parsed payload does not match encoded inputs")
	}
}

// TestKnockPayloadVectors parses the KNOCK payloads of the committed
// outer-frame vectors (read-only conformance fixtures, like
// TestFramingVectors) — byte-order and shape locked to the spec vectors.
func TestKnockPayloadVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../../docs/test-vectors/framing.json")
	if err != nil {
		t.Fatalf("reading committed vectors: %v", err)
	}
	var doc struct {
		OuterFrames []outerFrameVector `json:"outer_frames"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("decoding vectors: %v", err)
	}
	var seen int
	for _, v := range doc.OuterFrames {
		if v.FrameType != "0x03 KNOCK" {
			continue
		}
		seen++
		t.Run(v.Name, func(t *testing.T) {
			payload := mustHex(t, v.Payload)
			kp, err := ParseKnockPayload(payload)
			if err != nil {
				t.Fatalf("ParseKnockPayload: %v", err)
			}
			if kp.HasToken != (len(payload) > 0) {
				t.Fatalf("HasToken: got %v for %d payload bytes", kp.HasToken, len(payload))
			}
			if !kp.HasToken {
				return
			}
			if kp.Platform != PlatformAPNs && kp.Platform != PlatformFCM {
				t.Fatalf("platform: got %#x", byte(kp.Platform))
			}
			// Re-encoding must reproduce the vector payload exactly.
			if got := EncodeKnockPayload(kp.Platform, kp.Token); !bytes.Equal(got, payload) {
				t.Error("EncodeKnockPayload: bytes differ from vector payload")
			}
		})
	}
	if seen < 2 {
		t.Fatalf("expected the empty and with-token KNOCK vectors, found %d", seen)
	}
}
