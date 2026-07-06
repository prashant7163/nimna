# SESSION 13 — App lock & panic wipe (branch `session-13-lock-wipe`)

## Architect intake note — Phase 3 start (mandatory)

**2026-07-07 01:05 +0200 · tech-architect · INTAKE (research only, no code)**

Sources read in full: `docs/architecture/app-architecture.md` (binding — esp.
§2, §3, §6, §10), `application/mobile/lib/src` as merged from S7
(`key_service.dart`, `lock_gate.dart`, `storage_service.dart`, crypto/, diag/),
spec v0.2.1 §6 + §6.1 + §7 + §9 rows ("Peer's/Your own device seized"),
wireframes F7.2/F7.3 + F8.1–F8.3, screens `12-app-lock.html` +
`08-panic-wipe-confirm.html`, `designs/system/components.md`
(Destructive-hold, Sheet, Toast), `designs/brand/voice-and-microcopy.md`
(string 8, register notes), DECISIONS.md (2026-07-03 21:32 hold-to-wipe USER,
zero-leak lock USER, FLAG_SECURE flagged-for-USER, passcode-dot glyph CODE).
`local_auth` health verified on pub.dev 2026-07-07.

S13 is a **non-protocol** session: it consumes S7's merged storage API
read-only and builds the real gate + wipe flows on the settled S7
foundations. **Nothing in the S7 architecture note is redesigned here** —
the key hierarchy, `KeyService` sealed⇄open perimeter, `LockGate`
subtree-replacement, and the wipe-equals-key-destruction semantics all stand;
S13 fills the two seams the S7 note explicitly reserved for it ("S13 drops
PIN/biometric in front of `open()` and wires lifecycle-pause → `seal()`;
nothing else moves" — §3; "the S13 UI will call exactly this" — §10 wipe
seam). Zero overlap with S8's lanes (transport/protocol/pairing,
`src/crypto` Noise work): S13 touches `lib/src/lock`, `lib/src/wipe`,
settings/lock UI, and the one foreseen amendment to `app/lock_gate.dart`'s
sealed surface.

---

### 1. Module shape

```
lib/src/lock/
  lock_controller.dart    state machine over KeyService: disabled → open,
                          enabled: locked → unlocking → open; owns the
                          WidgetsBindingObserver (lifecycle → seal); the ONLY
                          caller of KeyService.open() once lock is enabled
  lock_config_store.dart  the sealed-readable lock configuration blob
                          (flutter_secure_storage item #2 — see §3)
  pin_verifier.dart       Argon2id verifier derive/verify (see §2); no other
                          file touches pwhash
  biometric_gate.dart     local_auth wrapper — the single call site (see §4)
lib/src/wipe/
  wipe_service.dart       thin orchestration over the S7 primitives:
                          fullWipe = StorageService.fullWipe()
                                     + LockConfigStore.delete()
                                     + post-wipe reopen to a fresh store;
                          channelWipe = StorageService.wipeChannel();
                          a pre-wipe hook seam for the (future) session layer
                          to hang up — S13 never calls transport itself
lib/src/ui/screens/settings/
  settings_root_screen.dart   F8.1 (App lock · Notifications(stub row) ·
                              Relay(stub row) · Licenses · Wipe everything)
  app_lock_setup_screen.dart  F8.2 (choose PIN → confirm PIN → biometric
                              toggle; turning lock off requires current PIN)
lib/src/ui/widgets/
  destructive_hold_button.dart  components.md Destructive-hold: dangerFill,
                                burn right→left, release-cancels, haptic tick,
                                1.5 s per-channel / 2.5 s full (USER
                                2026-07-03 21:32); completion animation 480 ms
  wipe_sheet.dart               the shared sheet body — full-wipe variant
                                (F8.3 / screen 08, string 8 verbatim) and
                                per-channel variant (F7.2/F7.3); the F7 host
                                screen belongs to a later session — S13 ships
                                the sheet + WipeService API as the reusable
                                seam, wired from F8 only
lib/src/app/lock_gate.dart      AMENDED (foreseen by S7 §3): the sealed
                                surface becomes screen 12 — symbol + pin dots
                                + pin pad, biometric auto-prompt when enabled.
                                Still a full Navigator-subtree replacement;
                                the zero-leak USER decision (2026-07-03) is
                                untouched. When lock is DISABLED the sealed
                                surface stays the bare brand surface (it only
                                appears transiently at boot).
```

Layering unchanged: `lock/` sits beside `storage/` in the domain tier
(imports `storage/keys`, `crypto`, `diag`; never `ui`); `wipe/` imports
`storage/` + `lock/`. Nothing below `ui/` touches locale.

### 2. PIN design — inside the S2 lock, gate-not-key (adjudication)

**Decision (CODE): the PIN is an interactive gate in front of
`KeyService.open()`, not key material.** Verification:

- Enrollment: `salt = randombytes(16)`;
  `verifier = Argon2id(v1.3, t=3, m=64 MiB, p=1, out=32)(pin_bytes, salt)` —
  **the spec §7 locked slow-KDF with its locked parameters, verbatim; no new
  crypto scheme and no new parameters are introduced.** Reached through the
  `sodium` package (already signed off); day-one spike: confirm `pwhash` is
  reachable from the package's high-level API on device + host CI — if the
  high-level API doesn't expose it, it goes through
  `package:sodium/sodium.ffi.dart` with marshalling-only glue **inside the
  existing `at_rest_aead.dart`-style fence**, same adjudication as S7 §2
  (audited libsodium computes every byte; the reviewer audits the fence).
  Never a Dart Argon2 implementation.
- Verify: recompute, compare with `sodium.memcmp` (constant-time). The
  verifier is structurally *never* usable as a key: `pin_verifier.dart`
  exposes only `bool verify(...)`; the derived bytes never leave the file and
  are zeroized after compare (test-asserted, see §7).
- **PIN-wrapping the MK is REJECTED** (the stronger-sounding alternative):
  (a) it redesigns the settled S7 hierarchy this session is forbidden to
  move; (b) it breaks the biometric path — platform biometrics return a
  verdict, not key material, so a PIN-wrapped MK would need per-key
  keystore auth-binding that `flutter_secure_storage` does not expose
  (hand-rolling that channel = new crypto-adjacent surface for marginal
  gain); (c) the honest at-rest claim (S7 §2) is already "nothing readable
  on disk without the *keystore-held* key" — the PIN's threat model is the
  person holding the unlocked phone, and a gate serves exactly that. Stated
  honestly: an attacker executing code inside our sandbox bypasses the gate;
  that class is already accepted (S7 §2 honesty note) and bounded by the
  platform keystore beneath.
- PIN length: pad accepts 4–8 digits, 6 dots shown — settled in the design
  phase (wireframes README, F8.2); implement, don't reinterpret.
- **Failed attempts (CODE):** each attempt already costs one Argon2id
  (~hundreds of ms at m=64 MiB). After 5 consecutive failures, an in-memory
  escalating delay (1 s doubling, cap 30 s) before the pad re-arms. The
  counter is **never persisted** — a persisted counter would be a new
  plaintext at-rest artifact outside the S7 §4 budget, and relaunching to
  reset it costs more than the delay it evades. **No auto-wipe-after-N
  failures**: not in any design artifact; if ever proposed it is a USER
  feature (destructive behavior), not a CODE hardening — noted, not asked.
- Forgotten PIN: no recovery, by design — F8.2's caption says it at setup
  time; reinstalling wipes (spec §6.1). No backdoor path may exist.

### 3. Lock configuration at rest — secure-storage scope amendment

The gate must be evaluable **while sealed** (before any MK-derived key
exists), so lock config cannot live in the encrypted store. **Decision
(CODE, architect scope amendment):** `flutter_secure_storage` now holds
exactly **TWO** items (was: exactly one, S7 §1):

1. the wrapped 32-byte MK (unchanged, `src/storage/keys/`);
2. one lock-config blob, key `nimna/lock/v1`:
   `ver(1) ‖ flags(1: pinEnabled, biometricEnabled) ‖ salt(16) ‖ verifier(32)`
   — fixed-length, no strings, read/written only by
   `lock/lock_config_store.dart`.

Same iOS accessibility class (`first_unlock_this_device`,
`ThisDeviceOnly` — never backed up), same Android Keystore wrap. Rationale
vs alternatives: a plaintext sidecar file would put the verifier outside the
keystore wrap for no benefit; a plaintext `meta` DB value both violates the
§4 plaintext budget and is unreadable-by-design pre-unlock is false but the
budget rule wins regardless. The reviewer fence updates from "one call site"
to "two call sites, both enumerated here." Existing behavior preserved: the
absence of the blob = lock disabled (S7 upgrade path is automatic).

### 4. Biometric integration — dependency sign-off

**`local_auth` ^3.0.1 — SIGN-OFF GIVEN (architect, 2026-07-07), scoped.**
flutter.dev verified publisher (first-party Flutter team plugin,
flutter/packages), 3.36k likes, ~1.08M downloads/30d, last release
2026-02-25, BSD-3-Clause. Pulls only its own endorsed platform packages
(`local_auth_android` — BiometricPrompt, `local_auth_darwin` —
LocalAuthentication/LAContext, `local_auth_windows` — inert for us,
`local_auth_platform_interface`). Zero network surface, zero telemetry;
purely a platform-channel shim over the OS biometric prompts. Platform
floors (Android 24+/iOS 13+) sit far below ours (29/17.0); BiometricPrompt
is solid from API 28 (S7 §9). **Rejected alternative:** hand-written
platform channels (~150 lines × 2 platforms re-discovering BiometricPrompt
lifecycle + LAContext error taxonomy the plugin has already absorbed — same
adjudication as flutter_secure_storage at S7).

Scope fence: one call site, `lock/biometric_gate.dart`, calling
`authenticate(biometricOnly: true)` — the fallback on biometric
failure/unavailability is **Nimna's own PIN pad**, never the OS device
credential (the device passcode is not the app PIN; delegating to it would
make the app gate as weak as the phone gate and bypass our verifier).
Semantics per F8.2: toggle ships ON in the setup flow (spec §6 strongly
recommended), row hidden when no biometric hardware, "Falls back to your
PIN." Biometric success gates `open()` exactly as a correct PIN does — a
verdict, not key material (consistent with §2).

Platform wiring (implementation notes, no new decisions):
`MainActivity` must extend `FlutterFragmentActivity` (BiometricPrompt
requirement); iOS `NSFaceIDUsageDescription` purpose string in Info.plist —
user-facing, so it rides `InfoPlist.strings` (EN now; DE/FR/ES/IT join the
S16 crafted pass with the ARB queue — noted for the S16 work list).

### 5. Lock-on-background timing — immediate, no grace (adjudication)

**Decision (CODE): seal immediately on `AppLifecycleState.hidden`** (fires
before `paused` on both platforms, i.e. before the OS captures the
app-switcher snapshot — the snapshot shows the sealed surface, upholding
zero-leak in recents). `inactive` does NOT seal: it fires for transient
non-departures (permission dialogs, notification shade, biometric prompt
itself, in-app pickers) and sealing there would fight the app's own flows.
Cold start with lock enabled: bootstrap consults `LockConfigStore` and does
**not** call `KeyService.open()` until the gate passes — the keystore is
never read behind a locked gate (test-asserted).

Why this is CODE, not USER taste: the zero-leak lock is USER-settled
(2026-07-03: "before anything shows" is F8.2's own caption), spec §6 says
"gate on app open," and **no design artifact contains a grace-period
affordance** — F8.2 has exactly a PIN pad and one biometric toggle. A
"require after N minutes" knob would invent UI the designs don't have
("implement, don't reinterpret"). If a grace period is ever wanted it is a
design-loop + USER matter, not an S13 default.

### 6. Wipe call-graph — confirmation against the S7 foundations

Confirmed: both wipe primitives already exist in
`StorageService` (S7) with the correct order; **S13 adds UI + orchestration
only, no new destruction logic.**

```
FULL WIPE (F8.3, hold 2.5 s completes)
  WipeService.fullWipe()
    → StorageService.fullWipe()            [S7, unchanged]
        1. KeyService.destroyMasterKey()    keystore MK entry deleted —
                                            security boundary crossed HERE:
                                            all disk bytes are dead ciphertext
                                            even if everything after fails
        2. diag.reset()                     ring + queue die (fresh-install
                                            indistinguishable — nothing may
                                            be logged after this point)
        3. close repos/DB, KeyService.seal()  in-memory keys zeroized
        4. root.wipeAndRecreate()           DB + WAL/SHM + media + diag gone
    → LockConfigStore.delete()             lock config dies too — a wiped
                                            phone equals a fresh install,
                                            including "App lock: Off"
    → reopen: KeyService.open() mints a new MK → F4.4 empty list
  (subscription survives via store identity — F9.5 Restore; no S13 action)

PER-CHANNEL WIPE (F7.2/F7.3 sheet, hold 1.5 s completes)
  WipeService.wipeChannel(id)  [pre-wipe hook fires — future session layer
                                hangs up; S13 ships the seam, not the call]
    → StorageService.wipeChannel(id)       [S7, unchanged]
        channel row deleted → the ONLY copy of the CDK dies → every
        message/media k_rec = HKDF(CDK, …) is underivable — free-page or
        flash-remnant ciphertext is dead the moment the row is gone;
        then message rows, media_ix rows, blob files, WAL checkpoint
        TRUNCATE (hygiene, not the boundary; PRAGMA secure_delete already ON)
    → toast "Channel wiped." → row simply isn't there (F4)
```

Both match app-architecture §3 exactly ("key destruction first, deletion
second"). Atomicity claim per the designs ("release cancels — nothing
happens, ever partially"): the hold gesture triggers exactly one call at
completion; before completion nothing has been invoked. Interruption
mid-wipe is covered by the ordering (see §7 evidence).

### 7. Test & QA-evidence strategy ("no recoverable trace under device inspection")

Framed exactly as the S7 precedent: **key destruction is the security
boundary; QA evidences (a) the keystore entry is gone, (b) the files are
gone, (c) any hypothetical residual bytes are undecryptable** — the
real-device forensic rung stays with S18 (USER 2026-07-05 deferral
precedent; S18's backup/wipe-forensics row picks it up).

Host tier (`flutter test` + `sqflite_common_ffi` + fake keystore — all CI):

- **Full-wipe planted-marker audit:** seed channels/messages/media/diag with
  known markers → `fullWipe()` → recursive raw-byte scan of the store root
  (fresh-empty; zero markers), fake keystore asserts MK **and** lock-config
  entries deleted, and asserts destruction ORDER (keystore delete observed
  before any file deletion).
- **Interrupted-wipe test:** inject failure after step 1 → assert every
  surviving ciphertext fails decryption via the public API (keys are gone;
  the boundary held mid-crash).
- **Per-channel:** markers in channel A + B → `wipeChannel(A)` → raw scan of
  DB + WAL + SHM + media dir: A's markers absent, B intact and decryptable;
  WAL checkpoint executed.
- **PIN verifier:** enrollment/verify round-trip, wrong-PIN rejects, RFC 9106
  Argon2id parameter pinning asserted (t=3, m=64 MiB, p=1 — the spec §7
  values), constant-time compare in use, derived bytes zeroized, and a
  structural test that `pin_verifier.dart` exports no byte-returning API.
- **Gate:** lock-enabled cold start performs zero keystore MK reads before a
  successful verify (fake keystore records access order); wrong PIN leaves
  KeyService sealed (`StorageSealedError` everywhere — S7 test extended);
  escalating-delay schedule after 5 failures.
- **Lifecycle/widget:** simulated `hidden` ⇒ sealed ⇒ LockGate subtree
  contains the lock surface and **zero content widgets** (extends the S7
  zero-leak test); `inactive` ⇒ not sealed; unlock restores the tree; all
  five locales render the settings/lock/wipe strings from ARB.
- **Hold semantics (widget):** release at 99% ⇒ no service call, track
  resets; completion ⇒ exactly one call; durations 1.5 s / 2.5 s pinned
  against the USER decision.
- **Diag:** new events are closed-enum members only (existing scans extend);
  a post-full-wipe store contains no diag files and no queued events.

Device tier (QA done-check run):

- Emulator (API 35): drive wipe → `adb shell run-as app.nimna` pull of the
  app dir → marker grep (absent) + fresh-install shape; biometric path via
  `adb -e emu finger touch`.
- iOS simulator: same store inspection via the simulator container; Face ID
  via Features → Face ID → Matching/Non-matching; app-switcher snapshot
  shows the sealed surface (screen recording as evidence).
- Real iPhone: **deferred to S18** with the §7.3 backup rung (same USER
  deferral), stated at wrap in PROGRESS.

### 8. Dependencies — declarations & verdicts (this session)

| Dependency | Verdict |
|---|---|
| `local_auth` ^3.0.1 (+ endorsed `local_auth_android`/`local_auth_darwin`/`local_auth_windows`/platform_interface) | **SIGN-OFF GIVEN** — §4; fence: one call site in `lock/biometric_gate.dart`; biometricOnly, our PIN is the fallback |
| `flutter_secure_storage` (existing) | **Scope AMENDED** from one item to exactly two — §3; no version change |
| `sodium` (existing) | No new sign-off needed; pwhash use is inside the S2 lock (spec §7 Argon2id, locked params). Day-one spike: pwhash reachability host+device; FFI-wrapper fallback rides the S7 §2 adjudication |
| Anything else | **None.** No new crypto, no network deps, no state-management deps |

### 9. Decisions ledger for the wrap fold

CODE (decided here, rationale above): PIN = Argon2id-verifier gate, not MK
entanglement (§2) · verifier + flags in a second secure-storage item, scope
amendment (§3) · in-memory escalating retry delay, never persisted, no
auto-wipe-after-N (§2) · seal on `hidden` immediately, no grace period, no
seal on `inactive` (§5) · biometric = `local_auth` biometricOnly with
Nimna-PIN fallback, never OS device credential (§4) · full wipe also
destroys the lock config — fresh-install indistinguishability (§6) ·
per-channel wipe sheet ships as a reusable component + WipeService seam; the
F7 host screen stays with its own session (§1).

USER (flagged, consolidated — one item):

1. **Android `FLAG_SECURE` — the deferred final call is now due.**
   DECISIONS 2026-07-03 21:32 recorded "Recommend NOT setting FLAG_SECURE ·
   CODE (flagged for USER) · final call deferred to build phase." S13 is the
   lock/discretion build session, so the question ripens here (S14
   screenshot-detection is the other natural home). **Architect
   recommendation: do NOT set it.** The zero-leak concern it would serve
   (app-switcher previews) is already met by sealing before the OS snapshot
   (§5), and blocking screenshots contradicts the settled honest stance
   ("a screenshot is still a screenshot" — string 7/11; detection-and-notify
   is spec §5.2's whole design, and FLAG_SECURE on our own screen would
   break symmetric self-notices). Drafted question for the orchestrator's
   consolidated list: *"FLAG_SECURE final call (deferred 2026-07-03): leave
   screenshots possible (recommended — honest stance; switcher privacy is
   already covered by seal-before-snapshot), or block them on Android? OK
   to resolve at S13, or defer to S14 with the screenshot work?"* S13
   proceeds on the recommended posture; flipping it later is a one-line
   change with no architectural coupling.

No other USER items foreseen: hold-to-wipe interaction + durations, the
zero-leak lock, and biometric-recommended-on are USER/spec-settled; PIN
length 4–8 is design-settled; lock timing and PIN mechanics are CODE per
the adjudications above.

### 10. Guardrails restated for the implementing dev

- Read-only on S7 storage: `StorageService`/`KeyService` internals do not
  move; `WipeService` composes them. The single foreseen S7-file amendment
  is the LockGate sealed surface (explicitly reserved by S7 §3).
- No overlap with S8: nothing under `src/crypto` (except, if the spike
  demands it, pwhash glue inside the existing adjudicated FFI fence file —
  coordinate at merge, it is append-only), nothing in transport/pairing.
- Strings: canonical microcopy verbatim (string 8; F7.2/F8 captions; "Wipe
  now"/"Keep"/"Hold to wipe"/"Channel wiped."), ARB-namespaced (`lock_*`,
  `wipe_*`, `settings_*`) for the merge fold; German-length survival per
  the i18n decision. App-lock iconography = passcode-dot glyph, never a
  padlock (CODE 2026-07-03).
- Diag stays string-free; nothing loggable after full-wipe step 2.
- No telemetry, no new plaintext-at-rest beyond the §3 lock blob
  (keystore-wrapped), no persistence anywhere else.

---

## Implementation — mobile-developer-flutter

**2026-07-07 01:45 +0200 · mobile-developer-flutter · IMPLEMENTATION
COMPLETE (pre-review)**

Checks: `flutter analyze` clean · `flutter test` 116/116 (71 pre-existing +
45 new) · `dart format --set-exit-if-changed lib test` clean.

### What landed (all under `application/mobile/`)

- `lib/src/lock/` — `lock_controller.dart` (state machine over KeyService;
  seal-on-`hidden` observer; escalating delay; the only path to `open()`
  once lock is enabled — bootstrap delegates the boot-time open here),
  `lock_config_store.dart` (LockConfig blob + the SECOND
  flutter_secure_storage call site, key `nimna/lock/v1`, same pinned iOS
  accessibility), `pin_verifier.dart` (Argon2id via sodium sumo pwhash,
  spec §7 params verbatim; constant-time compare via the fence),
  `biometric_gate.dart` (the ONE local_auth call site, biometricOnly).
- `lib/src/wipe/wipe_service.dart` — thin orchestration exactly per intake
  §6: `storage.fullWipe()` → `LockConfigStore.delete()` → `storage.open()`
  → `lockController.reload()`; `wipeChannel` with `preChannelWipeHook`
  seam. Zero new destruction logic.
- `lib/src/app/lock_gate.dart` — AMENDED (foreseen S7 §3): sealed surface
  = screen 12 (symbol + dots + pad, biometric auto-prompt on appearance
  and on each `resumed` while sealed) when lock enabled; bare brand
  surface otherwise. Subtree replacement untouched. Sealed subtree gets
  its own token-correct `Theme` (MaterialApp.builder contexts sit outside
  the app theme — the S7 fallback in `_SealedSurface` was the tell).
- `lib/src/ui/screens/settings/` — `settings_root_screen.dart` (F8.1, five
  rows; Notifications/Relay inert until their sessions; Licenses →
  standard `showLicensePage`), `app_lock_setup_screen.dart` (F8.2 choose →
  confirm → enroll; lock-on: current-PIN gate → manage w/ biometric toggle
  + Turn off).
- `lib/src/ui/widgets/` — `destructive_hold_button.dart` (dangerFill,
  start-anchored burn overlay per screens.css, haptic ticks + heavy impact
  on completion, release-cancels, fires exactly once, 480 ms completion
  fade), `wipe_sheet.dart` (`showFullWipeSheet` / `showChannelWipeSheet`
  over one `WipeSheetBody`; wipe is awaited BEFORE the sheet closes),
  `pin_pad.dart` (PinDots + PinPad, 72 px circular keys per screens.css),
  `nimna_toggle.dart` (components.md toggle), `nimna_symbol.dart`,
  `nav_bar.dart`, `glyphs.dart` (CustomPainter back/chevron/backspace,
  RTL-mirrored — no icon-font dependency).
- `lib/src/ui/screens/channel_list_screen.dart` — F4 footer Settings entry
  row added (wireframe F4.4 footer, design-backed).
- `lib/src/crypto/sodium_instance.dart` — switched to
  `SodiumSumoInit.init()` (same bundled native asset; `SodiumSumo
  implements Sodium`, all consumers unaffected). **Day-one spike outcome:
  pwhash IS reachable from the package's high-level (sumo) API — no FFI
  glue needed for Argon2id.** S8 coordination note: this file now hands
  S8/S9 the sumo surface (scalarmult) for free; merge is trivial.
- `lib/src/crypto/at_rest_aead.dart` — APPEND-ONLY fence addition:
  `constantTimeEquals` over `sodium_memcmp` (marshalling only; per intake
  §2/§10 the fence file is the sanctioned home).
- `lib/l10n/app_en.arb` — 30 new keys, namespaced `settings_*` / `lock_*`
  / `wipe_*`; non-EN ARBs stay `@@locale`-only (S16 rule); gen_l10n
  regenerated. Canonical strings byte-exact: string 8 (title/body/Keep),
  F8.1/F8.2/F7.2 captions, "Hold to wipe", "Channel wiped.".
- Platform: `MainActivity` → `FlutterFragmentActivity` (BiometricPrompt
  requirement); `NSFaceIDUsageDescription` added to `Info.plist` (EN);
  `local_auth ^3.0.1` added to pubspec (architect-signed, intake §4);
  `USE_BIOMETRIC` permission merges from the plugin's own manifest.
- `dart_test.yaml` — declares the `production_cost` tag (spec-parameter
  Argon2id lane; still CI-run, selectable/excludable).
- Tests: `test/lock/` (pin_verifier 9, lock_controller 8), `test/wipe/`
  (4 incl. planted-marker audit, destruction-ORDER probe, interrupted
  wipe), `test/ui/` (lock_gate 4, wipe_sheet 10, settings_flow 10);
  `test/helpers/test_env.dart` gained FakeLockConfigStore,
  FakeBiometricGate, reduced-cost pin constants, lockScheduler seam.

### CODE decisions made during implementation (beyond the intake's)

1. **Lock-config blob carries `pin_len(1)`** — format is
   `ver(1)‖flags(1)‖pin_len(1)‖salt(16)‖verifier(32)` (51 bytes), one byte
   more than intake §3's field list. Forced by the artifacts themselves:
   screen 12 renders one dot per enrolled digit (its mock shows a 4-dot
   row) and has NO submit key, so unlock must auto-submit at full length —
   which requires knowing the length while sealed. The byte lives INSIDE
   the keystore-wrapped blob: zero new plaintext-at-rest, still
   fixed-length, still string-free. **For architect ACK at merge.**
2. **Choose-a-PIN advances via an explicit "Next"** (ghost button, enabled
   at ≥4 digits) — the pad accepts 4–8 (design-settled) so the choose step
   cannot auto-submit; confirm and unlock auto-submit at known length.
3. **Bootstrap delegates the boot open to `LockController.initialize()`**
   (with an `observeLifecycle` seam because plain storage-layer tests run
   without a WidgetsBinding). The controller reaches storage through
   injected `openStorage`/`sealStorage` callbacks, keeping `lock/` from
   importing `storage_service.dart` (intake §1 layering: lock imports
   storage/keys only).
4. **App-lock row on-state caption**: biometric on → "On — PIN + Face ID"
   (F8.2 exit note verbatim); PIN-only → "On" (hi-fi screen 08's on-state
   value). Both strings come from artifacts; the pairing rule is mine.
5. **Hold-button label = "Hold to wipe"** everywhere (hi-fi screen 08 +
   F7.2/F7.3), superseding F8.3's wireframe "Wipe now" label; "Wipe now"
   is NOT shipped as a key (dead keys would enter the S16 translation
   queue). String 8's `[Wipe now][Keep]` button pair is honored in spirit
   — the safe word "Keep" is verbatim; the destructive affordance is the
   USER-settled hold, which the later hi-fi artifact labels "Hold to
   wipe". Full-wipe hold caption follows the hi-fi ("Hold for 2½ seconds.
   Release to cancel."); the channel sheet uses F7.2's wording verbatim.
6. **Full-wipe title emphasis** ("Wipe *everything*?" — weight 600 in the
   hi-fi) ships as key pair `wipe_fullTitle` + `wipe_fullTitleEmphasis`
   (substring located at runtime; falls back to unemphasized if a locale's
   rendering drops it) — locale-safe without HTML-ish markup in ARBs.
7. **Burn-overlay color** (`black @ 28%`, screens.css `.btn.hold .burn`)
   added to `nimna_tokens.dart` as `NimnaEffects.holdBurnOverlay` — the
   tokens file stays the only home for color literals; value is
   design-sourced but NOT in tokens.json (noted as potential tokens.json
   addition for the design loop).
8. **Wrong-PIN feedback on the lock screen is silence**: dots clear, pad
   re-arms (or disarms into the delay). No copy, no shake (the one
   permitted shake stays with wrong-code), no counter ever surfaced.

### Provisional strings — flagged for the design loop / PM (no artifact carries them)

`lock_confirmPinTitle` ("Enter it again") · `lock_confirmPinMismatch`
("Those didn't match — start again.") · `lock_actionNext` ("Next") ·
`lock_enterPinTitle` ("Enter your PIN") · `lock_actionTurnOff` ("Turn
off") · `lock_biometricPromptReason` ("Unlock your lines.") ·
`lock_keypadDeleteA11y` ("Delete") · the `NSFaceIDUsageDescription`
purpose line. All follow the voice register (short, plain, verbs 1–2
words, error states facts-not-blame); each ARB description carries the
PROVISIONAL flag so the S16 pass / design loop can replace them
wholesale. Also flagged: **"Face ID" is iOS naming** — the Android
biometric label for `lock_biometricToggleLabel` /
`settings_rowAppLockOnBiometric` needs a design-loop answer (S13 ships
the artifact strings verbatim).

### Observations for the architect (no action taken — storage is read-only for S13)

- **Interrupted-wipe recovery edge:** if the process dies after wipe step
  1 (MK destroyed) but before step 4 (file deletion), the next launch
  mints a fresh MK and then `ChannelRepository.openAll()` throws
  `AeadAuthError` on the surviving dead-ciphertext rows — a crash loop
  until reinstall. The security boundary is intact (test-proven: every
  surviving row is undecryptable); the availability edge suggests
  extending the pre-launch destructive-reset stance to
  auth-failure-at-open. Recommend adjudicating at the S14/S15 intake.
- `NSFaceIDUsageDescription` currently rides `Info.plist` (EN). The intake
  wanted `InfoPlist.strings`; moving it there (with DE/FR/ES/IT) requires
  pbxproj variant-group surgery — queued for the S16 crafted pass with the
  other four languages, noted on the S16 work list.

### Route registrations (for the merge fold)

- `Routes.settings = '/settings'` → `SettingsRootScreen` (F8.1)
- `Routes.appLock = '/settings/app-lock'` → `AppLockSetupScreen` (F8.2)

### Pubspec delta (for the merge fold)

- `local_auth: ^3.0.1` (runtime; architect sign-off in intake §4).
