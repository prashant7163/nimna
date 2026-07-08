# lib/src/screenshot/

Screenshot policy — **detect-and-notify only** (S14, spec §5.2, §5.5). Nimna
cannot PREVENT a screenshot and never pretends to: no FLAG_SECURE analog, no
blocking. It only NOTICES one taken while session content is on screen inside
the app, so the peer is always told (voice string 11/12). Delivery is
honor-system like expiry. ZERO extra permissions.

Platform floor (USER 2026-07-07): iOS 17
(`UIApplicationUserDidTakeScreenshotNotification`) + Android 14+
(`Activity.registerScreenCaptureCallback`, `SDK_INT >= 34`). On Android 10–13
there is NO notice — the honest gap, disclosed in onboarding copy.

- `screenshot_notice.dart` — the transient, session-scoped system-line model
  (own/peer + anchor). Pure Dart (no Flutter): the connection lane holds it.
  NEVER a `MessageRecord`, never persisted — an event, not speech.
- `screenshot_detector.dart` — `ScreenshotDetector` interface + the
  `PlatformScreenshotDetector` MethodChannel (`app.nimna/screenshot`). The chat
  screen `start()`s it only while mounted (content on screen) and `stop()`s on
  dispose; the controller additionally gates emission on liveness.
- `screenshot_system_line.dart` — the bare centered `caption` in `textTertiary`
  (no bubble, no icon, 16 vertical padding — components.md system line), voice
  string 12 verbatim.

Wire: on detection, `SessionController.noticeLocalScreenshot()` seals CONTROL
0x03 (empty payload) and records the own-side line; an inbound CONTROL 0x03
records the peer-side line. The connection lane consumes the FROZEN v0.2.1
codec — it does not modify the envelope.

Device rung (S18): a real capture on a physical device. The Dart glue is
tested headlessly (`test/screenshot/`).
