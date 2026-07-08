# SESSION-15 — Notifications end-to-end (push client)

Branch `session-15-notifications`. Consumes the FROZEN v0.2.1 codec; the
envelope layer (`lib/src/protocol/`) is untouched. Full agent pipeline still
to run (code-review → senior-qa) before the orchestrator merges.

Stamp: 2026-07-08 11:45 +0200.

---

## What was produced + where

### The push client — `lib/src/push/` (net-new module)
- `platform_push_source.dart` — the `PlatformPushSource` interface (acquire own
  token → §5.7 present/absent, OS rotations, content-free taps, foreground
  seam) + `InertPushSource` (push unsupported: host tests, desktop → zero
  third-party touch by construction).
- `apns_push_source.dart` — iOS **native APNs, NO SDK**: the `app.nimna/push`
  method channel (same hand-glue pattern as `app.nimna/storage`). Returns the
  RAW 32-byte device token (relay hex-encodes it into `/3/device/<hex>`).
- `fcm_push_source.dart` — Android FCM via `firebase_messaging`. **THE sole
  firebase import site.** Lazy `Firebase.initializeApp()` (only on opt-in),
  auto-init force-disabled, token as UTF-8 bytes (relay sends `message.token`
  verbatim). Any init failure (no Firebase project wired yet) degrades to
  burner mode.
- `push_source_factory.dart` — `defaultPushSource()` picks APNs/FCM/inert by
  `Platform` (the only platform branch in the lane).
- `push_service.dart` — the orchestrator: own-token acquisition + caching,
  `bindSession` → §5.5 token-refresh CONTROL when a line goes live and on OS
  rotation, `onOptInChanged` (eager acquire on opt-in — the honest permission
  moment; absent-form REVOKE on opt-out), `notificationTaps`, `setForeground`.
  Takes a **lazy `PushOptInLookup`** (not a captured `ChannelRepository`) so no
  stale repo is held across a seal/unseal cycle.

### Wiring (shared hotspots)
- `app/bootstrap.dart` — builds `PushService` over `defaultPushSource()` with a
  lazy `isOptedIn` lookup; added `PlatformPushSource? pushSource` injection for
  tests. `app/app_scope.dart` — exposes `pushService` on `NimnaServices`.
- `app/app.dart` — now stateful: notification tap → Navigator to root (F6
  knock-answer surface mounts there at S16); lifecycle → `setForeground`
  (in-app suppression). No-op with the inert source.
- `presence/session_launcher.dart` — added the optional `onSessionBound` hook
  (bare `SessionBoundHook` typedef; presence never imports the push lane) wired
  to `PushService.bindSession`. This is the ONLY presence-lane edit.
- `SendTokenRefresh` seam (peer_token_store.dart typedef) fulfilled:
  `PushService.bindSession` calls `SessionController.sendTokenRefresh` with THIS
  device's own token. Receive side (`onPeerTokenRefresh`) unchanged (S12).
- The pairing send path was **left absent-form** (join/initiator controllers
  untouched): push opt-in is strictly per-channel and the channel does not
  exist at pairing time, so the token necessarily rides the post-opt-in
  token-refresh CONTROL, never the M2/M3 handshake in the shipped model. No
  retrofit needed — flagged for reviewer.

### The reachable mount (requirement 4)
- `ui/screens/settings/notifications_directory_screen.dart` — Settings →
  "Notifications" (row now live, was inert S13) → per-line directory.
- `ui/screens/settings/channel_notifications_screen.dart` — minimal F7 mount:
  nav bar (channel label) + `channelSettings_subtitle` + the previously-inert
  `PushOptInTile`, wired to `PushOptIn.setEnabled` + `PushService.onOptInChanged`.
  Full F7 (label/receipts/typing/per-line wipe) remains S16.

### Content-free "New activity" body (net-new — there was no NEW_ACTIVITY string)
- Dart ARB `push_newActivityBody` = "New activity".
- iOS `ios/Runner/{en,de,fr,es,it}.lproj/Localizable.strings` — `NEW_ACTIVITY`.
- Android `res/values{,-de,-fr,-es,-it}/strings.xml` — `NEW_ACTIVITY`
  (+ `default_notification_channel_id`, translatable=false).
- EN canonical (voice string 18's "two words"); non-EN carry the EN
  placeholder for the S16 crafted-translation pass.

### Native config
- iOS `AppDelegate.swift`: `app.nimna/push` channel (registerForToken /
  setForeground), `registerForRemoteNotifications`, `UNUserNotificationCenter`
  delegate — `willPresent` returns `[]` (foreground suppression), `didReceive`
  → tap. `Info.plist`: `UIBackgroundModes` = remote-notification,
  `CFBundleLocalizations`. `Runner.entitlements`: `aps-environment` =
  development.
- Android `AndroidManifest.xml`: `POST_NOTIFICATIONS`; FCM auto-init OFF +
  analytics collection OFF/deactivated (belt-and-suspenders) + default channel
  meta-data.

### Relay (verified, not rebuilt)
- Confirmed content-free by construction (`push.go` loc-key/title_loc_key =
  NEW_ACTIVITY only; no token/identity in bodies) and stateless (token
  discarded after one call).
- Added the S15 APNs **sandbox switch**: `-apns-sandbox` flag →
  `APNsSandboxBaseURL` (dev-build `aps-environment=development` tokens route to
  `api.sandbox.push.apple.com`). Config-only; content-freeness/statelessness
  untouched. `go build/test/vet ./...` + `gofmt -l .` clean.

---

## Locked decisions (honored)

1. **USER — push SDK split.** iOS via native APNs (no third-party SDK:
   `UNUserNotificationCenter` + `registerForRemoteNotifications`, pure Apple).
   Android via `firebase_messaging` (pulls `firebase_core` + Play Services) —
   the ONE Google SDK, justified because Android push is impossible without
   Google FCM. Gated behind per-channel opt-in, DEFAULT OFF, disclosed by voice
   string 18. Pinned exact; pin-time no-telemetry audit recorded (below).
   Architect sign-off granted under this decision for the network-touching
   deps — noted.
2. **USER — live push verification deferral.** Full client built + wired to the
   already-built relay APNs/FCM transports; verified headless/mock now. Live
   real-device push against `api.push.apple.com` / `fcm.googleapis.com` (needs a
   real Apple APNs key + a real Firebase project + physical devices) rides a
   documented hand-step to PUBLISH_READY / S18–S19 — same pattern as S6
   live-relay, S7/S8/S13 device rungs, S17 sandbox.

---

## Dependency additions + no-telemetry audit (pin-time)

Added to `pubspec.yaml` (exact-pinned), fenced to `lib/src/push/`:
- `firebase_core: 4.11.0`
- `firebase_messaging: 16.4.1`

**Dart transitive subtree (`flutter pub deps`):** `firebase_core`,
`firebase_core_platform_interface`, `firebase_core_web`, `firebase_messaging`,
`firebase_messaging_platform_interface`, `firebase_messaging_web`,
`_flutterfire_internals`. **NO** `firebase_analytics`, `firebase_crashlytics`,
`firebase_performance`, `firebase_installations` (telemetry), `datatransport`,
`measurement`, `sentry`, or `beacon` — clean, messaging-only.

**Android native note (honest):** `firebase_messaging`'s Android artifact does
carry FCM's own delivery mechanics (Firelog/datatransport) — that is the
disclosed cost of Android push (voice string 18: "wake this phone through their
notification service … the relay forgets the address"), NOT Nimna telemetry.
Suppressed to the extent possible: no `firebase-analytics` dependency (the
measurement connector has no sink), and `firebase_messaging_auto_init_enabled`
/ `firebase_analytics_collection_enabled` = false +
`firebase_analytics_collection_deactivated` = true in the manifest, plus lazy
init only on opt-in.

**Fence:** `test/push/push_dependency_fence_test.dart` asserts firebase is
imported by EXACTLY ONE file (`fcm_push_source.dart`) and that no
analytics/crash/notification SDK appears anywhere under `lib/`. This REPLACES
the S12 blanket ban (`test/presence/no_push_sdk_test.dart`, deleted).

---

## ARB keys added (namespaced; EN canonical, non-EN @@locale EN-fallback)
- `push_newActivityBody` — "New activity" (the entire content-free body).
- `channelSettings_subtitle` — "Line settings — this phone only" (F7 header).
l10n regenerated (`flutter gen-l10n`); non-EN files carry only `@@locale` and
fall back to EN pending S16.

## Route registrations (for the orchestrator's fold — `app/routes.dart`)
- `Routes.notifications = '/settings/notifications'` → `NotificationsDirectoryScreen`.
- `Routes.channelNotifications = '/settings/notifications/channel'` →
  `ChannelNotificationsScreen` (arg `ChannelNotificationsArgs{channelId,label}`).
- Settings root "Notifications" row now navigates to `Routes.notifications`.

## READMEs
- New `lib/src/push/README.md`; `lib/README.md` module index + `test/README.md`
  index updated; `lib/src/presence/README.md` session_launcher row notes the
  `onSessionBound` hook. Native lproj/values dirs are inside the exempt native
  trees.

## analysis_options.yaml
- Added `analyzer.exclude: [build/**]` — the firebase SPM checkout drops its own
  `test/mock.dart` (older mockito) under the git-ignored `build/`; it is not our
  code and must never be analyzed.

---

## S6 DEFERRAL 2 absorption + the live-push hand-step (→ PUBLISH_READY / S18–S19)

**Absorbing DEFERRAL 2 (USER, 2026-07-04 21:59 — "live APNs/FCM platform
verification is DEFERRED TO S15").** S15 discharges the CLIENT half at the mock
boundary and re-defers the LIVE real-device half (per USER decision 2). What is
verified now (headless/mock): own-token acquisition + §5.7 wrapping (APNs raw
bytes, FCM UTF-8), the token-refresh CONTROL announced on live and persisted by
the peer, the absent-form revoke, opted-OUT = nothing leaves, content-free body
across ARB + iOS + Android, tap/foreground pass-through, the reachable opt-in
mount, and the fence. Relay side already mock-verified at S6 (JWT ES256/RS256
against runtime keys, exact request shapes, h2, sink E2E).

**The live-push hand-step (turnkey list):**
1. Apple: create an APNs Auth Key (.p8); set relay `-apns-key-file/-key-id/
   -team-id/-topic`. iOS: wire `Runner.entitlements` into the Xcode target
   (`CODE_SIGN_ENTITLEMENTS`), flip `aps-environment` to `production` for
   store/TestFlight; dev/sandbox tokens use relay `-apns-sandbox`.
2. Google: create a Firebase project; add `android/app/google-services.json`;
   apply the `com.google.gms.google-services` Gradle plugin (classpath +
   `apply`); set relay `-fcm-sa-file` (service-account JSON).
3. Two physical devices + a live relay: pair, opt into push on one line, hang
   up, knock while the peer is backgrounded → assert one content-free "New
   activity" wake; tap → open → reconnect.

---

## What's next
- **Code-review + senior-qa done-check**, then orchestrator merge (route fold,
  pubspec union, ARB namespaced keys, README index).
- **S16** (per-line F7 polish + crafted translations): the full F7 screen
  (label/receipts/typing/per-line wipe) around this push toggle; the F6
  incoming-knock surface the tap route lands on; NEW_ACTIVITY + the two new ARB
  keys enter the crafted-translation pass.
- **S18** device rung + **S19** store/live-push: the deferred live verification.

## Checks (green in-worktree)
- `flutter analyze` — no issues. `dart format --set-exit-if-changed lib test` —
  clean. `flutter test` — **415 pass, 0 skipped** (baseline 393; +23 push
  tests, −1 deleted ban test). Push suite 23/23, 3× repeat 0-flake.
- Relay `go build/test/vet ./...` + `gofmt -l .` — clean.

## Reviewer / QA — scrutinize
- Fence completeness (firebase single-site; analytics/crash absent).
- Content-free invariant (only NEW_ACTIVITY ships; native strings define only
  that key).
- The lazy `PushOptInLookup` (no stale channel-repo capture across seal/unseal).
- The pairing-plane absent-form decision (token rides token-refresh, not M2/M3)
  — confirm this matches the intended shipped model.
- The S12 `knockPayloadFor` gating on `record.pushOptIn` (the knocker's own
  opt-in gates carrying the PEER's token). Left AS-IS per intake ("ensure the
  knock path uses it — it should already"); noted as a possible semantic to
  confirm, not changed.
