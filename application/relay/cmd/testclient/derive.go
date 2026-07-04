// Rendezvous derivation — spec §3.1.1 (code canonicalization) and §3.1.2
// (topic derivation). This is CLIENT-side logic: it lives inside
// cmd/testclient and must never leak into relay packages — the relay
// never derives topics (routing_ids are opaque 16-byte values) and its
// import graph stays x/crypto-free.
package main

import (
	"crypto/hkdf"
	"crypto/sha256"
	"errors"
	"strings"

	"golang.org/x/crypto/argon2"
)

// crockfordAlphabet is the 32-character Crockford Base32 alphabet
// (no I, L, O, U) — fixed permanently (spec §3.1.1, §4).
const crockfordAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// codeLen is the canonical code length: exactly 9 ASCII bytes.
const codeLen = 9

// canonicalize maps raw user input to the canonical 9-byte code form
// (spec §3.1.1): strip whitespace (ASCII space, tab, CR, LF) and hyphens,
// fold to uppercase, map I→1, L→1, O→0 (Crockford decode rules). U is not
// in the alphabet and is rejected, never mapped. Anything that does not
// canonicalize to exactly 9 alphabet characters is invalid input —
// client-side error, nothing is sent.
func canonicalize(input string) (string, error) {
	var b strings.Builder
	for _, r := range input {
		switch {
		case r == '-' || r == ' ' || r == '\t' || r == '\r' || r == '\n':
			continue
		case r >= 'a' && r <= 'z':
			r = r - 'a' + 'A'
		}
		switch r {
		case 'I', 'L':
			r = '1'
		case 'O':
			r = '0'
		}
		if !strings.ContainsRune(crockfordAlphabet, r) {
			return "", errors.New("code: invalid character")
		}
		b.WriteRune(r)
	}
	if b.Len() != codeLen {
		return "", errors.New("code: canonical form must be exactly 9 characters")
	}
	return b.String(), nil
}

// argonParams are Argon2id cost parameters. MemoryKiB follows the
// x/crypto convention; the spec's m = 64 MiB is 65536 KiB.
type argonParams struct {
	time      uint32
	memoryKiB uint32
	threads   uint8
	outLen    uint32
}

// productionParams are the fixed protocol constants (spec §3.1.2):
// Argon2id v1.3, t=3, m=64 MiB, p=1, 32-byte output.
var productionParams = argonParams{time: 3, memoryKiB: 64 * 1024, threads: 1, outLen: 32}

// reducedParams is the REDUCED-COST parameter set from the committed
// vectors — for fast unit tests ONLY, never a protocol constant.
var reducedParams = argonParams{time: 1, memoryKiB: 8 * 1024, threads: 1, outLen: 32}

// topicSalt derives the 16-byte Argon2id salt from the UTC creation date
// ("YYYY-MM-DD"): SHA-256("nimna/topic/v1|" + date)[0:16].
func topicSalt(date string) []byte {
	sum := sha256.Sum256([]byte("nimna/topic/v1|" + date))
	return sum[:16]
}

// deriveSeed runs Argon2id over the canonical code bytes with the date
// salt (spec §3.1.2).
func deriveSeed(canonical string, salt []byte, p argonParams) []byte {
	return argon2.IDKey([]byte(canonical), salt, p.time, p.memoryKiB, p.threads, p.outLen)
}

// hkdfSHA256 is HKDF-SHA-256 (RFC 5869) via the stdlib, zero-length salt.
func hkdfSHA256(ikm []byte, info string, outLen int) []byte {
	out, err := hkdf.Key(sha256.New, ikm, nil, info, outLen)
	if err != nil {
		panic(err) // only possible for absurd output lengths
	}
	return out
}

// deriveTopic composes the full §3.1.2 topic derivation for a canonical
// code and UTC date: salt → Argon2id seed → HKDF expansion, first 16
// bytes.
func deriveTopic(canonical, date string, p argonParams) [16]byte {
	seed := deriveSeed(canonical, topicSalt(date), p)
	var topic [16]byte
	copy(topic[:], hkdfSHA256(seed, "nimna/topic/v1", 16))
	return topic
}
