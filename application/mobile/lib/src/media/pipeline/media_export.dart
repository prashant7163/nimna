/// Media export — the ONE deliberate act that moves a file OUT of Nimna's
/// encrypted store (spec §5.1: never auto-saved, never in the gallery;
/// components.md media viewer). A SECOND `share_plus` call site (the first is
/// the pairing-code share); fenced in test/pairing/single_call_site_test.dart.
///
/// Decrypt-to-temp → hand to the OS share sheet → delete the temp immediately
/// (app-architecture §5, the sanctioned quarantine exit). The temp file is the
/// only moment a plaintext attachment touches the filesystem outside the store,
/// and it is cleaned up in a `finally`. Device-dependent (the share sheet is a
/// platform channel — S18 real-device rung).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'media_mime.dart';

/// Exports a decrypted attachment through the platform share sheet.
abstract final class MediaExport {
  /// Writes [bytes] to a temp file (generic name — no original filename is ever
  /// kept, spec §5.1 privacy), shares it, then deletes the temp file.
  static Future<void> share({
    required Uint8List bytes,
    required String mime,
  }) async {
    final dir = await getTemporaryDirectory();
    final name = 'nimna-export.${extensionForMime(mime)}';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: mime)]),
      );
    } finally {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}
