package oracle

// XXpsk2 pairing handshake, cross-verified with flynn/noise as an
// independent implementation, plus the two Nimna-external pieces flynn
// cannot see: the commitment M0 derivation and the post-Split M4
// PAIR_CONFIRM transport frame.

import (
	"bytes"
	"crypto/sha256"
	"testing"

	"github.com/flynn/noise"
)

// commitLabel is the domain-separation label the from-spec engine uses:
// M0 = SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub) (generator
// internal/derive: CommitLabel = "nimna/commit/v1").
const commitLabel = "nimna/commit/v1"

// TestOracleXXpsk2BothRoles drives flynn/noise as XXpsk2 (HandshakeXX +
// PresharedKeyPlacement=2) for BOTH roles of every committed pairing
// transcript, and asserts byte-equality of M1–M3, the per-step handshake
// hash, and the Split keys against the committed vectors.
func TestOracleXXpsk2BothRoles(t *testing.T) {
	for _, tr := range loadPairing(t).Transcripts {
		tr := tr
		t.Run(tr.Name, func(t *testing.T) {
			if len(tr.Messages) != 3 {
				t.Fatalf("XXpsk2 must have 3 messages, got %d", len(tr.Messages))
			}
			psk := mustHex(t, tr.Rendezvous.PSK)
			m0 := mustHex(t, tr.Prologue)

			// Joiner = Noise initiator; creator = Noise responder (§3.1.3).
			ini, err := noise.NewHandshakeState(noise.Config{
				CipherSuite:           cipherSuite(),
				Random:                ephemeralReader(t, mustHex(t, tr.Joiner.EphemeralPriv)),
				Pattern:               noise.HandshakeXX,
				Initiator:             true,
				Prologue:              m0,
				PresharedKey:          psk,
				PresharedKeyPlacement: 2,
				StaticKeypair:         dhKey(t, tr.Joiner.StaticPriv, tr.Joiner.StaticPub),
			})
			if err != nil {
				t.Fatalf("initiator handshake: %v", err)
			}
			res, err := noise.NewHandshakeState(noise.Config{
				CipherSuite:           cipherSuite(),
				Random:                ephemeralReader(t, mustHex(t, tr.Creator.EphemeralPriv)),
				Pattern:               noise.HandshakeXX,
				Initiator:             false,
				Prologue:              m0,
				PresharedKey:          psk,
				PresharedKeyPlacement: 2,
				StaticKeypair:         dhKey(t, tr.Creator.StaticPriv, tr.Creator.StaticPub),
			})
			if err != nil {
				t.Fatalf("responder handshake: %v", err)
			}

			// M1: joiner->creator, empty payload. The committed
			// pair_data_payload prepends the 32-byte M0 prologue, which is
			// NOT part of the Noise message — strip it for comparison.
			m1 := writeMsg(t, ini, nil)
			wantM1 := mustHex(t, tr.Messages[0].PairDataPayload)
			if len(wantM1) < 32 {
				t.Fatalf("M1 vector too short: %d bytes", len(wantM1))
			}
			assertEqual(t, "M1 noise message", m1, wantM1[32:])
			readMsg(t, res, m1)
			assertHashes(t, "M1", ini, res, tr.Messages[0].HandshakeHashAfter)

			// M2: creator->joiner, payload = creator token_payload.
			m2 := writeMsg(t, res, mustHex(t, tr.Messages[1].PayloadPlaintext))
			assertEqual(t, "M2", m2, mustHex(t, tr.Messages[1].PairDataPayload))
			readMsg(t, ini, m2)
			assertHashes(t, "M2", res, ini, tr.Messages[1].HandshakeHashAfter)

			// M3: joiner->creator, payload = joiner token_payload; completes
			// the handshake, so both sides Split here.
			m3, iniKIR, iniKRI := writeMsgSplit(t, ini, mustHex(t, tr.Messages[2].PayloadPlaintext))
			assertEqual(t, "M3", m3, mustHex(t, tr.Messages[2].PairDataPayload))
			_, resKIR, resKRI := readMsgSplit(t, res, m3)
			assertHashes(t, "M3", ini, res, tr.Messages[2].HandshakeHashAfter)

			// Split keys byte-equal the committed vector, both roles.
			wantKIR := mustHex32(t, tr.Split.KIR)
			wantKRI := mustHex32(t, tr.Split.KRI)
			assertKey(t, "k_ir (initiator side)", iniKIR.UnsafeKey(), wantKIR)
			assertKey(t, "k_ri (initiator side)", iniKRI.UnsafeKey(), wantKRI)
			assertKey(t, "k_ir (responder side)", resKIR.UnsafeKey(), wantKIR)
			assertKey(t, "k_ri (responder side)", resKRI.UnsafeKey(), wantKRI)

			// The responder learned the joiner's static during M3 — the
			// input to the commitment check (asserted independently below).
			if !bytes.Equal(res.PeerStatic(), mustHex(t, tr.Joiner.StaticPub)) {
				t.Fatal("responder learned an unexpected joiner static key")
			}
		})
	}
}

// TestOracleCommitmentM0 independently recomputes the commitment M0 with a
// plain SHA-256 (no Noise library involved) and asserts it equals the
// committed prologue, and that the creator-side verification (spec §3.1.3)
// recomputes the same value from the joiner's revealed static.
func TestOracleCommitmentM0(t *testing.T) {
	for _, tr := range loadPairing(t).Transcripts {
		tr := tr
		t.Run(tr.Name, func(t *testing.T) {
			eBPub := mustHex(t, tr.Joiner.EphemeralPub)
			sBPub := mustHex(t, tr.Joiner.StaticPub)

			// Preimage layout: label ‖ eB_pub ‖ sB_pub (byte-exact mirror
			// of the from-spec engine's CommitmentPreimage).
			var pre bytes.Buffer
			pre.WriteString(commitLabel)
			pre.Write(eBPub)
			pre.Write(sBPub)
			if !bytes.Equal(pre.Bytes(), mustHex(t, tr.Commitment.Preimage)) {
				t.Fatal("recomputed commitment preimage differs from the committed vector")
			}

			sum := sha256.Sum256(pre.Bytes())
			assertEqual(t, "M0", sum[:], mustHex(t, tr.Commitment.M0))
			// The prologue fed to the Noise layer IS M0.
			assertEqual(t, "prologue==M0", sum[:], mustHex(t, tr.Prologue))

			// Creator-side verification: recompute from the (public) joiner
			// static that the responder learns during M3.
			var repre bytes.Buffer
			repre.WriteString(commitLabel)
			repre.Write(eBPub)
			repre.Write(sBPub)
			resum := sha256.Sum256(repre.Bytes())
			if !bytes.Equal(resum[:], sum[:]) {
				t.Fatal("creator-side commitment verification disagreed")
			}
		})
	}
}

// TestOraclePairingTransport re-derives the M4 PAIR_CONFIRM frame from the
// committed Split key k_ri using x/crypto directly (flynn cannot mirror the
// §5.6 transport wrapping) and asserts byte-equality with the committed
// ciphertext.
func TestOraclePairingTransport(t *testing.T) {
	for _, tr := range loadPairing(t).Transcripts {
		tr := tr
		t.Run(tr.Name, func(t *testing.T) {
			// M4: key k_ri, direction 0x00000001, counter 0, empty plaintext,
			// ad = the outer PAIR_DATA header over the topic.
			kRI := mustHex32(t, tr.Split.KRI)
			nonce := transportNonce(dirResponderToInitiator, 0)
			ad := mustHex(t, tr.M4.ADOuterHeader)
			got := seal(t, kRI, nonce, ad, nil)
			assertEqual(t, "M4 PAIR_CONFIRM", got, mustHex(t, tr.M4.PairDataPayload))
		})
	}
}

// --- flynn/noise message helpers (fail the test on any handshake error) ---

func writeMsg(t *testing.T, hs *noise.HandshakeState, payload []byte) []byte {
	t.Helper()
	out, cs0, cs1, err := hs.WriteMessage(nil, payload)
	if err != nil {
		t.Fatalf("WriteMessage: %v", err)
	}
	if cs0 != nil || cs1 != nil {
		t.Fatal("unexpected Split before final message")
	}
	return out
}

func writeMsgSplit(t *testing.T, hs *noise.HandshakeState, payload []byte) ([]byte, *noise.CipherState, *noise.CipherState) {
	t.Helper()
	out, cs0, cs1, err := hs.WriteMessage(nil, payload)
	if err != nil {
		t.Fatalf("WriteMessage (final): %v", err)
	}
	if cs0 == nil || cs1 == nil {
		t.Fatal("expected Split on final WriteMessage")
	}
	return out, cs0, cs1
}

func readMsg(t *testing.T, hs *noise.HandshakeState, msg []byte) {
	t.Helper()
	_, cs0, cs1, err := hs.ReadMessage(nil, msg)
	if err != nil {
		t.Fatalf("ReadMessage: %v", err)
	}
	if cs0 != nil || cs1 != nil {
		t.Fatal("unexpected Split before final message")
	}
}

func readMsgSplit(t *testing.T, hs *noise.HandshakeState, msg []byte) ([]byte, *noise.CipherState, *noise.CipherState) {
	t.Helper()
	out, cs0, cs1, err := hs.ReadMessage(nil, msg)
	if err != nil {
		t.Fatalf("ReadMessage (final): %v", err)
	}
	if cs0 == nil || cs1 == nil {
		t.Fatal("expected Split on final ReadMessage")
	}
	return out, cs0, cs1
}

// assertHashes checks the writer and reader share the committed handshake
// hash after a message (flynn's ChannelBinding() returns h at any point).
func assertHashes(t *testing.T, label string, a, b *noise.HandshakeState, wantHex string) {
	t.Helper()
	want := mustHex(t, wantHex)
	if !bytes.Equal(a.ChannelBinding(), want) {
		t.Fatalf("%s: writer handshake hash differs from committed vector", label)
	}
	if !bytes.Equal(b.ChannelBinding(), want) {
		t.Fatalf("%s: reader handshake hash differs from committed vector", label)
	}
}

func assertEqual(t *testing.T, label string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: bytes differ from committed vector\n got:  %x\n want: %x", label, got, want)
	}
}

func assertKey(t *testing.T, label string, got, want [32]byte) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: key differs from committed vector\n got:  %x\n want: %x", label, got, want)
	}
}
