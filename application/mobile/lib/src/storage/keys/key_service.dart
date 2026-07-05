import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sodium/sodium.dart';

import '../../crypto/at_rest_aead.dart';
import '../../crypto/hkdf.dart';
import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import 'master_key_store.dart';

/// Thrown by every key accessor while the service is sealed — the storage
/// layer structurally cannot decrypt while locked (app-architecture.md §3).
class StorageSealedError extends Error {
  @override
  String toString() => 'StorageSealedError';
}

/// Owns the master key and every MK-derived store key, all in `SecureKey`
/// native memory (the panic-wipe substrate). States: sealed ⇄ open.
///
/// Key hierarchy (app-architecture.md §3 — normative):
/// ```
/// platform keystore ─ MK (32 random bytes, minted at first launch)
///   ├─ k_channels  = HKDF(MK, "nimna/app/store/v1/channels")
///   ├─ k_media_ix  = HKDF(MK, "nimna/app/store/v1/media-index")
///   ├─ k_diag      = HKDF(MK, "nimna/app/store/v1/diag")
///   └─ k_meta      = HKDF(MK, "nimna/app/store/v1/meta")
/// ```
/// (Messages and media blobs key off each channel's CDK, which lives inside
/// the channel record ciphertext — not here.)
///
/// S7 ships `open()` loading from the keystore unconditionally; S13 drops
/// PIN/biometric in front of it and wires lifecycle-pause → `seal()`.
class KeyService extends ChangeNotifier {
  KeyService({
    required this._sodium,
    required this._keyStore,
    required this._diag,
  });

  static const int masterKeyBytes = 32;

  final Sodium _sodium;
  final MasterKeyStore _keyStore;
  final Diag _diag;

  SecureKey? _masterKey;
  SecureKey? _kChannels;
  SecureKey? _kMediaIndex;
  SecureKey? _kMeta;

  bool get sealed => _masterKey == null;

  /// Loads (or on first launch mints) the master key and derives the store
  /// keys. Returns true if a new master key was generated.
  Future<bool> open() async {
    if (!sealed) {
      return false;
    }
    var generated = false;
    Uint8List? bytes;
    try {
      bytes = await _keyStore.read();
      if (bytes == null) {
        bytes = _sodium.randombytes.buf(masterKeyBytes);
        await _keyStore.write(bytes);
        generated = true;
        _diag.log(DiagEvent.masterKeyGenerated);
      }
      _masterKey = SecureKey.fromList(_sodium, bytes);
    } finally {
      // Zeroize the heap copy on every path (review N5) — including a
      // keystore write failure, which would otherwise abandon a freshly
      // minted MK in GC memory.
      bytes?.fillRange(0, bytes.length, 0);
    }

    _kChannels = _deriveStoreKey('nimna/app/store/v1/channels');
    _kMediaIndex = _deriveStoreKey('nimna/app/store/v1/media-index');
    _kMeta = _deriveStoreKey('nimna/app/store/v1/meta');
    notifyListeners();
    return generated;
  }

  /// Zeroizes every key and seals the perimeter.
  void seal() {
    if (sealed) {
      return;
    }
    _masterKey?.dispose();
    _kChannels?.dispose();
    _kMediaIndex?.dispose();
    _kMeta?.dispose();
    _masterKey = null;
    _kChannels = null;
    _kMediaIndex = null;
    _kMeta = null;
    notifyListeners();
  }

  /// Panic-wipe step 1: destroys the keystore entry. In-memory keys are
  /// zeroized by the [seal] that must follow (StorageService orders this).
  Future<void> destroyMasterKey() => _keyStore.delete();

  /// `k_channels` — base key for channel records.
  SecureKey get channelsKey => _kChannels ?? (throw StorageSealedError());

  /// `k_media_ix` — base key for media-index records.
  SecureKey get mediaIndexKey => _kMediaIndex ?? (throw StorageSealedError());

  /// `k_meta` — base key for encrypted meta values.
  SecureKey get metaKey => _kMeta ?? (throw StorageSealedError());

  /// Derives a fresh copy of `k_diag` for [Diag] to own and dispose.
  SecureKey takeDiagKey() {
    if (sealed) {
      throw StorageSealedError();
    }
    return _deriveStoreKey('nimna/app/store/v1/diag');
  }

  SecureKey _deriveStoreKey(String label) {
    final mk = _masterKey;
    if (mk == null) {
      throw StorageSealedError();
    }
    return mk.runUnlockedSync((mkBytes) {
      final okm = hkdfSha256(
        ikm: mkBytes,
        info: ascii.encode(label),
        length: AtRestAead.keyBytes,
      );
      final key = SecureKey.fromList(_sodium, okm);
      okm.fillRange(0, okm.length, 0);
      return key;
    });
  }
}
