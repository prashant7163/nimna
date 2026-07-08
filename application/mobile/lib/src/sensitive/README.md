# lib/src/sensitive/

On-device sensitive-content handling (S14, spec §5.3) — a purely LOCAL display
decision, never moderation. HARD BOUNDARY: nothing is blocked, logged,
reported, or transmitted; the sender is NEVER told of recipient-side flags;
there are NO network calls. Our safety features have nowhere to phone home.

Platform floor (CODE decision, 2026-07-07): **iOS 17 only**
(`SensitiveContentAnalysis`). Android has no first-party on-device equivalent
and bundling an ML model is rejected on minimal-deps grounds — so Android does
NOT blur and does NOT whisper at launch (the pre-approved iOS-only fallback,
spec §5.3). FAIL-OPEN everywhere: a miss / unavailable framework / non-iOS /
any error → not sensitive (no blur, no whisper). Display sugar, not security.

- `sensitive_content_analyzer.dart` — `SensitiveContentAnalyzer` interface;
  `PlatformSensitiveContentAnalyzer` (MethodChannel `app.nimna/sensitive`,
  iOS-only, fail-open); `NoOpSensitiveContentAnalyzer` (the Android/default).
- `sensitive_image_veil.dart` — recipient-side blur: a RECEIVED flagged image
  renders blurred (`NimnaMedia.blurSigma` = 24) under `mediaVeil` with caption
  "Sensitive content — tap to view." (string 15); tap reveals in place with a
  `durStandard` cross-fade. Sender's own images are never blurred.
- `sensitive_whisper_card.dart` — sender-side whisper (string 14): a soft,
  non-blocking, never-modal card at attach time — "This looks like sensitive
  content — send anyway?" `[Send anyway]` / `[Go back]`. Never amber, never
  danger; at most once per attachment.

Recipient blur wires through `media/ui/media_bubble_content.dart` (received
images only); the whisper wires through `media/ui/attach_sheet.dart`. Both take
the injected analyzer from the chat screen.

Device rung (S18): a real `SensitiveContentAnalysis` pass on a physical iPhone.
The Dart logic is tested headlessly with a fake analyzer (`test/sensitive/`).
