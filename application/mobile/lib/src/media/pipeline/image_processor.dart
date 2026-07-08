/// On-device EXIF/metadata strip + compression for image attachments (spec
/// §5.1 "Metadata stripping by default … before encryption on the sender's
/// device"). THE SOLE `package:image` call site (SESSION-11 dependency fence).
///
/// 100% on-device: `package:image` is pure Dart with no platform channel and
/// no socket API, so "zero network calls" is structural. EXIF strip is
/// likewise structural — decoding to a pixel buffer and re-encoding cannot
/// carry the EXIF APP1 segment; we additionally [img.bakeOrientation] so
/// dropping the orientation tag does not rotate the image, then clear all
/// remaining metadata explicitly. Runs inside `Isolate.run` so the 5 MB worst
/// case never blocks the UI isolate. Flutter-free (dart:isolate + image).
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The final image plaintext after strip + (optional) compression, plus the
/// OUTPUT mime — re-encoding may change the container (webp/gif → jpeg/png),
/// so the manifest's mime is what this returns, not the picked extension.
class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
}

/// Raised when the picked bytes are not a decodable image.
class ImageDecodeError implements Exception {
  const ImageDecodeError();
}

/// Strips metadata and (by default) compresses an image on-device.
abstract final class ImageProcessor {
  /// Longest-edge cap for the compressed path (CODE default, contestable —
  /// SESSION-11 intake §7). Original-quality skips the downscale.
  static const int longestEdgeCap = 2048;

  /// JPEG quality: the default compress path vs the original-quality path
  /// (still re-encoded, still EXIF-stripped).
  static const int jpegQuality = 82;
  static const int jpegQualityOriginal = 100;

  /// Decodes [input], bakes orientation, strips ALL metadata, optionally
  /// downscales/recompresses, and re-encodes. Runs off the UI isolate.
  static Future<ProcessedImage> process(
    Uint8List input, {
    required bool originalQuality,
  }) {
    return Isolate.run(
      () => processSync(input, originalQuality: originalQuality),
    );
  }

  /// The synchronous core (also the unit-test entry — EXIF-strip verification).
  /// Never touches the network or the filesystem.
  static ProcessedImage processSync(
    Uint8List input, {
    required bool originalQuality,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(input);
    } on Object {
      // Some malformed inputs make a format probe throw rather than return
      // null; treat every decode failure uniformly (never a crash upstream).
      decoded = null;
    }
    if (decoded == null) {
      throw const ImageDecodeError();
    }
    // Apply the EXIF orientation to the pixels, then reset the tag so stripping
    // it cannot rotate the image.
    var image = img.bakeOrientation(decoded);
    // Structural strip: a fresh, empty ExifData carries no GPS/make/model/time.
    image.exif = img.ExifData();
    // The decoder copies the source ICC_PROFILE APP2 onto image.iccProfile and
    // encodeJpg/encodePng re-emit any non-null profile — clear it so the output
    // carries no (identifying-capable) colour profile either (spec §5.1).
    image.iccProfile = null;
    if (!originalQuality) {
      image = _downscale(image);
    }
    // Re-encode: JPEG for opaque images (small), PNG when alpha must survive
    // (screenshots/logos). Both containers drop EXIF by construction.
    final Uint8List out;
    final String mime;
    if (image.hasAlpha) {
      out = img.encodePng(image);
      mime = 'image/png';
    } else {
      out = img.encodeJpg(
        image,
        quality: originalQuality ? jpegQualityOriginal : jpegQuality,
      );
      mime = 'image/jpeg';
    }
    return ProcessedImage(
      bytes: out,
      mime: mime,
      width: image.width,
      height: image.height,
    );
  }

  static img.Image _downscale(img.Image image) {
    final longest = image.width >= image.height ? image.width : image.height;
    if (longest <= longestEdgeCap) {
      return image;
    }
    return image.width >= image.height
        ? img.copyResize(image, width: longestEdgeCap)
        : img.copyResize(image, height: longestEdgeCap);
  }
}
