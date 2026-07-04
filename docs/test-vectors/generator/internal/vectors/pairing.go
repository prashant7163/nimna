package vectors

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"math/big"

	"nimna.app/test-vectors/generator/internal/derive"
	"nimna.app/test-vectors/generator/internal/framing"
	"nimna.app/test-vectors/generator/internal/noise"
)

// pairing-handshake.json — spec §3.1.2–§3.1.5, §5.4, §5.6, §5.7.

type tokenPayloadJSON struct {
	Form     string `json:"form"`
	Platform string `json:"platform,omitempty"`
	Token    string `json:"token,omitempty"`
	Encoded  string `json:"encoded"`
}

type pairingPartyJSON struct {
	Device        string           `json:"device"`
	NoiseRole     string           `json:"noise_role"`
	StaticPriv    string           `json:"static_priv"`
	StaticPub     string           `json:"static_pub"`
	EphemeralPriv string           `json:"ephemeral_priv"`
	EphemeralPub  string           `json:"ephemeral_pub"`
	TokenPayload  tokenPayloadJSON `json:"token_payload"`
}

type rendezvousJSON struct {
	SaltPreimage string `json:"salt_preimage_ascii"`
	Salt         string `json:"salt"`
	Seed         string `json:"seed"`
	Topic        string `json:"topic"`
	PSK          string `json:"psk"`
}

type commitmentJSON struct {
	LabelASCII string `json:"label_ascii"`
	Preimage   string `json:"preimage"`
	M0         string `json:"m0"`
}

type pairingComponentsJSON struct {
	M0                    string `json:"m0,omitempty"`
	EphemeralPub          string `json:"ephemeral_pub,omitempty"`
	TagOverEmptyPayload   string `json:"tag_over_empty_payload,omitempty"`
	EncryptedStatic       string `json:"encrypted_static,omitempty"`
	EncryptedTokenPayload string `json:"encrypted_token_payload,omitempty"`
}

type pairingMsgJSON struct {
	Name               string                `json:"name"`
	Direction          string                `json:"direction"`
	NoiseTokens        string                `json:"noise_tokens"`
	PayloadPlaintext   string                `json:"payload_plaintext"`
	Components         pairingComponentsJSON `json:"components"`
	PairDataPayload    string                `json:"pair_data_payload"`
	Size               int                   `json:"size"`
	OuterFrame         string                `json:"outer_frame"`
	ChainingKeyAfter   string                `json:"chaining_key_after"`
	HandshakeHashAfter string                `json:"handshake_hash_after"`
}

type splitJSON struct {
	KIR     string `json:"k_ir"`
	KIRNote string `json:"k_ir_note"`
	KRI     string `json:"k_ri"`
	KRINote string `json:"k_ri_note"`
}

type m4JSON struct {
	Name            string `json:"name"`
	Direction       string `json:"direction"`
	Key             string `json:"key"`
	DirectionConst  string `json:"direction_constant"`
	Counter         uint64 `json:"counter"`
	Nonce           string `json:"nonce"`
	ADOuterHeader   string `json:"ad_outer_header"`
	Plaintext       string `json:"plaintext"`
	PairDataPayload string `json:"pair_data_payload"`
	Size            int    `json:"size"`
	OuterFrame      string `json:"outer_frame"`
}

type channelJSON struct {
	SS            string    `json:"ss"`
	Salt2         string    `json:"salt2"`
	CRID          string    `json:"crid"`
	PhraseBytes   string    `json:"phrase_bytes"`
	PhraseN       string    `json:"phrase_n"`
	PhraseIndices [3]int    `json:"phrase_indices"`
	PhraseWords   [3]string `json:"phrase_words"`
}

type pairingTranscriptJSON struct {
	Name                     string           `json:"name"`
	CodeInput                string           `json:"code_input"`
	CodeCanonical            string           `json:"code_canonical"`
	CreationDateUTC          string           `json:"creation_date_utc"`
	Rendezvous               rendezvousJSON   `json:"rendezvous"`
	Creator                  pairingPartyJSON `json:"creator"`
	Joiner                   pairingPartyJSON `json:"joiner"`
	Commitment               commitmentJSON   `json:"commitment"`
	Prologue                 string           `json:"prologue"`
	ChainingKeyInitial       string           `json:"chaining_key_initial"`
	HandshakeHashAfterProlog string           `json:"handshake_hash_after_prologue"`
	Messages                 []pairingMsgJSON `json:"messages"`
	Split                    splitJSON        `json:"split"`
	M4                       m4JSON           `json:"m4_pair_confirm"`
	Channel                  channelJSON      `json:"channel"`
}

type pairingFileJSON struct {
	Purpose      string                  `json:"_purpose"`
	Spec         string                  `json:"_spec"`
	ProtocolName string                  `json:"protocol_name"`
	Notes        []string                `json:"notes"`
	Transcripts  []pairingTranscriptJSON `json:"transcripts"`
}

// channelInfo carries a finished channel into the session-handshake file.
type channelInfo struct {
	name           string
	creatorPriv    []byte
	creatorPub     []byte
	joinerPriv     []byte
	joinerPub      []byte
	crid           [16]byte
	pairTranscript string
}

func genPairingHandshake(words []string, seeds seedCache) (*pairingFileJSON, []channelInfo, error) {
	file := &pairingFileJSON{
		Purpose: "Two full deterministic pairing-handshake transcripts " +
			"(Noise_XXpsk2 with commitment prologue): every key, every " +
			"message byte, per-step chaining keys and handshake hashes, " +
			"Split keys, M4 PAIR_CONFIRM, and the derived CRID and safety phrase.",
		Spec:         SpecRef + " §3.1.2–§3.1.5, §5.4, §5.6, §5.7",
		ProtocolName: noise.ProtocolName("XXpsk2"),
		Notes: []string{
			"The joiner is the Noise initiator; the creator is the responder (spec §3.1.3).",
			"Prologue = M0 alone (32 bytes), not the whole M1 frame. M0 = SHA-256(\"nimna/commit/v1\" ‖ eB_pub ‖ sB_pub) over the joiner's fresh keys.",
			"psk-pattern rule (Noise rev 34 §9.2): every 'e' token also calls MixKey(e.public_key); that is why M1 carries a 16-byte tag over its empty payload.",
			"Handshake-internal AEAD nonces use the Noise encoding: 4 zero bytes ‖ little-endian counter. Only post-Split traffic (M4 and session transport) uses the Nimna nonce of spec §5.6.",
			"chaining_key_initial is SHA-256 of the protocol name (the name is longer than 32 bytes); handshake_hash_after_prologue is h after MixHash(M0). XXpsk2 has no pre-messages.",
			"Split: the first derived key k_ir belongs to the initiator (joiner); the second, k_ri, to the responder (creator). M4 PAIR_CONFIRM is the only post-Split pairing frame: key k_ri, direction constant 0x00000001, counter 0, ad = outer PAIR_DATA header over the topic.",
			"After M4 both sides destroy handshake states, ephemerals, Split keys, seed and psk; message traffic always runs in sessions (spec §3.1.3).",
			"All PAIR_DATA frames ride the rendezvous topic: outer_frame = 01 ‖ 20 ‖ topic ‖ pair_data_payload.",
		},
	}

	// Fixed push-token constants.
	apnsToken := fixed32("pairing1/creator-apns-token")
	fcmToken := []byte("nimna-testvec-fcm-registration-token-0001")

	t1, ch1, err := pairingTranscript(pairingInputs{
		name:         "tokens-present",
		codeInput:    "7Q2-M4K-9XV",
		date:         "2026-07-04",
		keyLabel:     "pairing1",
		creatorToken: framing.TokenPayload{Present: true, Platform: framing.PlatformAPNs, Token: apnsToken},
		joinerToken:  framing.TokenPayload{Present: true, Platform: framing.PlatformFCM, Token: fcmToken},
	}, words, seeds)
	if err != nil {
		return nil, nil, err
	}
	t2, ch2, err := pairingTranscript(pairingInputs{
		name:         "tokens-absent",
		codeInput:    "3F8-P7R-WT2",
		date:         "2026-07-03",
		keyLabel:     "pairing2",
		creatorToken: framing.TokenPayload{},
		joinerToken:  framing.TokenPayload{},
	}, words, seeds)
	if err != nil {
		return nil, nil, err
	}
	file.Transcripts = []pairingTranscriptJSON{*t1, *t2}
	return file, []channelInfo{ch1, ch2}, nil
}

type pairingInputs struct {
	name         string
	codeInput    string
	date         string
	keyLabel     string
	creatorToken framing.TokenPayload
	joinerToken  framing.TokenPayload
}

func tokenJSON(t framing.TokenPayload) (tokenPayloadJSON, []byte, error) {
	enc, err := framing.EncodeTokenPayload(t)
	if err != nil {
		return tokenPayloadJSON{}, nil, err
	}
	out := tokenPayloadJSON{Form: "absent", Encoded: hexs(enc)}
	if t.Present {
		out.Form = "present"
		switch t.Platform {
		case framing.PlatformAPNs:
			out.Platform = "0x01 (APNs)"
		case framing.PlatformFCM:
			out.Platform = "0x02 (FCM)"
		}
		out.Token = hexs(t.Token)
	}
	return out, enc, nil
}

func pairingTranscript(in pairingInputs, words []string, seeds seedCache) (*pairingTranscriptJSON, channelInfo, error) {
	fail := func(err error) (*pairingTranscriptJSON, channelInfo, error) {
		return nil, channelInfo{}, fmt.Errorf("pairing %s: %w", in.name, err)
	}

	canonical, err := derive.Canonicalize(in.codeInput)
	if err != nil {
		return fail(err)
	}
	// Production-cost rendezvous derivation (cached across files).
	key := canonical + "|" + in.date
	outs, ok := seeds[key]
	if !ok {
		outs = deriveOutputs(canonical, in.date, derive.ProductionParams)
		seeds[key] = outs
	}
	topicB, _ := hex.DecodeString(outs.Topic)
	psk, _ := hex.DecodeString(outs.PSK)
	var topic [16]byte
	copy(topic[:], topicB)

	// Fixed keys. A = creator (responder), B = joiner (initiator).
	sAPriv := fixed32(in.keyLabel + "/creator-static")
	eAPriv := fixed32(in.keyLabel + "/creator-ephemeral")
	sBPriv := fixed32(in.keyLabel + "/joiner-static")
	eBPriv := fixed32(in.keyLabel + "/joiner-ephemeral")
	sAPub, err := noise.PublicKey(sAPriv)
	if err != nil {
		return fail(err)
	}
	eAPub, err := noise.PublicKey(eAPriv)
	if err != nil {
		return fail(err)
	}
	sBPub, err := noise.PublicKey(sBPriv)
	if err != nil {
		return fail(err)
	}
	eBPub, err := noise.PublicKey(eBPriv)
	if err != nil {
		return fail(err)
	}

	// Commitment prologue.
	preimage := derive.CommitmentPreimage(eBPub, sBPub)
	m0 := derive.Commitment(eBPub, sBPub)
	if len(preimage) != 79 {
		return fail(fmt.Errorf("M0 preimage must be 79 bytes, got %d", len(preimage)))
	}

	joiner, err := noise.NewHandshake(noise.Config{
		Pattern: "XXpsk2", Initiator: true, Prologue: m0,
		Static: sBPriv, Ephemeral: eBPriv, PSKs: [][]byte{psk},
	})
	if err != nil {
		return fail(err)
	}
	creator, err := noise.NewHandshake(noise.Config{
		Pattern: "XXpsk2", Initiator: false, Prologue: m0,
		Static: sAPriv, Ephemeral: eAPriv, PSKs: [][]byte{psk},
	})
	if err != nil {
		return fail(err)
	}

	ckInitial := joiner.ChainingKey()
	hAfterPrologue := joiner.HandshakeHash()
	if !bytes.Equal(hAfterPrologue, creator.HandshakeHash()) {
		return fail(fmt.Errorf("prologue hash disagreement"))
	}

	creatorTok, creatorTokEnc, err := tokenJSON(in.creatorToken)
	if err != nil {
		return fail(err)
	}
	joinerTok, joinerTokEnc, err := tokenJSON(in.joinerToken)
	if err != nil {
		return fail(err)
	}

	// step runs one handshake message, checks the reader agrees, and
	// asserts both states remain identical.
	step := func(w, r *noise.HandshakeState, payload []byte) ([]byte, error) {
		msg, _, err := w.WriteMessage(payload)
		if err != nil {
			return nil, err
		}
		got, _, err := r.ReadMessage(msg)
		if err != nil {
			return nil, err
		}
		if !bytes.Equal(got, payload) {
			return nil, fmt.Errorf("payload round-trip mismatch")
		}
		if !bytes.Equal(w.ChainingKey(), r.ChainingKey()) || !bytes.Equal(w.HandshakeHash(), r.HandshakeHash()) {
			return nil, fmt.Errorf("state divergence between roles")
		}
		return msg, nil
	}

	// M1: joiner → creator, "e" (+ psk-mode MixKey), empty payload.
	noiseM1, err := step(joiner, creator, nil)
	if err != nil {
		return fail(err)
	}
	pairM1 := append(append([]byte{}, m0...), noiseM1...)
	if len(pairM1) != 80 {
		return fail(fmt.Errorf("M1 must be 80 bytes, got %d", len(pairM1)))
	}
	m1 := pairingMsgJSON{
		Name: "M1", Direction: "joiner->creator", NoiseTokens: "e",
		PayloadPlaintext: "",
		Components: pairingComponentsJSON{
			M0:                  hexs(m0),
			EphemeralPub:        hexs(noiseM1[:32]),
			TagOverEmptyPayload: hexs(noiseM1[32:48]),
		},
		PairDataPayload:    hexs(pairM1),
		Size:               len(pairM1),
		OuterFrame:         hexs(framing.OuterFrame(framing.FramePairData, topic, pairM1)),
		ChainingKeyAfter:   hexs(joiner.ChainingKey()),
		HandshakeHashAfter: hexs(joiner.HandshakeHash()),
	}

	// M2: creator → joiner, "e, ee, s, es, psk", payload = token_payload_A.
	noiseM2, err := step(creator, joiner, creatorTokEnc)
	if err != nil {
		return fail(err)
	}
	if len(noiseM2) != 96+len(creatorTokEnc) {
		return fail(fmt.Errorf("M2 must be 96+n bytes, got %d (n=%d)", len(noiseM2), len(creatorTokEnc)))
	}
	m2 := pairingMsgJSON{
		Name: "M2", Direction: "creator->joiner", NoiseTokens: "e, ee, s, es, psk",
		PayloadPlaintext: hexs(creatorTokEnc),
		Components: pairingComponentsJSON{
			EphemeralPub:          hexs(noiseM2[:32]),
			EncryptedStatic:       hexs(noiseM2[32:80]),
			EncryptedTokenPayload: hexs(noiseM2[80:]),
		},
		PairDataPayload:    hexs(noiseM2),
		Size:               len(noiseM2),
		OuterFrame:         hexs(framing.OuterFrame(framing.FramePairData, topic, noiseM2)),
		ChainingKeyAfter:   hexs(creator.ChainingKey()),
		HandshakeHashAfter: hexs(creator.HandshakeHash()),
	}

	// M3: joiner → creator, "s, se", payload = token_payload_B.
	noiseM3, err := step(joiner, creator, joinerTokEnc)
	if err != nil {
		return fail(err)
	}
	if len(noiseM3) != 64+len(joinerTokEnc) {
		return fail(fmt.Errorf("M3 must be 64+n bytes, got %d", len(noiseM3)))
	}
	m3 := pairingMsgJSON{
		Name: "M3", Direction: "joiner->creator", NoiseTokens: "s, se",
		PayloadPlaintext: hexs(joinerTokEnc),
		Components: pairingComponentsJSON{
			EncryptedStatic:       hexs(noiseM3[:48]),
			EncryptedTokenPayload: hexs(noiseM3[48:]),
		},
		PairDataPayload:    hexs(noiseM3),
		Size:               len(noiseM3),
		OuterFrame:         hexs(framing.OuterFrame(framing.FramePairData, topic, noiseM3)),
		ChainingKeyAfter:   hexs(joiner.ChainingKey()),
		HandshakeHashAfter: hexs(joiner.HandshakeHash()),
	}

	// Creator-side commitment verification (spec §3.1.3): the creator
	// checks M0 against the joiner's revealed keys before sending M4.
	// bytes.Equal is acceptable only in this generator (every value is a
	// public test constant); production implementations must perform this
	// check in constant time (crypto/subtle.ConstantTimeCompare).
	if !bytes.Equal(creator.RemoteStatic(), sBPub) {
		return fail(fmt.Errorf("creator learned wrong joiner static"))
	}
	if !bytes.Equal(derive.Commitment(eBPub, creator.RemoteStatic()), m0) {
		return fail(fmt.Errorf("commitment verification failed"))
	}

	// Split.
	jk1, jk2, err := joiner.Split()
	if err != nil {
		return fail(err)
	}
	ck1, ck2, err := creator.Split()
	if err != nil {
		return fail(err)
	}
	if jk1 != ck1 || jk2 != ck2 {
		return fail(fmt.Errorf("split disagreement"))
	}

	// M4 PAIR_CONFIRM: post-Split transport frame under k_ri.
	ad := framing.OuterHeader(framing.FramePairData, topic)
	tr := noise.NewTransport(jk2, noise.DirResponderToInitiator)
	rec := tr.Seal(ad, nil)
	if len(rec.Ciphertext) != 16 {
		return fail(fmt.Errorf("M4 must be 16 bytes, got %d", len(rec.Ciphertext)))
	}
	// Joiner side must accept it.
	if _, err := noise.NewTransport(jk2, noise.DirResponderToInitiator).Open(ad, rec.Ciphertext); err != nil {
		return fail(fmt.Errorf("M4 verify: %w", err))
	}

	// Channel derivations.
	ss, err := derive.SharedSecret(sAPriv, sBPub)
	if err != nil {
		return fail(err)
	}
	ss2, err := derive.SharedSecret(sBPriv, sAPub)
	if err != nil {
		return fail(err)
	}
	if !bytes.Equal(ss, ss2) {
		return fail(fmt.Errorf("ss must be identical on both ends"))
	}
	salt2 := derive.Salt2(sAPub, sBPub)
	crid := derive.CRID(ss, salt2)
	phraseBytes := derive.PhraseBytes(ss, salt2)
	indices := derive.PhraseIndices(phraseBytes)
	phraseWords, err := derive.PhraseWords(indices, words)
	if err != nil {
		return fail(err)
	}

	var cridArr [16]byte
	copy(cridArr[:], crid)

	t := &pairingTranscriptJSON{
		Name:            in.name,
		CodeInput:       in.codeInput,
		CodeCanonical:   canonical,
		CreationDateUTC: in.date,
		Rendezvous: rendezvousJSON{
			SaltPreimage: string(derive.TopicSaltPreimage(in.date)),
			Salt:         hexs(derive.TopicSalt(in.date)),
			Seed:         outs.Seed,
			Topic:        outs.Topic,
			PSK:          outs.PSK,
		},
		Creator: pairingPartyJSON{
			Device: "A (created the code)", NoiseRole: "responder",
			StaticPriv: hexs(sAPriv), StaticPub: hexs(sAPub),
			EphemeralPriv: hexs(eAPriv), EphemeralPub: hexs(eAPub),
			TokenPayload: creatorTok,
		},
		Joiner: pairingPartyJSON{
			Device: "B (entered the code)", NoiseRole: "initiator",
			StaticPriv: hexs(sBPriv), StaticPub: hexs(sBPub),
			EphemeralPriv: hexs(eBPriv), EphemeralPub: hexs(eBPub),
			TokenPayload: joinerTok,
		},
		Commitment: commitmentJSON{
			LabelASCII: derive.CommitLabel,
			Preimage:   hexs(preimage),
			M0:         hexs(m0),
		},
		Prologue:                 hexs(m0),
		ChainingKeyInitial:       hexs(ckInitial),
		HandshakeHashAfterProlog: hexs(hAfterPrologue),
		Messages:                 []pairingMsgJSON{m1, m2, m3},
		Split: splitJSON{
			KIR:     hexs(jk1[:]),
			KIRNote: "initiator(joiner)->responder(creator); direction constant 0x00000000",
			KRI:     hexs(jk2[:]),
			KRINote: "responder(creator)->initiator(joiner); direction constant 0x00000001",
		},
		M4: m4JSON{
			Name: "M4 PAIR_CONFIRM", Direction: "creator->joiner",
			Key:             "k_ri",
			DirectionConst:  "0x00000001",
			Counter:         0,
			Nonce:           hexs(rec.Nonce[:]),
			ADOuterHeader:   hexs(ad),
			Plaintext:       "",
			PairDataPayload: hexs(rec.Ciphertext),
			Size:            len(rec.Ciphertext),
			OuterFrame:      hexs(framing.OuterFrame(framing.FramePairData, topic, rec.Ciphertext)),
		},
		Channel: channelJSON{
			SS:            hexs(ss),
			Salt2:         hexs(salt2),
			CRID:          hexs(crid),
			PhraseBytes:   hexs(phraseBytes),
			PhraseN:       new(big.Int).SetBytes(phraseBytes).String(),
			PhraseIndices: indices,
			PhraseWords:   phraseWords,
		},
	}
	info := channelInfo{
		name:           in.name,
		creatorPriv:    sAPriv,
		creatorPub:     sAPub,
		joinerPriv:     sBPriv,
		joinerPub:      sBPub,
		crid:           cridArr,
		pairTranscript: in.name,
	}
	return t, info, nil
}
