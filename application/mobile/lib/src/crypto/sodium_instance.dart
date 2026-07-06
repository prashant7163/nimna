import 'package:sodium/sodium_sumo.dart';

/// Process-wide libsodium instance holder.
///
/// `SodiumSumoInit.init()` loads the same libsodium native asset built by
/// the `sodium` package's build hooks (verified to load under
/// `flutter test` on the host as well as in app builds —
/// app-architecture.md §1 spike). The SUMO surface is the package's own
/// high-level API over the identical bundled binary — it additionally
/// exposes `crypto_pwhash` (Argon2id, spec §7 — the S13 PIN verifier) and
/// `crypto_scalarmult` (S8/S9 Noise). [SodiumSumo] implements [Sodium], so
/// every existing consumer is unaffected.
///
/// Initialised exactly once at bootstrap; everything else receives the
/// instance by construction.
class SodiumInstance {
  SodiumInstance._();

  static SodiumSumo? _instance;

  /// Initialises libsodium (idempotent) and returns the instance.
  static Future<SodiumSumo> init() async =>
      _instance ??= await SodiumSumoInit.init();
}
