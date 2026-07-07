# lib/src/transport/

Relay WebSocket transport — `dart:io` only (stdlib-first;
`web_socket_channel` rejected at the S8 intake). Transport knows the §5.4
*framing* and nothing about frame *meaning*: it moves `OuterFrame`s,
reports connection death (stream close = implicit TEARDOWN), and drops
malformed inbound frames silently.

```
relay_socket.dart  RelayConfig (URL always injected; dev default
                   ws://127.0.0.1:9440 via --dart-define NIMNA_RELAY_URL),
                   RelayConnector/RelayConnection interfaces (tests
                   substitute an in-memory fake), the dart:io
                   implementation, and ReconnectBackoff — the no-hammer
                   policy (exponential 2 s → 60 s cap, reset on success).
                   No layer here or above ever auto-retries in a loop: the
                   client is one polite registrant under the relay's §4
                   rendezvous throttling.
```

Connection failures surface as one indistinct `RelayUnreachableError` —
no addresses, no reasons, nothing loggable. Locale-independent; no Flutter
imports.
