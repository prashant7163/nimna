import 'package:sodium/sodium_sumo.dart';

/// Process-wide libsodium instance holder.
///
/// `SodiumSumoInit.init()` loads the libsodium native asset built by the
/// `sodium` package's build hooks (verified to load under `flutter test`
/// on the host as well as in app builds — app-architecture.md §1 spike).
/// Initialised exactly once at bootstrap; everything else receives the
/// instance by construction.
///
/// Widening to the SUMO variant is sanctioned (S8 intake §3): it is the
/// SUMO API surface of the SAME package over the identical bundled binary —
/// an API-surface widening, not a new dependency. The sumo surface
/// additionally exposes `crypto_pwhash` (Argon2id — the S13 PIN verifier,
/// spec §7) and `crypto_scalarmult` (S8/S9 rendezvous/Noise), neither of
/// which is on the base API. [SodiumSumo] implements [Sodium], so every
/// existing S7 consumer is unaffected.
class SodiumInstance {
  SodiumInstance._();

  static SodiumSumo? _instance;

  /// Initialises libsodium (idempotent) and returns the instance.
  static Future<SodiumSumo> init() async =>
      _instance ??= await SodiumSumoInit.init();
}
