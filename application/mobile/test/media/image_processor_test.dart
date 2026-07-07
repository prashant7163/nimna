import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nimna/src/media/pipeline/image_processor.dart';

/// S11 — EXIF/metadata strip is provable, on-device, before encryption (spec
/// §5.1). A JPEG fixture carrying GPS / make / DateTime goes through the
/// processor; the output must carry NO EXIF while the pixels survive.
void main() {
  /// Builds a solid-color JPEG with known EXIF tags embedded.
  Uint8List jpegWithExif() {
    final image = img.Image(width: 120, height: 90);
    img.fill(image, color: img.ColorRgb8(30, 60, 90));
    image.exif.imageIfd['Make'] = 'NimnaTestCam';
    image.exif.imageIfd['Model'] = 'Line-One';
    image.exif.imageIfd['DateTime'] = '2021:07:04 10:00:00';
    image.exif.gpsIfd.gpsLatitude = 37.7749;
    image.exif.gpsIfd.gpsLongitude = -122.4194;
    return img.encodeJpg(image);
  }

  test('precondition: the fixture actually carries EXIF', () {
    final decoded = img.decodeImage(jpegWithExif())!;
    expect(decoded.exif.isEmpty, isFalse, reason: 'fixture must embed EXIF');
    expect(decoded.exif.imageIfd['Make']?.toString(), contains('NimnaTestCam'));
  });

  test('processing strips ALL EXIF (GPS/make/time) and keeps pixels', () async {
    final processed = await ImageProcessor.process(
      jpegWithExif(),
      originalQuality: false,
    );
    final out = img.decodeImage(processed.bytes)!;

    // No metadata survives — GPS, make, model, and DateTime are all gone.
    expect(out.exif.isEmpty, isTrue, reason: 'no EXIF may survive the strip');
    expect(out.exif.imageIfd['Make'], isNull);
    expect(out.exif.gpsIfd.gpsLatitude, isNull);

    // Dimensions preserved (no downscale needed under the cap), pixels ~intact.
    expect(out.width, 120);
    expect(out.height, 90);
    final p = out.getPixel(60, 45);
    expect((p.r - 30).abs() <= 12, isTrue);
    expect((p.g - 60).abs() <= 12, isTrue);
    expect((p.b - 90).abs() <= 12, isTrue);
  });

  test(
    'original-quality path also strips EXIF (only skips downscale)',
    () async {
      final processed = await ImageProcessor.process(
        jpegWithExif(),
        originalQuality: true,
      );
      final out = img.decodeImage(processed.bytes)!;
      expect(out.exif.isEmpty, isTrue);
      expect(out.width, 120);
      expect(out.height, 90);
    },
  );

  test('compressed path downscales beyond the longest-edge cap', () async {
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(200, 100, 50));
    final processed = await ImageProcessor.process(
      img.encodeJpg(big),
      originalQuality: false,
    );
    final out = img.decodeImage(processed.bytes)!;
    expect(out.width, ImageProcessor.longestEdgeCap); // 2048
    expect(out.height, lessThanOrEqualTo(ImageProcessor.longestEdgeCap));
  });

  test('non-decodable bytes throw ImageDecodeError', () {
    expect(
      () => ImageProcessor.processSync(
        Uint8List.fromList([1, 2, 3, 4]),
        originalQuality: false,
      ),
      throwsA(isA<ImageDecodeError>()),
    );
  });
}
