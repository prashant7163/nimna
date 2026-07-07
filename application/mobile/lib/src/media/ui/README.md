# lib/src/media/ui/

The media widgets (S11) — BINDING to `designs/system/components.md` media
block and `tokens.json`. Hold no transport/store state; decrypt-to-memory via
callbacks the chat screen routes through the session controller.

- `media_bubble_content.dart` — image edge-to-edge / document row / 2 px
  transfer progress line (consumed by chat/message_bubble.dart).
- `attach_sheet.dart` — attach options + preview (metadata-strip notice,
  original-quality toggle off by default, over-cap error — voice string 17).
- `media_viewer.dart` — full-bleed viewer + Export (pushed on-the-fly; no
  named route — routes.dart untouched).
