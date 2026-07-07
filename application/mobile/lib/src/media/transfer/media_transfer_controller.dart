/// The media send/receive orchestrator the live session delegates to (S11).
/// Pure protocol/store glue — **Flutter-free by construction** so the
/// connection lane may hold a reference without breaking the import-direction
/// fence. It owns the chunker, the per-session reassembler, and the at-rest
/// media persistence (S7 `MediaRepository`), and talks to the session through
/// three narrow callbacks: seal-a-frame, on-inbound-complete, and (for expiry)
/// on-message-purge.
///
/// Error taxonomy (spec §5.1, exact): structural codec violations never reach
/// here (the session killed the session upstream). A transfer-integrity
/// failure — hash/length mismatch, out-of-range or duplicate chunk index,
/// chunk-before-manifest — is **discard + NO ACK, never a protocol error**.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import '../../domain/media_repository.dart';
import '../../domain/models/media_index_record.dart';
import '../../protocol/inner_envelope.dart';
import '../model/media_attachment.dart';
import 'media_chunker.dart';
import 'media_reassembler.dart';

/// A fully-reassembled, hash-verified inbound attachment, handed to the session
/// so it can persist a received message record and ACK the manifest `msg_id`.
class ReceivedMedia {
  const ReceivedMedia({
    required this.manifestMsgId,
    required this.mediaId,
    required this.mime,
    required this.byteLength,
    required this.timestampMs,
    this.expirySeconds,
    this.replyTo,
  });

  /// The manifest `msg_id` — the message id AND the ACK target (spec §5.1).
  final Uint8List manifestMsgId;

  /// The persisted media_ix / blob record id (also the blob file id).
  final Uint8List mediaId;

  final String mime;
  final int byteLength;
  final int timestampMs;
  final int? expirySeconds;
  final Uint8List? replyTo;
}

/// Drives media for one [SessionController]. Constructed per session and
/// attached post-construction (`SessionController.attachMedia`).
class MediaTransferController {
  MediaTransferController({
    required this._media,
    required Uint8List channelId,
    required this._randomBytes,
    required this._sealFrame,
    required this._onInboundComplete,
    required this._diag,
  }) : _channelId = Uint8List.fromList(channelId);

  final MediaRepository _media;
  final Uint8List _channelId;
  final Uint8List Function(int length) _randomBytes;
  final bool Function(InnerEnvelope env) _sealFrame;
  final void Function(ReceivedMedia received) _onInboundComplete;
  final Diag _diag;

  final MediaReassembler _reassembler = MediaReassembler();

  // ---- outbound -------------------------------------------------------

  /// Persists the sender's own encrypted copy (blob + media_ix) and returns the
  /// media id. content_hash is computed by `MediaRepository.add` over exactly
  /// [attachment].bytes — identical to the manifest's hash (same bytes).
  Future<Uint8List> persistOutgoing(
    MediaAttachment attachment,
    Uint8List manifestMsgId, {
    int? purgeAt,
  }) async {
    final record = await _media.add(
      channelId: _channelId,
      mime: attachment.mime,
      bytes: attachment.bytes,
      msgId: manifestMsgId,
      purgeAt: purgeAt,
    );
    return record.id;
  }

  /// Chunks [attachment] and seals every frame in order (manifest first). Stops
  /// early and returns false if a seal fails (the session already fired its
  /// protocol-error kill path).
  bool transmit(
    MediaAttachment attachment,
    Uint8List manifestMsgId,
    int timestampMs, {
    int? expirySeconds,
    Uint8List? replyTo,
  }) {
    final frames = MediaChunker.chunk(
      bytes: attachment.bytes,
      mime: attachment.mime,
      manifestMsgId: manifestMsgId,
      timestampMs: timestampMs,
      randomBytes: _randomBytes,
      expirySeconds: expirySeconds,
      replyTo: replyTo,
    );
    if (!_sealFrame(frames.manifest)) {
      return false;
    }
    for (final chunk in frames.chunks) {
      if (!_sealFrame(chunk)) {
        return false;
      }
    }
    return true;
  }

  // ---- inbound --------------------------------------------------------

  /// Feeds one inbound MEDIA_CHUNK envelope to the reassembler. On completion
  /// (hash verified) persists the blob and hands the result to the session
  /// (which creates the received record and ACKs). On a transfer-integrity
  /// failure the transfer is discarded and NO ACK is sent (spec §5.1).
  void onInbound(InnerEnvelope env) {
    final result = _reassembler.onEnvelope(env);
    switch (result.outcome) {
      case MediaReassemblyOutcome.buffered:
      case MediaReassemblyOutcome.ignored:
        break;
      case MediaReassemblyOutcome.discarded:
        if (result.reason == MediaDiscardReason.hashMismatch) {
          _diag.log(DiagEvent.mediaHashMismatch);
        }
      case MediaReassemblyOutcome.complete:
        unawaited(_ingest(result.transfer!));
    }
  }

  Future<void> _ingest(CompletedMediaTransfer transfer) async {
    // Persist the received blob + index BEFORE the record exists, so the
    // display path (readMedia) always finds the blob (never the gallery).
    final purgeAt = transfer.expirySeconds == null
        ? null
        : transfer.timestampMs + transfer.expirySeconds! * 1000;
    final record = await _media.add(
      channelId: _channelId,
      mime: transfer.mime,
      bytes: transfer.bytes,
      msgId: transfer.manifestMsgId,
      purgeAt: purgeAt,
    );
    _diag.log(DiagEvent.mediaTransferComplete);
    _onInboundComplete(
      ReceivedMedia(
        manifestMsgId: transfer.manifestMsgId,
        mediaId: record.id,
        mime: transfer.mime,
        byteLength: transfer.bytes.length,
        timestampMs: transfer.timestampMs,
        expirySeconds: transfer.expirySeconds,
        replyTo: transfer.replyTo,
      ),
    );
  }

  // ---- display + hygiene ---------------------------------------------

  /// Decrypts a blob to memory for display (never to a file — spec §5.1).
  Future<Uint8List> readMedia(Uint8List mediaId) =>
      _media.readBlob(channelId: _channelId, id: mediaId);

  /// This channel's persisted media index — used to hydrate mime/byteLength for
  /// history on session load.
  Future<List<MediaIndexRecord>> loadIndex() =>
      _media.indexByChannel(_channelId);

  /// Deletes every media item whose `purge_at` is due at [nowMs] — the blob
  /// file AND the media_ix row (spec §5.1: expiry applies to media identically,
  /// on both ends). Returns the manifest `msg_id`s purged so the session can
  /// drop the matching message rows.
  Future<List<Uint8List>> purgeExpired(int nowMs) =>
      _media.purgeExpired(_channelId, nowMs);

  /// Drops buffered partial transfers at session end.
  void dispose() => _reassembler.clear();
}
