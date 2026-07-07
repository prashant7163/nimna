/// A picked-and-processed attachment ready to seal (S11, spec §5.1). This is
/// the FINAL plaintext — EXIF/metadata already stripped and (for images)
/// compressed on-device BEFORE this type exists (`pipeline/image_processor`).
/// [bytes] are exactly what `MediaRepository.add` hashes and AEAD-seals and
/// what the manifest's `content_hash` covers, so the sender's blob and the
/// receiver's reassembly are byte-identical.
///
/// Flutter-free by construction (a leaf value type): the connection lane may
/// reference it without breaking the import-direction fence.
library;

import 'dart:typed_data';

/// One attachment ready for transfer. Immutable.
class MediaAttachment {
  MediaAttachment({
    required Uint8List bytes,
    required this.mime,
    this.pixelWidth,
    this.pixelHeight,
    this.originalQuality = false,
  }) : bytes = Uint8List.fromList(bytes);

  /// The complete attachment plaintext — post-strip, post-compress. Never the
  /// raw camera-roll bytes (those carried EXIF, stripped upstream).
  final Uint8List bytes;

  /// The attachment MIME type (in-repo derived; jpeg/png/webp/gif/pdf).
  final String mime;

  /// Decoded pixel dimensions for images (null for documents) — display sizing
  /// only, never on the wire.
  final int? pixelWidth;
  final int? pixelHeight;

  /// True when the sender chose "original quality" (EXIF still stripped; the
  /// downscale/recompress step was skipped). Off by default (components.md).
  final bool originalQuality;

  /// Byte length of the plaintext (the manifest's `total_len`).
  int get byteLength => bytes.length;

  /// True for image attachments (the edge-to-edge bubble), false for documents
  /// (the doc row) — spec §5.1 / components.md media bubbles.
  bool get isImage => mime.startsWith('image/');
}
