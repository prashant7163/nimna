# Nimna Build Plan — Atomic Claude Code Sessions

**Structure:** Each session is one atomic unit of work with a clear deliverable and a done-check. Sessions are sized to fit comfortably in a single focused Claude Code sitting (context-friendly, `/clear` between sessions). Order matters within phases; phases can overlap slightly.

**Stack assumptions (adjustable in Session 1):** Flutter/Dart app (you already have the toolchain from Zivya). Relay in a lightweight, WebSocket-friendly runtime — Node/TypeScript, Go, or Rust; decided Session 1. Single small VPS or Fly.io instance.

**Repo layout:** monorepo `nimna/` with `relay/`, `app/`, `docs/` (spec lives here), `protocol/` (shared framing definitions / test vectors).

---

## Phase 0 — Foundations

### Session 1 — Decisions & scaffolding
- Choose relay language/runtime (criteria: WebSocket maturity, memory footprint, your comfort maintaining it, single-binary deploy).
- Choose hosting target and provision nothing yet (just decide).
- Scaffold monorepo, CI lint/test skeleton, write `CLAUDE.md` for the repo (project context, conventions, spec pointers) — you know from Zivya how much this pays off.
- **Done when:** repo builds empty projects for relay + Flutter app; CLAUDE.md gives Claude Code full project context in <1 page.

### Session 2 — Crypto selection & protocol finalization
- Evaluate primitive options against §7 of the spec (agreement, AEAD, forward secrecy/ratchet, safety phrase, Dart + relay-side library availability, audit pedigree).
- Lock choices; update spec v0.1 → v0.2 with concrete primitives and exact handshake message sequence.
- Define wire framing precisely (byte layout), write protocol test vectors into `protocol/`.
- **Done when:** spec v0.2 committed; test vectors exist; you can explain the handshake on one whiteboard.

## Phase 1 — Relay

### Session 3 — Relay core: connections & rendezvous
- WebSocket server, connection lifecycle, in-memory registry, `H(code)` rendezvous topics with TTL, bridging two connections on a topic.
- **Done when:** two test clients (CLI scripts) can rendezvous via a code hash and exchange raw frames through the relay.

### Session 4 — Relay core: channels, knock, sessions
- CRID registration, `KNOCK`/`ACCEPT`/`PEER_OFFLINE`/`HANGUP` semantics, knock TTL, bridge teardown, keepalive/ping handling, decaying background timer semantics honored server-side (connection expiry).
- **Done when:** CLI clients can pair once, disconnect, reconnect later, knock, accept, chat, hang up — all state gone after.

### Session 5 — Relay hardening
- Rate limits (per-IP, per-connection, topic throttling), max frame size, structured error codes, graceful shutdown, zero-log production config vs. debug config, memory-leak soak test script.
- **Done when:** abuse test scripts bounce off limits; overnight soak shows flat memory.

### Session 6 — Relay deploy & open-sourcing
- Dockerfile/single-binary deploy, TLS termination, deploy to the $5 box, health endpoint, minimal ops runbook.
- Clean the repo for public eyes: README with the zero-storage claim and how to verify it, license, contribution note.
- **Done when:** relay is live on a domain (e.g., relay.nimna.app) and the repo is publishable (publish now or at launch — your call).

## Phase 2 — App core

### Session 7 — Flutter skeleton & local storage
- App scaffold, navigation shell, encrypted local DB (channel store + message store per spec §6), platform keystore integration, backup exclusion flags.
- **Done when:** app boots, creates/reads encrypted local records, survives restart, data absent from device backups.

### Session 8 — Pairing flow, part 1 (initiator)
- Generate keypair + code, QR render, connect/register on rendezvous topic, waiting-state UX, code TTL handling.
- **Done when:** app can create a code and hold rendezvous against a CLI test peer.

### Session 9 — Pairing flow, part 2 (joiner + handshake)
- Code entry + QR scan, key exchange through relay per spec, safety-phrase derivation and comparison screen, channel finalization, code discard.
- **Done when:** two devices (or device + emulator) pair end-to-end and both persist the channel; MITM test vector rejected.

### Session 10 — Live messaging
- Session UI (chat thread), encrypt/frame/send, receive/decrypt/ack, delivery states (waiting → sent → delivered), typing indicator control frames, hangup.
- **Done when:** two paired devices exchange E2E-encrypted messages live; relay logs (debug mode) show ciphertext only.

### Session 11 — Knock, presence & offline-compose
- Knock/accept UX, `PEER_OFFLINE` handling, local "waiting" outbox that auto-flushes on bridge, background socket decay timer, reconnect logic.
- **Done when:** compose-while-offline → peer comes online → knock → accept → backlog delivers in order.

## Phase 3 — The discretion features

### Session 12 — App lock & panic wipe
- PIN/biometric gate, lock-on-background, per-channel wipe and full wipe (keys + history, irrecoverable), confirmation UX that prevents accidents but stays fast.
- **Done when:** wipe leaves no recoverable trace (verified via device inspection); lock engages reliably.

### Session 13 — Disappearing messages & channel settings
- Per-message expiry (sender-dictated per spec §5), honor received expiry, channel label editing, per-channel read-receipt/typing toggles, honest UX copy about honor-system enforcement.
- **Done when:** expiry round-trips between devices and messages vanish on schedule on both ends.

### Session 14 — Notifications (opt-in)
- Content-free push ("New activity") via FCM/APNs, per-channel opt-in default-off, token registration flow, knock-triggered dispatch, in-app suppression when foregrounded.
- **Done when:** locked phone receives a contentless nudge on knock; disabling it results in zero third-party touch.

## Phase 4 — Ship

### Session 15 — Polish & first-run experience
- Onboarding (three screens max: what it is, how pairing works, what we can't see), empty states, error states, app icon + name, dark mode, accessibility pass.
- **Done when:** a stranger can go from install to paired chat without help.

### Session 16 — Paywall & monetization
- Free tier: join channels free forever, one initiated channel free. One-time unlock for unlimited channels (platform IAP), restore purchases, no accounts anywhere in the flow.
- **Done when:** IAP sandbox purchase unlocks channel creation; restore works on reinstall.

### Session 17 — Adversarial pass & test suite
- Threat-model walkthrough against the spec §9: replay, MITM, malformed frames, relay-impersonation, storage inspection. Automated protocol tests against test vectors; fuzz malformed input at both relay and app.
- **Done when:** every §9 row has either a passing test or a documented accepted limitation.

### Session 18 — Store preparation & launch assets
- App Store/Play listing copy (positioning: "a private line between two people — nothing stored anywhere, ever"), privacy questionnaires (unusually pleasant to fill: "data collected: none"), screenshots, review notes explaining the architecture proactively, website one-pager at nimna.app, HN launch draft ("the 300-line relay" post).
- **Done when:** both store submissions are ready to press; launch post drafted.

---

## Session hygiene (from your Zivya experience)
- One session = one sitting = one `/clear`. Keep `CLAUDE.md` under a page; link the spec instead of pasting it.
- End each session by committing + updating a `PROGRESS.md` (3 lines: done, decisions, next) so the next session boots with zero re-explanation.
- Sessions 3–6 and 7–11 are independent tracks after Session 2 — if you ever want parallelism, relay and app can interleave.

## Milestones
- **M1 (after S6):** relay live and auditable.
- **M2 (after S11):** two real phones talking privately. This is the demo-to-a-friend moment.
- **M3 (after S17):** honest product.
- **M4 (after S18):** launch day. Kill-or-continue checkpoint: 90 days after M4.
