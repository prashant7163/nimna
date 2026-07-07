# lib/src/session/connection/

The protocol lane of the live session (S12 extends it). `SessionController` is the
single owner of the live session's mutable protocol state; the chat lane never
touches any of it (the import-direction fence). Imports **no Flutter**.

`session_controller.dart` drives, for one channel:
- **Establishment** — register CRID, knock (knocker) or ACCEPT an incoming knock
  (accepter). On `SESSION_BRIDGED` it runs the §3.3.1 Noise_KK handshake: the
  knocker is the initiator (`writeS1` → `completeWithS2`), the accepter the
  responder (`readS1` → `writeS2` → `deriveTransport`). The first two SESSION_DATA
  frames on a fresh bridge ARE S1/S2.
- **Transport** — seal via `SessionTransport.send` (ad = the 18-byte outer header),
  send SESSION_DATA; on recv, open + `InnerEnvelope.decode`.
- **Delivery FSM** — waiting → sent (on relay send) → delivered (on the peer ACK),
  persisted through `MessageRepository`.
- **§5.8 reaction/reply state** — silent-drop a reaction whose referent is
  unknown/deleted/expired; one reaction per sender per message; never ACK a
  reaction; resolve reply referents from the LOCAL copy, tombstone when gone.
- **Typing** — CONTROL 0x01, ON BY DEFAULT (USER 2026-07-07), gated by the single
  `typingEnabled` seam (the future F7 toggle).
- **End** — explicit HANGUP → `SessionEnded.ended`; a bridge dying without one →
  `SessionEnded.connectionLost`. Any `TransportError`/`InnerEnvelopeError`/counter
  violation is the §3.3.1 protocol error: destroy all session keys, send relay
  TEARDOWN, `connectionLost`.

Exposes a READ-ONLY `Stream<ChatEvent>` + typed send methods (`sendText`,
`sendReply`, `sendReaction`, `removeReaction`, `setTyping`, `deleteMessage`,
`hangup`). `// TODO(S12)` marks the presence seams; the app never auto-retries a
knock.
