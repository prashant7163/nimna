import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../crypto/record_cipher.dart';
import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../domain/channel_repository.dart';
import '../domain/media_repository.dart';
import '../domain/message_repository.dart';
import 'backup/backup_exclusion.dart';
import 'db/meta_records.dart';
import 'db/nimna_database.dart';
import 'db/row_stores.dart';
import 'keys/key_service.dart';
import 'media/media_store.dart';
import 'store_root.dart';

/// The storage composition root: orders the open/seal/wipe sequences so the
/// privacy invariants hold by construction (app-architecture.md §3–§7).
class StorageService {
  StorageService({
    required this.keyService,
    required this.diag,
    required this.cipher,
    required this.root,
    required this.backupExclusion,
    required this._dbFactory,
  });

  final KeyService keyService;
  final Diag diag;
  final RecordCipher cipher;
  final StoreRoot root;
  final BackupExclusion backupExclusion;
  final DatabaseFactory _dbFactory;

  Database? _db;
  ChannelRepository? _channels;
  MessageRepository? _messages;
  MediaRepository? _media;
  MetaRecords? _metaRecords;

  bool get isOpen => _db != null;

  ChannelRepository get channels =>
      _channels ?? (throw StateError('storage not open'));
  MessageRepository get messages =>
      _messages ?? (throw StateError('storage not open'));
  MediaRepository get media => _media ?? (throw StateError('storage not open'));

  /// Encrypted meta values (S8+: the pending-pairings record).
  MetaRecords get metaRecords =>
      _metaRecords ?? (throw StateError('storage not open'));

  /// Boot/open sequence. Diag events raised before the log attaches queue
  /// in memory and flush at attach — order is deliberate.
  Future<void> open() async {
    if (isOpen) {
      return;
    }
    await keyService.open();

    root.create();
    // Backup exclusion: set at store-root creation, re-asserted every
    // launch (iOS; Android is manifest-static).
    await backupExclusion.assertExcluded(root.root.path);

    final result = await NimnaDatabase.open(
      factory: _dbFactory,
      root: root,
      diag: diag,
    );
    _db = result.db;
    if (result.created && !result.wasReset) {
      diag.log(DiagEvent.storeCreated);
    }

    diag.attach(diagKey: keyService.takeDiagKey(), dir: root.diagDir);

    final channelRepo = ChannelRepository(
      keyService: keyService,
      store: ChannelStore(result.db),
      cipher: cipher,
    );
    await channelRepo.openAll();
    _channels = channelRepo;
    _messages = MessageRepository(
      channels: channelRepo,
      store: MessageStore(result.db),
      cipher: cipher,
    );
    _media = MediaRepository(
      channels: channelRepo,
      indexStore: MediaIndexStore(result.db),
      blobStore: MediaStore(root: root, cipher: cipher),
      cipher: cipher,
      keyService: keyService,
    );
    _metaRecords = MetaRecords(
      db: result.db,
      keyService: keyService,
      cipher: cipher,
    );
    diag.log(DiagEvent.storeOpened);
  }

  /// Seals the perimeter: logs, detaches the log, zeroizes every key
  /// (store keys and held CDKs), closes the DB.
  Future<void> seal() async {
    if (!isOpen && keyService.sealed) {
      return;
    }
    diag.log(DiagEvent.storeSealed);
    diag.detach();
    _channels?.close();
    _channels = null;
    _messages = null;
    _media = null;
    _metaRecords = null;
    await _db?.close();
    _db = null;
    keyService.seal();
  }

  /// Full panic wipe (spec §6; app-architecture.md §3 — key destruction
  /// first, deletion second):
  /// 1. delete the keystore MK entry — everything on disk is now
  ///    undecryptable ciphertext even if the rest is interrupted;
  /// 2. zeroize in-memory keys (and drop the diag queue — a post-wipe
  ///    store is indistinguishable from a fresh install);
  /// 3. delete the store root recursively (DB + sidecars + media + diag);
  /// 4. recreate empty.
  Future<void> fullWipe() async {
    await keyService.destroyMasterKey();
    diag.reset();
    _channels?.close();
    _channels = null;
    _messages = null;
    _media = null;
    _metaRecords = null;
    await _db?.close();
    _db = null;
    keyService.seal();
    root.wipeAndRecreate();
  }

  /// Per-channel wipe: delete the channel row (the only copy of its CDK
  /// dies with it — the security boundary), then best-effort hygiene on
  /// rows and files.
  Future<void> wipeChannel(Uint8List channelId) async {
    final db = _db;
    if (db == null) {
      throw StateError('storage not open');
    }
    final mediaRows = await MediaIndexStore(db).byChannel(channelId);
    await channels.delete(channelId);
    await MessageStore(db).deleteByChannel(channelId);
    await MediaIndexStore(db).deleteByChannel(channelId);
    final blobStore = MediaStore(root: root, cipher: cipher);
    for (final row in mediaRows) {
      await blobStore.delete(row.id);
    }
    // WAL checkpoint after bulk deletes (deletion hygiene, not the
    // security boundary).
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    diag.log(DiagEvent.channelWiped);
  }
}
