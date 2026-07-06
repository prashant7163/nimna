/// The creator's outstanding codes — the at-rest pending-pairing record
/// (S8 intake §6). One encrypted value in the existing meta store
/// (`k = 'pending_pairings'`): a small list of
/// `{canonical code bytes, creation UTC date, TTL, X25519 keypair}`.
/// Zero schema change; the §4 plaintext budget is untouched. It exists so
/// the creator can (a) re-register across app restarts within the TTL
/// (F2.4) and (b) answer the §3.1 self-join guard (S9 reads it).
/// Cancelled/expired/finalized entries are deleted — a real erase
/// (spec §3.1 step 6 / F2.8 "no residue"); wipe semantics inherit from MK
/// destruction.
library;

import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../../protocol/pairing_code.dart';
import '../../storage/storage_service.dart';

/// One outstanding code. The X25519 static secret key lives in [SecureKey]
/// native memory from birth; it is serialized only into the encrypted
/// record (mirroring how channel records will hold statics,
/// app-architecture.md §4).
class PendingPairing {
  PendingPairing({
    required this.code,
    required this.utcDate,
    required this.ttl,
    required this.createdAt,
    required this.publicKey,
    required this.secretKey,
  });

  final PairingCode code;

  /// Code-creation UTC date, `YYYY-MM-DD` — the creator's derivation date
  /// (spec §3.1.2).
  final String utcDate;

  final Duration ttl;

  /// Creation instant (UTC).
  final DateTime createdAt;

  /// X25519 static public key (32 bytes).
  final Uint8List publicKey;

  /// X25519 static secret key — native memory, zeroed on dispose.
  final SecureKey secretKey;

  DateTime get expiresAt => createdAt.add(ttl);

  bool isExpired(DateTime now) => !now.toUtc().isBefore(expiresAt);

  void dispose() => secretKey.dispose();
}

/// Binary codec + meta-store access for the pending-pairings record.
/// Encoding (versioned, fixed layout, big-endian, locale-independent):
///
/// ```
/// ver(1)=0x01 ‖ count(1) ‖ count × entry
/// entry = code(9 ascii) ‖ date(10 ascii) ‖ ttl_s(u32) ‖
///         created_at_ms(u64) ‖ pub(32) ‖ sec(32)
/// ```
class PendingPairingStore {
  PendingPairingStore({required this._storage, required this.sodium});

  static const String metaKey = 'pending_pairings';
  static const int _version = 0x01;
  static const int _entryBytes = 9 + 10 + 4 + 8 + 32 + 32;

  final StorageService _storage;
  final Sodium sodium;

  /// Decrypts and decodes every outstanding entry. Callers own disposal of
  /// the returned secret keys.
  Future<List<PendingPairing>> readAll() async {
    final plain = await _storage.metaRecords.read(metaKey);
    if (plain == null) {
      return [];
    }
    try {
      return _decode(plain);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Appends [entry] to the record (read-modify-write).
  Future<void> add(PendingPairing entry) async {
    final existing = await readAll();
    try {
      await _writeAll([...existing, entry]);
    } finally {
      for (final e in existing) {
        e.dispose();
      }
    }
  }

  /// Removes the entry for [code] — a real erase: the row is deleted
  /// outright when the last entry goes.
  Future<void> remove(PairingCode code) async {
    final existing = await readAll();
    try {
      final kept = existing.where((e) => e.code != code).toList();
      if (kept.isEmpty) {
        await _storage.metaRecords.delete(metaKey);
      } else {
        await _writeAll(kept);
      }
    } finally {
      for (final e in existing) {
        e.dispose();
      }
    }
  }

  Future<void> _writeAll(List<PendingPairing> entries) async {
    if (entries.length > 0xFF) {
      throw StateError('too many pending pairings');
    }
    final plain = Uint8List(2 + entries.length * _entryBytes);
    try {
      plain[0] = _version;
      plain[1] = entries.length;
      var off = 2;
      for (final e in entries) {
        plain.setAll(off, e.code.canonicalBytes);
        off += 9;
        plain.setAll(off, e.utcDate.codeUnits);
        off += 10;
        final bd = ByteData.sublistView(plain);
        bd.setUint32(off, e.ttl.inSeconds);
        off += 4;
        bd.setUint64(off, e.createdAt.toUtc().millisecondsSinceEpoch);
        off += 8;
        plain.setAll(off, e.publicKey);
        off += 32;
        e.secretKey.runUnlockedSync((sec) => plain.setAll(off, sec));
        off += 32;
      }
      await _storage.metaRecords.write(metaKey, plain);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  List<PendingPairing> _decode(Uint8List plain) {
    if (plain.length < 2 ||
        plain[0] != _version ||
        plain.length != 2 + plain[1] * _entryBytes) {
      throw const FormatException('pending-pairings record malformed');
    }
    final out = <PendingPairing>[];
    var off = 2;
    for (var i = 0; i < plain[1]; i++) {
      final code = PairingCode.fromCanonicalBytes(
        Uint8List.sublistView(plain, off, off + 9),
      );
      off += 9;
      final date = String.fromCharCodes(plain, off, off + 10);
      off += 10;
      final bd = ByteData.sublistView(plain);
      final ttlS = bd.getUint32(off);
      off += 4;
      final createdMs = bd.getUint64(off);
      off += 8;
      final pub = Uint8List.fromList(plain.sublist(off, off + 32));
      off += 32;
      // A view, not a copy: fromList copies into native memory itself, and
      // the whole [plain] buffer is zeroized by the caller.
      final sec = SecureKey.fromList(
        sodium,
        Uint8List.sublistView(plain, off, off + 32),
      );
      off += 32;
      out.add(
        PendingPairing(
          code: code,
          utcDate: date,
          ttl: Duration(seconds: ttlS),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            createdMs,
            isUtc: true,
          ),
          publicKey: pub,
          secretKey: sec,
        ),
      );
    }
    return out;
  }
}
