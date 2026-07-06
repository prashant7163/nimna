import 'package:local_auth/local_auth.dart';

/// Seam over the OS biometric prompt (SESSION-13 intake §4). Tests fake
/// this; production uses [LocalAuthBiometricGate].
abstract interface class BiometricGate {
  /// True when biometric hardware exists and biometrics are enrolled —
  /// the F8.2 toggle row is hidden otherwise.
  Future<bool> isAvailable();

  /// Shows the OS biometric prompt. Returns true only on a biometric
  /// verdict; every failure/unavailability path returns false — the
  /// fallback is Nimna's own PIN pad, never the OS device credential.
  /// [reason] is the OS prompt's user-facing purpose line (localized by
  /// the caller — nothing below the UI layer touches locale).
  Future<bool> authenticate({required String reason});
}

/// The ONE `local_auth` call site in the app (fenced by review —
/// SESSION-13 intake §4). `biometricOnly: true` is load-bearing: the
/// device passcode is not the app PIN; delegating to it would make the
/// app gate as weak as the phone gate and bypass our verifier.
class LocalAuthBiometricGate implements BiometricGate {
  LocalAuthBiometricGate() : _auth = LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) {
        return false;
      }
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Exception {
      // LocalAuthException (lockout, canceled, unavailable, …) — every
      // path degrades to the PIN pad; nothing is surfaced or logged
      // (the pad is already on screen).
      return false;
    }
  }
}
