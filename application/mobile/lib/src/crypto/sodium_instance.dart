import 'package:sodium/sodium_sumo.dart';

/// Process-wide libsodium instance holder.
///
/// `SodiumSumoInit.init()` loads the libsodium native asset built by the
/// `sodium` package's build hooks (verified to load under `flutter test`
/// on the host as well as in app builds — app-architecture.md §1 spike).
/// Initialised exactly once at bootstrap; everything else receives the
/// instance by construction.
///
/// S8 widening (intake §3, sanctioned): the instance is the SUMO variant of
/// the SAME package — `crypto_pwhash` (Argon2id, spec §3.1.2) is only
/// exposed on the sumo API. On FFI platforms the native library is the one
/// full libsodium either way; sumo is an API-surface widening, not a new
/// dependency. [SodiumSumo] implements `Sodium`, so every S7 consumer is
/// unchanged.
class SodiumInstance {
  SodiumInstance._();

  static SodiumSumo? _instance;

  /// Initialises libsodium (idempotent) and returns the instance.
  static Future<SodiumSumo> init() async =>
      _instance ??= await SodiumSumoInit.init();
}
