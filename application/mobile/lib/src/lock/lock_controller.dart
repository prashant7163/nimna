import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../storage/keys/key_service.dart';
import 'biometric_gate.dart';
import 'lock_config_store.dart';
import 'pin_verifier.dart';

/// The app-lock state machine over the S7 perimeter (SESSION-13 intake
/// §1/§5): disabled → open; enabled: locked → unlocking → open. Once lock
/// is enabled, this is the ONLY path to `KeyService.open()` — bootstrap
/// delegates the boot-time open here, and a lock-enabled cold start never
/// touches the keystore until the gate passes (test-asserted).
///
/// Lifecycle (CODE, intake §5): seal immediately on
/// [AppLifecycleState.hidden] — it fires before the OS captures the
/// app-switcher snapshot, so the snapshot shows the sealed surface.
/// `inactive` NEVER seals (permission dialogs, the biometric prompt
/// itself, pickers). No grace period: no design artifact contains one.
///
/// Failed attempts (CODE, intake §2): each attempt already costs one
/// Argon2id; after 5 consecutive failures an in-memory escalating delay
/// (1 s doubling, cap 30 s) disarms the pad. The counter is NEVER
/// persisted, and there is no auto-wipe-after-N.
class LockController extends ChangeNotifier with WidgetsBindingObserver {
  LockController({
    required this._keyService,
    required this._configStore,
    required this._pinVerifier,
    required this._biometricGate,
    required this._openStorage,
    required this._sealStorage,
    void Function(Duration delay, void Function() callback)? scheduler,
  }) : _schedule = scheduler ?? _timerSchedule;

  static const int _freeFailures = 5;
  static const Duration _delayBase = Duration(seconds: 1);
  static const Duration _delayCap = Duration(seconds: 30);

  final KeyService _keyService;
  final LockConfigStore _configStore;
  final PinVerifier _pinVerifier;
  final BiometricGate _biometricGate;
  final Future<void> Function() _openStorage;
  final Future<void> Function() _sealStorage;
  final void Function(Duration delay, void Function() callback) _schedule;

  LockConfig? _config;
  int _consecutiveFailures = 0;
  bool _padArmed = true;
  bool _verifying = false;
  bool _biometricInFlight = false;

  static void _timerSchedule(Duration delay, void Function() callback) {
    Timer(delay, callback);
  }

  /// Whether the app lock is enrolled.
  bool get enabled => _config?.pinEnabled ?? false;

  bool get biometricEnabled => enabled && (_config?.biometricEnabled ?? false);

  /// Enrolled PIN length — the sealed surface renders exactly this many
  /// dots and auto-submits at full length (screen 12).
  int get pinLength => _config?.pinLength ?? LockConfig.pinLengthMin;

  /// False while the escalating retry delay runs; the pad ignores input.
  bool get padArmed => _padArmed && !_verifying;

  /// True while an Argon2id verification is in flight.
  bool get verifying => _verifying;

  /// The gate is currently between the user and the content.
  bool get locked => enabled && _keyService.sealed;

  /// The escalating in-memory delay schedule (intake §2): zero through the
  /// 4th consecutive failure, then 1 s doubling per failure, capped 30 s.
  static Duration delayForFailures(int consecutiveFailures) {
    if (consecutiveFailures < _freeFailures) {
      return Duration.zero;
    }
    final exponent = math.min(consecutiveFailures - _freeFailures, 30);
    final seconds = math.min(
      _delayBase.inSeconds << exponent,
      _delayCap.inSeconds,
    );
    return Duration(seconds: seconds);
  }

  /// Boot entry: reads the lock config and — only when no lock is
  /// enrolled — opens storage. With lock enabled the keystore is never
  /// read until the gate passes.
  ///
  /// [observeLifecycle] registers the seal-on-`hidden` observer; it
  /// requires an initialized WidgetsBinding (production and widget tests
  /// have one; pure storage-layer tests pass false).
  Future<void> initialize({bool observeLifecycle = true}) async {
    if (observeLifecycle && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _config = await _configStore.read();
    if (!enabled) {
      await _openStorage();
    }
    notifyListeners();
  }

  bool _observing = false;

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `hidden` fires before `paused` on both platforms — before the OS
    // snapshot. `inactive` deliberately does nothing.
    if (state == AppLifecycleState.hidden && enabled && !_keyService.sealed) {
      // Keys-before-I/O: flip the in-memory perimeter synchronously so the
      // LockGate repaints to the sealed surface within this callback —
      // before the OS captures the app-switcher snapshot. The async DB
      // close then runs behind it. `KeyService.seal()` is idempotent, so
      // the redundant `storage.seal()` → `keyService.seal()` inside
      // `_sealStorage()` is a harmless no-op.
      _keyService.seal();
      unawaited(_sealStorage());
    }
  }

  /// PIN attempt from the sealed surface (or the turn-off gate). Returns
  /// true and opens storage on success. Shares the failure escalation
  /// across every PIN surface.
  Future<bool> submitPin(String pin) async {
    if (!padArmed) {
      return false;
    }
    final ok = await _runVerify(pin);
    if (ok && _keyService.sealed) {
      await _openStorage();
      notifyListeners();
    }
    return ok;
  }

  /// PIN check without opening storage (turning lock off, F8.2 edge:
  /// requires the current PIN first).
  Future<bool> confirmPin(String pin) =>
      padArmed ? _runVerify(pin) : Future.value(false);

  /// Whether biometric hardware exists with enrolled biometrics — the
  /// F8.2 toggle row is hidden otherwise.
  Future<bool> biometricAvailable() => _biometricGate.isAvailable();

  /// One biometric attempt (auto-prompted by the sealed surface). A
  /// verdict gates `open()` exactly as a correct PIN does.
  Future<bool> tryBiometric({required String reason}) async {
    if (!biometricEnabled || _biometricInFlight || !_keyService.sealed) {
      return false;
    }
    _biometricInFlight = true;
    try {
      final ok = await _biometricGate.authenticate(reason: reason);
      if (ok) {
        _consecutiveFailures = 0;
        await _openStorage();
        notifyListeners();
      }
      return ok;
    } finally {
      _biometricInFlight = false;
    }
  }

  /// Enrolls the lock (F8.2 setup completion).
  Future<void> enableLock({
    required String pin,
    required bool biometricEnabled,
  }) async {
    await _pinVerifier.enroll(pin: pin, biometricEnabled: biometricEnabled);
    await reload();
  }

  /// Removes the lock after verifying the current PIN.
  Future<bool> disableLock({required String pin}) async {
    if (!await confirmPin(pin)) {
      return false;
    }
    await _configStore.delete();
    await reload();
    return true;
  }

  /// Flips the biometric flag on an enrolled lock.
  Future<void> setBiometricEnabled(bool value) async {
    final config = _config;
    if (config == null) {
      return;
    }
    await _configStore.write(config.copyWith(biometricEnabled: value));
    await reload();
  }

  /// Re-reads the config (post-wipe, post-setup).
  Future<void> reload() async {
    _config = await _configStore.read();
    _consecutiveFailures = 0;
    _padArmed = true;
    notifyListeners();
  }

  Future<bool> _runVerify(String pin) async {
    _verifying = true;
    notifyListeners();
    try {
      final ok = await _pinVerifier.verify(pin);
      if (ok) {
        _consecutiveFailures = 0;
      } else {
        _registerFailure();
      }
      return ok;
    } finally {
      _verifying = false;
      notifyListeners();
    }
  }

  void _registerFailure() {
    _consecutiveFailures++;
    final delay = delayForFailures(_consecutiveFailures);
    if (delay > Duration.zero) {
      _padArmed = false;
      _schedule(delay, () {
        _padArmed = true;
        notifyListeners();
      });
    }
  }
}
