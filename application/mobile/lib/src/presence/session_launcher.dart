/// THE factory that builds a live [SessionController] from a stored channel
/// (spec §3.3). It is the app's single entry point for constructing the
/// connection lane — the chat surface and the reconnect_coordinator both go
/// through here, so the wiring (sodium/aead/connector/messages/statics/role,
/// the receive-side token-refresh sink, and the §5.4 KNOCK push payload) lives
/// in exactly one place.
///
/// Reconnect is a FRESH controller every time (keys die per session, §3.3.1):
/// [build] takes a `seedPendingReactions` so an offline reaction survives the
/// rebuild (decision 3). Pure Dart, locale-independent.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/at_rest_aead.dart';
import '../diag/diag.dart';
import '../domain/channel_repository.dart';
import '../domain/message_repository.dart';
import '../noise/dh.dart';
import '../session/connection/session_controller.dart';
import '../session/model/chat_event.dart';
import '../transport/relay_socket.dart';
import 'peer_token_store.dart';
import 'push_opt_in.dart';

class SessionLauncher {
  SessionLauncher({
    required SodiumSumo sodium,
    required AtRestAead aead,
    required RelayConnector connector,
    required ChannelRepository channels,
    required MessageRepository messages,
    required Diag diag,
    required PushOptIn pushOptIn,
    required PeerTokenStore peerTokenStore,
    DateTime Function()? clock,
  }) : _sodium = sodium,
       _aead = aead,
       _connector = connector,
       _channels = channels,
       _messages = messages,
       _diag = diag,
       _pushOptIn = pushOptIn,
       _peerTokenStore = peerTokenStore,
       _clock = clock;

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final RelayConnector _connector;
  final ChannelRepository _channels;
  final MessageRepository _messages;
  final Diag _diag;
  final PushOptIn _pushOptIn;
  final PeerTokenStore _peerTokenStore;
  final DateTime Function()? _clock;

  // The pass-through fields above are assigned in the initializer list rather
  // than as `this._x` formals so the public constructor keeps meaningful,
  // typed parameter names (sodium/aead/…) for call sites and docs.
  // ignore_for_file: prefer_initializing_formals

  /// Constructs a controller for [channelId] in [role]. The static keypair is
  /// the channel's own (public from the record; secret from the repo's held
  /// SecureKey — NEVER disposed by the controller). [seedPendingReactions]
  /// carries an offline reaction across a reconnect rebuild.
  SessionController build(
    Uint8List channelId, {
    required SessionRole role,
    List<PendingReaction> seedPendingReactions = const [],
  }) {
    final record = _channels.byId(channelId);
    if (record == null) {
      throw ArgumentError('unknown channel');
    }
    final ownStatic = NoiseKeyPair(
      publicKey: record.ownStaticPublic,
      secretKey: _channels.ownStaticPrivateFor(channelId),
    );
    return SessionController(
      sodium: _sodium,
      aead: _aead,
      connector: _connector,
      messages: _messages,
      channelId: channelId,
      ownStatic: ownStatic,
      peerStaticPublic: record.peerStaticPublic,
      crid: record.crid,
      role: role,
      diag: _diag,
      clock: _clock,
      onPeerTokenRefresh: (token) =>
          unawaited(_peerTokenStore.onPeerTokenRefresh(channelId, token)),
      seedPendingReactions: seedPendingReactions,
    );
  }

  /// The §5.4 KNOCK payload for [channelId] (empty when push is off / no peer
  /// token). Passed to [SessionController.start] by the knocker.
  Uint8List knockPayloadFor(Uint8List channelId) =>
      _pushOptIn.knockPayloadFor(channelId);
}
