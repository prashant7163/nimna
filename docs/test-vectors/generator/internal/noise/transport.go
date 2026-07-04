package noise

import "encoding/binary"

// This file implements Nimna's post-Split transport discipline
// (spec v0.2 §3.3.1, §5.6) — NOT the generic Noise transport:
//
//   - nonce = 32-bit big-endian direction constant ‖ 64-bit big-endian
//     counter (initiator→responder 0x00000000, responder→initiator
//     0x00000001); counters start at 0, strict increment, never reset;
//   - ad = the 18-byte outer frame header;
//   - after every encrypt (and, on the receiver, every successful
//     decrypt), the direction key is replaced via the Noise REKEY function
//     (Noise spec §11.3).

// Direction constants (spec §5.6).
const (
	DirInitiatorToResponder uint32 = 0x00000000
	DirResponderToInitiator uint32 = 0x00000001
)

// ForbiddenCounter is the reserved counter value 2^64-1: its nonce would
// collide with the rekey nonce, so it must never be used (spec §3.3.1).
const ForbiddenCounter = ^uint64(0)

// TransportNonce encodes a Nimna transport nonce.
func TransportNonce(direction uint32, counter uint64) [12]byte {
	var n [12]byte
	binary.BigEndian.PutUint32(n[0:4], direction)
	binary.BigEndian.PutUint64(n[4:12], counter)
	return n
}

// Rekey is the Noise REKEY function (Noise spec §11.3): the first 32 bytes
// of ENCRYPT(k, maxnonce, zero-length ad, 32 zero bytes). For ChaChaPoly the
// maxnonce encoding is 4 zero bytes ‖ 0xFFFFFFFFFFFFFFFF — endian-agnostic,
// as the spec notes.
func Rekey(k [32]byte) [32]byte {
	nonce := TransportNonce(0, ForbiddenCounter) // 00000000 ‖ ff…ff
	ct := aeadSeal(k[:], nonce[:], nil, make([]byte, 32))
	var out [32]byte
	copy(out[:], ct[:32])
	return out
}

// SealRecord captures everything about one sealed transport frame, so the
// generator can emit per-frame keys, nonces and ciphertexts.
type SealRecord struct {
	Direction  uint32
	Counter    uint64
	Nonce      [12]byte
	KeyBefore  [32]byte
	Ciphertext []byte
	KeyAfter   [32]byte
}

// Transport is one direction of a Nimna transport channel.
type Transport struct {
	key     [32]byte
	dir     uint32
	counter uint64
}

// NewTransport starts a direction with its post-Split key and direction
// constant.
func NewTransport(key [32]byte, direction uint32) *Transport {
	return &Transport{key: key, dir: direction}
}

// Seal encrypts one frame under the current key and counter, then rekeys.
func (t *Transport) Seal(ad, plaintext []byte) SealRecord {
	if t.counter == ForbiddenCounter {
		panic("nimna transport: forbidden counter 2^64-1")
	}
	rec := SealRecord{
		Direction: t.dir,
		Counter:   t.counter,
		Nonce:     TransportNonce(t.dir, t.counter),
		KeyBefore: t.key,
	}
	rec.Ciphertext = aeadSeal(t.key[:], rec.Nonce[:], ad, plaintext)
	t.key = Rekey(t.key)
	rec.KeyAfter = t.key
	t.counter++
	return rec
}

// Open decrypts one frame under the current key and counter, then rekeys.
// Any AEAD failure is fatal to the session per spec §3.3.1; here it simply
// returns the error to the caller (the generator treats it as a bug).
func (t *Transport) Open(ad, ciphertext []byte) ([]byte, error) {
	if t.counter == ForbiddenCounter {
		panic("nimna transport: forbidden counter 2^64-1")
	}
	nonce := TransportNonce(t.dir, t.counter)
	pt, err := aeadOpen(t.key[:], nonce[:], ad, ciphertext)
	if err != nil {
		return nil, err
	}
	t.key = Rekey(t.key)
	t.counter++
	return pt, nil
}
