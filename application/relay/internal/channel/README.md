# internal/channel/

CRID registry: registrations, the single pending-knock slot, and the
knock → accept → bridged session state machine (spec §3.2, §3.3, §4;
architecture note §§9–10):

- `registry.go` — per-CRID entry = registration set (NO membership cap:
  the relay is role-blind; Noise KK authenticates, §3.3.1) + bridged pair
  + at most one pending knock. An entry exists iff its registration set is
  non-empty. Knock overwrites the pending (latest knocker, fresh deadline)
  and returns the forward set; an empty forward set is the peer-offline
  outcome the caller may answer with ONE push. Accept consumes the pending
  (first ACCEPT wins) and bridges (knocker, accepter). Teardown clears the
  bridge only — registrations survive; re-knock without re-register is
  expected. DropConn is the implicit-TEARDOWN unwind: pending dies with
  its knocker, a bridge survivor is returned for the notify, the entry
  dies with its last registration. Pending hold is exactly 60 s (valid iff
  now ≤ deadline), enforced lazily at every consumer; a 10 s janitor sweep
  is memory hygiene only. Every state-dependent rejection is a silent
  drop. Token-free by construction — no `ident.DeviceToken` ever enters
  this package; no logs exist here. Same shape as `internal/rendezvous`:
  one plain mutex, generic over a comparable endpoint handle, returns
  endpoints — the server delivers outside the lock. `Len()` /
  `PendingCount()` / `BridgedCount()` are the only introspection:
  identifier-free counts (the `crid_entries` / `pending_knocks` /
  `session_bridges` metrics gauges).
- `registry_test.go` — every row of the note §10 edge-semantics table
  (tests named `TestRowNN…` for reviewer mapping), the exact 60 s boundary
  under a fake clock (alive at 60 s−1 and at now == deadline, dead the
  nanosecond after; overwrite refreshes; consumed on bridge; no refresh on
  deliver-on-register), unwind paths, and sweep hygiene. No sleeping
  tests.
