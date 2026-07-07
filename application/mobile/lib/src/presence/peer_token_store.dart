/// Receive-side device-token refresh (spec §3.2.1 / §5.5 / §5.7).
///
/// The peer may rotate — or unilaterally REVOKE — its push device-token
/// inside a live session via a CONTROL token-refresh (§5.5). This persists
/// the decoded [TokenPayload] to the channel record: present → store the
/// §5.7 present-form bytes (platform-preserving, S12 CODE decision);
/// absent → delete (a revoke that silences that line's push permanently,
/// §4). The token lives ONLY here, encrypted, never sent anywhere but inside
/// E2E payloads.
///
/// This is also the home of the [SendTokenRefresh] seam CONTRACT that S15
/// fulfils with THIS device's real acquired token — S12 supplies only the
/// wire path ([SessionController.sendTokenRefresh]); no push SDK here.
///
/// Pure Dart, locale-independent.
library;

import 'dart:typed_data';

import '../domain/channel_repository.dart';
import '../protocol/token_payload.dart';

/// The S15 seam: given THIS device's own [TokenPayload] (acquired from
/// APNs/FCM at session start), put it on the wire. S12 wires this to
/// [SessionController.sendTokenRefresh]; S15 acquires the token and calls it.
typedef SendTokenRefresh = void Function(TokenPayload ownToken);

class PeerTokenStore {
  PeerTokenStore(this._channels);

  final ChannelRepository _channels;

  /// Persists a peer token-refresh to the channel record. Present → store the
  /// present-form bytes; absent → clear (revoke). No-op for an unknown channel.
  Future<void> onPeerTokenRefresh(
    Uint8List channelId,
    TokenPayload token,
  ) async {
    final record = _channels.byId(channelId);
    if (record == null) {
      return;
    }
    // isPresent → the encoded present form (0x01‖platform‖len‖token); absent →
    // null clears the stored token. copyWith's () sentinel distinguishes
    // "clear" from "leave untouched".
    final Uint8List? next = token.isPresent ? token.encode() : null;
    await _channels.update(record.copyWith(peerDeviceToken: () => next));
  }
}
