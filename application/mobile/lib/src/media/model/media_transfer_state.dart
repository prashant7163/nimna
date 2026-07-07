/// The media bubble's transfer phase (S11, components.md media bubbles). A
/// leaf value type carried on [MessageView] so the chat lane can render the
/// five media-bubble states without touching any transport/store state.
///
/// Flutter-free by construction (the import-direction fence).
library;

/// Which media-bubble phase to render (components.md media bubbles):
/// - [sending]   — outbound chunked transfer in flight (image 60% + 2 px
///   `accent` progress line along the bubble's bottom edge).
/// - [receiving] — inbound placeholder at intrinsic aspect (`surface2`) with
///   the same progress line.
/// - [loaded]    — the blob is on this device, decrypt-to-memory for display.
/// - [failed]    — a transfer-integrity failure (discarded, never ACKed); the
///   sender may resend (spec §5.1).
enum MediaTransferPhase { sending, receiving, loaded, failed }

/// A media message's transfer state. [progress] is a 0..1 reassurance fraction
/// (components.md: "reassurance, not a meter" — no percentage text is ever
/// shown); it is advisory and the progress line may render indeterminately.
class MediaTransferState {
  const MediaTransferState(this.phase, {this.progress = 0});

  const MediaTransferState.sending([this.progress = 0])
    : phase = MediaTransferPhase.sending;

  const MediaTransferState.receiving([this.progress = 0])
    : phase = MediaTransferPhase.receiving;

  static const MediaTransferState loaded = MediaTransferState(
    MediaTransferPhase.loaded,
  );
  static const MediaTransferState failed = MediaTransferState(
    MediaTransferPhase.failed,
  );

  final MediaTransferPhase phase;

  /// Advisory 0..1 fraction (never surfaced as a number).
  final double progress;

  /// True while bytes are moving — the progress line shows.
  bool get inFlight =>
      phase == MediaTransferPhase.sending ||
      phase == MediaTransferPhase.receiving;
}
