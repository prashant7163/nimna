# nimna — mobile app (Flutter)

The Nimna client for iOS and Android. **Closed source.** Implements the
protocol in [`docs/nimna-protocol-spec-v0.2.1.md`](../../docs/nimna-protocol-spec-v0.2.1.md);
all UI is bound by the artifacts in [`designs/`](../../designs/) (tokens,
components, wireframes, hi-fi screens, voice guide) — implemented, never
reinterpreted. The app-side technical shape (dependencies, at-rest crypto,
schemas, diag log, skeleton) is normative in
[`docs/architecture/app-architecture.md`](../../docs/architecture/app-architecture.md).

**Status:** Session 7 — skeleton + encrypted local storage. App shell
(LockGate perimeter, tokens theme, i18n from the first widget, the
empty-channel-list placeholder), encrypted stores (channels/messages/
media/meta + media blob files + diagnostic ring log), platform keystore
integration, and cloud-backup exclusion on both platforms. Real screens
and protocol flows arrive S8+.

## Identifiers & floors

- Dart package: `nimna` · applicationId / bundle ID: `app.nimna`.
- App name renders as lowercase **nimna** per the locked brand.
- Min OS floors (USER, 2026-07-05): **iOS 17.0** (pbxproj) ·
  **Android 10 / minSdk 29** (build.gradle.kts).

## Layout

- `lib/` — Dart source (see `lib/README.md` for the package map)
- `test/` — host test suite, all green under plain `flutter test`
  (see `test/README.md`)
- `integration_test/` — device-attached done-check slice
- `assets/fonts/` — vendored OFL typefaces (never fetched at runtime)
- `android/`, `ios/` — platform shells; hand-maintained pieces are the
  Android manifest + `res/xml/data_extraction_rules.xml` (backup
  exclusion) and `ios/Runner/AppDelegate.swift` (the `app.nimna/storage`
  isExcludedFromBackup channel)
- `l10n.yaml` — gen_l10n config (EN template; DE/FR/ES/IT filled at S16;
  `l10n-untranslated.json` is the generated S16 work-queue, git-ignored)

## Commands

```sh
flutter pub get       # fetch dependencies (also regenerates l10n)
flutter analyze       # static analysis (must be clean)
flutter test          # host suite: crypto vectors, storage round-trips,
                      # raw-byte marker scans, diag audits, tokens drift
dart format --output=none --set-exit-if-changed lib test   # format gate
flutter run           # launch on a connected device/simulator
flutter test integration_test/app_boot_test.dart -d <device-id>
```

## Storage at a glance (normative details: app-architecture.md §2–§7)

- One store root: `<ApplicationSupport>/nimna-store/` — DB (`nimna.db` +
  WAL/SHM), `media/` blob files, `diag/` day logs. One backup-exclusion
  point, one wipe point.
- Everything Nimna-authored on disk is ChaCha20-Poly1305-IETF ciphertext
  under HKDF-derived per-record keys; the only plaintext columns are
  random surrogate ids, integer counters, and `purge_at`.
- Master key lives in the platform keystore (iOS: Keychain,
  `AfterFirstUnlockThisDeviceOnly`; Android: Keystore-wrapped blob);
  a sealed `KeyService` structurally cannot decrypt anything.
- Backups: Android `allowBackup=false` + `dataExtractionRules` excluding
  every domain from cloud-backup AND device-transfer; iOS
  `isExcludedFromBackup` set at store-root creation and re-asserted every
  launch.

## Standing rules (see repo-root CLAUDE.md)

- No third-party crash/analytics/telemetry SDKs, ever.
- Dependencies minimal and boring; the S7 set is fixed by
  app-architecture.md §1 (architect sign-off per dependency); additions
  are a review event.
- Local diagnostic log only: encrypted, ring-buffered 7 days,
  events/error-codes only — its public API accepts no strings, so
  content/keys/codes/tokens are unrepresentable (test-enforced).
- Crypto primitives are locked in Session 2; nothing hand-rolled —
  `lib/src/crypto/` is byte plumbing around libsodium + the vector-locked
  RFC 5869 HKDF composition.
- i18n: EN/DE/FR/ES/IT at launch. Every user-facing string via ARB/l10n
  from the first widget (zero hardcoded strings, test- and
  reviewer-enforced); layouts survive German-length strings; the EN voice
  guide fixes canonical meaning for all translations.
