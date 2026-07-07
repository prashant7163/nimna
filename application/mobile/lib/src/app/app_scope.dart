import 'package:flutter/widgets.dart';

import '../diag/diag.dart';
import '../lock/lock_controller.dart';
import '../pairing/initiator/pairing_initiator_service.dart';
import '../pairing/joiner/joiner_service.dart';
import '../storage/keys/key_service.dart';
import '../storage/storage_service.dart';
import '../wipe/wipe_service.dart';

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
  });

  final KeyService keyService;
  final StorageService storage;
  final Diag diag;
  final PairingInitiatorService pairing;

  /// The joiner flow (F3) — the S9 counterpart to [pairing].
  final JoinerService joiner;
  final LockController lockController;
  final WipeService wipe;
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
