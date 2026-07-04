package main

import (
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// vectorsPath is the committed protocol test-vector file — read-only,
// never regenerated or edited here. It is a vendored byte-identical copy
// of the monorepo's docs/test-vectors/topic-derivation.json (see
// testdata/README.md): vendoring keeps `go test ./...` self-contained in
// the public relay repo, and monorepo CI cmp-asserts the copy never
// drifts from its source.
const vectorsPath = "testdata/topic-derivation.json"

type topicOutputs struct {
	Seed  string `json:"seed"`
	Topic string `json:"topic"`
	PSK   string `json:"psk"`
}

type topicVector struct {
	Name            string       `json:"name"`
	Input           string       `json:"input"`
	Valid           bool         `json:"valid"`
	Canonical       string       `json:"canonical"`
	CreationDateUTC string       `json:"creation_date_utc"`
	Salt            string       `json:"salt"`
	Production      topicOutputs `json:"production"`
	Reduced         topicOutputs `json:"reduced_test_only"`
}

func loadVectors(t *testing.T) []topicVector {
	t.Helper()
	raw, err := os.ReadFile(vectorsPath)
	if err != nil {
		t.Fatalf("reading committed vectors: %v", err)
	}
	var doc struct {
		Cases []topicVector `json:"cases"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("decoding vectors: %v", err)
	}
	if len(doc.Cases) == 0 {
		t.Fatal("no cases found in topic-derivation.json")
	}
	return doc.Cases
}

// TestCanonicalization exercises every committed case — valid inputs must
// converge on the canonical 9 bytes, invalid inputs must be rejected.
func TestCanonicalization(t *testing.T) {
	for _, v := range loadVectors(t) {
		t.Run(v.Name, func(t *testing.T) {
			got, err := canonicalize(v.Input)
			if !v.Valid {
				if err == nil {
					t.Fatalf("canonicalize(%q): accepted invalid input as %q", v.Input, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("canonicalize(%q): %v", v.Input, err)
			}
			if got != v.Canonical {
				t.Fatalf("canonicalize(%q): got %q, want %q", v.Input, got, v.Canonical)
			}
		})
	}
}

func TestTopicSalt(t *testing.T) {
	for _, v := range loadVectors(t) {
		if !v.Valid {
			continue
		}
		t.Run(v.Name, func(t *testing.T) {
			got := hex.EncodeToString(topicSalt(v.CreationDateUTC))
			if got != v.Salt {
				t.Fatalf("salt: got %s, want %s", got, v.Salt)
			}
		})
	}
}

// deriveCase checks seed, topic, and psk for one parameter set against the
// vector's expected outputs.
func deriveCase(t *testing.T, v topicVector, p argonParams, want topicOutputs) {
	t.Helper()
	seed := deriveSeed(v.Canonical, topicSalt(v.CreationDateUTC), p)
	if got := hex.EncodeToString(seed); got != want.Seed {
		t.Errorf("seed: got %s, want %s", got, want.Seed)
	}
	if got := hex.EncodeToString(hkdfSHA256(seed, "nimna/topic/v1", 16)); got != want.Topic {
		t.Errorf("topic: got %s, want %s", got, want.Topic)
	}
	if got := hex.EncodeToString(hkdfSHA256(seed, "nimna/psk/v1", 32)); got != want.PSK {
		t.Errorf("psk: got %s, want %s", got, want.PSK)
	}
	// deriveTopic (the composition main uses) must agree.
	topic := deriveTopic(v.Canonical, v.CreationDateUTC, p)
	if got := hex.EncodeToString(topic[:]); got != want.Topic {
		t.Errorf("deriveTopic: got %s, want %s", got, want.Topic)
	}
}

// TestDerivationReduced runs every valid case under the vectors' clearly
// labeled reduced-cost parameters — fast, always on.
func TestDerivationReduced(t *testing.T) {
	for _, v := range loadVectors(t) {
		if !v.Valid {
			continue
		}
		t.Run(v.Name, func(t *testing.T) {
			deriveCase(t, v, reducedParams, v.Reduced)
		})
	}
}

// TestDerivationProduction runs every valid case at the fixed protocol
// constants (t=3, m=64 MiB) — seconds-slow, skipped under -short
// (architecture note §6).
func TestDerivationProduction(t *testing.T) {
	if testing.Short() {
		t.Skip("production-cost Argon2id (t=3, m=64 MiB); skipped in -short mode")
	}
	for _, v := range loadVectors(t) {
		if !v.Valid {
			continue
		}
		t.Run(v.Name, func(t *testing.T) {
			deriveCase(t, v, productionParams, v.Production)
		})
	}
}
