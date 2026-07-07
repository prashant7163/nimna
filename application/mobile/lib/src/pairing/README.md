# lib/src/pairing/

Pairing flows. S8 ships the **initiator** side; S9 adds the **joiner** side
as a sibling that shares nothing here — only the pure `protocol/`,
`transport/`, and `noise/` layers below (intake §4: **no `pairing/common`,
no shared mutable scaffolding, ever**). The two sides read the SAME
`pending_pairings` record — the creator writes it, the joiner's self-join
guard reads it.

## joiner/ (S9)

```
join_line_entry.dart   THE entry point into the joiner flow (startJoinLine);
                       joining is ALWAYS free and never passes through the
                       paywall (S17 gates creation only, a separate door).
join_controller.dart   the F3 state machine (ChangeNotifier): entry →
                       joining (today+yesterday registration, two Argon2id
                       derivations; XXpsk2 handshake) → verify (safety
                       phrase) → naming → done; mismatch on decline. The
                       joiner is the Noise INITIATOR. Persists the channel
                       ONLY after "They match"; "They don't match" is a
                       LOCAL-ONLY silent discard (no peer wire signal, USER
                       2026-07-07). Self-join guard consumes the pending
                       store; the no-answer timeout drives the one generic
                       response (silence doctrine).
joiner_service.dart    DI bundle in AppScope; mints controllers.
safety_phrase_wordlist.dart  loads the pinned EFF wordlist asset (SHA-256
                       verified); protocol output, one global list.
join_entry/qr_source.dart     THE mobile_scanner call site (fence): live
                       scanner + still-image decode. Bundled MLKit, no
                       telemetry.
join_entry/upload_source.dart THE file_picker + pdfrx call site (fence):
                       pick an image or PDF, rasterize page 1, decode. All
                       four methods converge through PairingCode.
```

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
                        psk + static keypair held. S9 added the opt-in
                        `attachResponder` write-seam: the from-spec responder
                        engine (lib/src/noise) drives M2/M4 over the bridge,
                        and the TTL timer is cancelled at the bridge (TTL is a
                        pre-bridge gate only). Absent an attached responder,
                        behavior is exactly S8's (buffer, fabricate nothing).
                        TTL presets 1/8/24 h
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
