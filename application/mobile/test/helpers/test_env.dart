import 'dart:io';
import 'dart:typed_data';

import 'package:nimna/src/app/app_scope.dart';
import 'package:nimna/src/app/bootstrap.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/crypto/record_cipher.dart';
import 'package:nimna/src/crypto/sodium_instance.dart';
import 'package:nimna/src/storage/keys/master_key_store.dart';
import 'package:nimna/src/storage/store_root.dart';
import 'package:sodium/sodium.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared host-test environment: real libsodium (build-hook native asset),
/// real SQLite via FFI, in-memory keystore fake, temp-dir store roots.
/// Everything the app persists in production is exercised for real; only
/// the platform seams (keystore, path_provider) are faked.

Future<Sodium> testSodium() => SodiumInstance.init();

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

/// One simulated device: a stable store root + keystore across
/// "relaunches". [boot] builds a fresh service graph each call — calling
/// it again after [shutdown] is the storage-layer kill-and-relaunch.
class TestDevice {
  TestDevice(this.rootDir);

  static bool _ffiInitialized = false;

  final Directory rootDir;
  final FakeMasterKeyStore keyStore = FakeMasterKeyStore();
  DateTime Function()? clock;

  NimnaServices? _services;

  static TestDevice create() {
    final dir = Directory.systemTemp.createTempSync('nimna-test-');
    return TestDevice(dir);
  }

  StoreRoot get storeRoot => StoreRoot.at(rootDir);

  Future<NimnaServices> boot() async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    final services = await bootstrapNimna(
      dbFactory: databaseFactoryFfi,
      storeRoot: storeRoot,
      masterKeyStore: keyStore,
      clock: clock,
    );
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
