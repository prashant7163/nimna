/// The photo / file attach picker (spec §3.1 pattern; components.md attach
/// affordance). A `file_picker` wrapper — the SECOND call site of the S9-signed
/// dependency (the first is the joiner's QR upload). No camera-capture path is
/// designed (components.md: photo / file pickers only; SESSION-11 intake §7).
///
/// Device-dependent: the picker is a platform channel and cannot run headless
/// (the S7/S18 real-device deferral). It hands raw bytes to the pipeline; the
/// EXIF strip + compression + cap enforcement happen AFTER, before sealing.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'media_mime.dart';

/// A raw picked file: bytes + the derived MIME (null if not an allowed type).
class PickedAttachment {
  const PickedAttachment({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// Photo / document pickers. Both load bytes into memory (`withData: true`) —
/// safe under the 5 MB cap; the app never streams from a file path.
abstract final class AttachmentPicker {
  /// Picks an image (the photo path → the EXIF-strip + compress pipeline).
  static Future<PickedAttachment?> pickPhoto() =>
      _pick(type: FileType.image, allowed: imageExtensions);

  /// Picks a document (the file path → PDF, sent as-is; no image pipeline).
  static Future<PickedAttachment?> pickDocument() =>
      _pick(type: FileType.custom, allowed: documentExtensions);

  static Future<PickedAttachment?> _pick({
    required FileType type,
    required List<String> allowed,
  }) async {
    final result = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: type == FileType.custom ? allowed : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    final mime = mimeForExtension(file.extension ?? file.name);
    if (bytes == null || mime == null) {
      return null; // Not an allowed type / no in-memory bytes.
    }
    return PickedAttachment(bytes: bytes, mime: mime);
  }
}
