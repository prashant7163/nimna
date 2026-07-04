# internal/ident/

Unloggable identifier wrapper types (logging doctrine; architecture note
§4): `Topic`, `CRID`, `RemoteAddr`, `DeviceToken`.

- `ident.go` — every rendering surface (fmt via `fmt.Formatter` across all
  verbs, `String`/`GoString`, `MarshalText`, `MarshalJSON`,
  `slog.LogValuer`) emits a fixed tag like `topic[redacted]` with zero
  identifier bytes — no truncated hex, ever (partial values still
  correlate). Raw bytes live in unexported fields; the ONLY raw accessor
  is the deliberately greppable `WireBytes()`, used solely to build
  outbound frames, every call site review-audited. `Topic` and `CRID` are
  comparable so registries key maps on them directly.
- `ident_test.go` — proves redaction through fmt (`%v %s %q %x %X %d %+v
  %#v`, nested in structs/slices/maps), `encoding/json`, `MarshalText`,
  and `log/slog` with captured text+JSON handlers; scans outputs for hex,
  truncated-hex, raw-string, and decimal-byte leaks.

The CI log-scrub assertion over the whole module lands in Session 5; the
types and their tests ship from Session 3 so no unwrapped identifier ever
reaches a call site.
