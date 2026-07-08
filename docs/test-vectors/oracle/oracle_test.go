package oracle

// Shared oracle helpers: the flynn/noise cipher-suite handle, deterministic
// ephemeral injection, the Nimna transport primitives re-implemented over
// x/crypto (nonce layout + REKEY), and the committed-vector loaders. Every
// symbol here is used by pairing_test.go and session_test.go.

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"testing"

	"github.com/flynn/noise"
	"golang.org/x/crypto/chacha20poly1305"
)

// cipherSuite is Nimna's suite: X25519 DH, ChaCha20-Poly1305, SHA-256.
// This is the exact suite named by both committed protocol names
// (Noise_XXpsk2_25519_ChaChaPoly_SHA256, Noise_KK_25519_ChaChaPoly_SHA256).
func cipherSuite() noise.CipherSuite {
	return noise.NewCipherSuite(noise.DH25519, noise.CipherChaChaPoly, noise.HashSHA256)
}

// ephemeralReader injects a fixed ephemeral private key into flynn/noise.
// flynn calls CipherSuite.GenerateKeypair(rng), which reads exactly DHLen
// (32) bytes as the private scalar; each handshake side generates exactly
// one ephemeral, so a single-shot 32-byte reader makes flynn deterministic
// and byte-reproducible against the committed vector's ephemerals. A second
// read (which must not happen for XX/KK) fails loudly.
func ephemeralReader(t *testing.T, ephPriv []byte) io.Reader {
	t.Helper()
	if len(ephPriv) != 32 {
		t.Fatalf("ephemeral private key must be 32 bytes, got %d", len(ephPriv))
	}
	return bytes.NewReader(ephPriv)
}

// --- Nimna-specific transport wrapping, re-implemented over x/crypto ---
//
// HONEST SCOPE (design note §2.3): flynn/noise cannot reproduce Nimna's
// post-Split transport — it uses the standard Noise nonce and does not
// rekey per message. flynn's contribution therefore ends at Split (its keys
// are cross-checked byte-for-byte, below). The transport itself is
// re-derived here from those same committed keys using x/crypto's
// chacha20poly1305 DIRECTLY. The AEAD *core* is x/crypto on both sides (the
// from-spec engine and this oracle) — there is no independent second
// ChaCha20-Poly1305 worth trusting over the audited one. What IS
// independently re-implemented here is the Nimna-specific wrapping: the
// direction‖counter nonce layout and the per-message REKEY. The ultimate
// anchor for the transport discipline remains (a) the committed vectors and
// (b) both from-spec engines passing them byte-for-byte.

// Transport direction constants (spec §5.6).
const (
	dirInitiatorToResponder uint32 = 0x00000000
	dirResponderToInitiator uint32 = 0x00000001
)

// transportNonce encodes the §5.6 nonce: direction(4, BE) ‖ counter(8, BE).
func transportNonce(direction uint32, counter uint64) [12]byte {
	var n [12]byte
	binary.BigEndian.PutUint32(n[0:4], direction)
	binary.BigEndian.PutUint64(n[4:12], counter)
	return n
}

// seal is ChaCha20-Poly1305 AEAD encryption with the given nonce and AD.
func seal(t *testing.T, key [32]byte, nonce [12]byte, ad, plaintext []byte) []byte {
	t.Helper()
	aead, err := chacha20poly1305.New(key[:])
	if err != nil {
		t.Fatalf("chacha20poly1305.New: %v", err)
	}
	return aead.Seal(nil, nonce[:], plaintext, ad)
}

// rekey is the Noise REKEY function (spec §11.3):
// first 32 bytes of Seal(k, nonce=0x00000000ffffffffffffffff, ad="", 0^32).
func rekey(t *testing.T, k [32]byte) [32]byte {
	t.Helper()
	nonce := transportNonce(0, ^uint64(0)) // 00000000 ‖ ff…ff
	ct := seal(t, k, nonce, nil, make([]byte, 32))
	var out [32]byte
	copy(out[:], ct[:32])
	return out
}

// --- committed-vector structures (only the fields the oracle asserts) ---

type party struct {
	StaticPriv    string `json:"static_priv"`
	StaticPub     string `json:"static_pub"`
	EphemeralPriv string `json:"ephemeral_priv"`
	EphemeralPub  string `json:"ephemeral_pub"`
}

type pairingMsg struct {
	Name               string `json:"name"`
	PayloadPlaintext   string `json:"payload_plaintext"`
	PairDataPayload    string `json:"pair_data_payload"`
	HandshakeHashAfter string `json:"handshake_hash_after"`
}

type split struct {
	KIR string `json:"k_ir"`
	KRI string `json:"k_ri"`
}

type m4Confirm struct {
	ADOuterHeader   string `json:"ad_outer_header"`
	PairDataPayload string `json:"pair_data_payload"`
}

type pairingTranscript struct {
	Name       string `json:"name"`
	Rendezvous struct {
		PSK string `json:"psk"`
	} `json:"rendezvous"`
	Creator    party `json:"creator"`
	Joiner     party `json:"joiner"`
	Commitment struct {
		Preimage string `json:"preimage"`
		M0       string `json:"m0"`
	} `json:"commitment"`
	Prologue string       `json:"prologue"`
	Messages []pairingMsg `json:"messages"`
	Split    split        `json:"split"`
	M4       m4Confirm    `json:"m4_pair_confirm"`
}

type pairingFile struct {
	Transcripts []pairingTranscript `json:"transcripts"`
}

type sessionMsg struct {
	Name               string `json:"name"`
	SessionDataPayload string `json:"session_data_payload"`
	HandshakeHashAfter string `json:"handshake_hash_after"`
}

type transportFrame struct {
	Seq                int    `json:"seq"`
	DirectionConstant  string `json:"direction_constant"`
	Counter            uint64 `json:"counter"`
	KeyBefore          string `json:"key_before"`
	ADOuterHeader      string `json:"ad_outer_header"`
	SessionDataPayload string `json:"session_data_payload"`
	KeyAfterRekey      string `json:"key_after_rekey"`
	InnerEnvelope      struct {
		Encoded string `json:"encoded"`
	} `json:"inner_envelope_plaintext"`
}

type sessionTranscript struct {
	Name        string `json:"name"`
	Initiator   party  `json:"initiator"`
	Responder   party  `json:"responder"`
	Messages    []sessionMsg
	Split       split            `json:"split"`
	Frames      []transportFrame `json:"transport_frames"`
	HandshakeHF string           `json:"handshake_hash_final"`
}

// UnmarshalJSON is defined manually only to keep the field tags terse; the
// default decoder is used with explicit tags via an alias.
func (s *sessionTranscript) unmarshal(raw json.RawMessage) error {
	type alias struct {
		Name        string           `json:"name"`
		Initiator   party            `json:"initiator"`
		Responder   party            `json:"responder"`
		Messages    []sessionMsg     `json:"messages"`
		Split       split            `json:"split"`
		Frames      []transportFrame `json:"transport_frames"`
		HandshakeHF string           `json:"handshake_hash_final"`
	}
	var a alias
	if err := json.Unmarshal(raw, &a); err != nil {
		return err
	}
	s.Name, s.Initiator, s.Responder = a.Name, a.Initiator, a.Responder
	s.Messages, s.Split, s.Frames, s.HandshakeHF = a.Messages, a.Split, a.Frames, a.HandshakeHF
	return nil
}

type sessionFile struct {
	Transcripts []json.RawMessage `json:"transcripts"`
}

// loadPairing reads the committed pairing-handshake vectors (relative to the
// oracle module dir).
func loadPairing(t *testing.T) pairingFile {
	t.Helper()
	raw, err := os.ReadFile("../pairing-handshake.json")
	if err != nil {
		t.Fatalf("reading committed pairing vectors: %v", err)
	}
	var f pairingFile
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatalf("decoding pairing vectors: %v", err)
	}
	if len(f.Transcripts) == 0 {
		t.Fatal("no pairing transcripts in committed vectors")
	}
	return f
}

// loadSession reads the committed session-handshake vectors.
func loadSession(t *testing.T) []sessionTranscript {
	t.Helper()
	raw, err := os.ReadFile("../session-handshake.json")
	if err != nil {
		t.Fatalf("reading committed session vectors: %v", err)
	}
	var f sessionFile
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatalf("decoding session vectors: %v", err)
	}
	if len(f.Transcripts) == 0 {
		t.Fatal("no session transcripts in committed vectors")
	}
	out := make([]sessionTranscript, len(f.Transcripts))
	for i, rawT := range f.Transcripts {
		if err := out[i].unmarshal(rawT); err != nil {
			t.Fatalf("decoding session transcript %d: %v", i, err)
		}
	}
	return out
}

// --- small hex helpers ---

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex %q: %v", s, err)
	}
	return b
}

func mustHex32(t *testing.T, s string) [32]byte {
	t.Helper()
	b := mustHex(t, s)
	if len(b) != 32 {
		t.Fatalf("want 32 bytes, got %d (%q)", len(b), s)
	}
	var out [32]byte
	copy(out[:], b)
	return out
}

// dhKey builds a flynn/noise static keypair from committed hex.
func dhKey(t *testing.T, priv, pub string) noise.DHKey {
	t.Helper()
	return noise.DHKey{Private: mustHex(t, priv), Public: mustHex(t, pub)}
}
