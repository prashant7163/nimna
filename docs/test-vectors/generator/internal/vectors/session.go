package vectors

import (
	"bytes"
	"fmt"

	"nimna.app/test-vectors/generator/internal/framing"
	"nimna.app/test-vectors/generator/internal/noise"
)

// session-handshake.json — spec §3.3.1, §5.4–§5.6.

type sessionPartyJSON struct {
	Device        string `json:"device"`
	NoiseRole     string `json:"noise_role"`
	StaticPriv    string `json:"static_priv"`
	StaticPub     string `json:"static_pub"`
	EphemeralPriv string `json:"ephemeral_priv"`
	EphemeralPub  string `json:"ephemeral_pub"`
}

type sessionMsgJSON struct {
	Name               string `json:"name"`
	Direction          string `json:"direction"`
	NoiseTokens        string `json:"noise_tokens"`
	EphemeralPub       string `json:"ephemeral_pub"`
	TagOverEmptyPay    string `json:"tag_over_empty_payload"`
	SessionDataPayload string `json:"session_data_payload"`
	Size               int    `json:"size"`
	OuterFrame         string `json:"outer_frame"`
	ChainingKeyAfter   string `json:"chaining_key_after"`
	HandshakeHashAfter string `json:"handshake_hash_after"`
}

type envelopeJSON struct {
	Ver         string  `json:"ver"`
	Type        string  `json:"type"`
	Flags       string  `json:"flags"`
	MsgID       string  `json:"msg_id"`
	TimestampMS uint64  `json:"timestamp_ms"`
	ExpiryS     *uint32 `json:"expiry_s,omitempty"`
	Body        string  `json:"body"`
	Text        string  `json:"text,omitempty"`
	AckedMsgID  string  `json:"acked_msg_id,omitempty"`
	ControlType string  `json:"control_type,omitempty"`
	Note        string  `json:"note,omitempty"`
	Encoded     string  `json:"encoded"`
}

type transportFrameJSON struct {
	Seq                int          `json:"seq"`
	Direction          string       `json:"direction"`
	DirectionConst     string       `json:"direction_constant"`
	Counter            uint64       `json:"counter"`
	Nonce              string       `json:"nonce"`
	KeyBefore          string       `json:"key_before"`
	ADOuterHeader      string       `json:"ad_outer_header"`
	InnerEnvelope      envelopeJSON `json:"inner_envelope_plaintext"`
	SessionDataPayload string       `json:"session_data_payload"`
	OuterFrame         string       `json:"outer_frame"`
	KeyAfterRekey      string       `json:"key_after_rekey"`
}

type sessionTranscriptJSON struct {
	Name               string               `json:"name"`
	ChannelRef         string               `json:"channel_ref"`
	CRID               string               `json:"crid"`
	Initiator          sessionPartyJSON     `json:"initiator"`
	Responder          sessionPartyJSON     `json:"responder"`
	PreMessages        []string             `json:"pre_messages"`
	Prologue           string               `json:"prologue"`
	ChainingKeyInitial string               `json:"chaining_key_initial"`
	HashAfterPre       string               `json:"handshake_hash_after_pre_messages"`
	Messages           []sessionMsgJSON     `json:"messages"`
	HandshakeHashFinal string               `json:"handshake_hash_final"`
	Split              splitJSON            `json:"split"`
	TransportFrames    []transportFrameJSON `json:"transport_frames"`
}

type rekeyJSON struct {
	Function string `json:"function"`
	Applied  string `json:"applied"`
}

type forbiddenCounterJSON struct {
	Value string `json:"value"`
	Rule  string `json:"rule"`
}

type sessionFileJSON struct {
	Purpose          string                  `json:"_purpose"`
	Spec             string                  `json:"_spec"`
	ProtocolName     string                  `json:"protocol_name"`
	Notes            []string                `json:"notes"`
	NonceLayout      string                  `json:"transport_nonce_layout"`
	Rekey            rekeyJSON               `json:"rekey"`
	ForbiddenCounter forbiddenCounterJSON    `json:"forbidden_counter"`
	Transcripts      []sessionTranscriptJSON `json:"transcripts"`
}

// frameSpec describes one transport frame to generate.
type frameSpec struct {
	fromInitiator bool
	envelope      framing.Envelope
	text          string // set for TEXT (documents the UTF-8 string)
	acked         string
	controlType   string
	note          string
}

func genSessionHandshake(channels []channelInfo) (*sessionFileJSON, error) {
	file := &sessionFileJSON{
		Purpose: "Deterministic KK session-handshake transcripts (S1/S2) and " +
			"transport frames in both directions with per-frame keys before and " +
			"after the per-message rekey, exact nonces, and inner-envelope plaintexts.",
		Spec:         SpecRef + " §3.3.1, §5.4–§5.6",
		ProtocolName: noise.ProtocolName("KK"),
		Notes: []string{
			"The knocker is the Noise initiator (spec §3.3.1). Either side of the channel may knock; the two transcripts show both.",
			"Prologue is zero-length. Pre-messages are the two static public keys, initiator's first, per Noise pre-message rules.",
			"KK is not a psk pattern: 'e' tokens MixHash only (no MixKey of the ephemeral public key).",
			"chaining_key_initial is the 32-byte protocol name itself (Noise_KK_25519_ChaChaPoly_SHA256 is exactly HASHLEN bytes, used as h without hashing).",
			"Split: first key k_ir = initiator->responder (direction constant 0x00000000), second k_ri = responder->initiator (0x00000001).",
			"ad for every transport frame is the 18-byte outer header 01 ‖ 21 ‖ CRID (SESSION_DATA).",
			"Counters are per direction, starting at 0, strict increment; receivers enforce exact sequence and treat any deviation, AEAD failure, or malformed frame as a protocol error that kills the session (spec §3.3.1).",
		},
		NonceLayout: "12 bytes: direction (4, big-endian: 0x00000000 initiator->responder, 0x00000001 responder->initiator) ‖ counter (8, big-endian, from 0)",
		Rekey: rekeyJSON{
			Function: "k = first 32 bytes of ChaCha20-Poly1305-Encrypt(k, nonce = 0x00000000ffffffffffffffff, ad = empty, plaintext = 32 zero bytes) — Noise REKEY, spec §11.3",
			Applied:  "after every message: on encrypt (sender side) and on successful decrypt (receiver side); the old key is zeroized immediately",
		},
		ForbiddenCounter: forbiddenCounterJSON{
			Value: "0xffffffffffffffff",
			Rule: "Counter 2^64-1 is forbidden (reserved): its nonce would collide with the rekey nonce. " +
				"A frame carrying it is a protocol error (spec §3.3.1); unreachable in practice under §4 frame-rate limits.",
		},
	}

	if len(channels) != 2 {
		return nil, fmt.Errorf("session: expected 2 channels, got %d", len(channels))
	}

	// Transcript 1: on the tokens-present channel, the joiner (B) knocks.
	ch := channels[0]
	msgID1 := fixed16("session1/msg-id-1")
	msgID2 := fixed16("session1/msg-id-2")
	msgID3 := fixed16("session1/msg-id-3")
	msgID4 := fixed16("session1/msg-id-4")
	msgID5 := fixed16("session1/msg-id-5")
	text1 := "test message one"
	text2 := "disappearing message — café ☕ üñî"
	expiry := uint32(30)
	t1, err := sessionTranscript(sessionInputs{
		name:              "knocker-is-joiner",
		channelRef:        "statics from pairing-handshake.json transcript \"" + ch.pairTranscript + "\"; the joiner device (B) knocks",
		ch:                ch,
		initiatorIsJoiner: true,
		keyLabel:          "session1",
		frames: []frameSpec{
			{
				fromInitiator: true,
				envelope: framing.Envelope{
					Type: framing.TypeText, MsgID: msgID1,
					TimestampMS: tsBase + 1000, Body: []byte(text1),
				},
				text: text1,
				note: "TEXT without expiry; body is the raw UTF-8 bytes",
			},
			{
				fromInitiator: true,
				envelope: framing.Envelope{
					Type: framing.TypeText, Flags: framing.FlagExpiry, MsgID: msgID2,
					TimestampMS: tsBase + 2000, ExpiryS: expiry, Body: []byte(text2),
				},
				text: text2,
				note: "TEXT with expiry (flags bit 0; expiry_s inserted at offset 27, body shifts to 31); multi-byte UTF-8",
			},
			{
				fromInitiator: false,
				envelope: framing.Envelope{
					Type: framing.TypeAck, MsgID: msgID3,
					TimestampMS: tsBase + 3000, Body: msgID1[:],
				},
				acked: hexs(msgID1[:]),
				note:  "ACK of the first TEXT (acked_msg_id = its msg_id)",
			},
			{
				fromInitiator: false,
				envelope: framing.Envelope{
					Type: framing.TypeControl, MsgID: msgID4,
					TimestampMS: tsBase + 4000, Body: []byte{framing.ControlScreenshot},
				},
				controlType: "0x03 (screenshot notice, empty payload)",
				note:        "CONTROL screenshot notice (spec §5.2)",
			},
			{
				fromInitiator: true,
				envelope: framing.Envelope{
					Type: framing.TypeHangup, MsgID: msgID5,
					TimestampMS: tsBase + 5000, Body: []byte{},
				},
				note: "HANGUP: authenticated end-of-session, body empty; relay-plane TEARDOWN follows outside the encrypted channel",
			},
		},
	})
	if err != nil {
		return nil, err
	}

	// Transcript 2: on the tokens-absent channel, the creator (A) knocks.
	ch2 := channels[1]
	fcm := []byte("nimna-testvec-fcm-registration-token-0002")
	tokenRefresh, err := framing.EncodeTokenPayload(framing.TokenPayload{
		Present: true, Platform: framing.PlatformFCM, Token: fcm,
	})
	if err != nil {
		return nil, err
	}
	revoke, err := framing.EncodeTokenPayload(framing.TokenPayload{})
	if err != nil {
		return nil, err
	}
	mID1 := fixed16("session2/msg-id-1")
	mID2 := fixed16("session2/msg-id-2")
	mID3 := fixed16("session2/msg-id-3")
	t2, err := sessionTranscript(sessionInputs{
		name:              "knocker-is-creator",
		channelRef:        "statics from pairing-handshake.json transcript \"" + ch2.pairTranscript + "\"; the creator device (A) knocks",
		ch:                ch2,
		initiatorIsJoiner: false,
		keyLabel:          "session2",
		frames: []frameSpec{
			{
				fromInitiator: true,
				envelope: framing.Envelope{
					Type: framing.TypeControl, MsgID: mID1,
					TimestampMS: tsBase + 11000,
					Body:        append([]byte{framing.ControlTokenRefresh}, tokenRefresh...),
				},
				controlType: "0x04 (device-token refresh; token_payload present form, FCM)",
				note:        "CONTROL token refresh (spec §3.2.1, §5.5, §5.7)",
			},
			{
				fromInitiator: false,
				envelope: framing.Envelope{
					Type: framing.TypeControl, MsgID: mID2,
					TimestampMS: tsBase + 12000,
					Body:        append([]byte{framing.ControlTokenRefresh}, revoke...),
				},
				controlType: "0x04 (device-token refresh; absent form 0x00 = revoke)",
				note:        "CONTROL token revoke: push opt-out propagates unilaterally (spec §3.2.1)",
			},
			{
				fromInitiator: true,
				envelope: framing.Envelope{
					Type: framing.TypeControl, MsgID: mID3,
					TimestampMS: tsBase + 13000, Body: []byte{framing.ControlTyping},
				},
				controlType: "0x01 (typing, empty payload)",
				note:        "CONTROL typing indicator",
			},
		},
	})
	if err != nil {
		return nil, err
	}

	file.Transcripts = []sessionTranscriptJSON{*t1, *t2}
	return file, nil
}

type sessionInputs struct {
	name              string
	channelRef        string
	ch                channelInfo
	initiatorIsJoiner bool
	keyLabel          string
	frames            []frameSpec
}

func sessionTranscript(in sessionInputs) (*sessionTranscriptJSON, error) {
	fail := func(err error) (*sessionTranscriptJSON, error) {
		return nil, fmt.Errorf("session %s: %w", in.name, err)
	}

	iPriv, iPub := in.ch.joinerPriv, in.ch.joinerPub
	rPriv, rPub := in.ch.creatorPriv, in.ch.creatorPub
	iDevice, rDevice := "B (joiner at pairing)", "A (creator at pairing)"
	if !in.initiatorIsJoiner {
		iPriv, iPub, rPriv, rPub = rPriv, rPub, iPriv, iPub
		iDevice, rDevice = "A (creator at pairing)", "B (joiner at pairing)"
	}
	eIPriv := fixed32(in.keyLabel + "/initiator-ephemeral")
	eRPriv := fixed32(in.keyLabel + "/responder-ephemeral")
	eIPub, err := noise.PublicKey(eIPriv)
	if err != nil {
		return fail(err)
	}
	eRPub, err := noise.PublicKey(eRPriv)
	if err != nil {
		return fail(err)
	}

	ini, err := noise.NewHandshake(noise.Config{
		Pattern: "KK", Initiator: true, Prologue: nil,
		Static: iPriv, Ephemeral: eIPriv, RemoteStatic: rPub,
	})
	if err != nil {
		return fail(err)
	}
	rsp, err := noise.NewHandshake(noise.Config{
		Pattern: "KK", Initiator: false, Prologue: nil,
		Static: rPriv, Ephemeral: eRPriv, RemoteStatic: iPub,
	})
	if err != nil {
		return fail(err)
	}
	ckInitial := ini.ChainingKey()
	if !bytes.Equal(ckInitial, []byte(noise.ProtocolName("KK"))) {
		return fail(fmt.Errorf("KK chaining_key_initial must be the 32-byte protocol name"))
	}
	hashAfterPre := ini.HandshakeHash()
	if !bytes.Equal(hashAfterPre, rsp.HandshakeHash()) {
		return fail(fmt.Errorf("pre-message hash disagreement"))
	}

	step := func(w, r *noise.HandshakeState) ([]byte, error) {
		msg, _, err := w.WriteMessage(nil)
		if err != nil {
			return nil, err
		}
		pt, _, err := r.ReadMessage(msg)
		if err != nil {
			return nil, err
		}
		if len(pt) != 0 {
			return nil, fmt.Errorf("KK payloads must be zero-length")
		}
		if !bytes.Equal(w.ChainingKey(), r.ChainingKey()) || !bytes.Equal(w.HandshakeHash(), r.HandshakeHash()) {
			return nil, fmt.Errorf("state divergence between roles")
		}
		return msg, nil
	}

	s1, err := step(ini, rsp)
	if err != nil {
		return fail(err)
	}
	if len(s1) != 48 {
		return fail(fmt.Errorf("S1 must be 48 bytes, got %d", len(s1)))
	}
	s1JSON := sessionMsgJSON{
		Name: "S1", Direction: "knocker->accepter", NoiseTokens: "e, es, ss",
		EphemeralPub:       hexs(s1[:32]),
		TagOverEmptyPay:    hexs(s1[32:48]),
		SessionDataPayload: hexs(s1),
		Size:               len(s1),
		OuterFrame:         hexs(framing.OuterFrame(framing.FrameSessionData, in.ch.crid, s1)),
		ChainingKeyAfter:   hexs(ini.ChainingKey()),
		HandshakeHashAfter: hexs(ini.HandshakeHash()),
	}
	s2, err := step(rsp, ini)
	if err != nil {
		return fail(err)
	}
	if len(s2) != 48 {
		return fail(fmt.Errorf("S2 must be 48 bytes, got %d", len(s2)))
	}
	s2JSON := sessionMsgJSON{
		Name: "S2", Direction: "accepter->knocker", NoiseTokens: "e, ee, se",
		EphemeralPub:       hexs(s2[:32]),
		TagOverEmptyPay:    hexs(s2[32:48]),
		SessionDataPayload: hexs(s2),
		Size:               len(s2),
		OuterFrame:         hexs(framing.OuterFrame(framing.FrameSessionData, in.ch.crid, s2)),
		ChainingKeyAfter:   hexs(rsp.ChainingKey()),
		HandshakeHashAfter: hexs(rsp.HandshakeHash()),
	}

	ik1, ik2, err := ini.Split()
	if err != nil {
		return fail(err)
	}
	rk1, rk2, err := rsp.Split()
	if err != nil {
		return fail(err)
	}
	if ik1 != rk1 || ik2 != rk2 {
		return fail(fmt.Errorf("split disagreement"))
	}

	// Transport phase. Four half-channels: sender and receiver state per
	// direction (receiver state verifies every frame opens correctly).
	ad := framing.OuterHeader(framing.FrameSessionData, in.ch.crid)
	sendIR := noise.NewTransport(ik1, noise.DirInitiatorToResponder)
	recvIR := noise.NewTransport(ik1, noise.DirInitiatorToResponder)
	sendRI := noise.NewTransport(ik2, noise.DirResponderToInitiator)
	recvRI := noise.NewTransport(ik2, noise.DirResponderToInitiator)

	var frames []transportFrameJSON
	for i, fs := range in.frames {
		plaintext, err := framing.Encode(fs.envelope)
		if err != nil {
			return fail(fmt.Errorf("frame %d: %w", i+1, err))
		}
		send, recv := sendIR, recvIR
		dirName, dirConst := "initiator->responder", "0x00000000"
		if !fs.fromInitiator {
			send, recv = sendRI, recvRI
			dirName, dirConst = "responder->initiator", "0x00000001"
		}
		rec := send.Seal(ad, plaintext)
		back, err := recv.Open(ad, rec.Ciphertext)
		if err != nil {
			return fail(fmt.Errorf("frame %d does not decrypt: %w", i+1, err))
		}
		if !bytes.Equal(back, plaintext) {
			return fail(fmt.Errorf("frame %d round-trip mismatch", i+1))
		}

		env := envelopeJSON{
			Ver:         "0x01",
			Type:        envelopeTypeName(fs.envelope.Type),
			Flags:       fmt.Sprintf("0x%02x", fs.envelope.Flags),
			MsgID:       hexs(fs.envelope.MsgID[:]),
			TimestampMS: fs.envelope.TimestampMS,
			Body:        hexs(fs.envelope.Body),
			Text:        fs.text,
			AckedMsgID:  fs.acked,
			ControlType: fs.controlType,
			Note:        fs.note,
			Encoded:     hexs(plaintext),
		}
		if fs.envelope.Flags&framing.FlagExpiry != 0 {
			e := fs.envelope.ExpiryS
			env.ExpiryS = &e
		}
		frames = append(frames, transportFrameJSON{
			Seq:                i + 1,
			Direction:          dirName,
			DirectionConst:     dirConst,
			Counter:            rec.Counter,
			Nonce:              hexs(rec.Nonce[:]),
			KeyBefore:          hexs(rec.KeyBefore[:]),
			ADOuterHeader:      hexs(ad),
			InnerEnvelope:      env,
			SessionDataPayload: hexs(rec.Ciphertext),
			OuterFrame:         hexs(framing.OuterFrame(framing.FrameSessionData, in.ch.crid, rec.Ciphertext)),
			KeyAfterRekey:      hexs(rec.KeyAfter[:]),
		})
	}

	return &sessionTranscriptJSON{
		Name:       in.name,
		ChannelRef: in.channelRef,
		CRID:       hexs(in.ch.crid[:]),
		Initiator: sessionPartyJSON{
			Device: iDevice, NoiseRole: "initiator (knocker)",
			StaticPriv: hexs(iPriv), StaticPub: hexs(iPub),
			EphemeralPriv: hexs(eIPriv), EphemeralPub: hexs(eIPub),
		},
		Responder: sessionPartyJSON{
			Device: rDevice, NoiseRole: "responder (accepter)",
			StaticPriv: hexs(rPriv), StaticPub: hexs(rPub),
			EphemeralPriv: hexs(eRPriv), EphemeralPub: hexs(eRPub),
		},
		PreMessages: []string{
			"initiator static public key (first, per Noise pre-message rules): " + hexs(iPub),
			"responder static public key: " + hexs(rPub),
		},
		Prologue:           "",
		ChainingKeyInitial: hexs(ckInitial),
		HashAfterPre:       hexs(hashAfterPre),
		Messages:           []sessionMsgJSON{s1JSON, s2JSON},
		HandshakeHashFinal: hexs(ini.HandshakeHash()),
		Split: splitJSON{
			KIR:     hexs(ik1[:]),
			KIRNote: "initiator(knocker)->responder(accepter); direction constant 0x00000000",
			KRI:     hexs(ik2[:]),
			KRINote: "responder(accepter)->initiator(knocker); direction constant 0x00000001",
		},
		TransportFrames: frames,
	}, nil
}

func envelopeTypeName(t byte) string {
	switch t {
	case framing.TypeText:
		return "0x01 (TEXT)"
	case framing.TypeAck:
		return "0x02 (ACK)"
	case framing.TypeControl:
		return "0x03 (CONTROL)"
	case framing.TypeHangup:
		return "0x04 (HANGUP)"
	case framing.TypeMediaChunk:
		return "0x05 (MEDIA_CHUNK)"
	}
	return fmt.Sprintf("0x%02x", t)
}
