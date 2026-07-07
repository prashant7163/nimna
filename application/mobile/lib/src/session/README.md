# lib/src/session/

The live 1:1 session — the S10 "live text" path, decomposed into three lanes
so S11 (media) and S12 (presence) can extend it in parallel without a shared
mutable surface (the G4 gate). The split is **mechanically enforced** by
`test/session/import_direction_test.dart` (the G4-gating done-check clause).

```
model/       IMMUTABLE seam types — no keys, no transport, no store, no Flutter.
             chat_event.dart   sealed ChatEvent + SessionLineState / ReactionSide /
                               SessionEndReason enums.
             message_view.dart immutable per-message view model + ReplyPreview
                               (referent | neutral tombstone).
connection/  the protocol lane (S12 extends). SessionController owns the §3.3.1
             Noise_KK driver + the two-direction SessionTransport + counters, the
             send/receive loop, the delivery FSM (waiting→sent→delivered), the §5.8
             reaction/reply state rules, typing, expiry, HANGUP, and the
             protocol-error kill path. Exposes a READ-ONLY Stream<ChatEvent> +
             typed send methods. Imports NO Flutter.
chat/        the widget lane (S11 extends). Renders MessageViews and reports
             gestures; holds no protocol state. Bubbles + delivery ticks, reaction
             chips, quoted-reply preview + tombstone, the long-press actions card,
             the composer (timer picker with voice string 7 verbatim, reply strip),
             and the silent peer-typing glyph.
```

## Invariants (fence-enforced)
- `model/` is a leaf: it imports neither `connection/` nor `chat/`, and no Flutter
  widget library.
- `connection/` imports **no Flutter** and never `chat/` — it is the sole owner of
  the transport, keys, counters, and the message store.
- `chat/` may import `model/` and `connection/`'s public interface, but never holds
  or mutates a `NoiseTransport`/`SessionTransport`/`SecureKey`/`MessageRepository`/
  `MessageStore`/handshake type, and never imports the noise/transport/storage trees.

## Scope
S10 is the LIVE text path. `// TODO(S12)` marks the presence lane's seams
(knock-waiting/lapse, reconnect, 30 s background grace, offline-compose outbox
auto-flush, device-token refresh, per-channel push). `// TODO(S11)` marks media
(reply-to-media / react-on-manifest branches exist in the frozen codec but are
untestable until media lands). The app never auto-retries a knock (spec §4).

## Consumes (Phase A, frozen at this checkpoint)
`lib/src/protocol/inner_envelope.dart` (+ `reaction_body.dart`), `lib/src/noise`
(KK drivers + `SessionTransport`), `lib/src/transport/relay_socket.dart` (§5.4
outer frames), and the S7 storage layer (`MessageRepository`, `MessageRecord`).
