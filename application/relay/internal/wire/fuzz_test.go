package wire

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// S18 adversarial pass (§18-C): native Go fuzz targets on the two wire
// parsing surfaces. Both are TEST-ONLY and add nothing to the relay's
// runtime graph. Under `go test` they execute the seed corpus once (0 fuzz
// iterations); real fuzzing runs under `go test -fuzz`.
//
// The shared invariant, asserted for BOTH parsers:
//   - the parser never panics on arbitrary bytes;
//   - it never returns a nil error together with an out-of-spec frame; and
//   - every ACCEPTED frame round-trips: re-encoding the parsed fields
//     reproduces the input bytes exactly. Anything else is either a clean
//     rejection (non-nil error) or a fuzzer-found bug (t.Fatalf).

// seedOuterFrames returns the encoded bytes of every committed outer-frame
// vector, so the corpus starts from known-good, spec-shaped frames.
func seedOuterFrames(t *testing.F) [][]byte {
	t.Helper()
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
	var out [][]byte
	for _, v := range doc.OuterFrames {
		b, err := hex.DecodeString(v.Encoded)
		if err != nil {
			t.Fatalf("bad hex in vector %q: %v", v.Name, err)
		}
		out = append(out, b)
	}
	return out
}

// seedKnockPayloads returns the KNOCK payload bytes of every committed
// KNOCK vector (empty and with-token forms).
func seedKnockPayloads(t *testing.F) [][]byte {
	t.Helper()
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
	var out [][]byte
	for _, v := range doc.OuterFrames {
		if v.FrameType != "0x03 KNOCK" {
			continue
		}
		b, err := hex.DecodeString(v.Payload)
		if err != nil {
			t.Fatalf("bad hex in vector %q: %v", v.Name, err)
		}
		out = append(out, b)
	}
	return out
}

// FuzzParse fuzzes the §5.4 outer-frame parser. Seeds: every committed
// outer-frame vector, a minimal valid header, and the table-driven invalid
// cases from TestParseInvalid.
func FuzzParse(f *testing.F) {
	for _, b := range seedOuterFrames(f) {
		f.Add(b)
	}
	f.Add(validHeader())
	// Known-good boundary: an exactly-MaxFrame frame.
	f.Add(append(validHeader(), make([]byte, MaxFrame-HeaderLen)...))
	// Invalid seeds (mirror TestParseInvalid) so the corpus straddles the
	// accept/reject boundary from the first run.
	f.Add([]byte{})
	f.Add([]byte{Version})
	f.Add(validHeader()[:HeaderLen-1])
	f.Add(append([]byte{0x00}, validHeader()[1:]...))       // bad version
	f.Add(frameWithType(0x00))                              // unknown type
	f.Add(frameWithType(0xff))                              // unknown type
	f.Add(append(validHeader(), make([]byte, MaxFrame)...)) // oversize

	f.Fuzz(func(t *testing.T, b []byte) {
		frame, err := Parse(b) // invariant 1: must never panic.
		if err != nil {
			return // clean rejection — the only other allowed outcome.
		}
		// Invariant 2: an accepted frame MUST be in-spec.
		if len(b) < HeaderLen {
			t.Fatalf("accepted frame shorter than %d-byte header: %d bytes", HeaderLen, len(b))
		}
		if len(b) > MaxFrame {
			t.Fatalf("accepted frame exceeds MaxFrame: %d bytes", len(b))
		}
		if b[0] != Version {
			t.Fatalf("accepted frame with unsupported version %#x", b[0])
		}
		if !frame.Type.Valid() {
			t.Fatalf("accepted frame with out-of-spec type %#x", byte(frame.Type))
		}
		// Invariant 3: an accepted frame round-trips byte-for-byte.
		if got := Encode(frame.Type, frame.RoutingID, frame.Payload); !bytes.Equal(got, b) {
			t.Fatalf("round-trip mismatch: Encode(Parse(b)) != b\n in:  % x\n out: % x", b, got)
		}
	})
}

// FuzzParseKnockPayload fuzzes the §5.4/§5.7 KNOCK payload parser. Seeds:
// the committed KNOCK payloads plus the table-driven invalid cases from
// TestParseKnockPayloadInvalid.
func FuzzParseKnockPayload(f *testing.F) {
	for _, b := range seedKnockPayloads(f) {
		f.Add(b)
	}
	// Valid seeds.
	f.Add([]byte(nil))
	f.Add(EncodeKnockPayload(PlatformAPNs, []byte{0x7f}))
	f.Add(EncodeKnockPayload(PlatformFCM, bytes.Repeat([]byte{0xa5}, 32)))
	// Invalid seeds (mirror TestParseKnockPayloadInvalid).
	f.Add([]byte{0x01})                        // platform only
	f.Add([]byte{0x01, 0x00})                  // one length byte
	f.Add(knockPayload(0x01, 0, nil))          // token_len zero
	f.Add(knockPayload(0x01, 5, []byte{1, 2})) // token shorter than len
	f.Add(knockPayload(0x01, 1, []byte{1, 2})) // token longer than len
	f.Add(knockPayload(0x00, 1, []byte{0xAA})) // bad platform
	f.Add(knockPayload(0xff, 1, []byte{0xAA})) // bad platform

	f.Fuzz(func(t *testing.T, p []byte) {
		kp, err := ParseKnockPayload(p) // invariant 1: must never panic.
		if err != nil {
			return // clean rejection.
		}
		if !kp.HasToken {
			// Invariant 2a: the only no-token accept is the empty payload.
			if len(p) != 0 {
				t.Fatalf("no-token accept for a %d-byte payload", len(p))
			}
			return
		}
		// Invariant 2b: a with-token accept has a valid platform...
		if kp.Platform != PlatformAPNs && kp.Platform != PlatformFCM {
			t.Fatalf("accepted invalid platform %#x", byte(kp.Platform))
		}
		// ...and a token whose length exactly consumes the payload.
		if len(kp.Token) != len(p)-knockTokenHeaderLen {
			t.Fatalf("token length %d disagrees with payload %d", len(kp.Token), len(p))
		}
		// Invariant 3: round-trips byte-for-byte.
		if got := EncodeKnockPayload(kp.Platform, kp.Token); !bytes.Equal(got, p) {
			t.Fatalf("round-trip mismatch: Encode(Parse(p)) != p\n in:  % x\n out: % x", p, got)
		}
	})
}
