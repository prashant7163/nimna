// Package noise is a minimal Noise Protocol Framework engine (revision 34),
// implemented from the specification for the single suite Nimna uses:
// 25519_ChaChaPoly_SHA256. It exists to generate and validate the committed
// protocol test vectors (spec v0.2 §7 "Engine requirements"); it supports
// the fundamental handshake patterns plus psk modifiers so the engine can be
// validated against third-party vector sets (see thirdparty_test.go).
//
// Crypto comes exclusively from the Session-2-locked set: X25519
// (crypto/ecdh), ChaCha20-Poly1305 IETF (x/crypto/chacha20poly1305) and
// SHA-256/HMAC (stdlib). Nothing is hand-rolled below the Noise composition
// layer itself.
package noise

import (
	"crypto/ecdh"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"

	"golang.org/x/crypto/chacha20poly1305"
)

// dhLen is the X25519 public-key / shared-secret length.
const dhLen = 32

// hashLen is the SHA-256 output length.
const hashLen = 32

// TagLen is the ChaCha20-Poly1305 tag length.
const TagLen = 16

// dh computes X25519(priv, pub). Private keys are raw 32-byte scalars
// (clamping happens inside crypto/ecdh per RFC 7748).
func dh(priv, pub []byte) ([]byte, error) {
	sk, err := ecdh.X25519().NewPrivateKey(priv)
	if err != nil {
		return nil, err
	}
	pk, err := ecdh.X25519().NewPublicKey(pub)
	if err != nil {
		return nil, err
	}
	return sk.ECDH(pk)
}

// PublicKey returns the X25519 public key for a raw 32-byte private scalar.
func PublicKey(priv []byte) ([]byte, error) {
	sk, err := ecdh.X25519().NewPrivateKey(priv)
	if err != nil {
		return nil, err
	}
	return sk.PublicKey().Bytes(), nil
}

// noiseNonce encodes a Noise ChaChaPoly nonce: 4 zero bytes followed by
// n as 64-bit little-endian (Noise spec §12.3).
func noiseNonce(n uint64) []byte {
	var nonce [chacha20poly1305.NonceSize]byte
	binary.LittleEndian.PutUint64(nonce[4:], n)
	return nonce[:]
}

// aeadSeal is ENCRYPT(k, nonce, ad, plaintext).
func aeadSeal(key, nonce, ad, plaintext []byte) []byte {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		panic(err) // key is always 32 bytes here
	}
	return aead.Seal(nil, nonce, plaintext, ad)
}

// aeadOpen is DECRYPT(k, nonce, ad, ciphertext).
func aeadOpen(key, nonce, ad, ciphertext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		panic(err)
	}
	return aead.Open(nil, nonce, ciphertext, ad)
}

// hkdf is the Noise HKDF (spec §4.3): HMAC-SHA-256 extract-and-expand with
// zero-length info, returning numOutputs chained 32-byte outputs.
func hkdf(chainingKey, ikm []byte, numOutputs int) [][]byte {
	tempKey := hmacSHA256(chainingKey, ikm)
	out := make([][]byte, 0, numOutputs)
	prev := []byte{}
	for i := 1; i <= numOutputs; i++ {
		prev = hmacSHA256(tempKey, append(append([]byte{}, prev...), byte(i)))
		out = append(out, prev)
	}
	return out
}

func hmacSHA256(key []byte, data []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}

// cipherState is the Noise CipherState object (spec §5.1) with the standard
// Noise nonce encoding. Nimna's post-Split transport uses a different nonce
// and rekey discipline — see Transport in transport.go.
type cipherState struct {
	k      [32]byte
	hasKey bool
	n      uint64
}

func (c *cipherState) initializeKey(key []byte) {
	copy(c.k[:], key)
	c.hasKey = true
	c.n = 0
}

func (c *cipherState) encryptWithAd(ad, plaintext []byte) ([]byte, error) {
	if !c.hasKey {
		return append([]byte{}, plaintext...), nil
	}
	if c.n == maxNonce {
		return nil, errors.New("noise: nonce exhausted")
	}
	ct := aeadSeal(c.k[:], noiseNonce(c.n), ad, plaintext)
	c.n++
	return ct, nil
}

func (c *cipherState) decryptWithAd(ad, ciphertext []byte) ([]byte, error) {
	if !c.hasKey {
		return append([]byte{}, ciphertext...), nil
	}
	if c.n == maxNonce {
		return nil, errors.New("noise: nonce exhausted")
	}
	pt, err := aeadOpen(c.k[:], noiseNonce(c.n), ad, ciphertext)
	if err != nil {
		return nil, err
	}
	c.n++
	return pt, nil
}

// maxNonce (2^64-1) is reserved for rekey (Noise spec §5.1).
const maxNonce = ^uint64(0)

// CipherState is an exported Noise transport cipher state, used by the
// third-party vector tests for post-handshake transport messages.
type CipherState struct{ cs cipherState }

// NewCipherState returns a CipherState keyed with a 32-byte key.
func NewCipherState(key [32]byte) *CipherState {
	c := &CipherState{}
	c.cs.initializeKey(key[:])
	return c
}

// EncryptWithAd encrypts with the standard Noise nonce encoding.
func (c *CipherState) EncryptWithAd(ad, plaintext []byte) ([]byte, error) {
	return c.cs.encryptWithAd(ad, plaintext)
}

// DecryptWithAd decrypts with the standard Noise nonce encoding.
func (c *CipherState) DecryptWithAd(ad, ciphertext []byte) ([]byte, error) {
	return c.cs.decryptWithAd(ad, ciphertext)
}

// symmetricState is the Noise SymmetricState object (spec §5.2).
type symmetricState struct {
	cs cipherState
	ck [32]byte
	h  [32]byte
}

func newSymmetricState(protocolName string) *symmetricState {
	s := &symmetricState{}
	if len(protocolName) <= hashLen {
		copy(s.h[:], protocolName) // right-padded with zeros
	} else {
		s.h = sha256.Sum256([]byte(protocolName))
	}
	s.ck = s.h
	return s
}

func (s *symmetricState) mixKey(ikm []byte) {
	out := hkdf(s.ck[:], ikm, 2)
	copy(s.ck[:], out[0])
	s.cs.initializeKey(out[1])
}

func (s *symmetricState) mixHash(data []byte) {
	h := sha256.New()
	h.Write(s.h[:])
	h.Write(data)
	h.Sum(s.h[:0])
}

func (s *symmetricState) mixKeyAndHash(ikm []byte) {
	out := hkdf(s.ck[:], ikm, 3)
	copy(s.ck[:], out[0])
	s.mixHash(out[1])
	s.cs.initializeKey(out[2])
}

func (s *symmetricState) encryptAndHash(plaintext []byte) ([]byte, error) {
	ct, err := s.cs.encryptWithAd(s.h[:], plaintext)
	if err != nil {
		return nil, err
	}
	s.mixHash(ct)
	return ct, nil
}

func (s *symmetricState) decryptAndHash(ciphertext []byte) ([]byte, error) {
	pt, err := s.cs.decryptWithAd(s.h[:], ciphertext)
	if err != nil {
		return nil, err
	}
	s.mixHash(ciphertext)
	return pt, nil
}

func (s *symmetricState) split() (k1, k2 [32]byte) {
	out := hkdf(s.ck[:], nil, 2)
	copy(k1[:], out[0])
	copy(k2[:], out[1])
	return k1, k2
}

// Config describes one party of a handshake. All key material is supplied
// as fixed byte strings — the engine never generates randomness, which is
// what makes the committed vectors deterministic.
type Config struct {
	Pattern      string // e.g. "XX", "XXpsk2", "KK", "KKpsk0+psk2"
	Initiator    bool
	Prologue     []byte
	Static       []byte   // raw 32-byte X25519 private scalar, or nil
	Ephemeral    []byte   // raw 32-byte X25519 private scalar, or nil
	RemoteStatic []byte   // raw 32-byte X25519 public key, or nil
	PSKs         [][]byte // consumed in token order; each must be 32 bytes
}

// HandshakeState is the Noise HandshakeState object (spec §5.3).
type HandshakeState struct {
	ss        *symmetricState
	pat       pattern
	initiator bool

	s  []byte // local static private scalar
	e  []byte // local ephemeral private scalar
	rs []byte // remote static public
	re []byte // remote ephemeral public

	psks    [][]byte
	pskNext int

	msgIdx int
	done   bool
}

// ProtocolName assembles the full Noise protocol name for a pattern under
// Nimna's locked suite.
func ProtocolName(patternName string) string {
	return "Noise_" + patternName + "_25519_ChaChaPoly_SHA256"
}

// NewHandshake initializes a HandshakeState per Noise spec §5.3, including
// prologue and pre-message mixing.
func NewHandshake(cfg Config) (*HandshakeState, error) {
	pat, err := parsePattern(cfg.Pattern)
	if err != nil {
		return nil, err
	}
	for _, psk := range cfg.PSKs {
		if len(psk) != 32 {
			return nil, errors.New("noise: psk must be 32 bytes")
		}
	}
	hs := &HandshakeState{
		ss:        newSymmetricState(ProtocolName(cfg.Pattern)),
		pat:       pat,
		initiator: cfg.Initiator,
		s:         cfg.Static,
		e:         cfg.Ephemeral,
		rs:        cfg.RemoteStatic,
		psks:      cfg.PSKs,
	}
	hs.ss.mixHash(cfg.Prologue)

	// Pre-messages: initiator's pre-message pattern first, then the
	// responder's (spec §7.1); only public keys are hashed.
	mixPre := func(tokens []token, local bool) error {
		for _, t := range tokens {
			var pub []byte
			switch t {
			case tokS:
				if local {
					if hs.s == nil {
						return errors.New("noise: pre-message s requires local static")
					}
					p, err := PublicKey(hs.s)
					if err != nil {
						return err
					}
					pub = p
				} else {
					if hs.rs == nil {
						return errors.New("noise: pre-message s requires remote static")
					}
					pub = hs.rs
				}
			case tokE:
				return errors.New("noise: pre-message e unsupported (fundamental patterns only)")
			default:
				return errors.New("noise: invalid pre-message token")
			}
			hs.ss.mixHash(pub)
		}
		return nil
	}
	if err := mixPre(pat.preI, cfg.Initiator); err != nil {
		return nil, err
	}
	if err := mixPre(pat.preR, !cfg.Initiator); err != nil {
		return nil, err
	}
	return hs, nil
}

func (hs *HandshakeState) nextPSK() ([]byte, error) {
	if hs.pskNext >= len(hs.psks) {
		return nil, errors.New("noise: psk token but no psk left")
	}
	p := hs.psks[hs.pskNext]
	hs.pskNext++
	return p, nil
}

// WriteMessage produces the next handshake message carrying payload.
// done is true once the final handshake message has been produced.
func (hs *HandshakeState) WriteMessage(payload []byte) (msg []byte, done bool, err error) {
	if hs.done || hs.msgIdx >= len(hs.pat.msgs) {
		return nil, false, errors.New("noise: handshake complete")
	}
	if writerIsInitiator(hs.msgIdx) != hs.initiator {
		return nil, false, errors.New("noise: not our turn to write")
	}
	var out []byte
	for _, t := range hs.pat.msgs[hs.msgIdx] {
		switch t {
		case tokE:
			if hs.e == nil {
				return nil, false, errors.New("noise: e token requires a fixed ephemeral")
			}
			epub, err := PublicKey(hs.e)
			if err != nil {
				return nil, false, err
			}
			out = append(out, epub...)
			hs.ss.mixHash(epub)
			if hs.pat.hasPSK {
				// psk-mode rule (spec §9.2): e also MixKeys its public key.
				hs.ss.mixKey(epub)
			}
		case tokS:
			spub, err := PublicKey(hs.s)
			if err != nil {
				return nil, false, err
			}
			ct, err := hs.ss.encryptAndHash(spub)
			if err != nil {
				return nil, false, err
			}
			out = append(out, ct...)
		case tokEE:
			if err := hs.mixDH(hs.e, hs.re); err != nil {
				return nil, false, err
			}
		case tokES:
			if err := hs.mixDHRole(hs.e, hs.rs, hs.s, hs.re); err != nil {
				return nil, false, err
			}
		case tokSE:
			if err := hs.mixDHRole(hs.s, hs.re, hs.e, hs.rs); err != nil {
				return nil, false, err
			}
		case tokSS:
			if err := hs.mixDH(hs.s, hs.rs); err != nil {
				return nil, false, err
			}
		case tokPSK:
			psk, err := hs.nextPSK()
			if err != nil {
				return nil, false, err
			}
			hs.ss.mixKeyAndHash(psk)
		}
	}
	ct, err := hs.ss.encryptAndHash(payload)
	if err != nil {
		return nil, false, err
	}
	out = append(out, ct...)
	hs.msgIdx++
	hs.done = hs.msgIdx == len(hs.pat.msgs)
	return out, hs.done, nil
}

// ReadMessage consumes the next handshake message and returns its payload.
func (hs *HandshakeState) ReadMessage(msg []byte) (payload []byte, done bool, err error) {
	if hs.done || hs.msgIdx >= len(hs.pat.msgs) {
		return nil, false, errors.New("noise: handshake complete")
	}
	if writerIsInitiator(hs.msgIdx) == hs.initiator {
		return nil, false, errors.New("noise: not our turn to read")
	}
	rest := msg
	take := func(n int) ([]byte, error) {
		if len(rest) < n {
			return nil, errors.New("noise: message too short")
		}
		b := rest[:n]
		rest = rest[n:]
		return b, nil
	}
	for _, t := range hs.pat.msgs[hs.msgIdx] {
		switch t {
		case tokE:
			epub, err := take(dhLen)
			if err != nil {
				return nil, false, err
			}
			hs.re = append([]byte{}, epub...)
			hs.ss.mixHash(hs.re)
			if hs.pat.hasPSK {
				hs.ss.mixKey(hs.re)
			}
		case tokS:
			n := dhLen
			if hs.ss.cs.hasKey {
				n += TagLen
			}
			ct, err := take(n)
			if err != nil {
				return nil, false, err
			}
			spub, err := hs.ss.decryptAndHash(ct)
			if err != nil {
				return nil, false, err
			}
			hs.rs = spub
		case tokEE:
			if err := hs.mixDH(hs.e, hs.re); err != nil {
				return nil, false, err
			}
		case tokES:
			if err := hs.mixDHRole(hs.e, hs.rs, hs.s, hs.re); err != nil {
				return nil, false, err
			}
		case tokSE:
			if err := hs.mixDHRole(hs.s, hs.re, hs.e, hs.rs); err != nil {
				return nil, false, err
			}
		case tokSS:
			if err := hs.mixDH(hs.s, hs.rs); err != nil {
				return nil, false, err
			}
		case tokPSK:
			psk, err := hs.nextPSK()
			if err != nil {
				return nil, false, err
			}
			hs.ss.mixKeyAndHash(psk)
		}
	}
	pt, err := hs.ss.decryptAndHash(rest)
	if err != nil {
		return nil, false, err
	}
	hs.msgIdx++
	hs.done = hs.msgIdx == len(hs.pat.msgs)
	return pt, hs.done, nil
}

// mixDH mixes DH(priv, pub) into the key schedule.
func (hs *HandshakeState) mixDH(priv, pub []byte) error {
	if priv == nil || pub == nil {
		return errors.New("noise: DH key material missing")
	}
	ss, err := dh(priv, pub)
	if err != nil {
		return err
	}
	hs.ss.mixKey(ss)
	return nil
}

// mixDHRole picks the DH operands by role: the initiator uses
// (privI, pubI), the responder (privR, pubR). For "es" the initiator mixes
// DH(e, rs) and the responder DH(s, re); for "se" the reverse (spec §7.1).
func (hs *HandshakeState) mixDHRole(privI, pubI, privR, pubR []byte) error {
	if hs.initiator {
		return hs.mixDH(privI, pubI)
	}
	return hs.mixDH(privR, pubR)
}

func writerIsInitiator(msgIdx int) bool { return msgIdx%2 == 0 }

// Split returns the two 32-byte transport keys: k1 for initiator→responder
// traffic, k2 for responder→initiator (Noise spec §5.2: the first
// CipherState is for messages sent by the initiator).
func (hs *HandshakeState) Split() (k1, k2 [32]byte, err error) {
	if !hs.done {
		return k1, k2, errors.New("noise: handshake not complete")
	}
	k1, k2 = hs.ss.split()
	return k1, k2, nil
}

// ChainingKey exposes the current ck for vector emission.
func (hs *HandshakeState) ChainingKey() []byte { return append([]byte{}, hs.ss.ck[:]...) }

// HandshakeHash exposes the current h for vector emission.
func (hs *HandshakeState) HandshakeHash() []byte { return append([]byte{}, hs.ss.h[:]...) }

// RemoteStatic returns the remote static public key learned so far.
func (hs *HandshakeState) RemoteStatic() []byte { return append([]byte{}, hs.rs...) }

// Err helper for formatted errors (kept tiny; avoids importing fmt widely).
func errf(format string, args ...any) error { return fmt.Errorf(format, args...) }
