import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../crypto/record_cipher.dart';
import '../storage/db/row_stores.dart';
import '../storage/keys/key_service.dart';
import 'models/channel_record.dart';

/// Channel records + the in-memory CRID index built at unlock
/// (app-architecture.md §4): channel counts are dozens, so decrypting all
/// channel records at open is trivial — CRID never becomes a plaintext
/// column.
///
/// Key-material hygiene (review S1): each channel's CDK and own static
/// private key live ONLY in SecureKey native memory (`_cdkById` /
/// `_ownPrivById`). The cached [ChannelRecord]s have those two byte fields
/// zeroized at index time, so the GC heap never retains live key material
/// for the open lifetime; rewrites reconstruct the record content from the
/// held SecureKeys at persist time.
class ChannelRepository {
  ChannelRepository({
    required this._keyService,
    required this._store,
    required this._cipher,
  });

  final KeyService _keyService;
  final ChannelStore _store;
  final RecordCipher _cipher;

  final Map<String, ChannelRecord> _byId = {};
  final Map<String, String> _idByCrid = {};
  final Map<String, SecureKey> _cdkById = {};
  final Map<String, SecureKey> _ownPrivById = {};
  bool _opened = false;

  bool get isOpen => _opened;

  /// Decrypts every channel record and builds the CRID index. Plaintext
  /// buffers are zeroized once decoded; key material moves to SecureKeys.
  Future<void> openAll() async {
    close();
    final rows = await _store.getAll();
    for (final row in rows) {
      final plain = _cipher.open(
        baseKey: _keyService.channelsKey,
        storeId: StoreId.channels,
        recordId: row.id,
        sealed: row.ct,
      );
      final record = ChannelRecord.fromBytes(row.id, row.sort, plain);
      plain.fillRange(0, plain.length, 0);
      _index(record);
    }
    _opened = true;
  }

  /// Zeroizes held keys and drops the in-memory index (seal path). The
  /// cached records' key fields were already zeroized at index time.
  void close() {
    for (final key in _cdkById.values) {
      key.dispose();
    }
    for (final key in _ownPrivById.values) {
      key.dispose();
    }
    _cdkById.clear();
    _ownPrivById.clear();
    _byId.clear();
    _idByCrid.clear();
    _opened = false;
  }

  List<ChannelRecord> get all {
    _requireOpen();
    final list = _byId.values.toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  ChannelRecord? byId(Uint8List id) {
    _requireOpen();
    return _byId[_hex(id)];
  }

  ChannelRecord? byCrid(Uint8List crid) {
    _requireOpen();
    final id = _idByCrid[_hex(crid)];
    return id == null ? null : _byId[id];
  }

  /// The channel's CDK as a SecureKey (message/media record base key).
  SecureKey cdkFor(Uint8List channelId) {
    _requireOpen();
    final key = _cdkById[_hex(channelId)];
    if (key == null) {
      throw ArgumentError('unknown channel');
    }
    return key;
  }

  /// The channel's own X25519 static private key as a SecureKey (S8/S9
  /// session handshakes consume this; never exposed as raw bytes).
  SecureKey ownStaticPrivateFor(Uint8List channelId) {
    _requireOpen();
    final key = _ownPrivById[_hex(channelId)];
    if (key == null) {
      throw ArgumentError('unknown channel');
    }
    return key;
  }

  /// Persists a new channel record (id and CDK must be freshly minted by
  /// the caller — S8/S9 pairing does this for real channels). TAKES
  /// OWNERSHIP of the record's key material: `cdk` and `ownStaticPrivate`
  /// are moved into SecureKeys and the passed buffers are zeroized.
  Future<void> create(ChannelRecord record) async {
    _requireOpen();
    await _persist(record);
    _index(record);
  }

  /// Rewrites an existing channel record (fresh nonce by construction).
  /// [record] normally derives from the cached copy (zeroized key fields);
  /// the persisted content is rebuilt from the held SecureKeys.
  Future<void> update(ChannelRecord record) async {
    _requireOpen();
    await _persistWithHeldKeys(record);
    _reindex(record);
  }

  /// Claims the next per-channel message sequence number and persists the
  /// incremented counter inside the channel record ciphertext.
  Future<int> nextSeq(Uint8List channelId) async {
    _requireOpen();
    final record = _byId[_hex(channelId)];
    if (record == null) {
      throw ArgumentError('unknown channel');
    }
    final seq = record.nextSeq;
    final updated = record.copyWith(nextSeq: seq + 1);
    await _persistWithHeldKeys(updated);
    _reindex(updated);
    return seq;
  }

  /// Deletes the channel row — the only copy of the CDK dies with it
  /// (per-channel wipe step 1; StorageService deletes rows/files after).
  Future<void> delete(Uint8List channelId) async {
    _requireOpen();
    await _store.delete(channelId);
    final hexId = _hex(channelId);
    final record = _byId.remove(hexId);
    if (record != null) {
      _idByCrid.remove(_hex(record.crid));
    }
    _cdkById.remove(hexId)?.dispose();
    _ownPrivById.remove(hexId)?.dispose();
  }

  Future<void> _persist(ChannelRecord record) async {
    final plain = record.toBytes();
    final sealed = _cipher.seal(
      baseKey: _keyService.channelsKey,
      storeId: StoreId.channels,
      recordId: record.id,
      plaintext: plain,
    );
    plain.fillRange(0, plain.length, 0);
    await _store.upsert(
      ChannelRow(id: record.id, sort: record.sort, ct: sealed),
    );
  }

  /// Persists [cached] (whose key fields are zeroized) by temporarily
  /// materializing the CDK and static private key from the held
  /// SecureKeys; the temporaries are zeroized in all paths.
  Future<void> _persistWithHeldKeys(ChannelRecord cached) async {
    final hexId = _hex(cached.id);
    final cdkKey = _cdkById[hexId];
    final privKey = _ownPrivById[hexId];
    if (cdkKey == null || privKey == null) {
      throw ArgumentError('unknown channel');
    }
    final cdk = cdkKey.extractBytes();
    final priv = privKey.extractBytes();
    try {
      await _persist(
        ChannelRecord(
          id: cached.id,
          ownStaticPrivate: priv,
          ownStaticPublic: cached.ownStaticPublic,
          peerStaticPublic: cached.peerStaticPublic,
          crid: cached.crid,
          label: cached.label,
          cdk: cdk,
          createdAtMs: cached.createdAtMs,
          pushOptIn: cached.pushOptIn,
          defaultExpirySeconds: cached.defaultExpirySeconds,
          peerDeviceToken: cached.peerDeviceToken,
          nextSeq: cached.nextSeq,
          sort: cached.sort,
        ),
      );
    } finally {
      cdk.fillRange(0, cdk.length, 0);
      priv.fillRange(0, priv.length, 0);
    }
  }

  /// Moves key material into SecureKeys, zeroizes it in the record, caches
  /// the sanitized record.
  void _index(ChannelRecord record) {
    final hexId = _hex(record.id);
    _cdkById[hexId]?.dispose();
    _ownPrivById[hexId]?.dispose();
    _cdkById[hexId] = SecureKey.fromList(_cipher.sodium, record.cdk);
    _ownPrivById[hexId] = SecureKey.fromList(
      _cipher.sodium,
      record.ownStaticPrivate,
    );
    record.cdk.fillRange(0, record.cdk.length, 0);
    record.ownStaticPrivate.fillRange(0, record.ownStaticPrivate.length, 0);
    _byId[hexId] = record;
    _idByCrid[_hex(record.crid)] = hexId;
  }

  /// Re-caches a rewritten record. Defensive: zeroize its key fields even
  /// though cache-derived records already carry zeros.
  void _reindex(ChannelRecord record) {
    record.cdk.fillRange(0, record.cdk.length, 0);
    record.ownStaticPrivate.fillRange(0, record.ownStaticPrivate.length, 0);
    _byId[_hex(record.id)] = record;
  }

  void _requireOpen() {
    if (!_opened) {
      throw StateError('ChannelRepository is not open');
    }
    // Also surfaces StorageSealedError if the perimeter sealed underneath.
    _keyService.channelsKey;
  }

  static String _hex(Uint8List bytes) {
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
