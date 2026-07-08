import 'package:sodium/sodium_sumo.dart';

import '../../crypto/at_rest_aead.dart';
import '../../diag/diag.dart';
import '../../storage/storage_service.dart';
import '../../transport/relay_socket.dart';
import 'initiator_controller.dart';
import 'pending_pairing.dart';

/// Constructor-injected dependency bundle for the initiator flow
/// (app-architecture.md §8.2). Lives in AppScope; controllers are minted
/// per flow run — only by the flow's own wiring in create_line_entry.dart
/// (the G2 single-entry invariant).
class PairingInitiatorService {
  PairingInitiatorService({
    required SodiumSumo sodium,
    required StorageService storage,
    required this._diag,
    required this._connector,
    this._clock,
  }) : _sodium = sodium,
       _storage = storage,
       pendingStore = PendingPairingStore(storage: storage, sodium: sodium);

  final SodiumSumo _sodium;
  final StorageService _storage;
  final Diag _diag;
  final RelayConnector _connector;
  final DateTime Function()? _clock;

  /// The creator's outstanding codes (also the S9 self-join guard source).
  final PendingPairingStore pendingStore;

  PendingPairing? _initialResume;

  /// Set once by the composition root: the newest pending pairing read at
  /// boot (the store read happens OUTSIDE the widget layer, at real-async
  /// boot time), for the F2.4/F2.8 relaunch edges.
  void adoptInitialResume(PendingPairing? entry) => _initialResume = entry;

  /// Hands the boot-time pending pairing (if any) to the flow, exactly
  /// once. Synchronous by design — the widget layer never touches the DB
  /// for this.
  PendingPairing? takeInitialResume() {
    final entry = _initialResume;
    _initialResume = null;
    return entry;
  }

  /// Mints a controller for one flow run. Flow-internal. Supplies the S16
  /// finalize deps (storage/aead/wordlist) so a created line reaches the
  /// safety phrase (F2.6) and "channel ready" (F2.7) — the creator half of
  /// "install → paired chat unaided".
  CreateLineController newController() => CreateLineController(
    sodium: _sodium,
    connector: _connector,
    store: pendingStore,
    diag: _diag,
    storage: _storage,
    aead: AtRestAead(_sodium),
    clock: _clock,
  );
}
