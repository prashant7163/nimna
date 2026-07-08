import 'dart:io';
import 'dart:typed_data';

import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/bootstrap.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/crypto/record_cipher.dart';
import 'package:nimna/src/crypto/sodium_instance.dart';
import 'package:nimna/src/lock/biometric_gate.dart';
import 'package:nimna/src/lock/lock_config_store.dart';
import 'package:nimna/src/push/push_service.dart';
import 'package:nimna/src/storage/keys/master_key_store.dart';
import 'package:nimna/src/storage/store_root.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_entitlement.dart';
import 'fake_relay.dart';

/// Shared host-test environment: real libsodium (build-hook native asset),
/// real SQLite via FFI, in-memory keystore fake, temp-dir store roots.
/// Everything the app persists in production is exercised for real; only
/// the platform seams (keystore, path_provider) are faked.

Future<SodiumSumo> testSodium() => SodiumInstance.init();

/// Reduced-cost Argon2id lane for fast CI verifier round-trips. The
/// production-parameter lane is the tagged `production-cost` test
/// (dart_test.yaml) — the pinned spec constants are asserted separately.
const int testPinOpsLimit = 1;
const int testPinMemLimit = 8 * 1024 * 1024;

Future<AtRestAead> testAead() async => AtRestAead(await testSodium());

Future<RecordCipher> testCipher() async => RecordCipher(await testAead());

/// In-memory MasterKeyStore — the platform-keystore fake.
class FakeMasterKeyStore implements MasterKeyStore {
  Uint8List? stored;

  @override
  Future<Uint8List?> read() async =>
      stored == null ? null : Uint8List.fromList(stored!);

  @override
  Future<void> write(Uint8List key) async {
    stored = Uint8List.fromList(key);
  }

  @override
  Future<void> delete() async {
    stored = null;
  }
}

/// In-memory LockConfigStore — the second secure-storage item's fake.
class FakeLockConfigStore implements LockConfigStore {
  Uint8List? stored;

  @override
  Future<LockConfig?> read() async =>
      stored == null ? null : LockConfig.decode(Uint8List.fromList(stored!));

  @override
  Future<void> write(LockConfig config) async {
    stored = config.encode();
  }

  @override
  Future<void> delete() async {
    stored = null;
  }
}

/// Scriptable biometric fake: [available] gates the F8.2 row;
/// [nextResult] is what the "OS prompt" answers; [prompts] records the
/// reasons shown.
class FakeBiometricGate implements BiometricGate {
  bool available = false;
  bool nextResult = false;
  final List<String> prompts = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts.add(reason);
    return nextResult;
  }
}

/// One simulated device: a stable store root + keystore + lock config
/// across "relaunches". [boot] builds a fresh service graph each call —
/// calling it again after [shutdown] is the storage-layer
/// kill-and-relaunch.
class TestDevice {
  TestDevice(this.rootDir);

  static bool _ffiInitialized = false;

  final Directory rootDir;
  final FakeMasterKeyStore keyStore = FakeMasterKeyStore();
  final FakeLockConfigStore lockStore = FakeLockConfigStore();
  final FakeBiometricGate biometricGate = FakeBiometricGate();

  /// No-op relay connector so boot never constructs a real
  /// WebSocketRelayConnector; pairing tests that drive the wire build their
  /// own connector against [NimnaServices.storage].
  final FakeRelayConnector relayConnector = FakeRelayConnector();

  /// Billing seam fake — defaults to "no subscription" so the S17 gate is
  /// exercised without a store. Billing tests script it before [boot].
  final FakeEntitlementSource entitlement = FakeEntitlementSource();
  DateTime Function()? clock;

  /// Injectable escalating-delay scheduler (default: real timers).
  void Function(Duration delay, void Function() callback)? lockScheduler;

  /// Storage-layer tests run without a WidgetsBinding; widget tests that
  /// need seal-on-hidden flip this before [boot].
  bool observeLifecycle = false;

  NimnaServices? _services;

  static TestDevice create() {
    final dir = Directory.systemTemp.createTempSync('nimna-test-');
    return TestDevice(dir);
  }

  StoreRoot get storeRoot => StoreRoot.at(rootDir);

  /// [onboardingSeen] defaults TRUE: the vast majority of app-level tests
  /// predate the F1 first-run gate and expect to land on the channel list, so
  /// boot marks onboarding seen. Onboarding-flow tests pass `false`.
  Future<NimnaServices> boot({
    MasterKeyStore? masterKeyStore,
    PushService? pushService,
    bool onboardingSeen = true,
  }) async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    final services = await bootstrapNimna(
      dbFactory: databaseFactoryFfi,
      storeRoot: storeRoot,
      masterKeyStore: masterKeyStore ?? keyStore,
      relayConnector: relayConnector,
      lockConfigStore: lockStore,
      biometricGate: biometricGate,
      entitlementSource: entitlement,
      clock: clock,
      pinOpsLimit: testPinOpsLimit,
      pinMemLimit: testPinMemLimit,
      lockScheduler: lockScheduler,
      observeLifecycle: observeLifecycle,
      // S16: a spy PushService lets the bootstrap-level bind test assert the
      // SessionLauncher's onSessionBound hook fired at the composition root.
      pushService: pushService,
    );
    if (onboardingSeen) {
      await services.firstRun.markSeen();
    }
    _services = services;
    return services;
  }

  /// Simulates process death at the storage layer.
  Future<void> shutdown() async {
    await _services?.storage.seal();
    _services = null;
  }

  Future<void> dispose() async {
    await shutdown();
    if (rootDir.existsSync()) {
      rootDir.deleteSync(recursive: true);
    }
  }
}

/// Scans a file's raw bytes for an ASCII marker; returns true if found.
bool fileContainsMarker(File file, String marker) =>
    fileContainsBytes(file, marker.codeUnits);

/// Scans a file's raw bytes for a raw byte needle (review N1: key material
/// is scanned as bytes, not only as its hex-ASCII rendering).
bool fileContainsBytes(File file, List<int> needle) {
  if (!file.existsSync()) {
    return false;
  }
  return bytesContainBytes(file.readAsBytesSync(), needle);
}

bool bytesContainMarker(Uint8List haystack, String marker) =>
    bytesContainBytes(haystack, marker.codeUnits);

bool bytesContainBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return false;
  }
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

/// Every regular file under [dir], recursively.
List<File> allFilesUnder(Directory dir) => dir.existsSync()
    ? dir.listSync(recursive: true).whereType<File>().toList()
    : const [];

Uint8List asciiBytes(String s) => Uint8List.fromList(s.codeUnits);

Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
