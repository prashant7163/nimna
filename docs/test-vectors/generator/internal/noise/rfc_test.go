package noise

import (
	"bytes"
	stdhkdf "crypto/hkdf"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

// RFC validation of the primitives exactly as this engine invokes them.

// RFC 8439 §2.8.2 — ChaCha20-Poly1305 AEAD encryption test vector.
func TestChaCha20Poly1305RFC8439Encrypt(t *testing.T) {
	key := mustHex(t, "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
	nonce := mustHex(t, "070000004041424344454647")
	aad := mustHex(t, "50515253c0c1c2c3c4c5c6c7")
	plaintext := []byte("Ladies and Gentlemen of the class of '99: If I could offer you " +
		"only one tip for the future, sunscreen would be it.")
	wantCT := mustHex(t, strings.ReplaceAll(`
		d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6
		3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36
		92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc
		3ff4def08e4b7a9de576d26586cec64b6116`, "\n\t\t", ""))
	wantTag := mustHex(t, "1ae10b594f09e26a7e902ecbd0600691")

	got := aeadSeal(key, nonce, aad, plaintext)
	if !bytes.Equal(got, append(append([]byte{}, wantCT...), wantTag...)) {
		t.Fatalf("RFC 8439 §2.8.2 mismatch:\n got %x", got)
	}
	back, err := aeadOpen(key, nonce, aad, got)
	if err != nil || !bytes.Equal(back, plaintext) {
		t.Fatalf("round-trip failed: %v", err)
	}
}

// RFC 8439 A.5 — ChaCha20-Poly1305 AEAD decryption test vector.
func TestChaCha20Poly1305RFC8439Decrypt(t *testing.T) {
	key := mustHex(t, "1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0")
	nonce := mustHex(t, "000000000102030405060708")
	aad := mustHex(t, "f33388860000000000004e91")
	ct := mustHex(t, strings.ReplaceAll(`
		64a0861575861af460f062c79be643bd5e805cfd345cf389f108670ac76c8cb2
		4c6cfc18755d43eea09ee94e382d26b0bdb7b73c321b0100d4f03b7f355894cf
		332f830e710b97ce98c8a84abd0b948114ad176e008d33bd60f982b1ff37c855
		9797a06ef4f0ef61c186324e2b3506383606907b6a7c02b0f9f6157b53c867e4
		b9166c767b804d46a59b5216cde7a4e99040c5a40433225ee282a1b0a06c523e
		af4534d7f83fa1155b0047718cbc546a0d072b04b3564eea1b422273f548271a
		0bb2316053fa76991955ebd63159434ecebb4e466dae5a1073a6727627097a10
		49e617d91d361094fa68f0ff77987130305beaba2eda04df997b714d6c6f2c29
		a6ad5cb4022b02709b`, "\n\t\t", ""))
	tag := mustHex(t, "eead9d67890cbb22392336fea1851f38")
	wantPT := []byte("Internet-Drafts are draft documents valid for a maximum of six months " +
		"and may be updated, replaced, or obsoleted by other documents at any time. " +
		"It is inappropriate to use Internet-Drafts as reference material or to cite " +
		"them other than as /“work in progress./”")

	pt, err := aeadOpen(key, nonce, aad, append(ct, tag...))
	if err != nil {
		t.Fatalf("RFC 8439 A.5 decrypt failed: %v", err)
	}
	if !bytes.Equal(pt, wantPT) {
		t.Fatalf("RFC 8439 A.5 plaintext mismatch:\n got %q", pt)
	}
}

// RFC 7748 §5.2 — X25519 scalar-multiplication test vectors.
func TestX25519RFC7748Section52(t *testing.T) {
	cases := []struct{ scalar, u, want string }{
		{
			"a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
			"e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
			"c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
		},
		{
			"4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
			"e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
			"95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
		},
	}
	for i, c := range cases {
		got, err := dh(mustHex(t, c.scalar), mustHex(t, c.u))
		if err != nil {
			t.Fatalf("vector %d: %v", i, err)
		}
		if hex.EncodeToString(got) != c.want {
			t.Fatalf("vector %d mismatch: got %x", i, got)
		}
	}
}

// RFC 7748 §5.2 — iterated X25519 (1 and 1,000 iterations; the RFC's
// 1,000,000-iteration value is omitted for test-runtime reasons).
func TestX25519RFC7748Iterated(t *testing.T) {
	k := mustHex(t, "0900000000000000000000000000000000000000000000000000000000000000")
	u := append([]byte{}, k...)
	step := func() {
		out, err := dh(k, u)
		if err != nil {
			t.Fatal(err)
		}
		u, k = k, out
	}
	step()
	if hex.EncodeToString(k) != "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079" {
		t.Fatalf("after 1 iteration: got %x", k)
	}
	for i := 1; i < 1000; i++ {
		step()
	}
	if hex.EncodeToString(k) != "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51" {
		t.Fatalf("after 1000 iterations: got %x", k)
	}
}

// RFC 7748 §6.1 — X25519 Diffie-Hellman test.
func TestX25519RFC7748DH(t *testing.T) {
	alicePriv := mustHex(t, "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
	bobPriv := mustHex(t, "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
	alicePub, err := PublicKey(alicePriv)
	if err != nil {
		t.Fatal(err)
	}
	bobPub, err := PublicKey(bobPriv)
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(alicePub) != "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a" {
		t.Fatalf("alice pub mismatch: %x", alicePub)
	}
	if hex.EncodeToString(bobPub) != "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f" {
		t.Fatalf("bob pub mismatch: %x", bobPub)
	}
	const wantShared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
	s1, err := dh(alicePriv, bobPub)
	if err != nil {
		t.Fatal(err)
	}
	s2, err := dh(bobPriv, alicePub)
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(s1) != wantShared || hex.EncodeToString(s2) != wantShared {
		t.Fatalf("shared secret mismatch: %x / %x", s1, s2)
	}
}

// The Noise HKDF (§4.3 of the Noise spec) must equal RFC 5869
// extract-then-expand with zero-length info; cross-check against the
// stdlib implementation the derivation code uses.
func TestNoiseHKDFMatchesRFC5869(t *testing.T) {
	ck := mustHex(t, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	ikm := mustHex(t, "4a6f686e2047616c74")
	for _, n := range []int{2, 3} {
		got := hkdf(ck, ikm, n)
		want, err := stdhkdf.Key(sha256.New, ikm, ck, "", 32*n)
		if err != nil {
			t.Fatal(err)
		}
		for i := 0; i < n; i++ {
			if !bytes.Equal(got[i], want[32*i:32*(i+1)]) {
				t.Fatalf("hkdf(%d outputs): output %d mismatch", n, i)
			}
		}
	}
}
