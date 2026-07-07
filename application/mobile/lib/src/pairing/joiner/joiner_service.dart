import 'package:sodium/sodium_sumo.dart';

import '../../crypto/at_rest_aead.dart';
import '../../diag/diag.dart';
import '../../storage/storage_service.dart';
import '../../transport/relay_socket.dart';
import '../initiator/pending_pairing.dart';
import 'join_controller.dart';

/// Constructor-injected dependency bundle for the joiner flow (F3),
/// mirroring [PairingInitiatorService]. Lives in AppScope; a [JoinController]
/// is minted per flow run. The joiner shares only the pure `protocol/` +
/// `transport/` + `noise/` layers with the initiator (S8/S9 intake), plus
/// the same `pending_pairings` record for the self-join guard (its own
/// [PendingPairingStore] instance reads the identical at-rest record).
class JoinerService {
  JoinerService({
    required SodiumSumo sodium,
    required this._aead,
    required StorageService storage,
    required this._diag,
    required this._connector,
    this._clock,
  }) : _sodium = sodium,
       _storage = storage,
       pendingStore = PendingPairingStore(storage: storage, sodium: sodium);

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final StorageService _storage;
  final Diag _diag;
  final RelayConnector _connector;
  final DateTime Function()? _clock;

  /// Source of the self-join guard (own OUTSTANDING codes; §3.1 step 3).
  final PendingPairingStore pendingStore;

  /// Mints a controller for one join-flow run. Flow-internal.
  JoinController newController() => JoinController(
    sodium: _sodium,
    aead: _aead,
    storage: _storage,
    pendingStore: pendingStore,
    connector: _connector,
    diag: _diag,
    clock: _clock,
  );
}
