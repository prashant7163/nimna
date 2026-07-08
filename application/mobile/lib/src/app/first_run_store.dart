import 'dart:io';

import 'package:path/path.dart' as p;

/// The first-run gate for onboarding (F1, USER 2026-07-08 — four screens,
/// shown exactly once per install).
///
/// A single plaintext marker file under the store root. It is NOT user data —
/// every install shows onboarding once, so "seen" reveals nothing and needs no
/// encryption; being plaintext keeps it readable regardless of the app-lock
/// perimeter (onboarding runs before any lock exists). It lives inside the one
/// wipe/backup-exclusion point, so a panic wipe removes it and the app becomes
/// indistinguishable from a fresh install (onboarding shows again — the desired
/// symmetry).
///
/// There is no resumable state (USER decision): relaunching mid-onboarding
/// restarts at F1.1. The marker is written ONLY when onboarding is completed
/// (Start) or skipped, never mid-flow. Pure file I/O, locale-independent.
class FirstRunStore {
  FirstRunStore(this._dir);

  final Directory _dir;

  File get _marker => File(p.join(_dir.path, 'onboarding-seen'));

  /// Whether onboarding has been completed or skipped. Fails toward showing
  /// onboarding on any I/O error — never toward silently skipping the consent
  /// beat (the screenshot terms, F1.4, are informed consent — spec §5.2).
  bool hasSeenOnboarding() {
    try {
      return _marker.existsSync();
    } on FileSystemException {
      return false;
    }
  }

  /// Records that onboarding was seen (idempotent). Creates the store root if
  /// it does not yet exist. Swallows I/O errors — a failed write only re-shows
  /// onboarding next launch, never breaks a product path.
  Future<void> markSeen() async {
    try {
      if (!_dir.existsSync()) {
        _dir.createSync(recursive: true);
      }
      await _marker.writeAsString('1', flush: true);
    } on FileSystemException {
      // Best-effort; onboarding simply shows again next launch.
    }
  }
}
