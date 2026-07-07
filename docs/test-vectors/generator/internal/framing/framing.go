// Package framing implements the exact wire layouts of spec v0.2.1 §5.4–§5.8:
// the 18-byte relay-visible outer frame, the encrypted inner envelope
// (including MEDIA_CHUNK manifest/chunk bodies per §5.1, and REACTION and
// reply_to per §5.8), and token_payload. All integers are big-endian;
// layouts are fixed and hand-specified — no serialization library.
package framing

import (
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"unicode/utf8"
)

// Protocol version byte (outer frame and inner envelope).
const Ver = 0x01

// Outer frame types (spec §5.4).
const (
	FrameRegisterTopic  = 0x01
	FrameRegisterCRID   = 0x02
	FrameKnock          = 0x03
	FrameAccept         = 0x04
	FrameTeardown       = 0x05
	FrameTopicBridged   = 0x10
	FrameKnockFwd       = 0x11
	FrameSessionBridged = 0x12
	FramePairData       = 0x20
	FrameSessionData    = 0x21
)

// OuterHeaderLen is the fixed outer-frame header size; the header is also
// the AEAD ad for transport frames (§3.3.1).
const OuterHeaderLen = 18

// OuterHeader builds the 18-byte header ver ‖ frame_type ‖ routing_id.
func OuterHeader(frameType byte, routingID [16]byte) []byte {
	h := make([]byte, 0, OuterHeaderLen)
	h = append(h, Ver, frameType)
	h = append(h, routingID[:]...)
	return h
}

// OuterFrame builds a complete relay-visible frame.
func OuterFrame(frameType byte, routingID [16]byte, payload []byte) []byte {
	return append(OuterHeader(frameType, routingID), payload...)
}

// Inner envelope types (spec §5.5).
const (
	TypeText       = 0x01
	TypeAck        = 0x02
	TypeControl    = 0x03
	TypeHangup     = 0x04
	TypeMediaChunk = 0x05
	TypeReaction   = 0x06 // v0.2.1, §5.8
)

// Envelope flags (spec §5.5).
const (
	FlagExpiry   = 0x01 // bit 0: expiry_s present (TEXT and MEDIA_CHUNK manifest only)
	FlagManifest = 0x02 // bit 1: MEDIA_CHUNK manifest (MEDIA_CHUNK only)
	FlagReplyTo  = 0x04 // bit 2 (v0.2.1): reply_to present (TEXT and MEDIA_CHUNK manifest only)
)

// REACTION op values (spec §5.8).
const (
	ReactionRemove = 0x00
	ReactionAdd    = 0x01
)

// CONTROL body control_type values (spec §5.5).
const (
	ControlTyping       = 0x01
	ControlReadReceipt  = 0x02
	ControlScreenshot   = 0x03
	ControlTokenRefresh = 0x04
)

// token_payload platform values (spec §5.7).
const (
	PlatformAPNs = 0x01
	PlatformFCM  = 0x02
)

// Envelope is the decoded inner envelope. ExpiryS is meaningful only when
// Flags&FlagExpiry is set; ReplyTo only when Flags&FlagReplyTo is set.
type Envelope struct {
	Type        byte
	Flags       byte
	MsgID       [16]byte
	TimestampMS uint64
	ExpiryS     uint32
	ReplyTo     [16]byte
	Body        []byte
}

const headerLenNoExpiry = 27 // ver(1) type(1) flags(1) msg_id(16) timestamp(8)
const expiryLen = 4          // expiry_s (present only if flags bit 0)
const replyToLen = 16        // reply_to (present only if flags bit 2)

// Encode serializes an envelope, validating the spec's structural rules.
// Optional header fields appear in flag-bit order (§5.5): expiry_s (bit 0)
// then reply_to (bit 2), so reply_to follows expiry_s when both are present.
func Encode(e Envelope) ([]byte, error) {
	if err := validate(e); err != nil {
		return nil, err
	}
	n := headerLenNoExpiry
	if e.Flags&FlagExpiry != 0 {
		n += expiryLen
	}
	if e.Flags&FlagReplyTo != 0 {
		n += replyToLen
	}
	out := make([]byte, 0, n+len(e.Body))
	out = append(out, Ver, e.Type, e.Flags)
	out = append(out, e.MsgID[:]...)
	out = binary.BigEndian.AppendUint64(out, e.TimestampMS)
	if e.Flags&FlagExpiry != 0 {
		out = binary.BigEndian.AppendUint32(out, e.ExpiryS)
	}
	if e.Flags&FlagReplyTo != 0 {
		out = append(out, e.ReplyTo[:]...)
	}
	return append(out, e.Body...), nil
}

// Decode parses and validates an inner envelope.
func Decode(b []byte) (Envelope, error) {
	var e Envelope
	if len(b) < headerLenNoExpiry {
		return e, errors.New("envelope: too short")
	}
	if b[0] != Ver {
		return e, errors.New("envelope: unknown version")
	}
	e.Type = b[1]
	e.Flags = b[2]
	copy(e.MsgID[:], b[3:19])
	e.TimestampMS = binary.BigEndian.Uint64(b[19:27])
	off := headerLenNoExpiry
	if e.Flags&FlagExpiry != 0 {
		if len(b) < off+expiryLen {
			return Envelope{}, errors.New("envelope: expiry flag set but expiry_s missing")
		}
		e.ExpiryS = binary.BigEndian.Uint32(b[off : off+expiryLen])
		off += expiryLen
	}
	if e.Flags&FlagReplyTo != 0 {
		if len(b) < off+replyToLen {
			return Envelope{}, errors.New("envelope: reply_to flag set but reply_to missing")
		}
		copy(e.ReplyTo[:], b[off:off+replyToLen])
		off += replyToLen
	}
	e.Body = append([]byte{}, b[off:]...)
	if err := validate(e); err != nil {
		return Envelope{}, err
	}
	return e, nil
}

// validate enforces the structural rules of §5.5 (and §5.1 for MEDIA_CHUNK
// bodies). Content-level rules (TEXT soft cap, chunk-size discipline across
// a transfer, hash verification) are client behavior, not frame structure.
func validate(e Envelope) error {
	switch e.Type {
	case TypeText, TypeAck, TypeControl, TypeHangup, TypeMediaChunk, TypeReaction:
	default:
		return errors.New("envelope: unknown type")
	}
	if e.Flags&^(FlagExpiry|FlagManifest|FlagReplyTo) != 0 {
		return errors.New("envelope: reserved flag bits must be 0")
	}
	if e.Flags&FlagManifest != 0 && e.Type != TypeMediaChunk {
		return errors.New("envelope: manifest flag only valid on MEDIA_CHUNK")
	}
	// expiry_s (bit 0) and reply_to (bit 2) share one predicate: legal only
	// on TEXT or a MEDIA_CHUNK manifest (§5.5, §5.8). This rejects both flags
	// on ACK/CONTROL/HANGUP/REACTION and on a non-manifest MEDIA_CHUNK chunk —
	// and enforces that a REACTION carries no flags at all.
	optionalHeaderOK := e.Type == TypeText ||
		(e.Type == TypeMediaChunk && e.Flags&FlagManifest != 0)
	if e.Flags&FlagExpiry != 0 && !optionalHeaderOK {
		return errors.New("envelope: expiry flag only valid on TEXT and MEDIA_CHUNK manifest")
	}
	if e.Flags&FlagReplyTo != 0 && !optionalHeaderOK {
		return errors.New("envelope: reply_to flag only valid on TEXT and MEDIA_CHUNK manifest")
	}
	switch e.Type {
	case TypeAck:
		if len(e.Body) != 16 {
			return errors.New("envelope: ACK body must be acked_msg_id (16 bytes)")
		}
	case TypeControl:
		return validateControl(e.Body)
	case TypeHangup:
		if len(e.Body) != 0 {
			return errors.New("envelope: HANGUP body must be empty")
		}
	case TypeMediaChunk:
		if e.Flags&FlagManifest != 0 {
			_, err := ParseManifest(e.Body)
			return err
		}
		_, err := ParseChunk(e.Body)
		return err
	case TypeReaction:
		_, err := ParseReaction(e.Body)
		return err
	}
	return nil
}

func validateControl(body []byte) error {
	if len(body) < 1 {
		return errors.New("envelope: CONTROL body must carry control_type")
	}
	payload := body[1:]
	switch body[0] {
	case ControlTyping, ControlScreenshot:
		if len(payload) != 0 {
			return errors.New("envelope: CONTROL payload must be empty for this control_type")
		}
	case ControlReadReceipt:
		if len(payload) != 16 {
			return errors.New("envelope: read-receipt payload must be msg_id (16 bytes)")
		}
	case ControlTokenRefresh:
		_, err := ParseTokenPayload(payload)
		return err
	default:
		// Unknown control types are ignored, never errors (§5.5).
	}
	return nil
}

// Reaction is a REACTION body (spec §5.8):
// ref_msg_id(16) ‖ op(1) ‖ emoji_len(1) ‖ emoji(emoji_len). Emoji is 1–64
// bytes of valid UTF-8; emoji_len is its exact byte length.
type Reaction struct {
	RefMsgID [16]byte
	Op       byte // ReactionAdd (0x01) or ReactionRemove (0x00)
	Emoji    []byte
}

const reactionMinBody = 18 // ref_msg_id(16) ‖ op(1) ‖ emoji_len(1)

// EncodeReaction serializes a REACTION body, validating the §5.8 rules.
func EncodeReaction(r Reaction) ([]byte, error) {
	if err := validateReactionFields(r.Op, r.Emoji); err != nil {
		return nil, err
	}
	out := make([]byte, 0, reactionMinBody+len(r.Emoji))
	out = append(out, r.RefMsgID[:]...)
	out = append(out, r.Op, byte(len(r.Emoji)))
	return append(out, r.Emoji...), nil
}

// ParseReaction parses and structurally validates a REACTION body. Per §5.8
// these are deterministic byte-level checks; the sender-side single-grapheme
// rule is not receiver-validated — receivers never grapheme-segment (§5.5),
// only UTF-8 validity is checked.
func ParseReaction(b []byte) (Reaction, error) {
	var r Reaction
	if len(b) < reactionMinBody {
		return r, errors.New("reaction: body too short")
	}
	copy(r.RefMsgID[:], b[0:16])
	r.Op = b[16]
	emojiLen := int(b[17])
	if len(b) != reactionMinBody+emojiLen {
		return r, errors.New("reaction: emoji_len does not match remaining body length")
	}
	r.Emoji = append([]byte{}, b[reactionMinBody:]...)
	if err := validateReactionFields(r.Op, r.Emoji); err != nil {
		return Reaction{}, err
	}
	return r, nil
}

func validateReactionFields(op byte, emoji []byte) error {
	if op != ReactionAdd && op != ReactionRemove {
		return errors.New("reaction: op must be 0x00 (remove) or 0x01 (add)")
	}
	if len(emoji) < 1 || len(emoji) > 64 {
		return errors.New("reaction: emoji_len must be 1–64 bytes")
	}
	if !utf8.Valid(emoji) {
		return errors.New("reaction: emoji must be valid UTF-8")
	}
	return nil
}

// Manifest is a MEDIA_CHUNK manifest body (spec §5.1).
type Manifest struct {
	ChunkCount  uint32
	TotalLen    uint64
	ContentHash [32]byte
	Mime        string
}

// ChunkPlaintextSize is the fixed chunk plaintext size for every chunk
// except the last (spec §5.1).
const ChunkPlaintextSize = 65536

// EncodeManifest serializes a manifest body:
// chunk_count(4) ‖ total_len(8) ‖ content_hash(32) ‖ mime_len(1) ‖ mime.
func EncodeManifest(m Manifest) ([]byte, error) {
	if len(m.Mime) > 255 {
		return nil, errors.New("manifest: mime too long")
	}
	out := make([]byte, 0, 45+len(m.Mime))
	out = binary.BigEndian.AppendUint32(out, m.ChunkCount)
	out = binary.BigEndian.AppendUint64(out, m.TotalLen)
	out = append(out, m.ContentHash[:]...)
	out = append(out, byte(len(m.Mime)))
	return append(out, m.Mime...), nil
}

// ParseManifest parses and structurally validates a manifest body.
func ParseManifest(b []byte) (Manifest, error) {
	var m Manifest
	if len(b) < 45 {
		return m, errors.New("manifest: too short")
	}
	m.ChunkCount = binary.BigEndian.Uint32(b[0:4])
	m.TotalLen = binary.BigEndian.Uint64(b[4:12])
	copy(m.ContentHash[:], b[12:44])
	mimeLen := int(b[44])
	if len(b) != 45+mimeLen {
		return m, errors.New("manifest: mime_len does not match body length")
	}
	m.Mime = string(b[45:])
	return m, nil
}

// Chunk is a MEDIA_CHUNK chunk body (spec §5.1).
type Chunk struct {
	ManifestMsgID [16]byte
	ChunkIndex    uint32
	Data          []byte
}

// EncodeChunk serializes a chunk body:
// manifest_msg_id(16) ‖ chunk_index(4, 0-based) ‖ chunk_data.
func EncodeChunk(c Chunk) []byte {
	out := make([]byte, 0, 20+len(c.Data))
	out = append(out, c.ManifestMsgID[:]...)
	out = binary.BigEndian.AppendUint32(out, c.ChunkIndex)
	return append(out, c.Data...)
}

// ParseChunk parses a chunk body.
func ParseChunk(b []byte) (Chunk, error) {
	var c Chunk
	if len(b) < 20 {
		return c, errors.New("chunk: too short")
	}
	copy(c.ManifestMsgID[:], b[0:16])
	c.ChunkIndex = binary.BigEndian.Uint32(b[16:20])
	c.Data = append([]byte{}, b[20:]...)
	return c, nil
}

// Reassemble verifies a full transfer per §5.1: ordered chunks, fixed chunk
// size for all but the last, chunk_count = ceil(total_len/65536), and
// SHA-256(content) == content_hash. It returns the reassembled content.
func Reassemble(m Manifest, chunks []Chunk) ([]byte, error) {
	want := (m.TotalLen + ChunkPlaintextSize - 1) / ChunkPlaintextSize
	if uint64(m.ChunkCount) != want {
		return nil, errors.New("reassemble: chunk_count != ceil(total_len/65536)")
	}
	if uint64(len(chunks)) != want {
		return nil, errors.New("reassemble: wrong number of chunks")
	}
	content := make([]byte, 0, m.TotalLen)
	for i, c := range chunks {
		if c.ChunkIndex != uint32(i) {
			return nil, errors.New("reassemble: chunk out of order")
		}
		last := i == len(chunks)-1
		if !last && len(c.Data) != ChunkPlaintextSize {
			return nil, errors.New("reassemble: non-final chunk must be 65536 bytes")
		}
		content = append(content, c.Data...)
	}
	if uint64(len(content)) != m.TotalLen {
		return nil, errors.New("reassemble: content length != total_len")
	}
	// Direct comparison is acceptable only in this generator (public test
	// data); production implementations should compare content hashes in
	// constant time (crypto/subtle.ConstantTimeCompare).
	if sha256.Sum256(content) != m.ContentHash {
		return nil, errors.New("reassemble: content hash mismatch")
	}
	return content, nil
}

// TokenPayload is the E2E token_payload (spec §5.7).
type TokenPayload struct {
	Present  bool
	Platform byte // PlatformAPNs or PlatformFCM (when present)
	Token    []byte
}

// EncodeTokenPayload serializes the E2E form: 0x00 for absent/revoke, or
// 0x01 ‖ platform(1) ‖ token_len(2) ‖ token.
func EncodeTokenPayload(t TokenPayload) ([]byte, error) {
	if !t.Present {
		return []byte{0x00}, nil
	}
	body, err := encodePlatformToken(t.Platform, t.Token)
	if err != nil {
		return nil, err
	}
	return append([]byte{0x01}, body...), nil
}

// ParseTokenPayload parses the E2E form.
func ParseTokenPayload(b []byte) (TokenPayload, error) {
	var t TokenPayload
	if len(b) < 1 {
		return t, errors.New("token_payload: empty")
	}
	switch b[0] {
	case 0x00:
		if len(b) != 1 {
			return t, errors.New("token_payload: absent form must be exactly one byte")
		}
		return t, nil
	case 0x01:
		platform, token, err := parsePlatformToken(b[1:])
		if err != nil {
			return t, err
		}
		return TokenPayload{Present: true, Platform: platform, Token: token}, nil
	default:
		return t, errors.New("token_payload: unknown presence byte")
	}
}

// EncodeKnockToken serializes the relay-plane KNOCK token form (§5.4):
// platform(1) ‖ token_len(2) ‖ token — no presence byte; presence is
// signaled by a non-empty KNOCK payload.
func EncodeKnockToken(platform byte, token []byte) ([]byte, error) {
	return encodePlatformToken(platform, token)
}

// ParseKnockToken parses the relay-plane KNOCK token form.
func ParseKnockToken(b []byte) (platform byte, token []byte, err error) {
	return parsePlatformToken(b)
}

func encodePlatformToken(platform byte, token []byte) ([]byte, error) {
	if platform != PlatformAPNs && platform != PlatformFCM {
		return nil, errors.New("token: unknown platform")
	}
	if len(token) > 0xFFFF {
		return nil, errors.New("token: too long")
	}
	out := make([]byte, 0, 3+len(token))
	out = append(out, platform)
	out = binary.BigEndian.AppendUint16(out, uint16(len(token)))
	return append(out, token...), nil
}

func parsePlatformToken(b []byte) (byte, []byte, error) {
	if len(b) < 3 {
		return 0, nil, errors.New("token: too short")
	}
	platform := b[0]
	if platform != PlatformAPNs && platform != PlatformFCM {
		return 0, nil, errors.New("token: unknown platform")
	}
	n := int(binary.BigEndian.Uint16(b[1:3]))
	if len(b) != 3+n {
		return 0, nil, errors.New("token: token_len does not match")
	}
	return platform, append([]byte{}, b[3:]...), nil
}
