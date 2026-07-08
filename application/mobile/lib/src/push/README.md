# `lib/src/push` — notifications end-to-end, the push CLIENT (S15)

Acquires THIS device's own push token, puts it on the wire **only inside E2E
payloads**, and routes a content-free wake back into the app. It consumes the
FROZEN v0.2.1 codec (`token_payload` §5.7) and the already-built relay
APNs/FCM transports — no envelope changes.

## Doctrines this lane enforces
- **Push is opt-IN, DEFAULT OFF** (spec §3.2.1, voice string 18). Off = pure
  burner-line mode: `Firebase.initializeApp()` is never called and NOTHING
  about the device touches Apple or Google. Only an opted-in line acquires a
  token.
- **Content-free** (spec §3.2). The only body that ships is the two words
  **"New activity"** — the relay sends the loc-key `NEW_ACTIVITY`, the OS
  renders it from the app bundle (iOS `Localizable.strings`, Android
  `strings.xml`). No line, no name, no message — ever. In-app suppression:
  a knock landing while foregrounded shows no OS banner.
- **The token lives only peer-held + encrypted** (§4, §5.7). This device's
  own token rides the E2E handshake / token-refresh CONTROL; the relay sees a
  token transiently inside one KNOCK and forgets it. Opting out sends the
  absent-form REVOKE — unilateral and permanent.
- **One Google SDK, fenced** (USER decision 1). `firebase_messaging` +
  `firebase_core` are messaging-only and imported by EXACTLY ONE file
  (`fcm_push_source.dart`); `test/push/push_dependency_fence_test.dart`
  asserts it, and that no analytics/crash SDK appears anywhere. iOS is pure
  native APNs — no SDK at all.

## Files
| File | Lane | Responsibility |
|---|---|---|
| `platform_push_source.dart` | pure Dart + streams | The `PlatformPushSource` interface (acquire own token → §5.7 present/absent, rotations, taps, foreground) + `InertPushSource` (push unsupported — host tests, desktop). |
| `apns_push_source.dart` | Flutter (services) | iOS: native APNs over the `app.nimna/push` method channel. Returns the RAW 32-byte device token (the relay hex-encodes it). NO SDK. |
| `fcm_push_source.dart` | **firebase** | Android: FCM via `firebase_messaging`. THE sole firebase import site. Lazy init (only on opt-in), auto-init off, token as UTF-8 bytes. |
| `push_source_factory.dart` | `dart:io` | Picks the source by platform (APNs iOS / FCM Android / inert elsewhere) — the only platform branch. |
| `push_service.dart` | pure Dart | The orchestrator: own-token acquisition + caching, `bindSession` → §5.5 token-refresh on live / on rotation, `onOptInChanged` announce/revoke, `notificationTaps`, `setForeground`. Takes a lazy opt-in lookup (never a captured channel repo). |

## Where it wires in
- **Composition root** (`app/bootstrap.dart`): builds `PushService` over
  `defaultPushSource()` with a lazy `isOptedIn` lookup; exposed via
  `AppScope`.
- **App root** (`app/app.dart`): tap stream → bring the Navigator to root
  (the knock-answer surface mounts there at S16); lifecycle → foreground
  suppression.
- **Session launch** (`presence/session_launcher.dart`): the `onSessionBound`
  hook = `PushService.bindSession`, so every launched session announces this
  device's own token once live (opted-in only).
- **The mount** (`ui/screens/settings/notifications_directory_screen.dart` +
  `channel_notifications_screen.dart`): Settings → Notifications → a line →
  the F7 push toggle (the previously-inert `PushOptInTile`, now live).

## Deferred (USER decision 2 → PUBLISH_READY / S18–S19)
Live real-device push against `api.push.apple.com` / `fcm.googleapis.com`
needs a real Apple APNs key, a real Firebase project + `google-services.json`
(+ the `google-services` Gradle plugin), the iOS entitlement wired into the
Xcode target, and physical devices. Built + mock/headless-verified now; the
hand-step is documented in `progress/SESSION-15.md`. The relay's
`-apns-sandbox` flag routes dev-build tokens to Apple's sandbox host.
