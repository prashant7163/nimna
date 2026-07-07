import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S11 structural fences (same source-scan class as
/// test/pairing/single_call_site_test.dart and the S10 import-direction fence;
/// the reviewer remains the authority):
///
/// 1. `package:image` — the EXIF-strip/compress dependency — is imported by
///    exactly ONE module (image_processor.dart), keeping the image-codec
///    surface auditable (SESSION-11 intake §2).
/// 2. `lib/src/media/transfer` + `lib/src/media/model` are Flutter-free, so the
///    connection lane may hold a MediaTransferController without breaking the
///    import-direction fence.
/// 3. `lib/src/media` imports NO gallery / photo-roll save API — received media
///    lives ONLY in the encrypted store, never the system gallery (spec §5.1;
///    the real-forensic rung is S18).
void main() {
  String strip(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('package:image is imported only by image_processor.dart', () {
    const allowed = 'lib/src/media/pipeline/image_processor.dart';
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.path == allowed) {
        continue;
      }
      final code = strip(file.readAsStringSync());
      if (code.contains('package:image/')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the image codec is fenced to $allowed (SESSION-11 intake §2 — the '
          'sole EXIF-strip/compress site); found elsewhere in: $offenders',
    );
  });

  test('media/transfer and media/model are Flutter-free', () {
    for (final dir in ['lib/src/media/transfer', 'lib/src/media/model']) {
      for (final file in dartFilesUnder(dir)) {
        final code = strip(file.readAsStringSync());
        expect(
          code.contains('package:flutter/'),
          isFalse,
          reason:
              '${file.path}: must import NO Flutter — the connection lane holds '
              'a MediaTransferController (the import-direction fence)',
        );
      }
    }
  });

  test('lib/src/media imports no gallery / photo-roll save API', () {
    // Received media never touches the system gallery (spec §5.1); export is a
    // deliberate share-sheet act, not a gallery save.
    const banned = [
      'image_gallery_saver',
      'ImageGallerySaver',
      'gallery_saver',
      'GallerySaver',
      'saveImageToGallery',
      'saveToGallery',
      'photo_manager',
      'PhotoManager',
      'PHPhotoLibrary',
      'MediaStore.Images',
      'insertImage',
    ];
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib/src/media')) {
      final code = strip(file.readAsStringSync());
      for (final needle in banned) {
        if (code.contains(needle)) {
          offenders.add('${file.path}: $needle');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'lib/src/media must never save to the gallery/photo roll (spec §5.1). '
          'Offenders: $offenders',
    );
  });
}
