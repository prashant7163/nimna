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
  storageError(10),

  /// S8 pairing (initiator) events — events ONLY: the code, topic, and
  /// keys are structurally unloggable (no String parameter exists).

  /// A Nimna code (and its keypair) was created.
  pairingCodeCreated(11),

  /// The rendezvous topic was registered at the relay (first registration
  /// or a resume/reconnect re-registration).
  pairingTopicRegistered(12),

  /// The relay bridged the topic (the peer arrived); the flow holds for
  /// the S9 handshake.
  pairingBridged(13),

  /// The code's TTL lapsed unused; code and keypair were discarded.
  pairingExpired(14),

  /// The user cancelled the code; code and keypair were discarded.
  pairingCancelled(15),

  /// S9 pairing (joiner + handshake) events — events ONLY: the code, topic,
  /// keys, CRID, safety phrase, and device-tokens are structurally
  /// unloggable (no String/bytes parameter exists).

  /// A channel was finalized (valid handshake completed on this device):
  /// the joiner after "They match" + naming, or the creator's responder.
  pairingFinalized(16),

  /// A pairing handshake failed and everything was discarded fail-closed
  /// (§3.1.6) — a commitment/AEAD/transcript failure or a mid-handshake
  /// bridge loss. Never surfaced to the user (silence doctrine); a local
  /// diagnostic only.
  pairingHandshakeFailed(17),

  /// S10 live-session (transport) events — events ONLY: no content, keys,
  /// ids, or peer bytes are representable here.

  /// A live-session §3.3.1 protocol error killed the session fail-closed:
  /// a transport AEAD/counter violation, a malformed inbound frame or body
  /// (bad inner envelope, bad ACK/CONTROL/REACTION body, or a non-UTF-8
  /// TEXT body), or a session KK-handshake failure. All session keys were
  /// destroyed and a relay TEARDOWN sent. Distinct from
  /// [pairingHandshakeFailed], which stays the S8/S9 pairing lane's event.
  /// Never surfaced to the user (silence doctrine); a local diagnostic only.
  sessionProtocolError(18),

  /// S11 media (transfer) events — events ONLY: no content, mime, ids, hashes,
  /// or bytes are representable here.

  /// An inbound media transfer reassembled and its `SHA-256 == content_hash`;
  /// the blob was persisted and the manifest ACKed (spec §5.1).
  mediaTransferComplete(19),

  /// An inbound media transfer failed hash verification and was discarded with
  /// NO ACK (spec §5.1: a resend is the sender's call — never a protocol
  /// error). A local diagnostic only.
  mediaHashMismatch(20),

  /// Expired media was swept on this device — the media_ix row + blob file +
  /// message row were deleted (spec §5.1, expiry applies to media on both
  /// ends).
  mediaExpired(21),

  /// S12 presence events — events ONLY: no CRIDs, tokens, peer bytes, counts,
  /// or attribution are representable here. Wire ids 22–27 (renumbered from the
  /// session-branch's 19–24 at the G4 merge fold, appended after S11's media
  /// 19–21 — the append-only, renumber-if-claimed-first rule the branch noted).

  /// The knocker sent its ONE knock (spec §3.2). Never logged twice on its own
  /// — the app never auto-retries a cold knock (§4). Carries nothing about the
  /// peer, the channel, or whether a push token rode along.
  knockSent(22),

  /// A knock lapsed unanswered (the 60 s window closed with no pick-up). The
  /// knocker renders exactly "No answer." — offline vs saw-and-ignored is
  /// indistinguishable by construction, and this event preserves that: it says
  /// only THAT a knock lapsed, never why (DECISIONS 2026-07-04).
  knockLapsed(23),

  /// A LIVE-session drop began bounded auto-recovery (string 10). Distinct
  /// from a cold knock, which is never retried. No timing/peer detail.
  sessionReconnecting(24),

  /// Bounded auto-recovery re-established the line (a fresh knock+KK went
  /// live within the window).
  sessionRecovered(25),

  /// The ~30 s background-grace timer expired and closed the live session
  /// (client-side only; no relay state). Foregrounding cancels it silently and
  /// logs nothing.
  backgroundGraceExpired(26),

  /// A peer device-token refresh CONTROL (§5.5, token_payload §5.7) was
  /// received and persisted to the channel record. The event carries NO token
  /// bytes — present-vs-absent is not even recorded (events only).
  peerTokenRefreshed(27);

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
  schemaMismatch(7),

  /// A relay connection attempt failed (offline/refused/TLS —
  /// deliberately one indistinct class; no addresses, no reasons).
  relayUnreachable(8);

  const DiagCode(this.id);

  /// Stable wire id (uint16, append-only).
  final int id;

  static final Map<int, DiagCode> byId = {
    for (final c in DiagCode.values) c.id: c,
  };
}
