# integration_test/

Device-attached slice of the done-checks (run per target:
`flutter test integration_test/app_boot_test.dart -d <device-id>`).

- `app_boot_test.dart` — real keystore + real store root: encrypted
  persistence across a seal/reopen cycle, raw on-device DB bytes free of
  plaintext markers, iOS `isExcludedFromBackup` read-back **plus** the
  clear-then-relaunch re-assert path (app-architecture.md §7.3), and the
  app booting to the canonical empty shell. Run on the Android emulator
  and iOS simulator; the §7.3 attribute read-back also on a real iPhone.

Android's backup behavior is probed from the host, not from here:
`adb shell bmgr backupnow app.nimna` must report the package not allowed
to back up (QA captures this as done-check evidence).
