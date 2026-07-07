import 'dart:typed_data';

import '../lock/lock_config_store.dart';
import '../lock/lock_controller.dart';
import '../storage/storage_service.dart';

/// Thin orchestration over the S7 key-destruction-first wipe primitives
/// (SESSION-13 intake §6). ADDS ZERO NEW DESTRUCTION LOGIC — the security
/// boundary lives entirely in `StorageService`/`KeyService`:
///
/// ```
/// fullWipe    = StorageService.fullWipe()   [keystore MK deleted FIRST]
///             + LockConfigStore.delete()    [fresh-install
///                                            indistinguishability]
///             + StorageService.open()       [fresh store, new MK]
/// wipeChannel = pre-wipe hook (session hang-up seam)
///             + StorageService.wipeChannel()
/// ```
class WipeService {
  WipeService({
    required this._storage,
    required this._lockConfigStore,
    required this._lockController,
  });

  final StorageService _storage;
  final LockConfigStore _lockConfigStore;
  final LockController _lockController;

  /// Seam for the (future) session layer to hang up before a channel's
  /// keys die — S13 ships the seam, never calls transport itself.
  Future<void> Function(Uint8List channelId)? preChannelWipeHook;

  /// Full panic wipe (F8.3, hold 2.5 s completes). After this returns the
  /// store is a fresh install: new MK, empty list, App lock off.
  Future<void> fullWipe() async {
    await _storage.fullWipe();
    await _lockConfigStore.delete();
    await _storage.open();
    await _lockController.reload();
  }

  /// Per-channel wipe (F7.2/F7.3 sheet, hold 1.5 s completes). The F7
  /// host screen belongs to a later session; this is the reusable seam.
  Future<void> wipeChannel(Uint8List channelId) async {
    final hook = preChannelWipeHook;
    if (hook != null) {
      await hook(channelId);
    }
    await _storage.wipeChannel(channelId);
  }
}
