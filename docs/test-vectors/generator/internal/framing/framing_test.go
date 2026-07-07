package framing

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"math/rand"
	"reflect"
	"strings"
	"testing"
)

// Round-trip property test over randomly generated VALID envelopes, with a
// fixed seed so failures are reproducible.
func TestEnvelopeRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewSource(0x6e696d6e61)) // "nimna"
	randBytes := func(n int) []byte {
		b := make([]byte, n)
		rng.Read(b)
		return b
	}
	for i := 0; i < 2000; i++ {
		var e Envelope
		copy(e.MsgID[:], randBytes(16))
		e.TimestampMS = rng.Uint64()
		switch rng.Intn(5) {
		case 0:
			e.Type = TypeText
			e.Body = randBytes(rng.Intn(600))
			if rng.Intn(2) == 0 {
				e.Flags |= FlagExpiry
				e.ExpiryS = rng.Uint32()
			}
		case 1:
			e.Type = TypeAck
			e.Body = randBytes(16)
		case 2:
			e.Type = TypeControl
			switch rng.Intn(5) {
			case 0:
				e.Body = []byte{ControlTyping}
			case 1:
				e.Body = append([]byte{ControlReadReceipt}, randBytes(16)...)
			case 2:
				e.Body = []byte{ControlScreenshot}
			case 3:
				tp, err := EncodeTokenPayload(TokenPayload{
					Present:  true,
					Platform: byte(1 + rng.Intn(2)),
					Token:    randBytes(1 + rng.Intn(200)),
				})
				if err != nil {
					t.Fatal(err)
				}
				e.Body = append([]byte{ControlTokenRefresh}, tp...)
			case 4:
				// Unknown control type: ignored, never an error (§5.5).
				e.Body = append([]byte{0x7F}, randBytes(rng.Intn(40))...)
			}
		case 3:
			e.Type = TypeHangup
		case 4:
			e.Type = TypeMediaChunk
			if rng.Intn(2) == 0 {
				e.Flags |= FlagManifest
				m, err := EncodeManifest(Manifest{
					ChunkCount:  uint32(rng.Intn(80) + 1),
					TotalLen:    rng.Uint64() % (5 << 20),
					ContentHash: [32]byte(randBytes(32)),
					Mime:        "application/octet-stream",
				})
				if err != nil {
					t.Fatal(err)
				}
				e.Body = m
				if rng.Intn(2) == 0 {
					e.Flags |= FlagExpiry
					e.ExpiryS = rng.Uint32()
				}
			} else {
				e.Body = EncodeChunk(Chunk{
					ManifestMsgID: [16]byte(randBytes(16)),
					ChunkIndex:    uint32(rng.Intn(80)),
					Data:          randBytes(rng.Intn(500)),
				})
			}
		}
		if e.Body == nil {
			e.Body = []byte{}
		}

		enc, err := Encode(e)
		if err != nil {
			t.Fatalf("iteration %d: encode: %v (%+v)", i, err, e)
		}
		dec, err := Decode(enc)
		if err != nil {
			t.Fatalf("iteration %d: decode: %v", i, err)
		}
		if !reflect.DeepEqual(e, dec) {
			t.Fatalf("iteration %d: round-trip mismatch:\n in %+v\nout %+v", i, e, dec)
		}
		// Encode must be deterministic.
		enc2, err := Encode(dec)
		if err != nil || !bytes.Equal(enc, enc2) {
			t.Fatalf("iteration %d: re-encode differs", i)
		}
	}
}

func TestEnvelopeHeaderOffsets(t *testing.T) {
	var msgID [16]byte
	copy(msgID[:], bytes.Repeat([]byte{0xAB}, 16))
	// Without expiry the body starts at offset 27; with it, at 31 (§5.5).
	noExp, err := Encode(Envelope{Type: TypeText, MsgID: msgID, TimestampMS: 1, Body: []byte("x")})
	if err != nil {
		t.Fatal(err)
	}
	if len(noExp) != 27+1 || noExp[27] != 'x' {
		t.Fatalf("body must start at offset 27, frame %x", noExp)
	}
	exp, err := Encode(Envelope{Type: TypeText, Flags: FlagExpiry, MsgID: msgID,
		TimestampMS: 1, ExpiryS: 30, Body: []byte("x")})
	if err != nil {
		t.Fatal(err)
	}
	if len(exp) != 31+1 || exp[31] != 'x' {
		t.Fatalf("body must start at offset 31 with expiry, frame %x", exp)
	}
}

func TestEnvelopeDecodeRejects(t *testing.T) {
	valid, err := Encode(Envelope{Type: TypeText, MsgID: [16]byte{1}, TimestampMS: 2, Body: []byte("ok")})
	if err != nil {
		t.Fatal(err)
	}
	mutate := func(f func(b []byte) []byte) []byte {
		return f(append([]byte{}, valid...))
	}
	cases := map[string][]byte{
		"bad version":            mutate(func(b []byte) []byte { b[0] = 0x02; return b }),
		"unknown type":           mutate(func(b []byte) []byte { b[1] = 0x06; return b }),
		"reserved flag":          mutate(func(b []byte) []byte { b[2] = 0x04; return b }),
		"manifest flag on TEXT":  mutate(func(b []byte) []byte { b[2] = FlagManifest; return b }),
		"truncated header":       valid[:20],
		"expiry flag, no expiry": mutate(func(b []byte) []byte { b[2] = FlagExpiry; return b[:27] }),
	}
	for name, b := range cases {
		if _, err := Decode(b); err == nil {
			t.Fatalf("%s: decode succeeded, want error", name)
		}
	}
	// Structural body rules.
	bad := []Envelope{
		{Type: TypeAck, Body: []byte("short")},                                          // ACK body != 16
		{Type: TypeAck, Flags: FlagExpiry, ExpiryS: 1, Body: make([]byte, 16)},          // expiry on ACK
		{Type: TypeHangup, Body: []byte("x")},                                           // HANGUP body not empty
		{Type: TypeControl, Body: []byte{}},                                             // CONTROL missing control_type
		{Type: TypeControl, Body: []byte{ControlReadReceipt, 0x01}},                     // read receipt wrong length
		{Type: TypeControl, Flags: FlagExpiry, ExpiryS: 1, Body: []byte{ControlTyping}}, // expiry on CONTROL
	}
	for i, e := range bad {
		if _, err := Encode(e); err == nil {
			t.Fatalf("bad envelope %d: encode succeeded, want error", i)
		}
	}
}

func TestTokenPayloadForms(t *testing.T) {
	// Absent / revoke: exactly one 0x00 byte.
	absent, err := EncodeTokenPayload(TokenPayload{})
	if err != nil || !bytes.Equal(absent, []byte{0x00}) {
		t.Fatalf("absent form must be 0x00, got %x (%v)", absent, err)
	}
	// Present: 0x01 ‖ platform ‖ len(2, BE) ‖ token.
	token := bytes.Repeat([]byte{0xCD}, 32)
	present, err := EncodeTokenPayload(TokenPayload{Present: true, Platform: PlatformAPNs, Token: token})
	if err != nil {
		t.Fatal(err)
	}
	want := append([]byte{0x01, PlatformAPNs, 0x00, 0x20}, token...)
	if !bytes.Equal(present, want) {
		t.Fatalf("present form mismatch: %x", present)
	}
	back, err := ParseTokenPayload(present)
	if err != nil || !back.Present || back.Platform != PlatformAPNs || !bytes.Equal(back.Token, token) {
		t.Fatalf("present form did not round-trip: %+v (%v)", back, err)
	}
	// KNOCK relay-plane form: no presence byte.
	knock, err := EncodeKnockToken(PlatformFCM, token)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(knock, append([]byte{PlatformFCM, 0x00, 0x20}, token...)) {
		t.Fatalf("knock form mismatch: %x", knock)
	}
	p, tk, err := ParseKnockToken(knock)
	if err != nil || p != PlatformFCM || !bytes.Equal(tk, token) {
		t.Fatalf("knock form did not round-trip")
	}
	// Rejections.
	for name, b := range map[string][]byte{
		"empty":            {},
		"absent with tail": {0x00, 0x01},
		"unknown presence": {0x02},
		"unknown platform": {0x01, 0x03, 0x00, 0x00},
		"length mismatch":  {0x01, 0x01, 0x00, 0x05, 0xAA},
	} {
		if _, err := ParseTokenPayload(b); err == nil {
			t.Fatalf("%s: parse succeeded, want error", name)
		}
	}
}

func TestOuterFrame(t *testing.T) {
	var rid [16]byte
	copy(rid[:], bytes.Repeat([]byte{0x42}, 16))
	f := OuterFrame(FrameSessionData, rid, []byte{0xDE, 0xAD})
	if len(f) != 20 || f[0] != 0x01 || f[1] != 0x21 || !bytes.Equal(f[2:18], rid[:]) {
		t.Fatalf("outer frame mismatch: %x", f)
	}
	if h := OuterHeader(FramePairData, rid); len(h) != OuterHeaderLen || h[1] != 0x20 {
		t.Fatalf("outer header mismatch: %x", h)
	}
}

func TestMediaReassembly(t *testing.T) {
	content := make([]byte, ChunkPlaintextSize+3) // two chunks: 65536 + 3
	for i := range content {
		content[i] = byte(i * 31)
	}
	m := Manifest{
		ChunkCount:  2,
		TotalLen:    uint64(len(content)),
		ContentHash: sha256.Sum256(content),
		Mime:        "image/jpeg",
	}
	var mid [16]byte
	chunks := []Chunk{
		{ManifestMsgID: mid, ChunkIndex: 0, Data: content[:ChunkPlaintextSize]},
		{ManifestMsgID: mid, ChunkIndex: 1, Data: content[ChunkPlaintextSize:]},
	}
	got, err := Reassemble(m, chunks)
	if err != nil || !bytes.Equal(got, content) {
		t.Fatalf("reassembly failed: %v", err)
	}
	// chunk_count must equal ceil(total_len/65536).
	m2 := m
	m2.ChunkCount = 3
	if _, err := Reassemble(m2, chunks); err == nil {
		t.Fatal("wrong chunk_count accepted")
	}
	// Hash mismatch = discard (an error here; never a protocol error, §5.1).
	m3 := m
	m3.ContentHash[0] ^= 1
	if _, err := Reassemble(m3, chunks); err == nil {
		t.Fatal("hash mismatch accepted")
	}
	// Non-final chunk must be exactly 65536 bytes.
	badChunks := []Chunk{
		{ManifestMsgID: mid, ChunkIndex: 0, Data: content[:100]},
		{ManifestMsgID: mid, ChunkIndex: 1, Data: content[100:]},
	}
	if _, err := Reassemble(m, badChunks); err == nil {
		t.Fatal("short non-final chunk accepted")
	}
}

func TestManifestEncoding(t *testing.T) {
	m := Manifest{ChunkCount: 2, TotalLen: 65539, ContentHash: [32]byte{0xAA}, Mime: "image/jpeg"}
	enc, err := EncodeManifest(m)
	if err != nil {
		t.Fatal(err)
	}
	wantPrefix, _ := hex.DecodeString("00000002" + "0000000000010003")
	if !bytes.HasPrefix(enc, wantPrefix) {
		t.Fatalf("manifest prefix mismatch: %x", enc)
	}
	if enc[44] != byte(len("image/jpeg")) {
		t.Fatalf("mime_len mismatch")
	}
	back, err := ParseManifest(enc)
	if err != nil || !reflect.DeepEqual(m, back) {
		t.Fatalf("manifest round-trip failed: %+v (%v)", back, err)
	}
	if _, err := ParseManifest(enc[:20]); err == nil {
		t.Fatal("short manifest accepted")
	}
	if _, err := ParseManifest(append(enc, 'x')); err == nil {
		t.Fatal("mime_len mismatch accepted")
	}
}

// rawFrame builds a well-formed envelope header (ver ‖ type ‖ flags ‖ msg_id ‖
// timestamp) with an arbitrary trailer, so tests can reach the structural
// body/flag checks with deliberately malformed content.
func rawFrame(typ, flags byte, trailer []byte) []byte {
	var mid [16]byte
	copy(mid[:], bytes.Repeat([]byte{0x11}, 16))
	out := []byte{Ver, typ, flags}
	out = append(out, mid[:]...)
	out = binary.BigEndian.AppendUint64(out, 42)
	return append(out, trailer...)
}

func TestReactionEncoding(t *testing.T) {
	var ref [16]byte
	copy(ref[:], bytes.Repeat([]byte{0x22}, 16))
	cases := []struct {
		name  string
		op    byte
		emoji string
	}{
		{"add", ReactionAdd, "👍"},
		{"remove", ReactionRemove, "👍"},
		{"multibyte-zwj", ReactionAdd, "👩‍❤️‍👨"}, // 20 bytes, 6 code points
		{"one-byte-boundary", ReactionAdd, "!"},
		{"sixtyfour-byte-boundary", ReactionAdd, strings.Repeat("👍", 16)}, // exactly 64 bytes
	}
	for _, c := range cases {
		body, err := EncodeReaction(Reaction{RefMsgID: ref, Op: c.op, Emoji: []byte(c.emoji)})
		if err != nil {
			t.Fatalf("%s: EncodeReaction: %v", c.name, err)
		}
		// Body layout: ref_msg_id(16) ‖ op(1) ‖ emoji_len(1) ‖ emoji.
		if !bytes.Equal(body[:16], ref[:]) {
			t.Fatalf("%s: ref_msg_id not at offset 0", c.name)
		}
		if body[16] != c.op {
			t.Fatalf("%s: op not at offset 16", c.name)
		}
		if int(body[17]) != len(c.emoji) {
			t.Fatalf("%s: emoji_len %d != byte length %d", c.name, body[17], len(c.emoji))
		}
		if !bytes.Equal(body[18:], []byte(c.emoji)) {
			t.Fatalf("%s: emoji bytes mismatch", c.name)
		}
		r, err := ParseReaction(body)
		if err != nil || r.Op != c.op || !bytes.Equal(r.Emoji, []byte(c.emoji)) || r.RefMsgID != ref {
			t.Fatalf("%s: ParseReaction round-trip failed: %+v (%v)", c.name, r, err)
		}
		// Whole REACTION envelope must round-trip; flags stay 0.
		e := Envelope{Type: TypeReaction, MsgID: ref, TimestampMS: 7, Body: body}
		enc, err := Encode(e)
		if err != nil {
			t.Fatalf("%s: Encode envelope: %v", c.name, err)
		}
		dec, err := Decode(enc)
		if err != nil || !reflect.DeepEqual(e, dec) {
			t.Fatalf("%s: envelope round-trip failed: %v", c.name, err)
		}
	}
}

func TestReactionRejects(t *testing.T) {
	var ref [16]byte
	copy(ref[:], bytes.Repeat([]byte{0x33}, 16))
	valid := func(op byte, emojiLen byte, emoji []byte) []byte {
		return append(append(append([]byte{}, ref[:]...), op, emojiLen), emoji...)
	}
	bad := map[string][]byte{
		"emoji_len=0":            valid(ReactionAdd, 0x00, nil),
		"emoji_len=65":           valid(ReactionAdd, 65, make([]byte, 65)),
		"emoji_len!=remaining":   valid(ReactionAdd, 5, []byte("ab")),
		"bad-op":                 valid(0x02, 4, []byte("👍")),
		"invalid-utf8":           valid(ReactionAdd, 2, []byte{0xff, 0xfe}),
		"truncated-below-18":     append(append([]byte{}, ref[:8]...), ReactionAdd),
		"emoji_len=0-with-bytes": valid(ReactionAdd, 0x00, []byte("👍")), // len says 0, 4 bytes follow
	}
	for name, body := range bad {
		if _, err := ParseReaction(body); err == nil {
			t.Fatalf("%s: ParseReaction accepted a malformed body", name)
		}
		// The same violation must be caught when the body rides a full frame.
		if _, err := Decode(rawFrame(TypeReaction, 0x00, body)); err == nil {
			t.Fatalf("%s: Decode accepted a malformed REACTION frame", name)
		}
	}
	// A REACTION carries no flags: expiry (bit 0) and reply_to (bit 2) are both
	// illegal, as is any reserved bit.
	good := valid(ReactionAdd, 4, []byte("👍"))
	for name, flags := range map[string]byte{
		"expiry-flag":   FlagExpiry,
		"reply-to-flag": FlagReplyTo,
		"manifest-flag": FlagManifest,
		"reserved-flag": 0x08,
	} {
		// For expiry/reply_to the field bytes must be present so the flag/type
		// predicate (not truncation) is what rejects; build a trailer to suit.
		var trailer []byte
		switch flags {
		case FlagExpiry:
			trailer = append([]byte{0, 0, 0, 30}, good...)
		case FlagReplyTo:
			trailer = append(bytes.Repeat([]byte{0x44}, 16), good...)
		default:
			trailer = good
		}
		if _, err := Decode(rawFrame(TypeReaction, flags, trailer)); err == nil {
			t.Fatalf("%s: Decode accepted a flagged REACTION", name)
		}
	}
	// EncodeReaction rejects the same field violations at the source.
	for name, r := range map[string]Reaction{
		"bad-op":    {RefMsgID: ref, Op: 0x02, Emoji: []byte("👍")},
		"empty":     {RefMsgID: ref, Op: ReactionAdd, Emoji: nil},
		"too-long":  {RefMsgID: ref, Op: ReactionAdd, Emoji: make([]byte, 65)},
		"bad-utf8":  {RefMsgID: ref, Op: ReactionAdd, Emoji: []byte{0xff}},
		"remove-ok": {RefMsgID: ref, Op: ReactionRemove, Emoji: []byte("x")},
	} {
		_, err := EncodeReaction(r)
		if name == "remove-ok" {
			if err != nil {
				t.Fatalf("%s: EncodeReaction rejected a valid reaction: %v", name, err)
			}
			continue
		}
		if err == nil {
			t.Fatalf("%s: EncodeReaction accepted an invalid reaction", name)
		}
	}
}

func TestReplyToEncoding(t *testing.T) {
	var mid, reply [16]byte
	copy(mid[:], bytes.Repeat([]byte{0x55}, 16))
	copy(reply[:], bytes.Repeat([]byte{0x66}, 16))

	// reply_to only (bit 2): field at offset 27, body at 43.
	e := Envelope{Type: TypeText, Flags: FlagReplyTo, MsgID: mid, TimestampMS: 1,
		ReplyTo: reply, Body: []byte("x")}
	enc, err := Encode(e)
	if err != nil {
		t.Fatal(err)
	}
	if len(enc) != 27+16+1 || !bytes.Equal(enc[27:43], reply[:]) || enc[43] != 'x' {
		t.Fatalf("reply_to must sit at offset 27 without expiry: %x", enc)
	}
	if dec, err := Decode(enc); err != nil || !reflect.DeepEqual(e, dec) {
		t.Fatalf("reply_to-only round-trip failed: %v", err)
	}

	// expiry + reply_to (bits 0 and 2): expiry_s at 27, reply_to at 31, body 47.
	e2 := Envelope{Type: TypeText, Flags: FlagExpiry | FlagReplyTo, MsgID: mid,
		TimestampMS: 1, ExpiryS: 30, ReplyTo: reply, Body: []byte("x")}
	enc2, err := Encode(e2)
	if err != nil {
		t.Fatal(err)
	}
	if len(enc2) != 27+4+16+1 {
		t.Fatalf("expiry+reply_to length wrong: %d", len(enc2))
	}
	if !bytes.Equal(enc2[27:31], []byte{0, 0, 0, 30}) || !bytes.Equal(enc2[31:47], reply[:]) || enc2[47] != 'x' {
		t.Fatalf("flag-bit order wrong (expiry@27, reply_to@31): %x", enc2)
	}
	if dec, err := Decode(enc2); err != nil || !reflect.DeepEqual(e2, dec) {
		t.Fatalf("expiry+reply_to round-trip failed: %v", err)
	}

	// reply_to on a MEDIA_CHUNK manifest is legal (flags 0x06).
	mBody, err := EncodeManifest(Manifest{ChunkCount: 1, TotalLen: 3,
		ContentHash: sha256.Sum256([]byte("abc")), Mime: "text/plain"})
	if err != nil {
		t.Fatal(err)
	}
	em := Envelope{Type: TypeMediaChunk, Flags: FlagManifest | FlagReplyTo, MsgID: mid,
		TimestampMS: 1, ReplyTo: reply, Body: mBody}
	encm, err := Encode(em)
	if err != nil {
		t.Fatalf("reply_to on manifest must encode: %v", err)
	}
	if dec, err := Decode(encm); err != nil || !reflect.DeepEqual(em, dec) {
		t.Fatalf("reply_to-manifest round-trip failed: %v", err)
	}
}

func TestReplyToRejects(t *testing.T) {
	var reply, acked [16]byte
	copy(reply[:], bytes.Repeat([]byte{0x77}, 16))
	copy(acked[:], bytes.Repeat([]byte{0x88}, 16))
	reaction := append(append(append([]byte{}, reply[:]...), ReactionAdd, 0x04), []byte("👍")...)

	// reply_to (bit 2) present with a full 16-byte field on types that may not
	// carry it: the flag/type predicate rejects, not truncation.
	illegal := map[string][]byte{
		"on-ack":      rawFrame(TypeAck, FlagReplyTo, append(append([]byte{}, reply[:]...), acked[:]...)),
		"on-control":  rawFrame(TypeControl, FlagReplyTo, append(append([]byte{}, reply[:]...), ControlTyping)),
		"on-hangup":   rawFrame(TypeHangup, FlagReplyTo, reply[:]),
		"on-reaction": rawFrame(TypeReaction, FlagReplyTo, append(append([]byte{}, reply[:]...), reaction...)),
	}
	for name, frame := range illegal {
		if _, err := Decode(frame); err == nil {
			t.Fatalf("reply_to %s: Decode accepted an illegal reply_to", name)
		}
	}
	// bit 2 set but the frame ends before the 16-byte reply_to.
	if _, err := Decode(rawFrame(TypeText, FlagReplyTo, reply[:8])); err == nil {
		t.Fatal("reply_to truncation accepted")
	}
	// Encode enforces the same predicate at the source.
	for name, e := range map[string]Envelope{
		"encode-on-ack":    {Type: TypeAck, Flags: FlagReplyTo, ReplyTo: reply, Body: acked[:]},
		"encode-on-hangup": {Type: TypeHangup, Flags: FlagReplyTo, ReplyTo: reply},
	} {
		if _, err := Encode(e); err == nil {
			t.Fatalf("%s: Encode accepted an illegal reply_to", name)
		}
	}
}
