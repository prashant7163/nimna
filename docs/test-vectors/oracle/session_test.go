package oracle

// Noise_KK session handshake, cross-verified with flynn/noise, plus the
// post-Split transport frames re-wrapped independently over x/crypto (the
// one Nimna deviation flynn cannot mirror; see the honest-scope note in
// oracle_test.go).

import (
	"testing"

	"github.com/flynn/noise"
)

// TestOracleKKBothRoles drives flynn/noise as Noise_KK for both roles of
// every committed session transcript and asserts byte-equality of S1–S2, the
// handshake hash, and the Split keys.
func TestOracleKKBothRoles(t *testing.T) {
	for _, tr := range loadSession(t) {
		tr := tr
		t.Run(tr.Name, func(t *testing.T) {
			if len(tr.Messages) != 2 {
				t.Fatalf("KK must have 2 messages, got %d", len(tr.Messages))
			}
			// Knocker = Noise initiator; accepter = responder (§3.3.1). KK
			// pre-messages are both statics (initiator's first) — expressed
			// via StaticKeypair + PeerStatic. Zero prologue, no psk.
			ini, err := noise.NewHandshakeState(noise.Config{
				CipherSuite:   cipherSuite(),
				Random:        ephemeralReader(t, mustHex(t, tr.Initiator.EphemeralPriv)),
				Pattern:       noise.HandshakeKK,
				Initiator:     true,
				StaticKeypair: dhKey(t, tr.Initiator.StaticPriv, tr.Initiator.StaticPub),
				PeerStatic:    mustHex(t, tr.Responder.StaticPub),
			})
			if err != nil {
				t.Fatalf("initiator handshake: %v", err)
			}
			res, err := noise.NewHandshakeState(noise.Config{
				CipherSuite:   cipherSuite(),
				Random:        ephemeralReader(t, mustHex(t, tr.Responder.EphemeralPriv)),
				Pattern:       noise.HandshakeKK,
				Initiator:     false,
				StaticKeypair: dhKey(t, tr.Responder.StaticPriv, tr.Responder.StaticPub),
				PeerStatic:    mustHex(t, tr.Initiator.StaticPub),
			})
			if err != nil {
				t.Fatalf("responder handshake: %v", err)
			}

			// S1: knocker->accepter, empty payload.
			s1 := writeMsg(t, ini, nil)
			assertEqual(t, "S1", s1, mustHex(t, tr.Messages[0].SessionDataPayload))
			readMsg(t, res, s1)
			assertHashes(t, "S1", ini, res, tr.Messages[0].HandshakeHashAfter)

			// S2: accepter->knocker, empty payload; completes the handshake.
			s2, resKIR, resKRI := writeMsgSplit(t, res, nil)
			assertEqual(t, "S2", s2, mustHex(t, tr.Messages[1].SessionDataPayload))
			_, iniKIR, iniKRI := readMsgSplit(t, ini, s2)
			assertHashes(t, "S2", res, ini, tr.Messages[1].HandshakeHashAfter)
			if tr.HandshakeHF != tr.Messages[1].HandshakeHashAfter {
				t.Fatal("handshake_hash_final disagrees with S2 handshake_hash_after in the vector")
			}

			// Split keys byte-equal the committed vector, both roles.
			wantKIR := mustHex32(t, tr.Split.KIR)
			wantKRI := mustHex32(t, tr.Split.KRI)
			assertKey(t, "k_ir (initiator side)", iniKIR.UnsafeKey(), wantKIR)
			assertKey(t, "k_ri (initiator side)", iniKRI.UnsafeKey(), wantKRI)
			assertKey(t, "k_ir (responder side)", resKIR.UnsafeKey(), wantKIR)
			assertKey(t, "k_ri (responder side)", resKRI.UnsafeKey(), wantKRI)
		})
	}
}

// TestOracleSessionTransport re-derives every committed transport frame from
// the Split keys using x/crypto directly: it seals each frame's inner
// envelope under the §5.6 nonce and asserts byte-equality with the committed
// ciphertext, and independently reproduces the per-message REKEY schedule —
// anchoring the very first frame of each direction to the committed Split
// key and chaining forward from there.
func TestOracleSessionTransport(t *testing.T) {
	for _, tr := range loadSession(t) {
		tr := tr
		t.Run(tr.Name, func(t *testing.T) {
			// Per-direction rolling key; anchored to the Split output.
			cur := map[uint32][32]byte{
				dirInitiatorToResponder: mustHex32(t, tr.Split.KIR),
				dirResponderToInitiator: mustHex32(t, tr.Split.KRI),
			}
			nextCounter := map[uint32]uint64{
				dirInitiatorToResponder: 0,
				dirResponderToInitiator: 0,
			}
			for _, fr := range tr.Frames {
				dir := parseDirection(t, fr.DirectionConstant)

				// Anchor: the frame's committed key_before must equal our
				// independently-chained key for this direction.
				keyBefore := mustHex32(t, fr.KeyBefore)
				if keyBefore != cur[dir] {
					t.Fatalf("frame %d: committed key_before breaks the independent REKEY chain", fr.Seq)
				}
				// Counters are per-direction, strict increment from 0.
				if fr.Counter != nextCounter[dir] {
					t.Fatalf("frame %d: counter %d, expected %d", fr.Seq, fr.Counter, nextCounter[dir])
				}

				// Seal the committed inner envelope and match the wire bytes.
				nonce := transportNonce(dir, fr.Counter)
				ad := mustHex(t, fr.ADOuterHeader)
				pt := mustHex(t, fr.InnerEnvelope.Encoded)
				got := seal(t, keyBefore, nonce, ad, pt)
				assertEqual(t, "frame "+fr.Name(), got, mustHex(t, fr.SessionDataPayload))

				// Independently reproduce the REKEY and advance the chain.
				after := rekey(t, keyBefore)
				assertKey(t, "frame REKEY", after, mustHex32(t, fr.KeyAfterRekey))
				cur[dir] = after
				nextCounter[dir]++
			}
		})
	}
}

// Name gives a transport frame a stable label for assertion messages.
func (f transportFrame) Name() string {
	return "seq-" + itoa(f.Seq)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

func parseDirection(t *testing.T, s string) uint32 {
	t.Helper()
	switch s {
	case "0x00000000":
		return dirInitiatorToResponder
	case "0x00000001":
		return dirResponderToInitiator
	default:
		t.Fatalf("unknown direction constant %q", s)
		return 0
	}
}
