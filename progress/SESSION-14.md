# SESSION-14 — Screenshot policy & sensitive-content handling

Branch `session-14-screenshot-sensitive`. Lane: `application/mobile/` only.
Consumes the FROZEN v0.2.1 codec (envelope encode/decode untouched); CONTROL
0x03 was already defined — this session only uses it.

## What was produced + where

### New modules
- `lib/src/screenshot/`
  - `screenshot_notice.dart` — transient, session-scoped system-line model
    (`own` + `timestampMs` + nullable `anchorRecordId`). Pure Dart; NEVER a
    `MessageRecord`, never persisted (an event, not speech).
  - `screenshot_detector.dart` — `ScreenshotDetector` interface +
    `PlatformScreenshotDetector` (MethodChannel `app.nimna/screenshot`;
    `start`/`stop`/`onScreenshot`).
  - `screenshot_system_line.dart` — the bare centered `caption` in
    `textTertiary`, no bubble/icon, 16 vertical padding (string 12).
  - `README.md`.
- `lib/src/sensitive/`
  - `sensitive_content_analyzer.dart` — `SensitiveContentAnalyzer` interface;
    `PlatformSensitiveContentAnalyzer` (MethodChannel `app.nimna/sensitive`,
    iOS-only, fail-open); `NoOpSensitiveContentAnalyzer`.
  - `sensitive_image_veil.dart` — recipient-side blur veil (blurSigma 24 +
    mediaVeil + string 15 caption; tap reveals with `durStandard` cross-fade).
  - `sensitive_whisper_card.dart` — sender-side whisper (string 14; surface2
    radius 16, non-blocking, never amber/danger).
  - `README.md`.

### Wiring into existing files
- `lib/src/session/connection/session_controller.dart` — `+import
  screenshot_notice`; `_screenshotNotices` list + `screenshotNotices` getter;
  `noticeLocalScreenshot()` (seals CONTROL 0x03 empty payload when live, records
  own line); `_recordScreenshotNotice()`; inbound `ControlType.screenshot` case
  now records the peer line (was the S14 TODO stub).
- `lib/src/session/model/chat_event.dart` — `+ScreenshotNoticed(own)` event.
- `lib/src/session/chat/chat_screen.dart` — owns `ScreenshotDetector` lifecycle
  (start on mount = content on screen, stop+dispose on unmount →
  `noticeLocalScreenshot()`); interleaves screenshot system lines into the
  thread by anchor (`_threadChildren`, never re-sorting messages); threads the
  `SensitiveContentAnalyzer` to bubbles + the attach sheet. Two new optional
  injected params: `screenshotDetector`, `sensitiveAnalyzer` (default to the
  platform impls; fakes in tests).
- `lib/src/session/chat/message_bubble.dart` — `+sensitiveAnalyzer` param,
  forwarded to `MediaBubbleContent`.
- `lib/src/media/ui/media_bubble_content.dart` — `+sensitiveAnalyzer`; wraps a
  RECEIVED image in `SensitiveImageVeil` (sender's own image never blurred).
- `lib/src/media/ui/attach_sheet.dart` — `showAttachSheet`/`AttachImagePreview`
  take an analyzer; a flagged image raises the whisper once (dismissed on edit).
- `lib/src/storage/storage_service.dart` — the S13→S14 requirement (below).

### Native
- `ios/Runner/AppDelegate.swift` — `+import SensitiveContentAnalysis`; two new
  MethodChannels: `app.nimna/screenshot` (observes
  `UIApplication.userDidTakeScreenshotNotification` between start/stop, invokes
  `onScreenshot`) and `app.nimna/sensitive` (`analyze` → `SCSensitivityAnalyzer`
  on iOS 17, returns Bool, fail-open on any error / <17). No FLAG_SECURE analog.
- `android/app/src/main/kotlin/app/nimna/MainActivity.kt` — the FIRST custom
  Android MethodChannel `app.nimna/screenshot`:
  `registerScreenCaptureCallback` gated `SDK_INT >= 34`, unregister on pause /
  re-register on resume. NO FLAG_SECURE, NO sensitive-content on Android.
- Info.plist / entitlements: NONE added — screenshot needs none;
  `SensitiveContentAnalysis` requires no special entitlement. (Confirmed against
  intake §3.)

### l10n
- EN canonical keys added to `lib/l10n/app_en.arb`; l10n regenerated
  (`flutter gen-l10n`). Non-EN ARB files stay `@@locale`-only — gen-l10n falls
  back to English (the established S12 pattern), so de/fr/es/it were NOT edited.

## ARB keys added (7)
- `screenshot_systemLinePeer` — "They took a screenshot." (string 12, verbatim)
- `screenshot_systemLineOwn` — "You took a screenshot. They've been told."
  (string 12, verbatim)
- `screenshot_onboardingDisclosure` — string 11, verbatim (STAGED, see note)
- `screenshot_onboardingAndroidCaveat` — the honest sub-Android-14 caveat
  (STAGED, see note)
- `sensitive_veilCaption` — "Sensitive content — tap to view." (string 15)
- `sensitive_whisperQuestion` — "This looks like sensitive content — send
  anyway?" (string 14, verbatim)
- `sensitive_whisperSendAnyway` — "Send anyway"
- `sensitive_whisperGoBack` — "Go back"

All flagged `Enters the S16 crafted-translation pass` in their `@`-descriptions.

## The three LOCKED DECISIONS (record verbatim; rationale)

1. **USER — Android screenshot detection floor.** Detect on Android 14+ only
   via `Activity.registerScreenCaptureCallback` (`SDK_INT >= 34`) + iOS 17 via
   `UIApplicationUserDidTakeScreenshotNotification`. On Android 10–13 there is
   NO notice, disclosed honestly. ZERO extra permissions: no media-read grant,
   no ContentObserver, no screenshots-folder watching. Rationale: a screenshot
   is a system event, not a file to read; asking for gallery permission to
   watch a folder would betray the privacy posture, and the honest gap is
   disclosed rather than papered over. Implemented + the honest caveat copy is
   staged (`screenshot_onboardingAndroidCaveat`).

2. **USER — AeadAuthError auto-reset is SILENT.** No user-facing surface at
   all. Implemented in `StorageService.open()` (below). Rationale: an
   interrupted-wipe / keystore-loss signature is indistinguishable from a fresh
   install by design; a lock/wipe dialog would leak that "something was here."

3. **CODE — Android sensitive-content = iOS-only at launch.**
   `SensitiveContentAnalysis` (recipient blur + sender whisper) runs on iOS 17
   only. On Android there is no blur and no whisper at launch. Rationale: no
   first-party on-device equivalent exists on Android, and bundling an ML model
   is rejected on the minimal-deps standing rule; the iOS-only-at-launch
   fallback is pre-approved (spec §5.3, plan S14). The Android path is a
   deliberate `NoOpSensitiveContentAnalyzer` (fail-open = no blur, no whisper).

## S13→S14 storage requirement (requirement 4)
`StorageService.open()` now permits ONE silent fresh-install-reset: if
`ChannelRepository.openAll()` raises `AeadAuthError`, it destroys the MK, drops
the diag ring, closes the DB, seals, `root.wipeAndRecreate()`, and re-runs the
now-empty open (loop, guarded so a second failure rethrows). New private
`_freshInstallReset(db)` mirrors `fullWipe`'s key-first destruction. SILENT:
no lock/wipe UI, `wasReset` is NOT propagated, and no diag event marks it (a
post-reset store must be indistinguishable from a fresh install). Precedent:
`bootstrap.dart:152` already catches `AeadAuthError` for the pending-pairing
meta record.

## Route / README additions (for the orchestrator to fold)
- Routes: NONE. No named routes added — the detector/analyzer are injected into
  the existing `ChatScreen` (constructed at `lib/src/app/routes.dart:61`); the
  media viewer/attach continue to push on-the-fly. `routes.dart` untouched.
- READMEs updated: `lib/README.md` (module index +`src/screenshot/`
  +`src/sensitive/`), `lib/src/screenshot/README.md` (new),
  `lib/src/sensitive/README.md` (new), `lib/src/session/model/README.md`,
  `lib/src/session/connection/README.md`, `lib/src/session/chat/README.md`,
  `lib/src/media/ui/README.md`.

## Native-config additions
- iOS: `app.nimna/screenshot` + `app.nimna/sensitive` MethodChannels;
  `import SensitiveContentAnalysis` (weak-linked at build). No plist /
  entitlement changes.
- Android: `app.nimna/screenshot` MethodChannel; no manifest changes, no new
  permissions, no FLAG_SECURE.

## Device-deferral note (S18 rung)
Real screenshot capture (iOS notification + Android 14 `ScreenCaptureCallback`)
and real `SensitiveContentAnalysis` on a physical iPhone are the S18
device-verification rung. All Dart logic + native glue is built now; the Dart
paths and codec are tested headlessly (fakes injected for detector + analyzer).

## Website-copy-need note (S19)
The `/security` page needs honest copy for the Android screenshot gap (Android
10–13 receives no screenshot notice; only Android 14+ and iOS do). Flagged for
S19 website copy. The in-app onboarding caveat is staged as
`screenshot_onboardingAndroidCaveat`.

## Open item flagged for the orchestrator / PM
`screenshot_onboardingDisclosure` (string 11) and
`screenshot_onboardingAndroidCaveat` are STAGED canonical copy: there is
currently NO onboarding host screen in `lib/src/` (grep for "onboarding" in
lib/src is empty — wireframe F1 onboarding is a separate/future screen, S7/S16).
The keys carry the copy so the disclosure is ready; the onboarding session must
render them. Not rendered by any widget in this session — noted so a reviewer
does not read them as dead keys.

## Tests (all headless; `test/screenshot/`, `test/sensitive/`, + existing files)
- `test/screenshot/screenshot_widgets_test.dart` — system line own/peer copy
  (string 12 verbatim); `PlatformScreenshotDetector` start/stop invoke the
  channel; a native `onScreenshot` call emits on the stream.
- `test/sensitive/sensitive_widgets_test.dart` — veil blurs + string 15 +
  tap-reveals; a clear image is never blurred (fail-open); whisper card copy +
  callbacks (string 14); a flagged attachment raises the whisper in
  `AttachImagePreview`; analyzer NoOp/off-iOS/iOS-flag/fail-open.
- `test/session/session_controller_test.dart` — screenshot round trip (CONTROL
  0x03 → peer system line, own recorded, never a message); notice is a no-op
  when not live.
- `test/storage/storage_service_test.dart` — AeadAuthError on open → silent
  fresh-install-reset (empty store, fresh MK, no throw).
- `test/session/chat_screen_test.dart` [SHOULD-FIX, added at review] — the
  ChatScreen detector-lifecycle composition with an injected fake detector:
  start-on-mount, stop()+dispose()-on-unmount, and a screenshot emitted while
  NOT live records no line (the §5.2 privacy gate).

## Code-review NITs (review PASS 2026-07-08; no blockers)
- **SHOULD-FIX applied** — `test/session/chat_screen_test.dart` (above) now
  guards the detector-lifecycle composition; a regression dropping `stop()`/
  `dispose()` from `ChatScreen.dispose`, or the liveness gate, fails there.
- **NIT applied** — `_freshInstallReset` now closes the local `channelRepo` and
  nulls the repo fields for symmetry with `fullWipe` (cosmetic; no dangling
  resource today — the repo held no loaded keys after a failed `openAll`).
- **NIT noted, left as-is** — the iOS screenshot observer is torn down on
  stop/unmount but NOT on background (Android unregisters on `onPause`). Safe
  today: `UIApplicationUserDidTakeScreenshotNotification` is not delivered to a
  suspended app, so a backgrounded Nimna cannot fire a spurious notice. Confirm
  at the S18 device rung; if iOS ever changes that, add a background stop/start
  pair in `AppDelegate`.
- **NIT noted, left as-is** — an over-cap flagged image shows the size error but
  not the whisper (the size guard must clear first). Consistent with the
  non-blocking / fail-open posture: the whisper is caution sugar and an over-cap
  image cannot be sent until resized anyway.

## What's next
- S16 crafts the 4-language translations for the 8 new ARB keys.
- The onboarding host (F1) must render `screenshot_onboardingDisclosure` +
  `screenshot_onboardingAndroidCaveat`.
- S18 device rung: real capture + real SensitiveContentAnalysis.
- S19: `/security` copy for the Android screenshot gap.
