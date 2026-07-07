# lib/src/media/pipeline/

On-device processing + platform seams for the media lane (S11).

- `image_processor.dart` — THE `package:image` call site: EXIF/metadata strip
  + compression in `Isolate.run`; network-incapable by construction.
- `media_mime.dart` — in-repo MIME derivation (no `mime` package).
- `attachment_picker.dart` — the second `file_picker` call site (photo/file).
- `media_export.dart` — the second `share_plus` call site (decrypt-to-temp →
  share → immediate cleanup; the one deliberate quarantine exit).

The picker + export are device-dependent platform channels (S7/S18 rung); the
image processor and MIME map are fully headless.
