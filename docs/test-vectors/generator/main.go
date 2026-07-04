// Command generator deterministically (re)generates the Nimna protocol
// test vectors in docs/test-vectors/. Run from this directory:
//
//	go run . -dir ..
//
// The output is byte-identical on every run (no randomness, no clock); CI
// regenerates and diffs, so the committed vectors can never drift from
// this source. See docs/test-vectors/README.md.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"nimna.app/test-vectors/generator/internal/vectors"
)

func main() {
	dir := flag.String("dir", "..", "docs/test-vectors directory to write the JSON files into (must already contain wordlist-en-v1.txt)")
	flag.Parse()

	wordlist := filepath.Join(*dir, "wordlist-en-v1.txt")
	if err := vectors.Generate(*dir, wordlist); err != nil {
		fmt.Fprintln(os.Stderr, "generator:", err)
		os.Exit(1)
	}
	for _, f := range vectors.Files {
		fmt.Println("wrote", filepath.Join(*dir, f))
	}
}
