package vectors

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// committedDir is docs/test-vectors relative to this package directory.
const committedDir = "../../.."

// TestRegenerationIsByteIdentical regenerates every vector file into a
// temporary directory and compares it byte-for-byte with the committed
// copy. This is the drift guard: any change to the generator must be
// accompanied by regenerated committed vectors (and vice versa).
func TestRegenerationIsByteIdentical(t *testing.T) {
	if testing.Short() {
		t.Skip("regeneration runs production-cost Argon2id; skipped in -short mode")
	}
	tmp := t.TempDir()
	wordlist := filepath.Join(committedDir, "wordlist-en-v1.txt")
	if err := Generate(tmp, wordlist); err != nil {
		t.Fatalf("Generate: %v", err)
	}
	for _, name := range Files {
		got, err := os.ReadFile(filepath.Join(tmp, name))
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		want, err := os.ReadFile(filepath.Join(committedDir, name))
		if err != nil {
			t.Fatalf("%s: reading committed copy: %v (regenerate with `go run . -dir ..`)", name, err)
		}
		if !bytes.Equal(got, want) {
			t.Errorf("%s: committed file differs from regeneration — run `go run . -dir ..` and commit the result", name)
		}
	}
}

// TestGenerateTwiceIsDeterministic guards the no-randomness/no-clock rule
// independently of the committed files.
func TestGenerateTwiceIsDeterministic(t *testing.T) {
	if testing.Short() {
		t.Skip("runs production-cost Argon2id; skipped in -short mode")
	}
	wordlist := filepath.Join(committedDir, "wordlist-en-v1.txt")
	dirA, dirB := t.TempDir(), t.TempDir()
	if err := Generate(dirA, wordlist); err != nil {
		t.Fatalf("first run: %v", err)
	}
	if err := Generate(dirB, wordlist); err != nil {
		t.Fatalf("second run: %v", err)
	}
	for _, name := range Files {
		a, err := os.ReadFile(filepath.Join(dirA, name))
		if err != nil {
			t.Fatal(err)
		}
		b, err := os.ReadFile(filepath.Join(dirB, name))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(a, b) {
			t.Errorf("%s: two runs produced different bytes", name)
		}
	}
}
