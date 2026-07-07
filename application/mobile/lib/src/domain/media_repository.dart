import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import '../crypto/record_cipher.dart';
import '../storage/db/row_stores.dart';
import '../storage/keys/key_service.dart';
import '../storage/media/media_store.dart';
import 'channel_repository.dart';
import 'models/media_index_record.dart';

/// Media: index records under `k_media_ix`-derived per-record keys, blob
/// files under CDK-derived per-record keys (app-architecture.md §3/§5).
class MediaRepository {
  MediaRepository({
    required this._channels,
    required this._indexStore,
    required this._blobStore,
    required this._cipher,
    required this._keyService,
  });

  final ChannelRepository _channels;
  final MediaIndexStore _indexStore;
  final MediaStore _blobStore;
  final RecordCipher _cipher;
  final KeyService _keyService;

  /// Stores [bytes] as an encrypted blob + index record; returns the record.
  Future<MediaIndexRecord> add({
    required Uint8List channelId,
    required String mime,
    required Uint8List bytes,
    Uint8List? msgId,
    int? purgeAt,
  }) async {
    final id = _cipher.newRecordId();
    final record = MediaIndexRecord(
      id: id,
      msgId: msgId,
      mime: mime,
      byteLength: bytes.length,
      contentHash: Uint8List.fromList(hash.sha256.convert(bytes).bytes),
    );
    await _blobStore.write(
      cdk: _channels.cdkFor(channelId),
      id: id,
      bytes: bytes,
    );
    final plain = record.toBytes();
    final sealed = _cipher.seal(
      baseKey: _keyService.mediaIndexKey,
      storeId: StoreId.mediaIndex,
      recordId: id,
      plaintext: plain,
    );
    plain.fillRange(0, plain.length, 0);
    await _indexStore.upsert(
      MediaIndexRow(id: id, channelId: channelId, purgeAt: purgeAt, ct: sealed),
    );
    return record;
  }

  /// Loads and decrypts a channel's media index.
  Future<List<MediaIndexRecord>> indexByChannel(Uint8List channelId) async {
    final rows = await _indexStore.byChannel(channelId);
    return [
      for (final row in rows)
        MediaIndexRecord.fromBytes(
          row.id,
          _cipher.open(
            baseKey: _keyService.mediaIndexKey,
            storeId: StoreId.mediaIndex,
            recordId: row.id,
            sealed: row.ct,
          ),
        ),
    ];
  }

  /// Decrypts a blob to memory (display path — never to a file).
  Future<Uint8List> readBlob({
    required Uint8List channelId,
    required Uint8List id,
  }) => _blobStore.read(cdk: _channels.cdkFor(channelId), id: id);

  /// Deletes one media item (index row + blob file).
  Future<void> delete(Uint8List id) async {
    await _indexStore.delete(id);
    await _blobStore.delete(id);
  }

  /// Deletes every media item in [channelId] whose `purge_at` is due at
  /// [nowMs] — the media_ix row AND its blob file (spec §5.1: disappearing
  /// applies identically to media, on both ends). Returns the manifest
  /// `msg_id`s purged so the caller can drop the matching message rows.
  ///
  /// `purge_at` is the accepted plaintext expiry column (app-architecture §4);
  /// the sweep reads only due rows, decrypts each once to recover its
  /// `msg_id`, then deletes.
  Future<List<Uint8List>> purgeExpired(Uint8List channelId, int nowMs) async {
    final rows = await _indexStore.byChannel(channelId);
    final purgedMsgIds = <Uint8List>[];
    for (final row in rows) {
      final due = row.purgeAt;
      if (due == null || due > nowMs) {
        continue;
      }
      final record = MediaIndexRecord.fromBytes(
        row.id,
        _cipher.open(
          baseKey: _keyService.mediaIndexKey,
          storeId: StoreId.mediaIndex,
          recordId: row.id,
          sealed: row.ct,
        ),
      );
      await _indexStore.delete(row.id);
      await _blobStore.delete(row.id);
      if (record.msgId != null) {
        purgedMsgIds.add(record.msgId!);
      }
    }
    return purgedMsgIds;
  }
}
