/// The closed diagnostic vocabulary (app-architecture.md §6).
///
/// THIS FILE IS THE WHOLE VOCABULARY. Adding a member is a review event.
/// Wire ids are explicit and append-only — never renumber, never reuse.
/// There is deliberately no String anywhere in this package's public
/// surface: free-text logging is unrepresentable, not merely discouraged.
///
/// Note: a full panic wipe leaves NO trace by design — there is no
/// `fullWipe` event, because a post-wipe store must be indistinguishable
/// from a fresh install.
library;

/// What happened. Events only — never content, keys, codes, or tokens.
enum DiagEvent {
  /// The app process started.
  appLaunch(1),

  /// A master key was minted (first launch, or first launch after a wipe).
  masterKeyGenerated(2),

  /// The store root was created fresh (first open of an empty root).
  storeCreated(3),

  /// The encrypted store opened (keys loaded, DB ready).
  storeOpened(4),

  /// The store sealed (keys zeroized).
  storeSealed(5),

  /// Schema-version mismatch — destructive reset performed (pre-launch
  /// stance, app-architecture.md §4).
  schemaReset(6),

  /// A single channel was wiped (its CDK row destroyed).
  channelWiped(7),

  /// iOS backup-exclusion attribute asserted true on the store root.
  backupExclusionAsserted(8),

  /// Backup-exclusion assertion failed (see [DiagCode]).
  backupExclusionFailed(9),

  /// A storage-layer operation failed (see [DiagCode]).
  storageError(10);

  const DiagEvent(this.id);

  /// Stable wire id (uint16, append-only).
  final int id;

  static final Map<int, DiagEvent> byId = {
    for (final e in DiagEvent.values) e.id: e,
  };
}

/// Why it happened, when an error class is worth recording. Platform/OS
/// exceptions are mapped to members via an explicit lookup at the call-site
/// layer (default [unknown]); exception messages never enter this package.
enum DiagCode {
  none(0),
  unknown(1),

  /// Platform keystore read/write failed.
  keystoreUnavailable(2),

  /// SQLite database could not be opened.
  dbOpenFailed(3),

  /// A stored record failed authentication or decoding.
  recordCorrupt(4),

  /// Filesystem operation failed.
  ioError(5),

  /// A platform channel was unavailable or returned an error.
  platformChannelUnavailable(6),

  /// meta.schema_version did not match the code's schema epoch.
  schemaMismatch(7);

  const DiagCode(this.id);

  /// Stable wire id (uint16, append-only).
  final int id;

  static final Map<int, DiagCode> byId = {
    for (final c in DiagCode.values) c.id: c,
  };
}
