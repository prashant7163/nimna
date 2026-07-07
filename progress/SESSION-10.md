# Session 10 — Live text messaging (CODEC CHECKPOINT)

Worktree `session-10-live-text` · branch `session-10-live-text` · solo (G3).
Owns: `lib/src/protocol` (complete v0.2.1 §5.5–§5.8 inner envelope codec +
§3.3.1 Noise_KK session handshake + transport nonce/rekey), `lib/src/session`
(chat UI, delivery states — decomposed per-concern per the S10 done-check
addition), `docs/test-vectors/` generator extension (Go).

Prereqs merged: S9 (pairing/handshake), S4 relay, DS (reply/reaction UI).

---

## Intake (complete 2026-07-07)

**Architect memo** (protocol-touching, mandatory). Key findings:
- **Go stack ~90% done for S10** — `internal/noise/{transport,patterns}.go` already
  implement KK + §5.6 nonce + per-message REKEY + forbidden-counter guard;
  `internal/vectors/session.go` already emits KK transcripts w/ transport frames.
  Go gap = v0.2.1 envelope surface only (REACTION `0x06` + reply_to bit2) in
  `internal/framing/framing.go` + regenerate `framing.json`/`session-handshake.json`
  + SpecRef bump v0.2→v0.2.1.
- **Dart codec + KK are net-new** (the S8/S9 fence reserved them). New:
  `lib/src/protocol/inner_envelope.dart` (+reaction_body.dart) — pure/stateless
  §5.5 header codec + 6 body types + full structural-error set (§5.8). KK lands in
  `lib/src/noise` (parameterize `handshake_state` `e`-token MixKey via
  `mixKeyOnEphemeral` flag; add pre-messages; new `NoiseTransport` primitive
  mirroring Go transport.go). Transport-key state lives in the **session layer**,
  never the pure codec.
- **`lib/src/session` split** (G4-gating done-check clause): directory-level
  `session/{model,connection,chat}` — `connection/` (S12 lane: SessionController owns
  KK+2×NoiseTransport+counters+delivery FSM, read-only `Stream<ChatEvent>`) vs
  `chat/` (S11 lane: composer/bubbles, widgets only). Enforced by an
  import-direction assertion test (chat/ may not import connection internals or hold
  a key/transport). Makes senior-qa PASS/FAIL mechanical + fences G4.
- **Persistence**: reply_to + reactions fold into the encrypted **interior** (two
  slots own/peer reaction on the referent record) — honors app-arch §4
  "encrypted interiors, plaintext graph columns REJECTED"; reactions inherit expiry
  / die-with-referent automatically. S7 `MessageRepository` + `DeliveryState` reused
  as-is.
- **Deps: NONE.** Both agents reject any emoji-picker/graph/Noise/serialization lib.
  a11y emoji sanitization (64-byte bound + C0/C1/bidi strip) required per DS handoff.
- **No spec-vs-plan-vs-design conflict found.**

**PM memo** (scope/UX/copy). Key findings:
- REACTION/reply_to + typing are in-scope v0.2.1 envelope surface, NOT scope growth.
- **Boundaries held OUT of S10**: offline-compose outbox lifecycle → S12 (S10 renders
  the `waiting` visual + live sent→delivered(ACK), not the persistent outbox/
  auto-flush/reconnect); media MEDIA_CHUNK → S11 (reply-to-media/react-on-manifest
  branches ship but are S11-exercised); screenshot/sensitive → S14.
- **Read receipts recommended OUT of S10** — plan doesn't list them; "Seen" caption +
  toggle live with F7. Reconciled: CONTROL `0x02` read-receipt type ships in the
  **frozen codec** (can't add post-checkpoint), but S10 renders no "Seen" and ships
  no toggle. (CODE — PM+architect align.)
- Reply/reaction UI fully pre-specified by DS (components.md + F5.16–19 + 11 folded
  `chat_*` ARB keys); implement, don't invent. Emoji presets 👍❤️😂😮😢🙏 USER-locked
  (DECISIONS 2026-07-05 03:30). Expiry presets Off/1m/15m/1h/24h USER-locked
  (2026-07-03 21:32). String 7 honor-system disclaimer ships **verbatim** (F5.11).
- Net-new non-claim UI chrome strings (delivery-state a11y, line-state labels, timer
  preset labels, waiting/connection-lost) → normal PM microcopy review; one canonical
  claim (string 7) ships verbatim.
- **One real design gap**: in-thread rendering of a *received* typing indicator is
  design-silent (toggle+CONTROL frame specced; the visual is not).

### CODE decisions the orchestrator is making (recorded; no USER escalation)
1. **Read-receipt CONTROL `0x02` type is in the frozen codec; no "Seen" render / no
   toggle in S10** (defers to F7-owning session). Freezing-surface completeness reason.
2. **HANGUP trigger = explicit end / leave-chat tap → authenticated HANGUP ("ended");
   a bridge that dies without one (drop, background past 30s grace) → "connection
   lost."** Spec §3.3 distinction honored; design-guided; connection-lane seed (S12
   owns the fuller reconnect UX). "They hung up." ships verbatim from F5.4 and is
   elevated to a numbered voice string for the S16 translation pass.
3. **Ship the full MEDIA_CHUNK manifest/chunk body codec in S10** (not just the
   header/flag) so the frozen surface is complete + matches committed vectors; S11
   only consumes it.
4. Reaction interior two-slot fold; additive interior JSON version bump (pre-launch
   destructive-reset stance → no migration code).
5. No new dependency (rejected in advance: emoji-picker/graph/Noise/serialization).

### USER decision surfaced (ONE) — typing indicators
Both agents flagged typing. The F7 toggle is design-default-OFF and read receipts are
per-channel opt-in by spec, which points to "per-channel opt-in, default off" — but
the **received-typing rendering is design-silent** and, for a discretion product,
whether typing timing leaks to the live peer at all is a security-posture/taste call.
Consolidated to USER.

**USER DECISION (2026-07-07) — typing indicators: ON BY DEFAULT.** Sent by default
(still per-channel toggleable off later via F7), rendered as a silent animated
three-dot glyph in the received-bubble position, no text string. To record in
DECISIONS.md at merge (USER). Accepted posture note: this leaks keystroke-timing
metadata to the live peer by default; the per-channel off toggle (F7, later session)
is the mitigation. CONTROL `0x01` typing frame per §5.5.

---

## Implement (in progress)

Two-phase build (solo worktree; agents leave changes uncommitted, orchestrator
commits per phase after review):

**Phase A (parallel, disjoint trees):**
- A1 backend-developer-go — generator extension (REACTION `0x06` + reply_to bit2 +
  invalid cases) → regenerate `framing.json` + `session-handshake.json`, SpecRef
  v0.2→v0.2.1, Go framing tests. Tree: `docs/test-vectors/**`.
- A2 mobile-developer-flutter — `lib/src/protocol` inner-envelope codec + reaction
  body + full structural-error set; `lib/src/noise` KK (parameterized handshake,
  pre-messages, NoiseTransport); unit tests + Dart vector-conformance harness. Tree:
  `application/mobile/lib/src/{protocol,noise}` + `test/`.

**Phase B (after A):**
- B mobile-developer-flutter — `lib/src/session/{model,connection,chat}`
  (SessionController + delivery FSM + protocol-error kill + persistence; chat UI
  composer/bubbles/reply/reaction/typing/expiry), import-direction fence test, ARB +
  net-new strings, route/screen wiring.

**Phase C:** code-reviewer → senior-qa done-check (incl. explicit PASS/FAIL on the
session-decomposition clause + both-stacks vector conformance) → wrap.
