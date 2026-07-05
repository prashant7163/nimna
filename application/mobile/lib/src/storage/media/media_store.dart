import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sodium/sodium.dart';

import '../../crypto/record_cipher.dart';
import '../store_root.dart';

/// Encrypted media blobs as files, not DB rows (app-architecture.md §5):
/// `<root>/media/<hex(id)>` where id = the media_ix record id. The spec's
/// 5 MB cap (§5.1) means single-shot IETF AEAD per file — no streaming
/// construction needed or permitted (§2). Blob keys derive from the owning
/// channel's CDK, so per-channel wipe kills every blob's key with the CDK
/// row.
///
/// Blobs live exclusively here — never the system gallery, never Documents,
/// never tmp. Display decrypts to memory only.
class MediaStore {
  MediaStore({required this._root, required this._cipher});

  final StoreRoot _root;
  final RecordCipher _cipher;

  File fileFor(Uint8List id) =>
      File(p.join(_root.mediaDir.path, _hexLower(id)));

  /// Encrypts [bytes] under the channel's [cdk] and writes the blob file.
  Future<void> write({
    required SecureKey cdk,
    required Uint8List id,
    required Uint8List bytes,
  }) async {
    final sealed = _cipher.seal(
      baseKey: cdk,
      storeId: StoreId.mediaBlob,
      recordId: id,
      plaintext: bytes,
    );
    await fileFor(id).writeAsBytes(sealed, flush: true);
  }

  /// Decrypts a blob to memory; throws on authentication failure.
  Future<Uint8List> read({
    required SecureKey cdk,
    required Uint8List id,
  }) async {
    final sealed = await fileFor(id).readAsBytes();
    return _cipher.open(
      baseKey: cdk,
      storeId: StoreId.mediaBlob,
      recordId: id,
      sealed: sealed,
    );
  }

  Future<void> delete(Uint8List id) async {
    final file = fileFor(id);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static String _hexLower(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out
        ..write(digits[(b >> 4) & 0x0F])
        ..write(digits[b & 0x0F]);
    }
    return out.toString();
  }
}
