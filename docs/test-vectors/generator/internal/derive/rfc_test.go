package derive

import (
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"golang.org/x/crypto/argon2"
)

// HKDF-SHA-256 — RFC 5869 Appendix A test cases 1–3, run through the same
// stdlib crypto/hkdf entry points the derivation code uses.
func TestHKDFRFC5869(t *testing.T) {
	cases := []struct {
		name                      string
		ikm, salt, info, prk, okm string
	}{
		{
			name: "A.1 basic",
			ikm:  "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
			salt: "000102030405060708090a0b0c",
			info: "f0f1f2f3f4f5f6f7f8f9",
			prk:  "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5",
			okm: "3cb25f25faacd57a90434f64d0362f2a" +
				"2d2d0a90cf1a5a4c5db02d56ecc4c5bf" +
				"34007208d5b887185865",
		},
		{
			name: "A.2 longer inputs/outputs",
			ikm: "000102030405060708090a0b0c0d0e0f" +
				"101112131415161718191a1b1c1d1e1f" +
				"202122232425262728292a2b2c2d2e2f" +
				"303132333435363738393a3b3c3d3e3f" +
				"404142434445464748494a4b4c4d4e4f",
			salt: "606162636465666768696a6b6c6d6e6f" +
				"707172737475767778797a7b7c7d7e7f" +
				"808182838485868788898a8b8c8d8e8f" +
				"909192939495969798999a9b9c9d9e9f" +
				"a0a1a2a3a4a5a6a7a8a9aaabacadaeaf",
			info: "b0b1b2b3b4b5b6b7b8b9babbbcbdbebf" +
				"c0c1c2c3c4c5c6c7c8c9cacbcccdcecf" +
				"d0d1d2d3d4d5d6d7d8d9dadbdcdddedf" +
				"e0e1e2e3e4e5e6e7e8e9eaebecedeeef" +
				"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
			prk: "06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244",
			okm: "b11e398dc80327a1c8e7f78c596a4934" +
				"4f012eda2d4efad8a050cc4c19afa97c" +
				"59045a99cac7827271cb41c65e590e09" +
				"da3275600c2f09b8367793a9aca3db71" +
				"cc30c58179ec3e87c14c01d5c1f3434f" +
				"1d87",
		},
		{
			name: "A.3 zero-length salt/info",
			ikm:  "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
			salt: "",
			info: "",
			prk:  "19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04",
			okm: "8da4e775a563c18f715f802a063c5a31" +
				"b8a11f5c5ee1879ec3454e5f3c738d2d" +
				"9d201395faa4b61a96c8",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			ikm := mustHex(t, c.ikm)
			salt := mustHex(t, c.salt)
			info := mustHex(t, c.info)

			prk, err := hkdf.Extract(sha256.New, ikm, salt)
			if err != nil {
				t.Fatal(err)
			}
			if hex.EncodeToString(prk) != c.prk {
				t.Fatalf("PRK mismatch: got %x", prk)
			}
			okm, err := hkdf.Expand(sha256.New, prk, string(info), len(c.okm)/2)
			if err != nil {
				t.Fatal(err)
			}
			if hex.EncodeToString(okm) != c.okm {
				t.Fatalf("OKM (Expand) mismatch: got %x", okm)
			}
			okm2, err := hkdf.Key(sha256.New, ikm, salt, string(info), len(c.okm)/2)
			if err != nil {
				t.Fatal(err)
			}
			if hex.EncodeToString(okm2) != c.okm {
				t.Fatalf("OKM (Key) mismatch: got %x", okm2)
			}
		})
	}
}

// Argon2id — reference-implementation test vectors.
//
// Honesty note: RFC 9106 §5.3's Argon2id vector uses a secret key (K) and
// associated data (X), which golang.org/x/crypto/argon2 deliberately does
// not expose (IDKey passes empty K and X). The RFC vector therefore cannot
// be reproduced through x/crypto. These vectors instead come from the
// Argon2 reference implementation's own test suite (the same codebase the
// RFC is based on), which uses empty K/X:
// https://github.com/P-H-C/phc-winner-argon2/blob/master/src/test.c
// (Argon2id section, version 0x13). Parameter mapping to x/crypto:
// argon2.IDKey(password, salt, time=t, memory=m KiB, threads=p, keyLen=32).
func TestArgon2idReferenceVectors(t *testing.T) {
	if testing.Short() {
		t.Skip("memory-hard KDF vectors skipped in -short mode")
	}
	cases := []struct {
		time      uint32
		memoryKiB uint32
		threads   uint8
		password  string
		salt      string
		want      string
	}{
		{2, 1 << 16, 1, "password", "somesalt",
			"09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"},
		{2, 1 << 18, 1, "password", "somesalt",
			"78fe1ec91fb3aa5657d72e710854e4c3d9b9198c742f9616c2f085bed95b2e8c"},
		{2, 1 << 8, 1, "password", "somesalt",
			"9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe"},
		{2, 1 << 8, 2, "password", "somesalt",
			"6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037"},
		{1, 1 << 16, 1, "password", "somesalt",
			"f6a5adc1ba723dddef9b5ac1d464e180fcd9dffc9d1cbf76cca2fed795d9ca98"},
		{4, 1 << 16, 1, "password", "somesalt",
			"9025d48e68ef7395cca9079da4c4ec3affb3c8911fe4f86d1a2520856f63172c"},
		{2, 1 << 16, 1, "differentpassword", "somesalt",
			"0b84d652cf6b0c4beaef0dfe278ba6a80df6696281d7e0d2891b817d8c458fde"},
		{2, 1 << 16, 1, "password", "diffsalt",
			"bdf32b05ccc42eb15d58fd19b1f856b113da1e9a5874fdcc544308565aa8141c"},
	}
	for i, c := range cases {
		got := argon2.IDKey([]byte(c.password), []byte(c.salt), c.time, c.memoryKiB, c.threads, 32)
		if hex.EncodeToString(got) != c.want {
			t.Fatalf("vector %d (t=%d m=%d p=%d): got %x", i, c.time, c.memoryKiB, c.threads, got)
		}
	}
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}
