package derive

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"
)

func TestCanonicalize(t *testing.T) {
	valid := []struct{ in, want string }{
		{"7Q2M4K9XV", "7Q2M4K9XV"},
		{"7Q2-M4K-9XV", "7Q2M4K9XV"},
		{" 7q2 m4k 9xv\t", "7Q2M4K9XV"},
		{"7q2-m4k-9xv\n", "7Q2M4K9XV"},
		{"iLo-oLi-2ab", "1100112AB"}, // I→1, L→1, O→0 per Crockford decode
		{"ZZZZZZZZZ", "ZZZZZZZZZ"},
		{"000000000", "000000000"},
	}
	for _, c := range valid {
		got, err := Canonicalize(c.in)
		if err != nil {
			t.Fatalf("Canonicalize(%q): unexpected error %v", c.in, err)
		}
		if got != c.want {
			t.Fatalf("Canonicalize(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	invalid := []string{
		"7QU-M4K-9XV",  // U is rejected, never mapped
		"7qu-m4k-9xv",  // lowercase u equally rejected
		"7Q2-M4K-9X",   // 8 chars
		"7Q2-M4K-9XVA", // 10 chars
		"7Q2-M4K-9X$",  // invalid character
		"",             // empty
		"---   ---",    // strips to nothing
	}
	for _, in := range invalid {
		if got, err := Canonicalize(in); err == nil {
			t.Fatalf("Canonicalize(%q) = %q, want error", in, got)
		}
	}
}

func TestTopicSalt(t *testing.T) {
	// The salt preimage is exactly "nimna/topic/v1|" + date, 25 ASCII bytes.
	pre := TopicSaltPreimage("2026-07-04")
	if string(pre) != "nimna/topic/v1|2026-07-04" || len(pre) != 25 {
		t.Fatalf("bad preimage: %q", pre)
	}
	if len(TopicSalt("2026-07-04")) != 16 {
		t.Fatal("salt must be 16 bytes")
	}
	if bytes.Equal(TopicSalt("2026-07-04"), TopicSalt("2026-07-05")) {
		t.Fatal("different dates must give different salts")
	}
}

func TestCommitmentPreimageShape(t *testing.T) {
	e := bytes.Repeat([]byte{0x11}, 32)
	s := bytes.Repeat([]byte{0x22}, 32)
	pre := CommitmentPreimage(e, s)
	if len(pre) != 79 {
		t.Fatalf("preimage must be 79 bytes (15+32+32), got %d", len(pre))
	}
	if string(pre[:15]) != CommitLabel {
		t.Fatalf("preimage must start with %q", CommitLabel)
	}
	if len(Commitment(e, s)) != 32 {
		t.Fatal("M0 must be 32 bytes")
	}
}

func TestSalt2IsOrderIndependent(t *testing.T) {
	a := bytes.Repeat([]byte{0xAA}, 32)
	b := bytes.Repeat([]byte{0x0B}, 32)
	if !bytes.Equal(Salt2(a, b), Salt2(b, a)) {
		t.Fatal("salt2 must not depend on argument order")
	}
}

func TestPhraseIndices(t *testing.T) {
	cases := []struct {
		hex  string
		want [3]int
	}{
		{"0000000000000000", [3]int{0, 0, 0}},
		{"0000000000000001", [3]int{0, 0, 1}},
		{"000000000000050f", [3]int{0, 0, 1295}},
		{"0000000000000510", [3]int{0, 1, 0}},
		{"0000000081bf0fff", [3]int{1295, 1295, 1295}}, // 1296^3 - 1
		{"0000000081bf1000", [3]int{0, 0, 0}},          // 1296^3 wraps word0
		{"ffffffffffffffff", [3]int{220, 1024, 1023}},  // 2^64-1
	}
	for _, c := range cases {
		b, err := hex.DecodeString(c.hex)
		if err != nil {
			t.Fatal(err)
		}
		if got := PhraseIndices(b); got != c.want {
			t.Fatalf("PhraseIndices(%s) = %v, want %v", c.hex, got, c.want)
		}
	}
}

func TestParseWordlist(t *testing.T) {
	good := strings.Repeat("word\n", 1296)
	if _, err := ParseWordlist([]byte(good)); err != nil {
		t.Fatalf("valid wordlist rejected: %v", err)
	}
	bad := []string{
		strings.Repeat("word\n", 1295),          // too short
		strings.Repeat("word\n", 1297),          // too long
		strings.TrimSuffix(good, "\n"),          // no trailing newline
		strings.Repeat("word\r\n", 1296),        // CRLF
		strings.Repeat("word\n", 1295) + "\n\n", // empty line
	}
	for i, b := range bad {
		if _, err := ParseWordlist([]byte(b)); err == nil {
			t.Fatalf("bad wordlist %d accepted", i)
		}
	}
}
