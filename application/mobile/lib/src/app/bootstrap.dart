import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../billing/billing_service.dart';
import '../billing/entitlement_source.dart';
import '../billing/store_entitlement_source.dart';
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
import '../pairing/joiner/joiner_service.dart';
import '../presence/peer_token_store.dart';
import '../presence/push_opt_in.dart';
import '../presence/session_launcher.dart';
import '../push/platform_push_source.dart';
import '../push/push_service.dart';
import '../push/push_source_factory.dart';
import '../storage/backup/backup_exclusion.dart';
import '../storage/keys/key_service.dart';
import '../storage/keys/master_key_store.dart';
import '../storage/storage_service.dart';
import '../storage/store_root.dart';
import '../transport/relay_socket.dart';
import '../wipe/wipe_service.dart';
import 'app_scope.dart';
import 'first_run_store.dart';

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
  EntitlementSource? entitlementSource,
  DateTime Function()? clock,
  int pinOpsLimit = PinVerifier.specOpsLimit,
  int pinMemLimit = PinVerifier.specMemLimitBytes,
  void Function(Duration delay, void Function() callback)? lockScheduler,
  bool observeLifecycle = true,
  PlatformPushSource? pushSource,
  PushService? pushService,
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

  final connector =
      relayConnector ?? WebSocketRelayConnector(config: const RelayConfig());

  final pairing = PairingInitiatorService(
    sodium: sodium,
    storage: storage,
    diag: diag,
    connector: connector,
    clock: clock,
  );

  final joiner = JoinerService(
    sodium: sodium,
    aead: aead,
    storage: storage,
    diag: diag,
    connector: connector,
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

  // S17 billing: production reads the platform's signed on-device
  // entitlement cache (StoreEntitlementSource over in_app_purchase); tests
  // inject a fake EntitlementSource. Nothing here persists an entitlement
  // flag — permanence is structural (spec §10).
  final billing = BillingService(entitlementSource ?? StoreEntitlementSource());

  // S15 push: the orchestrator over the platform push source. Production
  // picks native APNs (iOS) / FCM (Android); off-mobile and host tests get
  // InertPushSource — NOTHING touches Google/Apple until a line opts in
  // (default off, string 18). `initialize()` subscribes to OS token
  // rotations (no-op when inert). The opt-in lookup is LAZY (resolves the
  // current channel repo at read time, false while sealed) so no stale repo
  // is captured across a seal/unseal cycle.
  // Tests inject a [PushService] spy (e.g. to assert the SessionLauncher's
  // bindSession hook fired at the composition root); production builds the
  // real orchestrator over the platform source.
  final push =
      (pushService ??
            PushService(
              source: pushSource ?? defaultPushSource(),
              isOptedIn: (channelId) =>
                  storage.isOpen &&
                  PushOptIn(storage.channels).isEnabled(channelId),
            ))
        ..initialize();

  // S16 composition root (architect Concern 1 / the S15 forward-requirement):
  // a FACTORY that builds a fresh SessionLauncher over the CURRENTLY-open
  // repositories each time a session is launched — channels/messages/media are
  // recreated on every seal→unseal, so capturing them once would go stale
  // (the same lazy-repo discipline the S15 minimal push mount uses). The one
  // line the forward-requirement is about — `onSessionBound: push.bindSession`
  // — lives HERE, at the composition root, so a launched session announces
  // this device's own token to an opted-in peer. `presence` never imports the
  // push lane; the hook is a bare typedef.
  SessionLauncher buildSessionLauncher() => SessionLauncher(
    sodium: sodium,
    aead: aead,
    connector: connector,
    channels: storage.channels,
    messages: storage.messages,
    media: storage.media,
    diag: diag,
    pushOptIn: PushOptIn(storage.channels),
    peerTokenStore: PeerTokenStore(storage.channels),
    clock: clock,
    onSessionBound: push.bindSession,
  );

  final firstRun = FirstRunStore(root.root);

  // Lock first: with a lock enrolled this leaves the perimeter SEALED and
  // never reads the keystore; with the lock disabled it opens storage.
  await lockController.initialize(observeLifecycle: observeLifecycle);

  // Boot-time read of the creator's outstanding codes (F2.4/F2.8 relaunch
  // edges): the newest entry is handed to the flow via the channel list's
  // first frame; the widget layer itself never queries the DB for this.
  //
  // The read requires an OPEN store. With the lock disabled the store is
  // open at boot, so it runs immediately. With a lock enrolled the perimeter
  // is sealed at boot (StorageSealedError otherwise), so it defers to the
  // first sealed→unsealed transition (S13 // TODO(S9)) via a one-shot
  // listener on the LockController. A single idempotency latch guarantees it
  // fires EXACTLY once across both paths, guarding against a stale re-adopt
  // of a consumed one-shot entry.
  var pendingResumeLoaded = false;
  Future<void> loadPendingPairing() async {
    if (pendingResumeLoaded || !storage.isOpen) {
      return;
    }
    pendingResumeLoaded = true;
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

  // Lock-disabled cold start: the store is already open.
  await loadPendingPairing();

  // Lock-enrolled cold start: resume on the first unlock. `locked` reflects
  // `keyService.sealed`; unlock opens the store and notifies. The latch
  // makes this a no-op if the boot read already ran.
  if (!pendingResumeLoaded) {
    void onLockTransition() {
      if (pendingResumeLoaded) {
        lockController.removeListener(onLockTransition);
        return;
      }
      if (storage.isOpen && !lockController.locked) {
        lockController.removeListener(onLockTransition);
        unawaited(loadPendingPairing());
      }
    }

    lockController.addListener(onLockTransition);
  }

  return NimnaServices(
    keyService: keyService,
    storage: storage,
    diag: diag,
    pairing: pairing,
    joiner: joiner,
    lockController: lockController,
    wipe: wipe,
    billing: billing,
    pushService: push,
    sessionLauncher: buildSessionLauncher,
    firstRun: firstRun,
  );
}
