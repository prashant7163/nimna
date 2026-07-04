package noise

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Third-party Noise vector validation. The committed files under
// generator/testdata/ are filtered subsets (fundamental patterns, suite
// 25519_ChaChaPoly_SHA256) of:
//
//   - cacophony (Haskell, public domain): vectors/cacophony.txt
//   - snow (Rust, MIT/Apache-2.0): tests/vectors/snow.txt
//
// See generator/testdata/README.md for exact provenance. The test runs
// fully offline against the committed files.

type tpMessage struct {
	Payload    string `json:"payload"`
	Ciphertext string `json:"ciphertext"`
}

type tpVector struct {
	ProtocolName     string      `json:"protocol_name"`
	InitPrologue     *string     `json:"init_prologue,omitempty"`
	InitPsks         []string    `json:"init_psks,omitempty"`
	InitStatic       *string     `json:"init_static,omitempty"`
	InitEphemeral    *string     `json:"init_ephemeral,omitempty"`
	InitRemoteStatic *string     `json:"init_remote_static,omitempty"`
	RespPrologue     *string     `json:"resp_prologue,omitempty"`
	RespPsks         []string    `json:"resp_psks,omitempty"`
	RespStatic       *string     `json:"resp_static,omitempty"`
	RespEphemeral    *string     `json:"resp_ephemeral,omitempty"`
	RespRemoteStatic *string     `json:"resp_remote_static,omitempty"`
	HandshakeHash    *string     `json:"handshake_hash,omitempty"`
	Messages         []tpMessage `json:"messages"`
}

type tpFile struct {
	Vectors []tpVector `json:"vectors"`
}

func mustHexPtr(t *testing.T, s *string) []byte {
	t.Helper()
	if s == nil {
		return nil
	}
	b, err := hex.DecodeString(*s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}

func TestThirdPartyVectors(t *testing.T) {
	files := []string{
		filepath.Join("..", "..", "testdata", "cacophony-25519-chachapoly-sha256.json"),
		filepath.Join("..", "..", "testdata", "snow-25519-chachapoly-sha256.json"),
	}
	total := 0
	for _, path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("reading %s: %v", path, err)
		}
		var f tpFile
		if err := json.Unmarshal(raw, &f); err != nil {
			t.Fatalf("parsing %s: %v", path, err)
		}
		if len(f.Vectors) == 0 {
			t.Fatalf("%s: no vectors", path)
		}
		for _, v := range f.Vectors {
			total++
			t.Run(filepath.Base(path)+"/"+v.ProtocolName, func(t *testing.T) {
				runThirdPartyVector(t, v)
			})
		}
	}
	t.Logf("validated %d third-party vectors", total)
}

func runThirdPartyVector(t *testing.T, v tpVector) {
	const prefix = "Noise_"
	const suffix = "_25519_ChaChaPoly_SHA256"
	if !strings.HasPrefix(v.ProtocolName, prefix) || !strings.HasSuffix(v.ProtocolName, suffix) {
		t.Fatalf("unexpected protocol name %q in committed testdata", v.ProtocolName)
	}
	patternName := strings.TrimSuffix(strings.TrimPrefix(v.ProtocolName, prefix), suffix)

	psks := func(hexes []string) [][]byte {
		var out [][]byte
		for _, h := range hexes {
			out = append(out, mustHex(t, h))
		}
		return out
	}

	ini, err := NewHandshake(Config{
		Pattern:      patternName,
		Initiator:    true,
		Prologue:     mustHexPtr(t, v.InitPrologue),
		Static:       mustHexPtr(t, v.InitStatic),
		Ephemeral:    mustHexPtr(t, v.InitEphemeral),
		RemoteStatic: mustHexPtr(t, v.InitRemoteStatic),
		PSKs:         psks(v.InitPsks),
	})
	if err != nil {
		t.Fatalf("init handshake: %v", err)
	}
	rsp, err := NewHandshake(Config{
		Pattern:      patternName,
		Initiator:    false,
		Prologue:     mustHexPtr(t, v.RespPrologue),
		Static:       mustHexPtr(t, v.RespStatic),
		Ephemeral:    mustHexPtr(t, v.RespEphemeral),
		RemoteStatic: mustHexPtr(t, v.RespRemoteStatic),
		PSKs:         psks(v.RespPsks),
	})
	if err != nil {
		t.Fatalf("resp handshake: %v", err)
	}

	msgCount, err := MessageCount(patternName)
	if err != nil {
		t.Fatal(err)
	}
	oneWay := IsOneWay(patternName)

	var cIniSend, cIniRecv, cRspSend, cRspRecv *CipherState
	handshakeDone := false

	for i, m := range v.Messages {
		payload := mustHex(t, m.Payload)
		wantCT := mustHex(t, m.Ciphertext)

		if !handshakeDone {
			w, r := ini, rsp
			if writerIsInitiator(i) != true {
				w, r = rsp, ini
			}
			if !writerIsInitiator(i) && oneWay {
				t.Fatalf("one-way pattern cannot have responder handshake messages")
			}
			ct, doneW, err := w.WriteMessage(payload)
			if err != nil {
				t.Fatalf("message %d write: %v", i, err)
			}
			if !bytes.Equal(ct, wantCT) {
				t.Fatalf("message %d ciphertext mismatch:\n got %x\nwant %x", i, ct, wantCT)
			}
			pt, doneR, err := r.ReadMessage(ct)
			if err != nil {
				t.Fatalf("message %d read: %v", i, err)
			}
			if !bytes.Equal(pt, payload) {
				t.Fatalf("message %d payload mismatch", i)
			}
			if doneW != doneR {
				t.Fatalf("message %d: done disagreement", i)
			}
			if doneW {
				if i != msgCount-1 {
					t.Fatalf("handshake finished at message %d, pattern says %d", i, msgCount-1)
				}
				ik1, ik2, err := ini.Split()
				if err != nil {
					t.Fatal(err)
				}
				rk1, rk2, err := rsp.Split()
				if err != nil {
					t.Fatal(err)
				}
				if ik1 != rk1 || ik2 != rk2 {
					t.Fatalf("split keys disagree between roles")
				}
				if v.HandshakeHash != nil {
					want := mustHex(t, *v.HandshakeHash)
					if !bytes.Equal(ini.HandshakeHash(), want) || !bytes.Equal(rsp.HandshakeHash(), want) {
						t.Fatalf("handshake hash mismatch")
					}
				}
				cIniSend, cRspRecv = NewCipherState(ik1), NewCipherState(rk1)
				cRspSend, cIniRecv = NewCipherState(rk2), NewCipherState(ik2)
				handshakeDone = true
			}
			continue
		}

		// Transport messages: senders alternate with the message index
		// parity (initiator wrote message 0); one-way patterns only ever
		// send initiator→responder.
		senderIsInitiator := oneWay || writerIsInitiator(i)
		send, recv := cIniSend, cRspRecv
		if !senderIsInitiator {
			send, recv = cRspSend, cIniRecv
		}
		ct, err := send.EncryptWithAd(nil, payload)
		if err != nil {
			t.Fatalf("transport %d encrypt: %v", i, err)
		}
		if !bytes.Equal(ct, wantCT) {
			t.Fatalf("transport %d ciphertext mismatch:\n got %x\nwant %x", i, ct, wantCT)
		}
		pt, err := recv.DecryptWithAd(nil, ct)
		if err != nil {
			t.Fatalf("transport %d decrypt: %v", i, err)
		}
		if !bytes.Equal(pt, payload) {
			t.Fatalf("transport %d payload mismatch", i)
		}
	}
	if !handshakeDone {
		t.Fatalf("vector ended before handshake completed")
	}
}
