import 'package:sqflite/sqflite.dart';

import '../crypto/at_rest_aead.dart';
import '../crypto/record_cipher.dart';
import '../crypto/sodium_instance.dart';
import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../lock/biometric_gate.dart';
import '../lock/lock_config_store.dart';
import '../lock/lock_controller.dart';
import '../lock/pin_verifier.dart';
import '../pairing/initiator/pairing_initiator_service.dart';
import '../pairing/initiator/pending_pairing.dart';
import '../storage/backup/backup_exclusion.dart';
import '../storage/keys/key_service.dart';
import '../storage/keys/master_key_store.dart';
import '../storage/storage_service.dart';
import '../storage/store_root.dart';
import '../transport/relay_socket.dart';
import '../wipe/wipe_service.dart';
import 'app_scope.dart';

/// Composition root. Production boot passes nothing; tests inject the
/// database factory, store root, master-key store, relay connector,
/// keystore/lock-config fakes, and the reduced-cost Argon2id lane.
///
/// S13: boot no longer opens storage unconditionally —
/// [LockController.initialize] consults the lock config first and, with a
/// lock enrolled, leaves the perimeter sealed (the keystore is never read
/// behind a locked gate). [observeLifecycle] is true in production
/// (requires an initialized WidgetsBinding); storage-layer tests without
/// a binding pass false.
Future<NimnaServices> bootstrapNimna({
  DatabaseFactory? dbFactory,
  StoreRoot? storeRoot,
  MasterKeyStore? masterKeyStore,
  RelayConnector? relayConnector,
  LockConfigStore? lockConfigStore,
  BiometricGate? biometricGate,
  DateTime Function()? clock,
  int pinOpsLimit = PinVerifier.specOpsLimit,
  int pinMemLimit = PinVerifier.specMemLimitBytes,
  void Function(Duration delay, void Function() callback)? lockScheduler,
  bool observeLifecycle = true,
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

  final pairing = PairingInitiatorService(
    sodium: sodium,
    storage: storage,
    diag: diag,
    connector:
        relayConnector ?? WebSocketRelayConnector(config: const RelayConfig()),
    clock: clock,
  );

  final configStore = lockConfigStore ?? SecureStorageLockConfigStore();
  final lockController = LockController(
    keyService: keyService,
    configStore: configStore,
    pinVerifier: PinVerifier(
      sodium: sodium,
      aead: aead,
      store: configStore,
      opsLimit: pinOpsLimit,
      memLimit: pinMemLimit,
    ),
    biometricGate: biometricGate ?? LocalAuthBiometricGate(),
    openStorage: storage.open,
    sealStorage: storage.seal,
    scheduler: lockScheduler,
  );
  final wipe = WipeService(
    storage: storage,
    lockConfigStore: configStore,
    lockController: lockController,
  );

  // Lock first: with a lock enrolled this leaves the perimeter SEALED and
  // never reads the keystore; with the lock disabled it opens storage.
  await lockController.initialize(observeLifecycle: observeLifecycle);

  // Boot-time read of the creator's outstanding codes (F2.4/F2.8 relaunch
  // edges): the newest entry is handed to the flow via the channel list's
  // first frame; the widget layer itself never queries the DB for this.
  // Fail-closed: a record that no longer decodes is unusable (the codes in
  // it are unrecoverable by design) — erase it and boot clean.
  //
  // Only when the store is actually open (lock disabled). With a lock
  // enrolled the perimeter is sealed at boot, so this read cannot run
  // without crashing (StorageSealedError) — skip it and treat it as no
  // pending entry.
  // TODO(S9): when a lock is enrolled, resume the pending-pairing flow
  // after a successful unlock (read pending_pairings once the perimeter is
  // unsealed) so F2.4/F2.8 relaunch edges also work behind the lock.
  if (storage.isOpen) {
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
  }

  return NimnaServices(
    keyService: keyService,
    storage: storage,
    diag: diag,
    pairing: pairing,
    lockController: lockController,
    wipe: wipe,
  );
}
