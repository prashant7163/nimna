import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../crypto/record_cipher.dart';
import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import '../store_root.dart';

/// Result of opening the database.
class DatabaseOpenResult {
  const DatabaseOpenResult({
    required this.db,
    required this.created,
    required this.wasReset,
  });

  final Database db;

  /// True if the schema was created fresh (empty root).
  final bool created;

  /// True if a schema-version mismatch forced a destructive reset.
  final bool wasReset;
}

/// Opens `nimna.db` at the store root with the §4 schema.
///
/// Plaintext-column budget (normative — nothing else is ever plaintext):
/// random 16-byte surrogate ids, integer ordering counters, `purge_at`, and
/// inherent blob sizes. No CRID, public key, label, timestamp, or token ever
/// appears as a plaintext column.
///
/// Schema-versioning stance (pre-launch): `meta.schema_version` mismatch =
/// destructive reset — log `schemaReset`, wipe the store root, recreate.
abstract final class NimnaDatabase {
  static const String _schemaVersionKey = 'schema_version';

  static Future<DatabaseOpenResult> open({
    required DatabaseFactory factory,
    required StoreRoot root,
    required Diag diag,
  }) async {
    var db = await _openRaw(factory, root);
    var created = !(await _hasSchemaVersion(db));
    var wasReset = false;

    if (created) {
      await _writeSchemaVersion(db);
    } else {
      final stored = await _readSchemaVersion(db);
      if (stored != kSchemaVersion) {
        diag.log(DiagEvent.schemaReset, code: DiagCode.schemaMismatch);
        await db.close();
        root.wipeAndRecreate();
        db = await _openRaw(factory, root);
        await _writeSchemaVersion(db);
        created = true;
        wasReset = true;
      }
    }
    return DatabaseOpenResult(db: db, created: created, wasReset: wasReset);
  }

  static Future<Database> _openRaw(
    DatabaseFactory factory,
    StoreRoot root,
  ) async {
    final db = await factory.openDatabase(
      root.dbPath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          // Best-effort deletion hygiene; CDK/MK destruction is the real
          // security boundary (app-architecture.md §3). rawQuery, not
          // execute: PRAGMAs can return rows, and Android's SQLiteDatabase
          // rejects row-returning statements on the exec path.
          await db.rawQuery('PRAGMA secure_delete = ON');
        },
      ),
    );
    // WAL mode (returns a row, so rawQuery).
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await _createSchema(db);
    return db;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channels(
        id BLOB PRIMARY KEY,
        sort INTEGER NOT NULL,
        ct BLOB NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages(
        id BLOB PRIMARY KEY,
        channel_id BLOB NOT NULL,
        seq INTEGER NOT NULL,
        purge_at INTEGER,
        ct BLOB NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_messages_channel_seq '
      'ON messages(channel_id, seq)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_messages_purge '
      'ON messages(purge_at) WHERE purge_at IS NOT NULL',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_ix(
        id BLOB PRIMARY KEY,
        channel_id BLOB NOT NULL,
        purge_at INTEGER,
        ct BLOB NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_media_channel '
      'ON media_ix(channel_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_media_purge '
      'ON media_ix(purge_at) WHERE purge_at IS NOT NULL',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta(
        k TEXT PRIMARY KEY,
        v BLOB NOT NULL
      )''');
  }

  static Future<bool> _hasSchemaVersion(Database db) async {
    final rows = await db.query(
      'meta',
      where: 'k = ?',
      whereArgs: [_schemaVersionKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// `schema_version` is the one plaintext meta value (ASCII decimal); any
  /// other meta value is an encrypted record (app-architecture.md §4).
  static Future<int?> _readSchemaVersion(Database db) async {
    final rows = await db.query(
      'meta',
      columns: ['v'],
      where: 'k = ?',
      whereArgs: [_schemaVersionKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.single['v'];
    if (value is! List<int>) {
      return null;
    }
    return int.tryParse(ascii.decode(value, allowInvalid: true));
  }

  static Future<void> _writeSchemaVersion(Database db) async {
    await db.insert('meta', {
      'k': _schemaVersionKey,
      'v': Uint8List.fromList(ascii.encode('$kSchemaVersion')),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
