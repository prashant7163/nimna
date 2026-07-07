# lib/src/media/model/

Flutter-free leaf value types for the media lane (S11). Carried on
`MessageView` and across the connection lane without breaking the
import-direction fence.

- `media_attachment.dart` — a picked+processed attachment ready to seal
  (post-strip, post-compress plaintext; the bytes the manifest hashes).
- `media_transfer_state.dart` — the media bubble's transfer phase
  (sending / receiving / loaded / failed) + advisory 0..1 progress.
