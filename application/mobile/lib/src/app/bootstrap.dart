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
import '../storage/backup/backup_exclusion.dart';
import '../storage/keys/key_service.dart';
import '../storage/keys/master_key_store.dart';
import '../storage/storage_service.dart';
import '../storage/store_root.dart';
import '../wipe/wipe_service.dart';
import 'app_scope.dart';

/// Composition root. Production boot passes nothing; tests inject the
/// database factory, store root, keystore/lock-config fakes, and the
/// reduced-cost Argon2id lane.
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

  await lockController.initialize(observeLifecycle: observeLifecycle);

  return NimnaServices(
    keyService: keyService,
    storage: storage,
    diag: diag,
    lockController: lockController,
    wipe: wipe,
  );
}
