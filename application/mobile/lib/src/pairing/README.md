# lib/src/pairing/

Pairing flows. S8 ships the **initiator** side only; S9's `joiner/` will
be a sibling that shares nothing here — only the pure `protocol/` and
`transport/` layers below (S8 intake §4: **no `pairing/common`, no shared
mutable scaffolding, ever**).

## initiator/

```
create_line_entry.dart  THE single entry point into code creation (the G2
                        opening condition): startCreateLine is called from
                        exactly one place (F4's create action) —
                        test-pinned; S17 wires the paywall gate by editing
                        exactly this file. resumeCreateLineIfPending
                        reopens a boot-time-read pending pairing (not a
                        creation entry, never gated).
initiator_controller.dart  the flow state machine (ChangeNotifier):
                        setup → generating → waiting ⇄ (grace/backoff) →
                        bridged (hold) | expired | cancelled | spent.
                        Bridged = S8's terminal success: socket held at the
                        F2.4→F2.5 boundary, PAIR_DATA buffered opaquely,
                        psk + static keypair held — the S9 responder engine
                        attaches exactly here. TTL presets 1/8/24 h
                        (protocol rail: ≤ 24 h), wall-clock expiry checked
                        by timer + on resume; ~30 s background grace then
                        the socket closes (the copy promises the code's
                        lifetime, never background presence).
pending_pairing.dart    the creator's outstanding codes: one encrypted
                        record in the S7 meta store ('pending_pairings') —
                        {canonical code, creation UTC date, TTL, X25519
                        keypair}. Zero schema change; discard is a real
                        erase; S9's self-join guard reads this.
pairing_initiator_service.dart  DI bundle in AppScope; mints controllers
                        for the flow wiring only.
share.dart              THE one share_plus call site (scoped sign-off):
                        code-as-text / QR-as-PNG via a temp file deleted
                        after handoff. Fence test-pinned.
qr_matrix.dart          THE one `qr`-encoder call site: encodes exactly the
                        §3.1.1 payload at EC level M; output pinned by the
                        committed fixture (test/fixtures/, independently
                        decoder-verified).
```
