# Session 16 — Polish & first-run

## Tech-architect intake memo (start-of-session)

**Author:** tech-architect · **Date:** 2026-07-08 · **Kind:** start-of-session
analysis (Phase-4 open). Not implementation. Appends to
`docs/architecture/app-architecture.md` §11's S16 line; binding on S16 build.

**Codec-frozen invariant CONFIRMED for S16.** S16 owns the whole `lib/`
cross-cut (onboarding, empty/error states, dark mode, a11y, microcopy sweep,
DE/FR/ES/IT translation) plus the two seams below. NONE of that touches
`lib/src/protocol` envelope layout, the `lib/src/noise` transport, or the wire
formats/limits/TTLs. The production-wiring work (Concern 1) *consumes* the
frozen codec via `SessionLauncher`/`SessionController`; it constructs no new
frame type and alters no §5.5–§5.8 encoding. **Anything that would edit an
inner-envelope field, a frame-type byte, a nonce rule, or a body layout is
out of scope and re-serializes protocol work per the S10 checkpoint rule.**

---

### Concern 1 — production SessionLauncher wiring (S15 forward-requirement)

**Finding: the presence/knock/session-launch stack has NO production
composition root today.** `SessionLauncher`, `KnockController`,
`IncomingKnockController`, and `ReconnectCoordinator` are constructed ONLY in
`test/`. `bootstrapNimna()` (`lib/src/app/bootstrap.dart`) builds and holds in
`NimnaServices`: keyService, storage, diag, pairing, joiner, lockController,
wipe, billing, **pushService** — but no launcher and no presence stack. The
`/chat` route (`lib/src/app/routes.dart:80`) takes a `ChatScreenArgs` carrying
an already-built `SessionController`; nothing in `lib/` navigates to it in
production. So S15's `onSessionBound` hook is seam-ready
(`session_launcher.dart:51,132` fires `_onSessionBound?.call(...)`) but there
is no production `SessionLauncher(...)` to attach it to.

**Minimal correct wiring:**

1. In `bootstrapNimna()`, construct the presence/session stack from services
   already in scope: `SessionLauncher(sodium, aead, connector, channels,
   messages, diag, media, pushOptIn, peerTokenStore, clock,
   onSessionBound: pushService.bindSession)`. `pushService` is built at
   `bootstrap.dart:136` BEFORE the return — the hook is a bare typedef
   (`presence` never imports the push lane), so passing
   `pushService.bindSession` here is the whole wiring. This is the single line
   the S15 forward-requirement is about.
2. Add `sessionLauncher` (and the knock/incoming/reconnect controllers, as the
   presence-mount UX needs them) to `NimnaServices` / `AppScope` so the
   channel-list → knock → chat flow resolves them from the one DI surface.
3. The `SodiumSumo` requirement: `SessionLauncher` needs `SodiumSumo` (sumo
   variant); confirm the boot `sodium` is the sumo instance or thread the sumo
   handle through (already used by pairing/joiner, so it is in scope).

**Regression guard (required by the forward-requirement):** a wiring test that
asserts the PRODUCTION-constructed `SessionLauncher` fires
`pushService.bindSession` on `build()`. Concretely: bootstrap with an
`InertPushSource`-backed `PushService` spy, build a session for a stored
channel, assert `bindSession` was invoked with that controller+channelId. This
belongs beside the composition root (a `bootstrap`/`app` test), NOT only in the
existing `test/push/push_wire_test.dart` — that test wires the hook by hand and
would stay green even if bootstrap forgot it. Without a bootstrap-level
assertion the hook silently regresses to dead push in production.

---

### Concern 2 — "Share diagnostics" export path

**Architectural shape CONFIRMED and already substrate-ready.** `Diag.readAll()`
(`lib/src/diag/diag.dart:133`) decrypts the whole retained ring and returns
`List<DiagRecord>`. A `DiagRecord` (`diag_record.dart`) is
`{DiagEvent event, DiagCode code, int timestampMs, List<int> args}` — **closed
enums + int64s, zero string fields, no text pathway** (the §6 layer-1
source-scan test asserts the whole diag public API is String-free; layer-3
planted-marker audit asserts no sensitive markers reach the bytes). The export
renders enum *names* (developer constants) + ints + timestamps — no content,
keys, codes, tokens, or peer-identifiers can structurally appear.

**Seam:** mirror the reviewed `media_export.dart` pattern (the 2nd `share_plus`
site): read-in-memory → format a human-readable events/codes/timestamps dump →
hand to `SharePlus.instance.share(...)` → clean up. `share_plus` is already a
dependency (no new dep). Settings entry sits under the F8 settings root
(`lib/src/ui/screens/settings/`), inside the app-lock perimeter.

**Flags / risks:**
- **Must be unsealed.** `readAll()` throws `StateError('diag log is sealed')`
  when `k_diag` is absent — export is only reachable behind an OPEN
  LockGate. Good (this is the desired perimeter), but the settings action must
  handle the sealed case gracefully, not surface a crash.
- **Transient plaintext-at-rest.** PREFER sharing the rendered text in-memory
  via `ShareParams(text: ...)` — this avoids writing any plaintext file at all.
  If a file attachment is required by a target share sheet, mirror
  `media_export`'s decrypt-to-temp → share → **immediate `delete()`** under
  `getTemporaryDirectory()` (already the accepted, reviewed class). Do NOT
  write the dump under the `nimna-store` root or anywhere persistent; tmp is
  not backup-excluded by our iOS `isExcludedFromBackup` (that only covers the
  store root), so the immediate-delete-after-handoff discipline is load-bearing.
- **Nothing auto-uploads** — confirmed by design; the export is a single
  deliberate user tap through the OS share sheet, no network from the app.
- **`args` sanity.** `args` are int64s (event counts, error codes, sizes). The
  layer-3 planted-marker audit already guarantees no token bytes / key hex /
  code strings ride in `args`. The export inherits that guarantee; no new leak
  surface. Recommend the export render `args` as plain integers (never
  hex/ascii-reinterpreted) so the rendering itself introduces no decode ambiguity.

---

### Concern 3 — dependency-tree telemetry audit (the done-when gate)

**Gap identified.** The existing `test/push/push_dependency_fence_test.dart` is
a **source-import fence** — it greps `lib/**.dart` imports against a
banned-package list and confirms firebase is fenced to
`fcm_push_source.dart`. That is necessary but NOT sufficient for the S16
done-when ("dependency tree contains zero telemetry/analytics/crash SDKs"): a
telemetry SDK could enter **transitively** (pulled by a dependency) without any
`lib/` import. Nothing today walks `pubspec.lock`. There is also no
`ios/Podfile` (iOS plugins via SPM per app-arch §9) and Android has **no**
google-services / firebase gradle plugin (confirmed: grep of
`android/**/build.gradle.kts` is clean — `firebase_messaging` auto-registers,
no analytics plugin).

**Rigorous "zero telemetry SDKs" proof for QA to execute:**
1. **Transitive walk of `pubspec.lock`** — a new fence test (or extend the S15
   fence) that parses `application/mobile/pubspec.lock` and asserts NO package
   name (direct OR transitive, including the `firebase_messaging` subtree:
   `firebase_core`, `firebase_core_platform_interface`, `firebase_messaging`,
   `firebase_messaging_platform_interface`, `firebase_messaging_web`) matches
   the banned set — `firebase_analytics`/`crashlytics`/`performance`/
   `remote_config`/`in_app_messaging`/`ml`, `sentry*`, `mixpanel*`,
   `amplitude*`, `onesignal`, `segment*`, `datadog*`, `bugsnag*`,
   `google_analytics`, `flutter_local_notifications`, etc. This is the actual
   done-when gate; the source-import fence stays as the second belt.
2. **Native surface check** — assert `android/**/build.gradle*` contains no
   `com.google.firebase` analytics/crashlytics/perf plugin and no
   `google-services.json` firebase-analytics config; on iOS, since there is no
   Podfile, assert the SPM `Package.resolved` (Runner) carries no analytics
   framework and Info.plist declares only the intended
   remote-notification/localization keys (no analytics collection keys). The
   only sanctioned native frameworks are APNs (Apple), the FCM messaging
   client, and StoreKit/Play Billing (S17) — payment/messaging substrate, not
   telemetry.
3. **Non-vacuity** — the transitive test must fail if a banned name is planted
   (QA plants one in a scratch lock copy and confirms red), same discipline the
   S15 fence's "fence is not vacuous" test already models.

The CLAUDE.md line "No telemetry/crash/analytics SDKs anywhere, ever — not a
CODE decision" makes this a hard, non-waivable gate; the transitive walk is
what turns the doctrine into a mechanical CI assertion.

---

## USER-level decisions surfaced

**None from the architecture side.** All three concerns are CODE decisions
within already-locked rails (composition-root wiring, export shape mirroring an
existing reviewed pattern, an audit method strengthening an existing fence).
Nothing touches security posture, persistence beyond the at-rest inventory, or
a new dependency (`share_plus` already present; the audit adds a test, not a
dep). Recorded as CODE:
- **CODE:** production `SessionLauncher` built in `bootstrapNimna` with
  `onSessionBound: pushService.bindSession`; presence stack folded into
  `NimnaServices`/`AppScope`; bootstrap-level bind assertion guards it.
- **CODE:** diagnostics export = in-memory render of `Diag.readAll()` (prefer
  `ShareParams(text:)`; temp-file fallback mirrors `media_export`
  decrypt→share→immediate-delete). Inside the unsealed lock perimeter.
- **CODE:** telemetry proof = new `pubspec.lock` transitive-walk fence +
  native (gradle/SPM/plist) check, alongside the retained S15 source-import
  fence; non-vacuity asserted.

(i18n crafted-translation disputes route to USER per the standing rule, but
that is PM/translation-lane, not an architecture decision.)

---

## Product-manager intake memo (start-of-session)

**Author:** product-manager · **Date:** 2026-07-08 · **Kind:** scope + user-value
analysis + foreseeable-USER-decision surfacing. Not implementation.

### What S16 must ship for user value (the done-when spine)
"A stranger goes install → paired chat unaided." Two functional gaps stand
between us and that, plus the polish/i18n cross-cut:

- **Creator-finalize UI (F2.6 safety phrase + F2.7 channel ready) is UNBUILT.**
  `initiator_controller.dart` holds `_material` "for the creator-finalize UI (a
  later session)"; S9 left the initiator tree untouched. Without it the CREATOR
  completes the handshake but never sees the safety phrase to verify and never
  gets a "channel ready" confirmation — the creator half of "install → paired
  chat unaided" does not exist. **Verdict: IN v1 / S16, and it is core, not
  polish.** Copy constraint: the initiator's mismatch path must NOT claim it
  notifies the peer (DECISIONS 2026-07-07 12:24 — mismatch is local-only
  discard, no wire notification; same reconciliation as the F3.4 reword).
- **Onboarding host (F1) does not exist yet.** S14 staged
  `screenshot_onboardingDisclosure` + `screenshot_onboardingAndroidCaveat` with
  no host. IN scope (see USER-1/USER-2 for the two open calls on it).

### Copy: BINDING-from-design vs must-be-crafted
- **BINDING, verbatim, do not reinterpret:** all voice-guide strings 1–22 —
  onboarding 1/2/3/11, screenshot system lines (12), sensitive (14/15), push
  (18), paywall (9), disappearing (7), reply/reaction/self-join (19/20/21),
  hangup (22), empty state (4), error strings. These are canonical in
  `app_en.arb` already. S16 renders, it does not re-word.
- **Design is SILENT / copy must be crafted to the voice guide:** empty/error
  states beyond string 4 (per-surface "nothing here" + failure copy),
  "Share diagnostics" settings screen explainer (what the log is, that nothing
  auto-uploads), a11y labels not already in strings 20/21, and any onboarding
  connective tissue. Craft to the guide; anything near-promissory escalates.

### Carried follow-ups — in-scope vs punt (one line each)
- **F2.6/F2.7 creator-finalize UI → IN.** Load-bearing for the done-when (above).
- **F3.4 edge-annotation reword + joiner "Go back" verb → IN.** Already directed
  as a PM copy fix (DECISIONS 2026-07-07 12:24); it is the microcopy sweep's job.
  CODE (PM-crafted), not USER.
- **screen-09 `<title>nimna — unlock` tidy → IN, trivial.** "unlock" is a
  voice-ban word; already ruled an implementation fix, not USER copy (DECISIONS
  2026-07-07 12:24). Design-file + any app tab title. CODE.
- **Typing per-channel OFF toggle (F7) → IN.** SETTLED defaults, do NOT reopen:
  typing default ON (USER 2026-07-07, DECISIONS L145), read-receipts default
  OFF/opt-in (same), push default OFF. F7 wires all three toggles; the design's
  "all three default OFF" annotation is superseded for typing only. Read
  receipts ARE in the frozen codec (CONTROL 0x02) so the toggle ships without a
  freeze violation. Pure CODE build.
- **F6 incoming-knock surface → IN.** The push-tap route lands here (F6.3 live
  knock / F6.4 lapsed); required for the notification round-trip to be usable.
  CODE, copy is BINDING (string "No answer." for lapse; F6.4 attribution-neutral).

### Honest read on USER decisions
**Few.** S14/S13/S9/S17-reconciliation already pre-settled the thorny copy/scope
items (typing default, read-receipts default, "unlock" ban, F3.4 reword,
subscription model, Android screenshot floor + caveat copy, silent reset).
App display name is SETTLED ("nimna" all-lowercase, DECISIONS 2026-07-03) and
the quietly-branded icon exists in `designs/brand/app-icon` — S16 wires them, no
decision. Three genuine USER calls remain (below); the rest is CODE execution.

### Foreseeable USER decisions (detail in the return message)
1. Onboarding screen count — plan "3 max" vs binding design F1 "4, never more".
2. Android screenshot caveat — placement/conditionality in onboarding.
3. Crafted-translation review depth + dispute policy.

### Minor bookkeeping flag (not a decision)
Typing-default-ON is correctly recorded (DECISIONS L145); the shipped code cites
it accurately. No gap. Noted only because it looked like a design conflict (F7
"all-OFF") and is in fact settled.
