import 'package:sqflite/sqflite.dart';

import '../crypto/at_rest_aead.dart';
import '../crypto/record_cipher.dart';
import '../crypto/sodium_instance.dart';
import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../pairing/initiator/pairing_initiator_service.dart';
import '../pairing/initiator/pending_pairing.dart';
import '../storage/backup/backup_exclusion.dart';
import '../storage/keys/key_service.dart';
import '../storage/keys/master_key_store.dart';
import '../storage/storage_service.dart';
import '../storage/store_root.dart';
import '../transport/relay_socket.dart';
import 'app_scope.dart';

/// Composition root. Production boot passes nothing; tests inject the
/// database factory, store root, master-key store, and relay connector.
Future<NimnaServices> bootstrapNimna({
  DatabaseFactory? dbFactory,
  StoreRoot? storeRoot,
  MasterKeyStore? masterKeyStore,
  RelayConnector? relayConnector,
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

  final pairing = PairingInitiatorService(
    sodium: sodium,
    storage: storage,
    diag: diag,
    connector:
        relayConnector ?? WebSocketRelayConnector(config: const RelayConfig()),
    clock: clock,
  );

  // Boot-time read of the creator's outstanding codes (F2.4/F2.8 relaunch
  // edges): the newest entry is handed to the flow via the channel list's
  // first frame; the widget layer itself never queries the DB for this.
  // Fail-closed: a record that no longer decodes is unusable (the codes in
  // it are unrecoverable by design) — erase it and boot clean.
  List<PendingPairing> pendingEntries;
  try {
    pendingEntries = await pairing.pendingStore.readAll();
  } on FormatException {
    diag.log(DiagEvent.storageError, code: DiagCode.recordCorrupt);
    await storage.metaRecords.delete(PendingPairingStore.metaKey);
    pendingEntries = [];
  } on AeadAuthError {
    diag.log(DiagEvent.storageError, code: DiagCode.recordCorrupt);
    await storage.metaRecords.delete(PendingPairingStore.metaKey);
    pendingEntries = [];
  }
  if (pendingEntries.isNotEmpty) {
    pendingEntries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final latest = pendingEntries.removeLast();
    for (final stale in pendingEntries) {
      stale.dispose();
    }
    pairing.adoptInitialResume(latest);
  }

  return NimnaServices(
    keyService: keyService,
    storage: storage,
    diag: diag,
    pairing: pairing,
  );
}
