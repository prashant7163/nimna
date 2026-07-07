# lib/src/media/

Media & documents (S11, spec §5.1) — attach, on-device EXIF-strip +
compression, MEDIA_CHUNK chunking/reassembly over the FROZEN v0.2.1 codec
(S10), the encrypted at-rest store (S7 `MediaRepository`), the media bubble,
viewer, and the one deliberate export. Received media lives ONLY in the
encrypted store, never the system gallery (spec §5.1); export is a deliberate
share-sheet act.

## Layout

- `model/` — Flutter-free leaf value types.
  - `media_attachment.dart` — a picked+processed attachment ready to seal
    (post-strip, post-compress plaintext; the bytes the manifest hashes).
  - `media_transfer_state.dart` — the media bubble's transfer phase
    (sending / receiving / loaded / failed) + advisory progress.
- `transfer/` — Flutter-free protocol/store glue (the connection lane holds a
  reference — the import-direction fence).
  - `media_chunker.dart` — attachment → manifest + ordered chunk envelopes,
    consuming the frozen codec verbatim (65,536-B chunks; SHA-256 hash).
  - `media_reassembler.dart` — per-transfer buffers; hash-verifies on
    completion; discard + NO ACK on any transfer-integrity failure (spec §5.1).
  - `media_transfer_controller.dart` — the orchestrator the session delegates
    to: persist blob + index, transmit, reassemble, expiry purge.
- `pipeline/` — the on-device processing + platform seams.
  - `image_processor.dart` — THE `package:image` call site: EXIF/metadata
    strip + compression in `Isolate.run`, network-incapable by construction.
  - `media_mime.dart` — in-repo MIME derivation (no `mime` package).
  - `attachment_picker.dart` — the second `file_picker` call site (photo/file).
  - `media_export.dart` — the second `share_plus` call site (decrypt-to-temp →
    share → cleanup; the one quarantine exit).
- `ui/` — the media widgets (BINDING to components.md media block).
  - `media_bubble_content.dart` — image edge-to-edge / document row / progress
    line (consumed by the chat lane's `message_bubble.dart`).
  - `attach_sheet.dart` — attach options + preview (metadata-strip notice,
    original-quality toggle off by default, over-cap error).
  - `media_viewer.dart` — full-bleed viewer + Export (pushed on-the-fly, no
    named route).

## Invariants (test-enforced)

- EXIF/metadata stripped BEFORE encryption, on-device, provably absent post
  strip (`test/media/image_processor_test.dart`).
- Reassembly hash mismatch / incomplete = discard + NO ACK, never a protocol
  error (`media_chunker_reassembler_test.dart`, `media_transfer_integration_test.dart`).
- Expiry deletes the media_ix row + blob + message on both ends (integration).
- `package:image` fenced to `image_processor.dart`; `transfer/` + `model/`
  Flutter-free; no gallery/photo-roll save API anywhere in `media/`
  (`media_fences_test.dart`).
