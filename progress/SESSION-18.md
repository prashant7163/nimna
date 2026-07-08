# Session 18 — Adversarial pass & test suite (G7 solo)

Branch: `session-18-adversarial` · opened 2026-07-08 · consumes the FROZEN
v0.2.1 codec (envelope untouched — S18 tests the frozen surface, never
changes it).

Owns (dep graph): test suites both stacks, fuzz harnesses, the Noise
test-oracle harness (test-only), threat-model docs. Prereqs S7–S17 all
merged. Solo group — no parallel peer, no ARB/pubspec/route fold hotspots
expected beyond dev-only test deps.

Done-check (plan §18): every §9 row has a passing test OR a documented
accepted limitation.

## Intake decisions
- **USER (device rungs):** HOST-MAX — S18 does the maximal host+emulator
  adversarial pass; the four genuinely hardware-bound rungs (real-camera
  EXIF, OS screenshot keystroke, locked-device push delivery, seized-device
  cold-disk forensics) are documented accepted limitations carried into
  PUBLISH_READY device-QA hand-steps. See DECISIONS.md (2026-07-08 S18).
- **USER (settled 2026-07-05):** Noise engine cross-verified against
  flynn/noise-class Go library as a TEST ORACLE — test-only, never a
  runtime dependency, in addition to the committed vectors.

## Starting state (survey)
- Mobile: 66 `*_test.dart` files (455/455 green at S16). Relay: 22
  `*_test.go` files (green). No Go fuzz targets yet; no Dart
  property/fuzz harness yet; no Noise oracle yet.

## Log
- Intake ran: architect oracle-design (`docs/architecture/s18-noise-oracle-design.md`)
  ∥ QA coverage-matrix (`progress/s18-coverage-matrix.md`). 1 USER decision (HOST-MAX).
- Go lane: `internal/wire/fuzz_test.go` (FuzzParse + FuzzParseKnockPayload) + the
  isolated flynn/noise oracle module `docs/test-vectors/oracle/` + 3-layer CI guard.
- Dart lane: 11 adversarial tests; 2 production findings (ICC leak + outer-frame
  bound) looped back and fixed (only `lib/src/` diff = 2 one-liners + README note).
- Deliverable: `docs/architecture/threat-model.md` (§9 + plan-§18 rows → test/limitation).
- code-reviewer PASS (no blocking, 3 NITs applied). senior-qa done-check PASS
  (467/467 mobile, relay+oracle green, fuzz 11.6M/14.7M no-crash, §9 contract holds).

**DONE — see canonical `PROGRESS.md` "Session 18" + "G7 CLOSED" entries.** M3 reached.
