package vectors

import (
	"nimna.app/test-vectors/generator/internal/derive"
)

// topic-derivation.json — spec §3.1.1 (canonicalization) and §3.1.2
// (topic/psk derivation).

type argonParamsJSON struct {
	Variant     string `json:"variant"`
	Version     int    `json:"version"`
	Time        uint32 `json:"time"`
	MemoryKiB   uint32 `json:"memory_kib"`
	Parallelism uint8  `json:"parallelism"`
	OutputLen   uint32 `json:"output_len"`
	Note        string `json:"note"`
}

type topicOutputsJSON struct {
	Seed  string `json:"seed"`
	Topic string `json:"topic"`
	PSK   string `json:"psk"`
}

type topicCaseJSON struct {
	Name            string            `json:"name"`
	Input           string            `json:"input"`
	Valid           bool              `json:"valid"`
	RejectReason    string            `json:"reject_reason,omitempty"`
	Canonical       string            `json:"canonical,omitempty"`
	CreationDateUTC string            `json:"creation_date_utc,omitempty"`
	SaltPreimage    string            `json:"salt_preimage_ascii,omitempty"`
	Salt            string            `json:"salt,omitempty"`
	Production      *topicOutputsJSON `json:"production,omitempty"`
	ReducedTestOnly *topicOutputsJSON `json:"reduced_test_only,omitempty"`
	Note            string            `json:"note,omitempty"`
}

type topicFileJSON struct {
	Purpose    string          `json:"_purpose"`
	Spec       string          `json:"_spec"`
	Alphabet   string          `json:"crockford_alphabet"`
	Production argonParamsJSON `json:"argon2id_production"`
	Reduced    argonParamsJSON `json:"argon2id_reduced_test_only"`
	HKDF       topicHKDFJSON   `json:"hkdf"`
	Cases      []topicCaseJSON `json:"cases"`
}

type topicHKDFJSON struct {
	Salt      string `json:"salt"`
	TopicInfo string `json:"topic_info"`
	TopicLen  int    `json:"topic_len"`
	PSKInfo   string `json:"psk_info"`
	PSKLen    int    `json:"psk_len"`
}

// seedCache lets pairing transcripts reuse topic-file derivations without
// recomputing production-cost Argon2id.
type seedCache map[string]topicOutputsJSON // key: canonical + "|" + date

func deriveOutputs(canonical, date string, p derive.Argon2Params) topicOutputsJSON {
	seed := derive.Seed(canonical, derive.TopicSalt(date), p)
	return topicOutputsJSON{
		Seed:  hexs(seed),
		Topic: hexs(derive.Topic(seed)),
		PSK:   hexs(derive.PSK(seed)),
	}
}

func genTopicDerivation() (*topicFileJSON, seedCache) {
	cache := seedCache{}
	prodFor := func(canonical, date string) topicOutputsJSON {
		key := canonical + "|" + date
		if out, ok := cache[key]; ok {
			return out
		}
		out := deriveOutputs(canonical, date, derive.ProductionParams)
		cache[key] = out
		return out
	}

	valid := func(name, input, date, note string) topicCaseJSON {
		canonical, err := derive.Canonicalize(input)
		if err != nil {
			panic("generator bug: case " + name + " expected valid: " + err.Error())
		}
		prod := prodFor(canonical, date)
		red := deriveOutputs(canonical, date, derive.ReducedParams)
		return topicCaseJSON{
			Name:            name,
			Input:           input,
			Valid:           true,
			Canonical:       canonical,
			CreationDateUTC: date,
			SaltPreimage:    string(derive.TopicSaltPreimage(date)),
			Salt:            hexs(derive.TopicSalt(date)),
			Production:      &prod,
			ReducedTestOnly: &red,
			Note:            note,
		}
	}
	invalid := func(name, input, reason string) topicCaseJSON {
		if _, err := derive.Canonicalize(input); err == nil {
			panic("generator bug: case " + name + " expected invalid")
		}
		return topicCaseJSON{Name: name, Input: input, Valid: false, RejectReason: reason}
	}

	file := &topicFileJSON{
		Purpose: "Pairing-code canonicalization and rendezvous topic/psk derivation. " +
			"Valid cases carry outputs under both parameter sets; invalid inputs " +
			"must be rejected client-side with nothing sent.",
		Spec:     SpecRef + " §3.1.1, §3.1.2",
		Alphabet: derive.Alphabet,
		Production: argonParamsJSON{
			Variant: "Argon2id", Version: 19, Time: 3, MemoryKiB: 64 * 1024,
			Parallelism: 1, OutputLen: 32,
			Note: "Fixed protocol constants (spec §3.1.2): t=3, m=64 MiB, p=1, Argon2 v1.3 (0x13).",
		},
		Reduced: argonParamsJSON{
			Variant: "Argon2id", Version: 19, Time: 1, MemoryKiB: 8 * 1024,
			Parallelism: 1, OutputLen: 32,
			Note: "REDUCED COST — FOR FAST UNIT TESTS ONLY. Never used by the protocol; " +
				"exists so test suites can exercise the derivation pipeline cheaply.",
		},
		HKDF: topicHKDFJSON{
			Salt:      "zero-length (RFC 5869 default)",
			TopicInfo: "nimna/topic/v1",
			TopicLen:  16,
			PSKInfo:   "nimna/psk/v1",
			PSKLen:    32,
		},
		Cases: []topicCaseJSON{
			valid("canonical-input", "7Q2M4K9XV", "2026-07-04",
				"Already canonical: 9 uppercase Crockford Base32 characters."),
			valid("display-hyphens", "7Q2-M4K-9XV", "2026-07-04",
				"Display form XXX-XXX-XXX; hyphens strip to the same canonical bytes and identical outputs."),
			valid("lowercase-and-whitespace", " 7q2 m4k 9xv\t", "2026-07-04",
				"Lowercase folds up, whitespace strips; same canonical bytes and identical outputs."),
			valid("crockford-mappings", "iLo-oLi-2ab", "2026-01-31",
				"Crockford decode mappings: I→1, L→1, O→0 (upper- and lowercase). Canonical is 1100112AB."),
			valid("alphabet-edge", "ZZZZZZZZZ", "2026-12-31",
				"Last alphabet character; distinct creation date exercises the date-salted derivation."),
			invalid("u-rejected", "7QU-M4K-9XV",
				"U is not in the Crockford alphabet and is rejected, never mapped (spec §3.1.1)."),
			invalid("wrong-length-short", "7Q2-M4K-9X",
				"Canonicalizes to 8 characters; canonical form must be exactly 9."),
			invalid("wrong-length-long", "7Q2-M4K-9XVA",
				"Canonicalizes to 10 characters; canonical form must be exactly 9."),
			invalid("invalid-character", "7Q2-M4K-9X$",
				"'$' is not in the alphabet and has no mapping."),
		},
	}
	return file, cache
}
