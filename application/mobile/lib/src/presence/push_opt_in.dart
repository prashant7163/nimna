/// Per-channel push opt-in (spec §3.2.1) — the F7 toggle's model half.
///
/// Push is per-line, opt-IN, DEFAULT OFF. A push-off channel is pure
/// burner-line mode: NOTHING about it ever touches Apple or Google (string
/// 18), and its KNOCK payload is empty. When on, the peer's stored
/// device-token rides INSIDE the knock so the relay can make a single
/// content-free APNs/FCM call and immediately forget the address (§3.2) —
/// nothing this layer controls.
///
/// SCOPE (S12 ⟂ S15). S12 owns the opt-in flag persistence and building the
/// token-into-KNOCK payload from the STORED peer token. Acquiring THIS
/// device's own token from the platform push SDK is S15's — no push SDK is
/// imported here (a push-off channel proves it: zero third-party touch).
///
/// Pure Dart, locale-independent, no I/O beyond the encrypted channel record.
library;

import 'dart:typed_data';

import '../domain/channel_repository.dart';

/// The §5.7 present-form marker byte (`0x01 ‖ platform ‖ token_len ‖ token`).
/// `peerDeviceToken` persists that whole form (S12 CODE decision,
/// 2026-07-07) so the KNOCK payload and the token-refresh CONTROL body derive
/// from one stored shape.
const int _tokenPresentByte = 0x01;

class PushOptIn {
  PushOptIn(this._channels);

  final ChannelRepository _channels;

  /// Whether this channel opted into push (DEFAULT OFF).
  bool isEnabled(Uint8List channelId) =>
      _channels.byId(channelId)?.pushOptIn ?? false;

  /// Flips the per-channel opt-in and persists it inside the channel record
  /// ciphertext (no new store). Idempotent.
  Future<void> setEnabled(Uint8List channelId, {required bool enabled}) async {
    final record = _channels.byId(channelId);
    if (record == null || record.pushOptIn == enabled) {
      return;
    }
    await _channels.update(record.copyWith(pushOptIn: enabled));
  }

  /// The §5.4 KNOCK payload (`platform(1) ‖ token_len(2) ‖ token`) for this
  /// channel, or EMPTY when push is off / no peer token exists (pure
  /// burner-line, zero third-party touch). Derived from the stored present-form
  /// `token_payload` by dropping its leading presence byte.
  Uint8List knockPayloadFor(Uint8List channelId) {
    final record = _channels.byId(channelId);
    if (record == null || !record.pushOptIn) {
      return Uint8List(0);
    }
    final stored = record.peerDeviceToken;
    // Only a present-form token yields a payload; absent/empty → burner-line.
    if (stored == null || stored.length < 4 || stored[0] != _tokenPresentByte) {
      return Uint8List(0);
    }
    return Uint8List.fromList(Uint8List.sublistView(stored, 1));
  }
}
