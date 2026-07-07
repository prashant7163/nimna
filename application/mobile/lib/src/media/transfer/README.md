# lib/src/media/transfer/

Flutter-free protocol/store glue (S11) — the connection lane holds a
`MediaTransferController`, so nothing here may import Flutter (the
import-direction fence). Consumes the FROZEN v0.2.1 codec (S10) verbatim.

- `media_chunker.dart` — attachment → MEDIA_CHUNK manifest + ordered chunk
  envelopes (65,536-B chunks; SHA-256 content hash).
- `media_reassembler.dart` — per-transfer buffers; hash-verifies on
  completion; discard + NO ACK on any transfer-integrity failure (spec §5.1).
- `media_transfer_controller.dart` — the orchestrator the session delegates
  to: persist blob+index, transmit, reassemble, expiry purge.
