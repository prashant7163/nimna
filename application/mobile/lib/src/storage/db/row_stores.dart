/// Row-level access to the §4 tables. This layer sees ONLY ciphertext blobs
/// and the plaintext-column budget (surrogate ids, counters, purge_at);
/// encryption happens above it (domain repositories via RecordCipher).
///
/// BLOB primary keys are matched via `hex(col) = ?` — sqflite's documented
/// portable form for blob where-arguments on Android.
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

String _hex(Uint8List bytes) {
  const digits = '0123456789ABCDEF';
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..write(digits[(b >> 4) & 0x0F])
      ..write(digits[b & 0x0F]);
  }
  return out.toString();
}

/// One `channels` row: `id BLOB16 PK · sort INTEGER · ct BLOB`.
class ChannelRow {
  const ChannelRow({required this.id, required this.sort, required this.ct});

  final Uint8List id;
  final int sort;
  final Uint8List ct;
}

class ChannelStore {
  ChannelStore(this._db);

  final Database _db;

  Future<void> upsert(ChannelRow row) => _db.insert('channels', {
    'id': row.id,
    'sort': row.sort,
    'ct': row.ct,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<ChannelRow?> get(Uint8List id) async {
    final rows = await _db.query(
      'channels',
      where: 'hex(id) = ?',
      whereArgs: [_hex(id)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromMap(rows.single);
  }

  Future<List<ChannelRow>> getAll() async {
    final rows = await _db.query('channels', orderBy: 'sort ASC');
    return rows.map(_fromMap).toList();
  }

  Future<void> delete(Uint8List id) =>
      _db.delete('channels', where: 'hex(id) = ?', whereArgs: [_hex(id)]);

  static ChannelRow _fromMap(Map<String, Object?> map) => ChannelRow(
    id: map['id']! as Uint8List,
    sort: map['sort']! as int,
    ct: map['ct']! as Uint8List,
  );
}

/// One `messages` row:
/// `id BLOB16 PK · channel_id BLOB16 · seq INTEGER · purge_at INTEGER NULL ·
/// ct BLOB`.
class MessageRow {
  const MessageRow({
    required this.id,
    required this.channelId,
    required this.seq,
    required this.ct,
    this.purgeAt,
  });

  final Uint8List id;
  final Uint8List channelId;
  final int seq;

  /// Stated, accepted plaintext leak (app-architecture.md §4): epoch time
  /// at which a disappearing message becomes due, so expiry can find due
  /// rows without decrypting all history. Null = keep forever.
  final int? purgeAt;

  final Uint8List ct;
}

class MessageStore {
  MessageStore(this._db);

  final Database _db;

  Future<void> upsert(MessageRow row) => _db.insert('messages', {
    'id': row.id,
    'channel_id': row.channelId,
    'seq': row.seq,
    'purge_at': row.purgeAt,
    'ct': row.ct,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<MessageRow?> get(Uint8List id) async {
    final rows = await _db.query(
      'messages',
      where: 'hex(id) = ?',
      whereArgs: [_hex(id)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromMap(rows.single);
  }

  Future<List<MessageRow>> byChannel(Uint8List channelId) async {
    final rows = await _db.query(
      'messages',
      where: 'hex(channel_id) = ?',
      whereArgs: [_hex(channelId)],
      orderBy: 'seq ASC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<void> delete(Uint8List id) =>
      _db.delete('messages', where: 'hex(id) = ?', whereArgs: [_hex(id)]);

  Future<void> deleteByChannel(Uint8List channelId) => _db.delete(
    'messages',
    where: 'hex(channel_id) = ?',
    whereArgs: [_hex(channelId)],
  );

  static MessageRow _fromMap(Map<String, Object?> map) => MessageRow(
    id: map['id']! as Uint8List,
    channelId: map['channel_id']! as Uint8List,
    seq: map['seq']! as int,
    purgeAt: map['purge_at'] as int?,
    ct: map['ct']! as Uint8List,
  );
}

/// One `media_ix` row:
/// `id BLOB16 PK · channel_id BLOB16 · purge_at INTEGER NULL · ct BLOB`.
class MediaIndexRow {
  const MediaIndexRow({
    required this.id,
    required this.channelId,
    required this.ct,
    this.purgeAt,
  });

  final Uint8List id;
  final Uint8List channelId;
  final int? purgeAt;
  final Uint8List ct;
}

class MediaIndexStore {
  MediaIndexStore(this._db);

  final Database _db;

  Future<void> upsert(MediaIndexRow row) => _db.insert('media_ix', {
    'id': row.id,
    'channel_id': row.channelId,
    'purge_at': row.purgeAt,
    'ct': row.ct,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<MediaIndexRow?> get(Uint8List id) async {
    final rows = await _db.query(
      'media_ix',
      where: 'hex(id) = ?',
      whereArgs: [_hex(id)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromMap(rows.single);
  }

  Future<List<MediaIndexRow>> byChannel(Uint8List channelId) async {
    final rows = await _db.query(
      'media_ix',
      where: 'hex(channel_id) = ?',
      whereArgs: [_hex(channelId)],
    );
    return rows.map(_fromMap).toList();
  }

  Future<void> delete(Uint8List id) =>
      _db.delete('media_ix', where: 'hex(id) = ?', whereArgs: [_hex(id)]);

  Future<void> deleteByChannel(Uint8List channelId) => _db.delete(
    'media_ix',
    where: 'hex(channel_id) = ?',
    whereArgs: [_hex(channelId)],
  );

  static MediaIndexRow _fromMap(Map<String, Object?> map) => MediaIndexRow(
    id: map['id']! as Uint8List,
    channelId: map['channel_id']! as Uint8List,
    purgeAt: map['purge_at'] as int?,
    ct: map['ct']! as Uint8List,
  );
}
