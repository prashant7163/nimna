package vectors

import (
	"encoding/hex"
	"math/big"

	"nimna.app/test-vectors/generator/internal/derive"
)

// phrase-words.json — spec §3.1.4 (safety-phrase rendering).

type phraseCaseJSON struct {
	Name       string    `json:"name"`
	HKDFOutput string    `json:"hkdf_output"`
	N          string    `json:"n"`
	Indices    [3]int    `json:"indices"`
	Words      [3]string `json:"words"`
	Note       string    `json:"note,omitempty"`
}

type phraseWordlistJSON struct {
	File   string `json:"file"`
	SHA256 string `json:"sha256"`
	Size   int    `json:"size"`
	Source string `json:"source"`
}

type phraseFileJSON struct {
	Purpose  string             `json:"_purpose"`
	Spec     string             `json:"_spec"`
	Wordlist phraseWordlistJSON `json:"wordlist"`
	Mapping  string             `json:"mapping"`
	Cases    []phraseCaseJSON   `json:"cases"`
}

func genPhraseWords(words []string) (*phraseFileJSON, error) {
	mk := func(name, hexOut, note string) (phraseCaseJSON, error) {
		out, err := hex.DecodeString(hexOut)
		if err != nil {
			return phraseCaseJSON{}, err
		}
		indices := derive.PhraseIndices(out)
		w, err := derive.PhraseWords(indices, words)
		if err != nil {
			return phraseCaseJSON{}, err
		}
		return phraseCaseJSON{
			Name:       name,
			HKDFOutput: hexOut,
			N:          new(big.Int).SetBytes(out).String(),
			Indices:    indices,
			Words:      w,
			Note:       note,
		}, nil
	}

	arbitrary := hexs(fixed32("phrase/arbitrary-1")[:8])
	specs := []struct{ name, hexOut, note string }{
		{"all-zero", "0000000000000000",
			"n = 0 → indices [0,0,0] → wordlist[0] three times."},
		{"n-1", "0000000000000001", "Least-significant digit only."},
		{"n-1295", "000000000000050f", "Last index of the least-significant digit."},
		{"n-1296", "0000000000000510", "Carries into the middle digit."},
		{"max-in-range", "0000000081bf0fff",
			"n = 1296^3 - 1 → [1295,1295,1295] → the last word three times."},
		{"wraps-word0", "0000000081bf1000",
			"n = 1296^3: word0 = (n ÷ 1296²) mod 1296 = 0 — the modulo on the most-significant digit matters because n is a full uint64."},
		{"max-uint64", "ffffffffffffffff",
			"n = 2^64 - 1, the largest 8-byte value; exercises the modulo path on all three digits."},
		{"arbitrary", arbitrary,
			"An arbitrary fixed value (first 8 bytes of SHA-256(\"nimna/test-vectors/v1/phrase/arbitrary-1\"))."},
	}
	file := &phraseFileJSON{
		Purpose: "Safety-phrase mapping: 8 HKDF output bytes → uint64 (big-endian) → " +
			"three base-1296 digits, most-significant first → wordlist indices → words. " +
			"End-to-end derivations from key material live in pairing-handshake.json.",
		Spec: SpecRef + " §3.1.4",
		Wordlist: phraseWordlistJSON{
			File:   "wordlist-en-v1.txt",
			SHA256: WordlistSHA256,
			Size:   derive.WordlistSize,
			Source: "EFF short wordlist 2.0 (dice indices stripped); one global wordlist, rendered identically in all locales",
		},
		Mapping: "n = uint64 big-endian from the 8 bytes; word0 = (n ÷ 1296²) mod 1296, " +
			"word1 = (n ÷ 1296) mod 1296, word2 = n mod 1296; rendered lowercase in derivation order",
	}
	for _, s := range specs {
		c, err := mk(s.name, s.hexOut, s.note)
		if err != nil {
			return nil, err
		}
		file.Cases = append(file.Cases, c)
	}
	return file, nil
}
