import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:sqflite/sqflite.dart';

import '../../crypto/record_cipher.dart';
import '../keys/key_service.dart';

/// Encrypted values in the §4 `meta` table (`k TEXT PK · v BLOB`).
///
/// `schema_version` is the ONE plaintext meta value (owned by
/// NimnaDatabase); everything written through this class is an at-rest
/// AEAD record under `k_meta` (app-architecture.md §4). The record id
/// bound into the AD and the per-record key derivation is deterministic
/// from the key name — `SHA-256(ascii(k))[0:16]` — so a value re-encrypts
/// under the same identity across rewrites (fresh random nonce each write,
/// §2 belt 2) and a ciphertext transplanted onto another key fails
/// authentication.
///
/// S8 consumer: the pending-pairings record (`pending_pairings`) — the
/// creator's outstanding codes + keypairs (intake §6; zero schema change,
/// zero new plaintext columns).
class MetaRecords {
  MetaRecords({
    required this._db,
    required this._keyService,
    required this._cipher,
  });

  final Database _db;
  final KeyService _keyService;
  final RecordCipher _cipher;

  static Uint8List recordIdFor(String key) => Uint8List.fromList(
    sha256.convert(ascii.encode(key)).bytes.sublist(0, 16),
  );

  /// Decrypts the value stored under [key]; null if absent. Throws
  /// [StorageSealedError] while sealed, `AeadAuthError` on tamper.
  Future<Uint8List?> read(String key) async {
    final rows = await _db.query(
      'meta',
      columns: ['v'],
      where: 'k = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _cipher.open(
      baseKey: _keyService.metaKey,
      storeId: StoreId.meta,
      recordId: recordIdFor(key),
      sealed: rows.single['v']! as Uint8List,
    );
  }

  /// Encrypts and upserts [plaintext] under [key].
  Future<void> write(String key, Uint8List plaintext) async {
    final sealed = _cipher.seal(
      baseKey: _keyService.metaKey,
      storeId: StoreId.meta,
      recordId: recordIdFor(key),
      plaintext: plaintext,
    );
    await _db.insert('meta', {
      'k': key,
      'v': sealed,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Deletes the row (a real erase; `PRAGMA secure_delete=ON` is hygiene,
  /// key destruction is the boundary).
  Future<void> delete(String key) =>
      _db.delete('meta', where: 'k = ?', whereArgs: [key]);
}
