import 'package:flutter/widgets.dart';

import '../billing/billing_service.dart';
import '../diag/diag.dart';
import '../lock/lock_controller.dart';
import '../pairing/initiator/pairing_initiator_service.dart';
import '../pairing/joiner/joiner_service.dart';
import '../presence/session_launcher.dart';
import '../push/push_service.dart';
import '../storage/keys/key_service.dart';
import '../storage/storage_service.dart';
import '../wipe/wipe_service.dart';
import 'first_run_store.dart';

/// Constructor-injected singleton services (app-architecture.md §8.2 —
/// zero-dependency state management: ChangeNotifier services through one
/// InheritedWidget, consumed via ListenableBuilder).
class NimnaServices {
  const NimnaServices({
    required this.keyService,
    required this.storage,
    required this.diag,
    required this.pairing,
    required this.joiner,
    required this.lockController,
    required this.wipe,
    required this.billing,
    required this.pushService,
    required this.sessionLauncher,
    required this.firstRun,
  });

  final KeyService keyService;
  final StorageService storage;
  final Diag diag;
  final PairingInitiatorService pairing;

  /// The joiner flow (F3) — the S9 counterpart to [pairing].
  final JoinerService joiner;
  final LockController lockController;
  final WipeService wipe;

  /// S17 — the creation-gate billing orchestrator. Consulted ONLY by
  /// `startCreateLine`; the session/send/receive path and the channel list
  /// never reference it (permanence is structural, spec §10).
  final BillingService billing;

  /// S15 — the push orchestrator: own-token acquisition, token-refresh
  /// wiring, tap routing, foreground suppression. Off-Android/off-iOS (and in
  /// host tests) its source is inert, so push is a no-op with zero
  /// third-party touch.
  final PushService pushService;

  /// S16 — the production presence/session composition root. A FACTORY, not a
  /// singleton: each call builds a fresh [SessionLauncher] bound to the
  /// CURRENTLY-open storage repositories (channels/messages/media are recreated
  /// on every seal→unseal, so a captured launcher would go stale). The push
  /// hook (`onSessionBound: pushService.bindSession`) is wired inside the
  /// factory in [bootstrapNimna] — the S15 forward-requirement — so every
  /// launched session announces this device's own token to an opted-in peer.
  final SessionLauncher Function() sessionLauncher;

  /// S16 — the first-run gate: whether onboarding (F1) has been seen. Plaintext
  /// marker under the store root (no user data), so it is readable regardless
  /// of the lock perimeter and wiped with everything on panic wipe.
  final FirstRunStore firstRun;
}

/// The one DI surface. `AppScope.of(context)` anywhere below the app root.
class AppScope extends InheritedWidget {
  const AppScope({required this.services, required super.child, super.key});

  final NimnaServices services;

  static NimnaServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
