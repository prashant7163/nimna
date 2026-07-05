import 'package:sqflite/sqflite.dart';

import '../crypto/at_rest_aead.dart';
import '../crypto/record_cipher.dart';
import '../crypto/sodium_instance.dart';
import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../storage/backup/backup_exclusion.dart';
import '../storage/keys/key_service.dart';
import '../storage/keys/master_key_store.dart';
import '../storage/storage_service.dart';
import '../storage/store_root.dart';
import 'app_scope.dart';

/// Composition root. Production boot passes nothing; tests inject the
/// database factory, store root, and master-key store.
Future<NimnaServices> bootstrapNimna({
  DatabaseFactory? dbFactory,
  StoreRoot? storeRoot,
  MasterKeyStore? masterKeyStore,
  DateTime Function()? clock,
}) async {
  final sodium = await SodiumInstance.init();
  final aead = AtRestAead(sodium);
  final cipher = RecordCipher(aead);

  final diag = Diag(aead: aead, clock: clock);
  diag.log(DiagEvent.appLaunch);

  final keyService = KeyService(
    sodium: sodium,
    keyStore: masterKeyStore ?? SecureStorageMasterKeyStore(),
    diag: diag,
  );

  final root = storeRoot ?? await StoreRoot.resolve();
  final storage = StorageService(
    keyService: keyService,
    diag: diag,
    cipher: cipher,
    root: root,
    backupExclusion: BackupExclusion(diag: diag),
    dbFactory: dbFactory ?? databaseFactory,
  );
  await storage.open();

  return NimnaServices(keyService: keyService, storage: storage, diag: diag);
}
