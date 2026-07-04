# internal/ident/

Unloggable identifier wrapper types (logging doctrine; architecture note
§4, §15): `Topic`, `CRID`, `RemoteAddr`, `DeviceToken`.

- `ident.go` — every rendering surface (fmt via `fmt.Formatter` across all
  verbs, `String`/`GoString`, `MarshalText`, `MarshalJSON`,
  `slog.LogValuer`) emits a fixed tag like `topic[redacted]` with zero
  identifier bytes — no truncated hex, ever (partial values still
  correlate). Raw bytes live in unexported fields; the ONLY raw accessor
  is the deliberately greppable `WireBytes()`, used solely to build
  outbound frames, every call site review-audited. `Topic` and `CRID` are
  comparable so registries key maps on them directly. `RemoteAddrFrom`
  CANONICALIZES at the accept boundary (note §15): port stripped, IPv4
  (incl. v4-mapped) keys exact, IPv6 keys as its /64 prefix (a single v6
  host owns a /64 — exact-address keying would be a free per-IP-cap
  bypass); the canonical key is the only address form held anywhere and
  has no raw accessor.
- `ident_test.go` — proves redaction through fmt (`%v %s %q %x %X %d %+v
  %#v`, nested in structs/slices/maps), `encoding/json`, `MarshalText`,
  and `log/slog` with captured text+JSON handlers; scans outputs for hex,
  truncated-hex, raw-string, and decimal-byte leaks; pins the
  canonicalization table (ports irrelevant, /64 collapse, zone strip,
  v4-mapped) and that canonical forms redact like raw ones.

The module-wide CI log-scrub assertion lives in `cmd/relay/
logscrub_test.go` (Session 5): it drives the real binary with known
identifier bytes and asserts none reach any output in any encoding.
