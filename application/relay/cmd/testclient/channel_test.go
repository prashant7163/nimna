package main

import (
	"encoding/hex"
	"testing"
)

// TestDeriveCRIDPinned pins the TEST-ONLY derivation so both ends of a
// scripted done-check provably agree on the CRID bytes. The expected
// values are SHA-256("nimna/testclient/crid/v1|" + code)[0:16], computed
// independently — NOT the spec §3.1.5 derivation.
func TestDeriveCRIDPinned(t *testing.T) {
	cases := []struct {
		code string
		want string
	}{
		{"7Q2M4K9XV", "81ff97991ce2c56c40435c4e37e562fa"},
		{"AAAAAAAAA", "6b16b86a70635827dfc9d04b00954528"},
	}
	for _, tc := range cases {
		got := deriveCRID(tc.code)
		if hex.EncodeToString(got[:]) != tc.want {
			t.Errorf("deriveCRID(%q) = %x, want %s", tc.code, got, tc.want)
		}
	}
	// Distinct codes must yield distinct CRIDs (sanity, not crypto).
	if deriveCRID("7Q2M4K9XV") == deriveCRID("AAAAAAAAA") {
		t.Fatal("distinct codes collided")
	}
}

// TestDeriveCRIDUsesCanonicalForm: the CRID comes from the canonical code,
// so every §3.1.1 input form of the same code lands on the same CRID.
func TestDeriveCRIDUsesCanonicalForm(t *testing.T) {
	canonical, err := canonicalize("7q2 m4k 9xv")
	if err != nil {
		t.Fatalf("canonicalize: %v", err)
	}
	if deriveCRID(canonical) != deriveCRID("7Q2M4K9XV") {
		t.Fatal("canonicalized input forms must derive the same CRID")
	}
}
