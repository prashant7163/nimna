import 'package:sodium/sodium.dart';

/// Process-wide libsodium instance holder.
///
/// `SodiumInit.init()` loads the libsodium native asset built by the
/// `sodium` package's build hooks (verified to load under `flutter test`
/// on the host as well as in app builds — app-architecture.md §1 spike).
/// Initialised exactly once at bootstrap; everything else receives the
/// [Sodium] instance by construction.
class SodiumInstance {
  SodiumInstance._();

  static Sodium? _instance;

  /// Initialises libsodium (idempotent) and returns the instance.
  static Future<Sodium> init() async => _instance ??= await SodiumInit.init();
}
