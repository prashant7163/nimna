// Package derive implements Nimna's deterministic derivations from spec
// v0.2: pairing-code canonicalization (§3.1.1), rendezvous topic and psk
// (§3.1.2), commitment M0 (§3.1.3), safety phrase (§3.1.4) and CRID
// (§3.1.5). All primitives are from the Session-2-locked set.
package derive

import (
	"bytes"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Alphabet is the 32-character Crockford Base32 alphabet (no I, L, O, U).
const Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// CodeLen is the fixed canonical code length in bytes.
const CodeLen = 9

// Canonicalize maps raw user input to the canonical 9-byte code form
// (spec §3.1.1): strip whitespace and hyphens, fold to uppercase, map
// I→1, L→1, O→0. U is not in the alphabet and is rejected, never mapped.
// Anything that does not canonicalize to exactly 9 alphabet characters is
// invalid.
func Canonicalize(input string) (string, error) {
	var b strings.Builder
	for _, r := range input {
		switch {
		case r == '-' || r == ' ' || r == '\t' || r == '\n' || r == '\r':
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
		if !strings.ContainsRune(Alphabet, r) {
			return "", errors.New("code: invalid character")
		}
		b.WriteRune(r)
	}
	if b.Len() != CodeLen {
		return "", errors.New("code: canonical form must be exactly 9 characters")
	}
	return b.String(), nil
}

// Argon2Params are the Argon2id cost parameters. MemoryKiB follows the
// x/crypto convention (KiB); the spec's m = 64 MiB is 65536 KiB.
type Argon2Params struct {
	Time      uint32
	MemoryKiB uint32
	Threads   uint8
	OutLen    uint32
}

// ProductionParams are the fixed protocol constants (spec §3.1.2):
// Argon2id v1.3, t=3, m=64 MiB, p=1, 32-byte output.
var ProductionParams = Argon2Params{Time: 3, MemoryKiB: 64 * 1024, Threads: 1, OutLen: 32}

// ReducedParams is a REDUCED-COST parameter set for fast unit tests only
// (t=1, m=8 MiB). It appears in the vectors clearly labeled; it is never a
// protocol constant.
var ReducedParams = Argon2Params{Time: 1, MemoryKiB: 8 * 1024, Threads: 1, OutLen: 32}

// TopicSaltPreimage returns the ASCII salt preimage "nimna/topic/v1|" + date.
func TopicSaltPreimage(date string) []byte {
	return []byte("nimna/topic/v1|" + date)
}

// TopicSalt derives the 16-byte Argon2id salt from the UTC creation date
// ("YYYY-MM-DD"): SHA-256("nimna/topic/v1|" + date)[0:16].
func TopicSalt(date string) []byte {
	sum := sha256.Sum256(TopicSaltPreimage(date))
	return sum[:16]
}

// Seed runs Argon2id over the canonical code bytes with the date salt.
func Seed(canonicalCode string, salt []byte, p Argon2Params) []byte {
	return argon2.IDKey([]byte(canonicalCode), salt, p.Time, p.MemoryKiB, p.Threads, p.OutLen)
}

// hkdfSHA256 is HKDF-SHA-256 (RFC 5869) via the stdlib.
func hkdfSHA256(ikm, salt []byte, info string, outLen int) []byte {
	out, err := hkdf.Key(sha256.New, ikm, salt, info, outLen)
	if err != nil {
		panic(err) // only fails for absurd output lengths
	}
	return out
}

// Topic derives the 16-byte rendezvous topic from the seed:
// HKDF-SHA-256(ikm=seed, salt=empty, info="nimna/topic/v1")[0:16].
func Topic(seed []byte) []byte { return hkdfSHA256(seed, nil, "nimna/topic/v1", 16) }

// PSK derives the 32-byte pairing psk from the seed:
// HKDF-SHA-256(ikm=seed, salt=empty, info="nimna/psk/v1")[0:32].
func PSK(seed []byte) []byte { return hkdfSHA256(seed, nil, "nimna/psk/v1", 32) }

// CommitLabel is the ASCII label of the commitment preimage (15 bytes).
const CommitLabel = "nimna/commit/v1"

// CommitmentPreimage returns the 79-byte M0 preimage
// "nimna/commit/v1" ‖ eB_pub ‖ sB_pub (spec §3.1.3).
func CommitmentPreimage(joinerEphemeralPub, joinerStaticPub []byte) []byte {
	pre := make([]byte, 0, len(CommitLabel)+64)
	pre = append(pre, CommitLabel...)
	pre = append(pre, joinerEphemeralPub...)
	pre = append(pre, joinerStaticPub...)
	return pre
}

// Commitment computes M0 = SHA-256(preimage) (32 bytes, the Noise prologue
// of the pairing handshake).
func Commitment(joinerEphemeralPub, joinerStaticPub []byte) []byte {
	sum := sha256.Sum256(CommitmentPreimage(joinerEphemeralPub, joinerStaticPub))
	return sum[:]
}

// SharedSecret computes ss = X25519(own static private, peer static public)
// — identical on both ends (spec §3.1.4).
func SharedSecret(ownStaticPriv, peerStaticPub []byte) ([]byte, error) {
	sk, err := ecdh.X25519().NewPrivateKey(ownStaticPriv)
	if err != nil {
		return nil, err
	}
	pk, err := ecdh.X25519().NewPublicKey(peerStaticPub)
	if err != nil {
		return nil, err
	}
	return sk.ECDH(pk)
}

// Salt2 computes salt2 = SHA-256(min(A_pub,B_pub) ‖ max(A_pub,B_pub)) with
// lexicographic byte-order comparison of the two static public keys.
func Salt2(pubA, pubB []byte) []byte {
	lo, hi := pubA, pubB
	if bytes.Compare(lo, hi) > 0 {
		lo, hi = hi, lo
	}
	h := sha256.New()
	h.Write(lo)
	h.Write(hi)
	return h.Sum(nil)
}

// CRID derives the 16-byte channel routing ID:
// HKDF-SHA-256(ikm=ss, salt=salt2, info="nimna/crid/v1")[0:16] (spec §3.1.5).
func CRID(ss, salt2 []byte) []byte { return hkdfSHA256(ss, salt2, "nimna/crid/v1", 16) }

// PhraseBytes derives the 8 phrase bytes:
// HKDF-SHA-256(ikm=ss, salt=salt2, info="nimna/phrase/v1")[0:8] (spec §3.1.4).
func PhraseBytes(ss, salt2 []byte) []byte { return hkdfSHA256(ss, salt2, "nimna/phrase/v1", 8) }

// WordlistSize is the fixed size of the phrase wordlist (EFF short
// wordlist 2.0).
const WordlistSize = 1296

// PhraseIndices maps the 8 phrase bytes to the three wordlist indices:
// n = uint64 big-endian, then three base-1296 digits most-significant
// first (spec §3.1.4).
func PhraseIndices(out8 []byte) [3]int {
	n := binary.BigEndian.Uint64(out8)
	return [3]int{
		int((n / (WordlistSize * WordlistSize)) % WordlistSize),
		int((n / WordlistSize) % WordlistSize),
		int(n % WordlistSize),
	}
}

// PhraseWords resolves indices against a 1296-word list.
func PhraseWords(indices [3]int, wordlist []string) ([3]string, error) {
	var w [3]string
	if len(wordlist) != WordlistSize {
		return w, errors.New("phrase: wordlist must have exactly 1296 words")
	}
	for i, idx := range indices {
		w[i] = wordlist[idx]
	}
	return w, nil
}

// ParseWordlist splits the pinned wordlist file (one word per line, LF
// endings, trailing newline) and validates its shape.
func ParseWordlist(content []byte) ([]string, error) {
	if len(content) == 0 || content[len(content)-1] != '\n' {
		return nil, errors.New("wordlist: must end with a trailing LF")
	}
	if bytes.Contains(content, []byte{'\r'}) {
		return nil, errors.New("wordlist: must use LF line endings")
	}
	words := strings.Split(strings.TrimSuffix(string(content), "\n"), "\n")
	if len(words) != WordlistSize {
		return nil, errors.New("wordlist: must contain exactly 1296 words")
	}
	for _, w := range words {
		if w == "" {
			return nil, errors.New("wordlist: empty line")
		}
	}
	return words, nil
}
