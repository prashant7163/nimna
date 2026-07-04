# internal/rendezvous/

Topic registry + bridging state machine (spec §3.1.6, §4; architecture
note §5):

- `registry.go` — lifecycle absent → waiting → bridged; registration is
  always silent (no ack frame exists); first-come-wins: while bridged,
  further registrants are ignored with NO state kept; the entry is deleted
  whole when either end's connection dies or its 24 h registration cap
  fires (coarse janitor tick, injectable clock). NO tombstones: a dead
  topic's bytes re-register as a fresh waiting entry — expired, used, and
  never-existed stay structurally indistinguishable (§3.1.6). Pure
  in-memory state machine behind one plain mutex, generic over a
  comparable endpoint handle; it returns peers and the server delivers —
  it never touches the network.
- `registry_test.go` — every transition, membership-checked unwind,
  no-tombstone re-registration, and the 24 h cap driven by a fake clock
  (no sleeping tests).
