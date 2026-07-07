import 'dart:typed_data';

import '../crypto/record_cipher.dart';
import '../storage/db/row_stores.dart';
import 'channel_repository.dart';
import 'models/message_record.dart';

/// Message records, encrypted under per-record keys derived from the owning
/// channel's CDK (app-architecture.md §3) — so per-channel wipe kills every
/// message's key with the CDK row. Ordering is the per-channel `seq`
/// counter (claimed via [ChannelRepository.nextSeq]); wall-clock stays
/// inside ciphertext.
class MessageRepository {
  MessageRepository({
    required this._channels,
    required this._store,
    required this._cipher,
  });

  final ChannelRepository _channels;
  final MessageStore _store;
  final RecordCipher _cipher;

  /// Appends a message to a channel. [purgeAt] is the accepted plaintext
  /// expiry column (epoch ms) for disappearing messages — null keeps
  /// forever.
  Future<void> append(
    Uint8List channelId,
    MessageRecord record, {
    int? purgeAt,
  }) async {
    final seq = await _channels.nextSeq(channelId);
    final plain = record.toBytes();
    final sealed = _cipher.seal(
      baseKey: _channels.cdkFor(channelId),
      storeId: StoreId.messages,
      recordId: record.id,
      plaintext: plain,
    );
    plain.fillRange(0, plain.length, 0);
    await _store.upsert(
      MessageRow(
        id: record.id,
        channelId: channelId,
        seq: seq,
        purgeAt: purgeAt,
        ct: sealed,
      ),
    );
  }

  /// Rewrites an existing message record (delivery-state / read_at / reaction
  /// updates; fresh nonce by construction). [purgeAt] mirrors the read-time
  /// disappearing deadline into the existing plaintext `purge_at` column (the
  /// accepted, already-disclosed leak — spec §5, app-architecture §4): pass it
  /// once, when a received disappearing message is first read
  /// (`read_at + expiry_s*1000`); omit it to preserve the current value. No
  /// new plaintext column is ever introduced.
  Future<void> update(
    Uint8List channelId,
    MessageRecord record, {
    int? purgeAt,
  }) async {
    final existing = await _store.get(record.id);
    if (existing == null) {
      throw ArgumentError('unknown message');
    }
    final plain = record.toBytes();
    final sealed = _cipher.seal(
      baseKey: _channels.cdkFor(channelId),
      storeId: StoreId.messages,
      recordId: record.id,
      plaintext: plain,
    );
    plain.fillRange(0, plain.length, 0);
    await _store.upsert(
      MessageRow(
        id: record.id,
        channelId: channelId,
        seq: existing.seq,
        purgeAt: purgeAt ?? existing.purgeAt,
        ct: sealed,
      ),
    );
  }

  /// Loads and decrypts a channel's history in `seq` order. A wiped or
  /// unknown channel has no rows — returns empty without touching keys.
  Future<List<MessageRecord>> byChannel(Uint8List channelId) async {
    final rows = await _store.byChannel(channelId);
    if (rows.isEmpty) {
      return const [];
    }
    final cdk = _channels.cdkFor(channelId);
    return [
      for (final row in rows)
        MessageRecord.fromBytes(
          row.id,
          _cipher.open(
            baseKey: cdk,
            storeId: StoreId.messages,
            recordId: row.id,
            sealed: row.ct,
          ),
        ),
    ];
  }

  Future<void> delete(Uint8List id) => _store.delete(id);
}
