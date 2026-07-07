package vectors

import (
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"strings"

	"nimna.app/test-vectors/generator/internal/framing"
)

// framing.json — spec §5.1, §5.4, §5.5, §5.7: inner envelopes (every type,
// every flag combination, invalid cases), MEDIA_CHUNK transfers with
// reassembly, token_payload forms, and outer frames for every frame_type.

type framingEnvelopeCaseJSON struct {
	Name     string        `json:"name"`
	Valid    bool          `json:"valid"`
	Reason   string        `json:"reason,omitempty"`
	Envelope *envelopeJSON `json:"envelope,omitempty"`
	Encoded  string        `json:"encoded,omitempty"`
	Note     string        `json:"note,omitempty"`
}

type mediaEnvelopeJSON struct {
	Envelope envelopeJSON `json:"envelope"`
	BodyOf   string       `json:"body_layout"`
}

type manifestJSON struct {
	ChunkCount  uint32 `json:"chunk_count"`
	TotalLen    uint64 `json:"total_len"`
	ContentHash string `json:"content_hash"`
	MimeLen     int    `json:"mime_len"`
	Mime        string `json:"mime"`
	EncodedBody string `json:"encoded_body"`
}

type chunkJSON struct {
	ManifestMsgID string `json:"manifest_msg_id"`
	ChunkIndex    uint32 `json:"chunk_index"`
	DataLen       int    `json:"data_len"`
	Data          string `json:"data"`
	EncodedBody   string `json:"encoded_body"`
}

type mediaTransferJSON struct {
	Name               string         `json:"name"`
	Content            string         `json:"content"`
	ContentLen         uint64         `json:"content_len"`
	ContentSHA256      string         `json:"content_sha256"`
	Mime               string         `json:"mime"`
	ChunkPlaintextSize int            `json:"chunk_plaintext_size"`
	ChunkCount         uint32         `json:"chunk_count"`
	Manifest           manifestJSON   `json:"manifest"`
	ManifestEnvelope   envelopeJSON   `json:"manifest_envelope"`
	Chunks             []chunkJSON    `json:"chunks"`
	ChunkEnvelopes     []envelopeJSON `json:"chunk_envelopes"`
	Note               string         `json:"note"`
}

type tokenPayloadCaseJSON struct {
	Name     string `json:"name"`
	Form     string `json:"form"`
	Platform string `json:"platform,omitempty"`
	Token    string `json:"token,omitempty"`
	Encoded  string `json:"encoded"`
	Note     string `json:"note,omitempty"`
}

type outerFrameCaseJSON struct {
	Name        string `json:"name"`
	FrameType   string `json:"frame_type"`
	Direction   string `json:"direction"`
	RoutingID   string `json:"routing_id"`
	RoutingKind string `json:"routing_id_kind"`
	Payload     string `json:"payload"`
	Encoded     string `json:"encoded"`
	Note        string `json:"note,omitempty"`
}

type framingFileJSON struct {
	Purpose        string                    `json:"_purpose"`
	Spec           string                    `json:"_spec"`
	EnvelopeLayout []string                  `json:"envelope_layout"`
	Envelopes      []framingEnvelopeCaseJSON `json:"envelopes"`
	MediaTransfers []mediaTransferJSON       `json:"media_transfers"`
	TokenPayloads  []tokenPayloadCaseJSON    `json:"token_payloads"`
	OuterFrames    []outerFrameCaseJSON      `json:"outer_frames"`
}

func envJSON(e framing.Envelope, text, acked, controlType, note string) (envelopeJSON, []byte, error) {
	enc, err := framing.Encode(e)
	if err != nil {
		return envelopeJSON{}, nil, err
	}
	// Decode must agree (generator self-check).
	if _, err := framing.Decode(enc); err != nil {
		return envelopeJSON{}, nil, fmt.Errorf("generated envelope does not decode: %w", err)
	}
	out := envelopeJSON{
		Ver:         "0x01",
		Type:        envelopeTypeName(e.Type),
		Flags:       fmt.Sprintf("0x%02x", e.Flags),
		MsgID:       hexs(e.MsgID[:]),
		TimestampMS: e.TimestampMS,
		Body:        hexs(e.Body),
		Text:        text,
		AckedMsgID:  acked,
		ControlType: controlType,
		Note:        note,
		Encoded:     hexs(enc),
	}
	if e.Flags&framing.FlagExpiry != 0 {
		exp := e.ExpiryS
		out.ExpiryS = &exp
	}
	if e.Flags&framing.FlagReplyTo != 0 {
		out.ReplyTo = hexs(e.ReplyTo[:])
	}
	return out, enc, nil
}

func genFraming() (*framingFileJSON, error) {
	file := &framingFileJSON{
		Purpose: "Envelope encode/decode cases for every v0.2.1 inner type and " +
			"flag combination (plus invalid encodings that must be rejected), " +
			"including REACTION (0x06) and the reply_to flag (bit 2) with " +
			"expiry+reply_to ordering; full MEDIA_CHUNK transfers with " +
			"reassembly and content_hash; all three token_payload forms; and " +
			"an outer-frame example for every frame_type.",
		Spec: SpecRef + " §5.1, §5.4, §5.5, §5.7, §5.8",
		EnvelopeLayout: []string{
			"offset 0: ver (1) = 0x01",
			"offset 1: type (1) — 0x01 TEXT, 0x02 ACK, 0x03 CONTROL, 0x04 HANGUP, 0x05 MEDIA_CHUNK, 0x06 REACTION (v0.2.1)",
			"offset 2: flags (1) — bit 0 expiry present (TEXT and MEDIA_CHUNK manifest only), bit 1 MEDIA_CHUNK manifest, bit 2 reply_to present (v0.2.1; TEXT and MEDIA_CHUNK manifest only), bits 3–7 reserved and must be 0",
			"offset 3: msg_id (16)",
			"offset 19: timestamp (8) — sender local time, Unix milliseconds, uint64 big-endian",
			"offset 27: expiry_s (4) — present only if flags bit 0; all later offsets shift by 4",
			"then reply_to (16) — present only if flags bit 2; in flag-bit order it follows expiry_s (offset 31) when both are present, else follows timestamp (offset 27)",
			"then: body per type — REACTION body = ref_msg_id(16) ‖ op(1: 0x01 add / 0x00 remove) ‖ emoji_len(1) ‖ emoji(emoji_len, 1–64 bytes valid UTF-8)",
		},
	}
	if err := addEnvelopeCases(file); err != nil {
		return nil, err
	}
	if err := addMediaTransfers(file); err != nil {
		return nil, err
	}
	if err := addTokenPayloads(file); err != nil {
		return nil, err
	}
	addOuterFrames(file)
	return file, nil
}

func addEnvelopeCases(file *framingFileJSON) error {
	type spec struct {
		name        string
		env         framing.Envelope
		text        string
		acked       string
		controlType string
		note        string
	}
	apnsRefresh, err := framing.EncodeTokenPayload(framing.TokenPayload{
		Present: true, Platform: framing.PlatformAPNs,
		Token: fixed32("framing/apns-token"),
	})
	if err != nil {
		return err
	}
	fcmRefresh, err := framing.EncodeTokenPayload(framing.TokenPayload{
		Present: true, Platform: framing.PlatformFCM,
		Token: []byte("nimna-testvec-fcm-registration-token-0003"),
	})
	if err != nil {
		return err
	}
	revoke, err := framing.EncodeTokenPayload(framing.TokenPayload{})
	if err != nil {
		return err
	}
	manifestBody, err := framing.EncodeManifest(framing.Manifest{
		ChunkCount:  1,
		TotalLen:    24,
		ContentHash: sha256.Sum256([]byte("nimna framing manifest x")),
		Mime:        "text/plain",
	})
	if err != nil {
		return err
	}
	chunkBody := framing.EncodeChunk(framing.Chunk{
		ManifestMsgID: fixed16("framing/manifest-msg-id"),
		ChunkIndex:    0,
		Data:          []byte("nimna framing manifest x"),
	})

	readReceipt := fixed16("framing/read-receipt-of")
	acked := fixed16("framing/acked-msg-id")
	textUTF8 := "Grüße — ελληνικά — 日本語 — 🤫"

	// v0.2.1 REACTION bodies (§5.8). ref_msg_id names a TEXT or manifest the
	// recipient displays; the referent's existence is a receiver-state matter
	// (silent-drop), never a structural check — so these are all structurally
	// valid whatever ref_msg_id they carry.
	reactRef := fixed16("framing/react-ref")
	// "👍" is 4 UTF-8 bytes; a ZWJ family sequence is 20 bytes across 6 code
	// points — proof that receivers must not grapheme-segment (§5.5).
	zwjEmoji := "👩‍❤️‍👨"
	emoji64 := strings.Repeat("👍", 16) // 4 bytes × 16 = exactly 64 bytes
	reactAddBody, err := framing.EncodeReaction(framing.Reaction{
		RefMsgID: reactRef, Op: framing.ReactionAdd, Emoji: []byte("👍"),
	})
	if err != nil {
		return err
	}
	reactRemoveBody, err := framing.EncodeReaction(framing.Reaction{
		RefMsgID: reactRef, Op: framing.ReactionRemove, Emoji: []byte("👍"),
	})
	if err != nil {
		return err
	}
	reactZWJBody, err := framing.EncodeReaction(framing.Reaction{
		RefMsgID: reactRef, Op: framing.ReactionAdd, Emoji: []byte(zwjEmoji),
	})
	if err != nil {
		return err
	}
	react1Body, err := framing.EncodeReaction(framing.Reaction{
		RefMsgID: reactRef, Op: framing.ReactionAdd, Emoji: []byte("!"),
	})
	if err != nil {
		return err
	}
	react64Body, err := framing.EncodeReaction(framing.Reaction{
		RefMsgID: reactRef, Op: framing.ReactionAdd, Emoji: []byte(emoji64),
	})
	if err != nil {
		return err
	}
	replyRef := fixed16("framing/reply-ref")

	valid := []spec{
		{name: "text-min", text: "hi",
			env: framing.Envelope{Type: framing.TypeText, MsgID: fixed16("framing/text-min"),
				TimestampMS: tsBase + 100, Body: []byte("hi")},
			note: "Smallest interesting TEXT; body at offset 27"},
		{name: "text-utf8", text: textUTF8,
			env: framing.Envelope{Type: framing.TypeText, MsgID: fixed16("framing/text-utf8"),
				TimestampMS: tsBase + 200, Body: []byte(textUTF8)},
			note: "TEXT bodies are raw UTF-8; multi-byte sequences must survive round-trips byte-identically"},
		{name: "text-empty",
			env: framing.Envelope{Type: framing.TypeText, MsgID: fixed16("framing/text-empty"),
				TimestampMS: tsBase + 250, Body: []byte{}},
			note: "Zero-length TEXT body is structurally valid"},
		{name: "text-expiry", text: "vanishing",
			env: framing.Envelope{Type: framing.TypeText, Flags: framing.FlagExpiry,
				MsgID:       fixed16("framing/text-expiry"),
				TimestampMS: tsBase + 300, ExpiryS: 30, Body: []byte("vanishing")},
			note: "flags bit 0: expiry_s (4 bytes, big-endian) at offset 27; body shifts to offset 31"},
		{name: "ack", acked: hexs(acked[:]),
			env: framing.Envelope{Type: framing.TypeAck, MsgID: fixed16("framing/ack"),
				TimestampMS: tsBase + 400, Body: acked[:]},
			note: "ACK body = acked_msg_id (16 bytes)"},
		{name: "control-typing", controlType: "0x01 (typing)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-typing"),
				TimestampMS: tsBase + 500, Body: []byte{framing.ControlTyping}},
			note: "Payload empty"},
		{name: "control-read-receipt", controlType: "0x02 (read receipt)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-rr"),
				TimestampMS: tsBase + 600,
				Body:        append([]byte{framing.ControlReadReceipt}, readReceipt[:]...)},
			note: "Payload = msg_id (16) of the message that was read"},
		{name: "control-screenshot", controlType: "0x03 (screenshot notice)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-ss"),
				TimestampMS: tsBase + 700, Body: []byte{framing.ControlScreenshot}},
			note: "Payload empty (spec §5.2)"},
		{name: "control-token-refresh-apns", controlType: "0x04 (device-token refresh)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-tr-apns"),
				TimestampMS: tsBase + 800,
				Body:        append([]byte{framing.ControlTokenRefresh}, apnsRefresh...)},
			note: "Payload = token_payload, present form, APNs"},
		{name: "control-token-refresh-fcm", controlType: "0x04 (device-token refresh)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-tr-fcm"),
				TimestampMS: tsBase + 900,
				Body:        append([]byte{framing.ControlTokenRefresh}, fcmRefresh...)},
			note: "Payload = token_payload, present form, FCM"},
		{name: "control-token-revoke", controlType: "0x04 (device-token refresh)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-revoke"),
				TimestampMS: tsBase + 1000,
				Body:        append([]byte{framing.ControlTokenRefresh}, revoke...)},
			note: "Payload = token_payload absent form (0x00) — revokes the stored peer token (spec §3.2.1)"},
		{name: "control-unknown-type", controlType: "0x7f (unknown)",
			env: framing.Envelope{Type: framing.TypeControl, MsgID: fixed16("framing/control-unknown"),
				TimestampMS: tsBase + 1100, Body: []byte{0x7F, 0x01, 0x02, 0x03}},
			note: "Unknown control types are ignored (forward compatibility), never errors (spec §5.5)"},
		{name: "hangup",
			env: framing.Envelope{Type: framing.TypeHangup, MsgID: fixed16("framing/hangup"),
				TimestampMS: tsBase + 1200, Body: []byte{}},
			note: "HANGUP body is empty: the authenticated end-of-session marker"},
		{name: "media-manifest",
			env: framing.Envelope{Type: framing.TypeMediaChunk, Flags: framing.FlagManifest,
				MsgID:       fixed16("framing/manifest-msg-id"),
				TimestampMS: tsBase + 1300, Body: manifestBody},
			note: "flags bit 1: MEDIA_CHUNK manifest; body = chunk_count(4) ‖ total_len(8) ‖ content_hash(32) ‖ mime_len(1) ‖ mime"},
		{name: "media-manifest-expiry",
			env: framing.Envelope{Type: framing.TypeMediaChunk,
				Flags:       framing.FlagManifest | framing.FlagExpiry,
				MsgID:       fixed16("framing/manifest-expiry"),
				TimestampMS: tsBase + 1400, ExpiryS: 120, Body: manifestBody},
			note: "flags 0x03: manifest with disappearing instruction — expiry applies to media identically (spec §5.1)"},
		{name: "media-chunk",
			env: framing.Envelope{Type: framing.TypeMediaChunk,
				MsgID:       fixed16("framing/chunk-msg-id"),
				TimestampMS: tsBase + 1500, Body: chunkBody},
			note: "flags bit 1 clear: chunk; body = manifest_msg_id(16) ‖ chunk_index(4, 0-based) ‖ chunk_data"},
		{name: "reaction-add",
			env: framing.Envelope{Type: framing.TypeReaction, MsgID: fixed16("framing/react-add"),
				TimestampMS: tsBase + 1800, Body: reactAddBody},
			note: "REACTION (v0.2.1, §5.8); flags must be 0 (a reaction inherits its referent's expiry, never carries its own); body = ref_msg_id(16) ‖ op(1)=0x01 add ‖ emoji_len(1)=0x04 ‖ emoji(👍)"},
		{name: "reaction-remove",
			env: framing.Envelope{Type: framing.TypeReaction, MsgID: fixed16("framing/react-remove"),
				TimestampMS: tsBase + 1810, Body: reactRemoveBody},
			note: "REACTION remove (op=0x00): clears the sender's reaction unconditionally; the carried emoji keeps the body shape uniform and is not compared (§5.8)"},
		{name: "reaction-emoji-multibyte",
			env: framing.Envelope{Type: framing.TypeReaction, MsgID: fixed16("framing/react-zwj"),
				TimestampMS: tsBase + 1820, Body: reactZWJBody},
			note: "REACTION whose emoji is a 20-byte ZWJ sequence spanning six code points; receivers never grapheme-segment (§5.5), only emoji_len byte-length and UTF-8 validity are checked"},
		{name: "reaction-emoji-1byte",
			env: framing.Envelope{Type: framing.TypeReaction, MsgID: fixed16("framing/react-1byte"),
				TimestampMS: tsBase + 1830, Body: react1Body},
			note: "REACTION at the emoji_len=1 boundary (a single ASCII byte); structurally valid — the sender-side single-grapheme rule is a compose-time rule, not receiver-validated (§5.8)"},
		{name: "reaction-emoji-64byte",
			env: framing.Envelope{Type: framing.TypeReaction, MsgID: fixed16("framing/react-64byte"),
				TimestampMS: tsBase + 1840, Body: react64Body},
			note: "REACTION at the emoji_len=64 upper boundary (16×👍 = 64 bytes)"},
		{name: "reply-to-text",
			env: framing.Envelope{Type: framing.TypeText, Flags: framing.FlagReplyTo,
				MsgID: fixed16("framing/reply-text"), TimestampMS: tsBase + 1850,
				ReplyTo: replyRef, Body: []byte("quoting you")},
			text: "quoting you",
			note: "flags bit 2 (v0.2.1): reply_to(16) present at offset 27 (no expiry); the wire carries only the referenced msg_id — no quoted content (§5.8)"},
		{name: "reply-to-manifest",
			env: framing.Envelope{Type: framing.TypeMediaChunk,
				Flags: framing.FlagManifest | framing.FlagReplyTo,
				MsgID: fixed16("framing/reply-manifest"), TimestampMS: tsBase + 1860,
				ReplyTo: replyRef, Body: manifestBody},
			note: "reply_to legal on a MEDIA_CHUNK manifest (flags 0x06): marks the attachment as sent-in-reply; chunks never carry it (§5.8)"},
		{name: "reply-to-and-expiry",
			env: framing.Envelope{Type: framing.TypeText,
				Flags: framing.FlagExpiry | framing.FlagReplyTo,
				MsgID: fixed16("framing/reply-expiry"), TimestampMS: tsBase + 1870,
				ExpiryS: 30, ReplyTo: replyRef, Body: []byte("vanishing reply")},
			text: "vanishing reply",
			note: "flags 0x05: expiry_s and reply_to compose freely in flag-bit order — expiry_s(4) at offset 27, reply_to(16) at offset 31, body at offset 47 (§5.5, §5.8)"},
	}
	for _, s := range valid {
		e, _, err := envJSON(s.env, s.text, s.acked, s.controlType, "")
		if err != nil {
			return fmt.Errorf("envelope case %s: %w", s.name, err)
		}
		file.Envelopes = append(file.Envelopes, framingEnvelopeCaseJSON{
			Name: s.name, Valid: true, Envelope: &e, Encoded: e.Encoded, Note: s.note,
		})
	}

	// Invalid encodings: decoders must reject each of these.
	base, _, err := envJSON(framing.Envelope{Type: framing.TypeText,
		MsgID: fixed16("framing/invalid-base"), TimestampMS: tsBase + 1600,
		Body: []byte("x")}, "x", "", "", "")
	if err != nil {
		return err
	}
	mutate := func(f func([]byte)) string {
		b := mustHexBytes(base.Encoded)
		f(b)
		return hexs(b)
	}
	ackGood, _, err := envJSON(framing.Envelope{Type: framing.TypeAck,
		MsgID: fixed16("framing/invalid-ack"), TimestampMS: tsBase + 1700,
		Body: acked[:]}, "", hexs(acked[:]), "", "")
	if err != nil {
		return err
	}

	// Hand-built frame with an arbitrary type/flags and a raw (possibly
	// malformed) trailer — the header is well-formed so decoding reaches the
	// structural body/flag checks under test.
	invalidMsgID := fixed16("framing/invalid-v021")
	rawFrame := func(typ, flags byte, trailer []byte) []byte {
		out := []byte{framing.Ver, typ, flags}
		out = append(out, invalidMsgID[:]...)
		out = binary.BigEndian.AppendUint64(out, tsBase+1900)
		return append(out, trailer...)
	}
	// A 16-byte reply_to present on a type that may not carry it: the frame
	// is long enough to parse the field, so the type/flag predicate (not
	// truncation) is what rejects it.
	replyToTrailer := func(body []byte) []byte {
		return append(append([]byte{}, replyRef[:]...), body...)
	}

	invalid := []struct{ name, encoded, reason string }{
		{"bad-version", mutate(func(b []byte) { b[0] = 0x02 }),
			"ver must be 0x01"},
		{"unknown-type", mutate(func(b []byte) { b[1] = 0x07 }),
			"type 0x07 does not exist (0x06 is REACTION as of spec v0.2.1)"},
		{"reserved-flag-set", mutate(func(b []byte) { b[2] = 0x08 }),
			"reserved flag bits (bit 3 and up) must be 0"},
		{"manifest-flag-on-text", mutate(func(b []byte) { b[2] = framing.FlagManifest }),
			"flags bit 1 is only valid on MEDIA_CHUNK"},
		{"expiry-flag-on-ack", func() string {
			// Hand-built: a structurally complete ACK frame with flags bit 0
			// set and an expiry_s field present — must fail the flag rule.
			b := mustHexBytes(ackGood.Encoded)
			out := append([]byte{}, b[:2]...)         // ver, type
			out = append(out, framing.FlagExpiry)     // flags
			out = append(out, b[3:27]...)             // msg_id, timestamp
			out = append(out, 0x00, 0x00, 0x00, 0x1e) // expiry_s = 30
			out = append(out, b[27:]...)              // 16-byte body
			return hexs(out)
		}(), "flags bit 0 (expiry) is only valid on TEXT and MEDIA_CHUNK manifest"},
		{"truncated-header", base.Encoded[:2*20],
			"shorter than the 27-byte minimum header"},
		{"expiry-flag-but-truncated", mutate(func(b []byte) { b[2] = framing.FlagExpiry })[:2*27],
			"flags bit 0 set but the frame ends before expiry_s"},
		{"ack-body-wrong-length", ackGood.Encoded[:len(ackGood.Encoded)-2],
			"ACK body must be exactly 16 bytes"},
		{"hangup-with-body", mutate(func(b []byte) { b[1] = framing.TypeHangup }),
			"HANGUP body must be empty"},
		{"control-empty-body", func() string {
			b := mustHexBytes(base.Encoded)
			b[1] = framing.TypeControl
			return hexs(b[:27])
		}(), "CONTROL body must carry at least control_type"},
		// REACTION structural violations (§5.8): deterministic byte-level
		// malformation is a protocol error, distinct from the state-dependent
		// silent-drop of a well-formed reaction with an unknown referent.
		{"reaction-emoji-len-zero", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append([]byte{}, reactRef[:]...), framing.ReactionAdd, 0x00))),
			"emoji_len must be 1–64; 0 is out of range (body ref_msg_id(16) ‖ op ‖ emoji_len=0, no emoji)"},
		{"reaction-emoji-len-65", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append(append([]byte{}, reactRef[:]...), framing.ReactionAdd, 0x41), make([]byte, 65)...))),
			"emoji_len must be 1–64; 65 is out of range"},
		{"reaction-emoji-len-mismatch", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append(append([]byte{}, reactRef[:]...), framing.ReactionAdd, 0x05), []byte("ab")...))),
			"emoji_len (5) must equal the remaining body length (2)"},
		{"reaction-bad-op", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append(append([]byte{}, reactRef[:]...), 0x02, 0x04), []byte("👍")...))),
			"op must be 0x00 (remove) or 0x01 (add); 0x02 is undefined"},
		{"reaction-invalid-utf8", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append(append([]byte{}, reactRef[:]...), framing.ReactionAdd, 0x02), 0xff, 0xfe))),
			"emoji must be valid UTF-8; 0xff 0xfe is not"},
		{"reaction-truncated-body", hexs(rawFrame(framing.TypeReaction, 0x00,
			append(append([]byte{}, reactRef[:8]...), framing.ReactionAdd))),
			"REACTION body shorter than the 18-byte minimum (ref_msg_id ‖ op ‖ emoji_len)"},
		{"reaction-with-expiry-flag", hexs(rawFrame(framing.TypeReaction, framing.FlagExpiry,
			append([]byte{0x00, 0x00, 0x00, 0x1e}, reactAddBody...))),
			"a REACTION carries no flags — expiry (bit 0) is illegal; a reaction inherits its referent's expiry (§5.8)"},
		// reply_to (bit 2) present on a type that may not carry it: the field
		// is fully present (16 bytes), so the flag/type predicate rejects it.
		{"reply-to-on-ack", hexs(rawFrame(framing.TypeAck, framing.FlagReplyTo,
			replyToTrailer(acked[:]))),
			"reply_to flag only valid on TEXT and MEDIA_CHUNK manifest, not ACK"},
		{"reply-to-on-control", hexs(rawFrame(framing.TypeControl, framing.FlagReplyTo,
			replyToTrailer([]byte{framing.ControlTyping}))),
			"reply_to flag only valid on TEXT and MEDIA_CHUNK manifest, not CONTROL"},
		{"reply-to-on-hangup", hexs(rawFrame(framing.TypeHangup, framing.FlagReplyTo,
			replyToTrailer(nil))),
			"reply_to flag only valid on TEXT and MEDIA_CHUNK manifest, not HANGUP"},
		{"reply-to-on-reaction", hexs(rawFrame(framing.TypeReaction, framing.FlagReplyTo,
			replyToTrailer(reactAddBody))),
			"reply_to flag only valid on TEXT and MEDIA_CHUNK manifest, not REACTION"},
		{"reply-to-truncated", hexs(rawFrame(framing.TypeText, framing.FlagReplyTo,
			replyRef[:8])),
			"flags bit 2 set but the frame ends before the 16-byte reply_to"},
	}
	for _, s := range invalid {
		if _, err := framing.Decode(mustHexBytes(s.encoded)); err == nil {
			return fmt.Errorf("invalid case %s unexpectedly decodes", s.name)
		}
		file.Envelopes = append(file.Envelopes, framingEnvelopeCaseJSON{
			Name: s.name, Valid: false, Reason: s.reason, Encoded: s.encoded,
		})
	}
	return nil
}

func addMediaTransfers(file *framingFileJSON) error {
	build := func(name, mime, note string, content []byte, manifestMsgIDLabel string, expiry *uint32, tsOffset uint64) error {
		manifestMsgID := fixed16(manifestMsgIDLabel)
		chunkCount := uint32((uint64(len(content)) + framing.ChunkPlaintextSize - 1) / framing.ChunkPlaintextSize)
		m := framing.Manifest{
			ChunkCount:  chunkCount,
			TotalLen:    uint64(len(content)),
			ContentHash: sha256.Sum256(content),
			Mime:        mime,
		}
		mBody, err := framing.EncodeManifest(m)
		if err != nil {
			return err
		}
		mEnv := framing.Envelope{
			Type: framing.TypeMediaChunk, Flags: framing.FlagManifest,
			MsgID: manifestMsgID, TimestampMS: tsBase + tsOffset, Body: mBody,
		}
		if expiry != nil {
			mEnv.Flags |= framing.FlagExpiry
			mEnv.ExpiryS = *expiry
		}
		mEnvJSON, _, err := envJSON(mEnv, "", "", "", "")
		if err != nil {
			return err
		}
		transfer := mediaTransferJSON{
			Name:               name,
			Content:            hexs(content),
			ContentLen:         uint64(len(content)),
			ContentSHA256:      hexs(m.ContentHash[:]),
			Mime:               mime,
			ChunkPlaintextSize: framing.ChunkPlaintextSize,
			ChunkCount:         chunkCount,
			Manifest: manifestJSON{
				ChunkCount:  m.ChunkCount,
				TotalLen:    m.TotalLen,
				ContentHash: hexs(m.ContentHash[:]),
				MimeLen:     len(mime),
				Mime:        mime,
				EncodedBody: hexs(mBody),
			},
			ManifestEnvelope: mEnvJSON,
			Note:             note,
		}
		var chunks []framing.Chunk
		for i := uint32(0); i < chunkCount; i++ {
			lo := int(i) * framing.ChunkPlaintextSize
			hi := min(lo+framing.ChunkPlaintextSize, len(content))
			c := framing.Chunk{ManifestMsgID: manifestMsgID, ChunkIndex: i, Data: content[lo:hi]}
			chunks = append(chunks, c)
			cBody := framing.EncodeChunk(c)
			cEnv := framing.Envelope{
				Type:        framing.TypeMediaChunk,
				MsgID:       fixed16(fmt.Sprintf("%s/chunk-%d", manifestMsgIDLabel, i)),
				TimestampMS: tsBase + tsOffset + uint64(i+1),
				Body:        cBody,
			}
			cEnvJSON, _, err := envJSON(cEnv, "", "", "", "")
			if err != nil {
				return err
			}
			transfer.Chunks = append(transfer.Chunks, chunkJSON{
				ManifestMsgID: hexs(manifestMsgID[:]),
				ChunkIndex:    i,
				DataLen:       len(c.Data),
				Data:          hexs(c.Data),
				EncodedBody:   hexs(cBody),
			})
			transfer.ChunkEnvelopes = append(transfer.ChunkEnvelopes, cEnvJSON)
		}
		// Generator self-check: the transfer must reassemble and verify.
		back, err := framing.Reassemble(m, chunks)
		if err != nil {
			return fmt.Errorf("media transfer %s does not reassemble: %w", name, err)
		}
		if len(back) != len(content) {
			return fmt.Errorf("media transfer %s reassembled wrong length", name)
		}
		file.MediaTransfers = append(file.MediaTransfers, transfer)
		return nil
	}

	exp := uint32(300)
	if err := build(
		"single-chunk",
		"text/plain",
		"Smallest transfer: one chunk carries the whole attachment; the receiver "+
			"verifies SHA-256(content) == content_hash, then ACKs the manifest msg_id. "+
			"This manifest carries an expiry instruction (flags 0x03).",
		[]byte("nimna single-chunk attachment: reassemble me and check the hash"),
		"media/single", &exp, 2000,
	); err != nil {
		return err
	}
	if err := build(
		"two-chunks-boundary",
		"image/jpeg",
		"65537 bytes = 65536 + 1: chunk_count = ceil(total_len/65536) = 2; every "+
			"chunk except the last is exactly 65536 bytes, the last carries the single "+
			"remaining byte. Content is a fixed SHA-256 counter stream (see generator).",
		stream("media/two-chunks-content", framing.ChunkPlaintextSize+1),
		"media/two-chunks", nil, 3000,
	); err != nil {
		return err
	}
	return nil
}

func addTokenPayloads(file *framingFileJSON) error {
	apns := fixed32("framing/knock-apns-token")
	fcm := []byte("nimna-testvec-fcm-registration-token-0004")
	absent, err := framing.EncodeTokenPayload(framing.TokenPayload{})
	if err != nil {
		return err
	}
	presentAPNs, err := framing.EncodeTokenPayload(framing.TokenPayload{
		Present: true, Platform: framing.PlatformAPNs, Token: apns,
	})
	if err != nil {
		return err
	}
	presentFCM, err := framing.EncodeTokenPayload(framing.TokenPayload{
		Present: true, Platform: framing.PlatformFCM, Token: fcm,
	})
	if err != nil {
		return err
	}
	knockForm, err := framing.EncodeKnockToken(framing.PlatformAPNs, apns)
	if err != nil {
		return err
	}
	file.TokenPayloads = []tokenPayloadCaseJSON{
		{Name: "absent-or-revoke", Form: "absent", Encoded: hexs(absent),
			Note: "One byte 0x00. In M2/M3 it means push off; in CONTROL token-refresh it revokes (spec §5.7)."},
		{Name: "present-apns", Form: "present", Platform: "0x01 (APNs)",
			Token: hexs(apns), Encoded: hexs(presentAPNs),
			Note: "0x01 ‖ platform(1) ‖ token_len(2, big-endian) ‖ token."},
		{Name: "present-fcm", Form: "present", Platform: "0x02 (FCM)",
			Token: hexs(fcm), Encoded: hexs(presentFCM),
			Note: "FCM registration tokens are opaque ASCII; carried verbatim."},
		{Name: "knock-relay-plane", Form: "knock (prefix-less)", Platform: "0x01 (APNs)",
			Token: hexs(apns), Encoded: hexs(knockForm),
			Note: "The relay-plane KNOCK payload carries platform ‖ token_len ‖ token without " +
				"the presence byte; presence is signaled by a non-empty payload (spec §5.4)."},
	}
	return nil
}

func addOuterFrames(file *framingFileJSON) {
	topic := fixed16("framing/outer-topic")
	crid := fixed16("framing/outer-crid")
	knockToken, _ := framing.EncodeKnockToken(framing.PlatformAPNs, fixed32("framing/knock-apns-token"))
	pairPayload := stream("framing/outer-pair-data", 80)
	sessionPayload := stream("framing/outer-session-data", 44)

	add := func(name string, frameType byte, typeName, dir string, rid [16]byte, ridKind string, payload []byte, note string) {
		file.OuterFrames = append(file.OuterFrames, outerFrameCaseJSON{
			Name:        name,
			FrameType:   typeName,
			Direction:   dir,
			RoutingID:   hexs(rid[:]),
			RoutingKind: ridKind,
			Payload:     hexs(payload),
			Encoded:     hexs(framing.OuterFrame(frameType, rid, payload)),
			Note:        note,
		})
	}
	add("register-topic", framing.FrameRegisterTopic, "0x01 REGISTER_TOPIC", "client->relay",
		topic, "topic", nil, "Registers rendezvous interest; payload empty.")
	add("register-crid", framing.FrameRegisterCRID, "0x02 REGISTER_CRID", "client->relay",
		crid, "CRID", nil, "One frame per CRID; payload empty.")
	add("knock-no-push", framing.FrameKnock, "0x03 KNOCK", "client->relay",
		crid, "CRID", nil, "Empty payload: no push token, online/grace-window delivery only.")
	add("knock-with-token", framing.FrameKnock, "0x03 KNOCK", "client->relay",
		crid, "CRID", knockToken,
		"Payload = platform ‖ token_len ‖ token (the peer's push token, prefix-less form, spec §5.4); used once, then discarded by the relay.")
	add("accept", framing.FrameAccept, "0x04 ACCEPT", "client->relay",
		crid, "CRID", nil, "Payload empty.")
	add("teardown", framing.FrameTeardown, "0x05 TEARDOWN", "both directions",
		crid, "CRID", nil, "Client->relay: tear down my bridge. Relay->client: your bridge is gone. Disconnection is an implicit TEARDOWN.")
	add("topic-bridged", framing.FrameTopicBridged, "0x10 TOPIC_BRIDGED", "relay->client",
		topic, "topic", nil, "Sent to both ends when a topic's second registrant arrives; the joiner then sends M1.")
	add("knock-fwd", framing.FrameKnockFwd, "0x11 KNOCK_FWD", "relay->client",
		crid, "CRID", nil, "Forwarded knock — the relay strips any token before forwarding; payload always empty.")
	add("session-bridged", framing.FrameSessionBridged, "0x12 SESSION_BRIDGED", "relay->client",
		crid, "CRID", nil, "Sent to both ends on ACCEPT; the knocker then sends S1.")
	add("pair-data", framing.FramePairData, "0x20 PAIR_DATA", "both directions (forwarded verbatim)",
		topic, "topic", pairPayload,
		"Opaque pairing-handshake bytes; this sample payload is an arbitrary fixed 80-byte string, real M1–M4 bytes live in pairing-handshake.json.")
	add("session-data", framing.FrameSessionData, "0x21 SESSION_DATA", "both directions (forwarded verbatim)",
		crid, "CRID", sessionPayload,
		"Opaque S1/S2 or transport ciphertext; this sample payload is an arbitrary fixed 44-byte string, real frames live in session-handshake.json.")
}

func mustHexBytes(s string) []byte {
	b := make([]byte, len(s)/2)
	for i := 0; i < len(b); i++ {
		hi := hexNibble(s[2*i])
		lo := hexNibble(s[2*i+1])
		b[i] = hi<<4 | lo
	}
	return b
}

func hexNibble(c byte) byte {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10
	}
	panic("bad hex")
}
