import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../crypto/at_rest_aead.dart';
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
  ///
  /// One SILENT fresh-install-reset is permitted (S13→S14, architect ACK
  /// 2026-07-07): if [ChannelRepository.openAll] raises [AeadAuthError] — a
  /// stored channel row no longer authenticates under the current MK, the
  /// interrupted-wipe / keystore-loss signature — destroy the MK, wipe the
  /// root, and re-open empty. There is NO user surface for this path (decision
  /// 2, AeadAuthError auto-reset is SILENT): not a lock screen, not the panic-
  /// wipe UI, and `wasReset` is deliberately NOT propagated — a post-reset
  /// store is indistinguishable from a fresh install.
  Future<void> open() async {
    if (isOpen) {
      return;
    }
    var didReset = false;
    while (true) {
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
      if (result.created && !result.wasReset) {
        diag.log(DiagEvent.storeCreated);
      }

      diag.attach(diagKey: keyService.takeDiagKey(), dir: root.diagDir);

      final channelRepo = ChannelRepository(
        keyService: keyService,
        store: ChannelStore(result.db),
        cipher: cipher,
      );
      try {
        await channelRepo.openAll();
      } on AeadAuthError {
        if (didReset) {
          // A freshly created store still failing is NOT a wipe signature —
          // surface it rather than loop.
          rethrow;
        }
        didReset = true;
        await _freshInstallReset(result.db, channelRepo);
        continue; // Re-open from scratch against the now-empty store.
      }

      _db = result.db;
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
      return;
    }
  }

  /// The SILENT fresh-install-reset primitive (decision 2). Mirrors [fullWipe]'s
  /// key-FIRST destruction so on-disk data is undecryptable even if the sweep
  /// is interrupted: destroy the MK, drop the diag ring, close the DB, zeroize
  /// in-memory keys, then delete + recreate the store root. The caller re-runs
  /// [open] against the empty root. No diag event marks this — a post-reset
  /// store must be indistinguishable from a fresh install (mirrors the
  /// no-`fullWipe`-event stance). [channelRepo] is the not-yet-adopted repo
  /// whose `openAll` raised — closed here for symmetry with [fullWipe] (it
  /// holds no loaded key material after a failed open, but we mirror the field
  /// teardown so no future refactor leaks one).
  Future<void> _freshInstallReset(
    Database db,
    ChannelRepository channelRepo,
  ) async {
    await keyService.destroyMasterKey();
    diag.reset();
    channelRepo.close();
    _channels = null;
    _messages = null;
    _media = null;
    _metaRecords = null;
    await db.close();
    _db = null;
    keyService.seal();
    root.wipeAndRecreate();
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
