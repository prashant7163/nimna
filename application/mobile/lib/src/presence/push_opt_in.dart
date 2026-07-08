/// Per-channel push opt-in (spec §3.2.1) — the F7 toggle's model half.
///
/// Push is per-line, opt-IN, DEFAULT OFF, and **per-side** (spec §3.2.1: each
/// side carries the "absent" form if ITS push is off; voice string 18 frames
/// it as "wake THIS phone"). The two directions are independent:
///  - **My own opt-in** governs only whether I share MY OWN token so the PEER
///    can wake me — carried by the token-refresh CONTROL (S15) / the pairing
///    absent path, NOT by this KNOCK payload.
///  - **The outgoing KNOCK** carries the PEER's stored token so the relay can
///    wake the PEER. That is gated SOLELY on whether I hold a present-form
///    peer token — which already encodes the peer's opt-in (the peer shares
///    its token only on opt-in and revokes on opt-out). A push-off peer means
///    no stored token means an empty knock, a burner-line wake for that side.
/// Coupling the KNOCK to MY own opt-in (as an earlier draft did) silences a
/// peer who explicitly asked to be woken — the CODE fix here decouples them.
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
  /// channel — the PEER's token, so the relay can wake the PEER — or EMPTY when
  /// no present-form peer token is stored (the peer's push is off / was
  /// revoked ⇒ a burner-line wake for that side). Derived from the stored
  /// present-form `token_payload` by dropping its leading presence byte.
  ///
  /// Gated SOLELY on the stored peer token, NOT on the knocker's OWN opt-in
  /// (`record.pushOptIn`): push is per-side (spec §3.2.1). My own opt-in
  /// governs a DIFFERENT direction — sharing MY token so the peer can wake me,
  /// carried by the token-refresh CONTROL. Coupling them would drop the token
  /// of a peer who explicitly opted to be woken (CODE, 2026-07-08).
  Uint8List knockPayloadFor(Uint8List channelId) {
    final record = _channels.byId(channelId);
    if (record == null) {
      return Uint8List(0);
    }
    final stored = record.peerDeviceToken;
    // Only a present-form token yields a payload; absent/revoked → empty.
    if (stored == null || stored.length < 4 || stored[0] != _tokenPresentByte) {
      return Uint8List(0);
    }
    return Uint8List.fromList(Uint8List.sublistView(stored, 1));
  }
}
