package noise

import "strings"

// token is one Noise message-pattern token.
type token int

const (
	tokE token = iota
	tokS
	tokEE
	tokES
	tokSE
	tokSS
	tokPSK
)

// pattern is a parsed handshake pattern: pre-message patterns for the
// initiator and responder, and the message token sequences.
type pattern struct {
	preI   []token
	preR   []token
	msgs   [][]token
	hasPSK bool
}

// fundamentalPatterns holds the Noise fundamental one-way and interactive
// patterns (Noise spec rev 34 §7.4/§7.5). Deferred variants (NK1, XX1, …)
// are deliberately out of scope: Nimna uses only XXpsk2 and KK, and the
// fundamentals plus psk modifiers are what the third-party vector sets
// exercise.
var fundamentalPatterns = map[string]pattern{
	// One-way patterns.
	"N": {preR: []token{tokS}, msgs: [][]token{{tokE, tokES}}},
	"K": {preI: []token{tokS}, preR: []token{tokS}, msgs: [][]token{{tokE, tokES, tokSS}}},
	"X": {preR: []token{tokS}, msgs: [][]token{{tokE, tokES, tokS, tokSS}}},
	// Interactive patterns.
	"NN": {msgs: [][]token{{tokE}, {tokE, tokEE}}},
	"NK": {preR: []token{tokS}, msgs: [][]token{{tokE, tokES}, {tokE, tokEE}}},
	"NX": {msgs: [][]token{{tokE}, {tokE, tokEE, tokS, tokES}}},
	"XN": {msgs: [][]token{{tokE}, {tokE, tokEE}, {tokS, tokSE}}},
	"XK": {preR: []token{tokS}, msgs: [][]token{{tokE, tokES}, {tokE, tokEE}, {tokS, tokSE}}},
	"XX": {msgs: [][]token{{tokE}, {tokE, tokEE, tokS, tokES}, {tokS, tokSE}}},
	"KN": {preI: []token{tokS}, msgs: [][]token{{tokE}, {tokE, tokEE, tokSE}}},
	"KK": {preI: []token{tokS}, preR: []token{tokS}, msgs: [][]token{{tokE, tokES, tokSS}, {tokE, tokEE, tokSE}}},
	"KX": {preI: []token{tokS}, msgs: [][]token{{tokE}, {tokE, tokEE, tokSE, tokS, tokES}}},
	"IN": {msgs: [][]token{{tokE, tokS}, {tokE, tokEE, tokSE}}},
	"IK": {preR: []token{tokS}, msgs: [][]token{{tokE, tokES, tokS, tokSS}, {tokE, tokEE, tokSE}}},
	"IX": {msgs: [][]token{{tokE, tokS}, {tokE, tokEE, tokSE, tokS, tokES}}},
}

// parsePattern parses a pattern name with optional psk modifiers
// ("XX", "XXpsk2", "KKpsk0+psk2", …) and applies the modifiers per Noise
// spec rev 34 §9.1: psk0 prepends a psk token to the first message; pskN
// (N ≥ 1) appends a psk token to the N-th message (1-based).
func parsePattern(name string) (pattern, error) {
	base := name
	var modifiers []string
	if i := strings.Index(name, "psk"); i >= 0 {
		base = name[:i]
		modifiers = strings.Split(name[i:], "+")
	}
	p, ok := fundamentalPatterns[base]
	if !ok {
		return pattern{}, errf("noise: unsupported pattern %q", name)
	}
	// Deep-copy the message token lists before modifying.
	msgs := make([][]token, len(p.msgs))
	for i, m := range p.msgs {
		msgs[i] = append([]token{}, m...)
	}
	p.msgs = msgs
	for _, mod := range modifiers {
		if !strings.HasPrefix(mod, "psk") || len(mod) != 4 || mod[3] < '0' || mod[3] > '9' {
			return pattern{}, errf("noise: unsupported modifier %q in %q", mod, name)
		}
		n := int(mod[3] - '0')
		switch {
		case n == 0:
			p.msgs[0] = append([]token{tokPSK}, p.msgs[0]...)
		case n <= len(p.msgs):
			p.msgs[n-1] = append(p.msgs[n-1], tokPSK)
		default:
			return pattern{}, errf("noise: modifier %q out of range for %q", mod, name)
		}
		p.hasPSK = true
	}
	return p, nil
}

// IsOneWay reports whether the named pattern (without modifiers) is a
// Noise one-way pattern — needed by the vector runner, where all transport
// messages of a one-way pattern flow initiator→responder.
func IsOneWay(name string) bool {
	base := name
	if i := strings.Index(name, "psk"); i >= 0 {
		base = name[:i]
	}
	return len(base) == 1
}

// MessageCount returns the number of handshake messages in the pattern.
func MessageCount(name string) (int, error) {
	p, err := parsePattern(name)
	if err != nil {
		return 0, err
	}
	return len(p.msgs), nil
}
