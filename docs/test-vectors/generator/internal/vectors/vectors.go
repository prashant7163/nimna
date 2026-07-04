// Package vectors deterministically generates the committed protocol test
// vectors in docs/test-vectors/ (spec v0.2 §7: both implementations must
// reproduce them byte-for-byte).
//
// Determinism rules:
//   - No randomness and no clock anywhere. Every input — keys, ephemerals,
//     msg_ids, timestamps, codes, dates, tokens — is a fixed constant.
//     Byte-string constants are derived as SHA-256 of readable ASCII
//     labels ("nimna/test-vectors/v1/…"), so they are reproducible from
//     source and visibly non-degenerate; their values appear verbatim in
//     the emitted JSON.
//   - JSON is emitted from structs only (never maps), so field order is
//     fixed; encoding/json output is byte-stable across runs and
//     platforms. Files end with a trailing newline.
package vectors

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"nimna.app/test-vectors/generator/internal/derive"
)

// WordlistSHA256 pins the committed wordlist file
// (docs/test-vectors/wordlist-en-v1.txt, EFF short wordlist 2.0, dice
// indices stripped). The hash is normative alongside the vectors
// (spec §3.1.4).
const WordlistSHA256 = "7aa57a4d3ecf6581729992bad9575bacdebf7c28378af2aec6a50f11aec326f5"

// SpecRef names the spec version these vectors are generated from.
const SpecRef = "nimna-protocol-spec-v0.2.md"

// Generate writes all five JSON vector files into outDir, reading the
// pinned wordlist from wordlistPath and verifying its SHA-256 first.
func Generate(outDir, wordlistPath string) error {
	raw, err := os.ReadFile(wordlistPath)
	if err != nil {
		return fmt.Errorf("wordlist: %w", err)
	}
	if got := sha256.Sum256(raw); hex.EncodeToString(got[:]) != WordlistSHA256 {
		return fmt.Errorf("wordlist: SHA-256 mismatch: got %x, pinned %s — the wordlist is pinned and must not drift", got, WordlistSHA256)
	}
	words, err := derive.ParseWordlist(raw)
	if err != nil {
		return fmt.Errorf("wordlist: %w", err)
	}

	topicFile, seeds := genTopicDerivation()
	if err := writeJSON(filepath.Join(outDir, "topic-derivation.json"), topicFile); err != nil {
		return err
	}
	pairingFile, channels, err := genPairingHandshake(words, seeds)
	if err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(outDir, "pairing-handshake.json"), pairingFile); err != nil {
		return err
	}
	sessionFile, err := genSessionHandshake(channels)
	if err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(outDir, "session-handshake.json"), sessionFile); err != nil {
		return err
	}
	phraseFile, err := genPhraseWords(words)
	if err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(outDir, "phrase-words.json"), phraseFile); err != nil {
		return err
	}
	framingFile, err := genFraming()
	if err != nil {
		return err
	}
	return writeJSON(filepath.Join(outDir, "framing.json"), framingFile)
}

// Files lists the JSON files Generate writes (used by the regeneration
// test and documented in the README).
var Files = []string{
	"topic-derivation.json",
	"pairing-handshake.json",
	"session-handshake.json",
	"phrase-words.json",
	"framing.json",
}

// writeJSON marshals v with two-space indentation, HTML escaping off (the
// vectors contain "->" and "‖" in prose), and a trailing newline.
func writeJSON(path string, v any) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil { // Encode appends the trailing newline
		return err
	}
	return os.WriteFile(path, buf.Bytes(), 0o644)
}

// hexs is the one hex encoding used everywhere in the vectors: lowercase,
// no separators.
func hexs(b []byte) string { return hex.EncodeToString(b) }

// fixed32 derives a fixed 32-byte constant from a readable label.
func fixed32(label string) []byte {
	sum := sha256.Sum256([]byte("nimna/test-vectors/v1/" + label))
	return sum[:]
}

// fixed16 derives a fixed 16-byte constant from a readable label.
func fixed16(label string) [16]byte {
	var out [16]byte
	copy(out[:], fixed32(label))
	return out
}

// stream derives n deterministic bytes from a label (SHA-256 counter mode).
func stream(label string, n int) []byte {
	out := make([]byte, 0, n)
	var ctr [4]byte
	for i := 0; len(out) < n; i++ {
		binary.BigEndian.PutUint32(ctr[:], uint32(i))
		sum := sha256.Sum256(append([]byte("nimna/test-vectors/v1/"+label+"/"), ctr[:]...))
		out = append(out, sum[:]...)
	}
	return out[:n]
}

// Fixed timestamps (Unix milliseconds). Base: 2026-07-04T12:00:00Z; each
// vector states its value explicitly, so these are constants, not clock
// reads.
const tsBase = uint64(1783166400000)
