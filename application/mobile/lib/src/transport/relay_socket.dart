/// Relay WebSocket transport — a thin `dart:io` wrapper (S8 intake §2/§7:
/// stdlib-first, `web_socket_channel` rejected). Transport knows the §5.4
/// framing and NOTHING about frame meaning: it moves [OuterFrame]s and
/// reports connection state. Reconnect *policy* lives in [ReconnectBackoff]
/// (used by callers) — this layer never retries on its own, and nothing
/// here loops: the client behaves like one polite registrant under the §4
/// rendezvous throttling.
///
/// Locale-independent by definition; no Flutter imports.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/outer_frame.dart';

/// Relay endpoint configuration — always injected, never hardcoded at a
/// call site. The compile-time default targets the local dev relay
/// (`application/relay`, `go run ./cmd/relay`, default listen
/// 127.0.0.1:9440); deployments override via `--dart-define`.
class RelayConfig {
  const RelayConfig({this.url = defaultUrl});

  static const String defaultUrl = String.fromEnvironment(
    'NIMNA_RELAY_URL',
    defaultValue: 'ws://127.0.0.1:9440',
  );

  /// `ws://` or `wss://` URL of the relay's WebSocket endpoint.
  final String url;
}

/// Raised when a connection attempt fails (offline, refused, TLS failure).
/// Carries no addresses or reasons by design — nothing here may reach a
/// log or a UI string.
class RelayUnreachableError extends Error {
  @override
  String toString() => 'RelayUnreachableError';
}

/// One live relay connection.
abstract interface class RelayConnection {
  /// Decoded inbound frames (single subscription). Malformed frames are
  /// dropped silently — the relay never explains itself and neither do we.
  /// The stream closes when the connection dies (implicit TEARDOWN).
  Stream<OuterFrame> get frames;

  /// Sends one frame as a binary WebSocket message.
  void send(OuterFrame frame);

  /// Closes the connection. Registrations at the relay die with it.
  Future<void> close();
}

/// Dials relay connections. The production implementation is
/// [WebSocketRelayConnector]; tests substitute an in-memory fake.
abstract interface class RelayConnector {
  /// One connection attempt — no internal retry, ever.
  Future<RelayConnection> connect();
}

/// `dart:io` WebSocket implementation.
class WebSocketRelayConnector implements RelayConnector {
  WebSocketRelayConnector({required this.config, this.connectTimeout});

  final RelayConfig config;

  /// Optional override for tests; production uses [defaultConnectTimeout].
  final Duration? connectTimeout;

  static const Duration defaultConnectTimeout = Duration(seconds: 10);

  @override
  Future<RelayConnection> connect() async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        config.url,
      ).timeout(connectTimeout ?? defaultConnectTimeout);
    } on Exception {
      // Includes TimeoutException, SocketException, WebSocketException,
      // TLS handshake failures — one indistinct outcome by design.
      throw RelayUnreachableError();
    }
    return _WebSocketRelayConnection(socket);
  }
}

class _WebSocketRelayConnection implements RelayConnection {
  _WebSocketRelayConnection(this._socket) {
    _socket.listen(
      (message) {
        if (message is! List<int>) {
          return; // Text frames have no meaning on this protocol; drop.
        }
        final OuterFrame frame;
        try {
          frame = OuterFrame.decode(
            message is Uint8List ? message : Uint8List.fromList(message),
          );
        } on OuterFrameError {
          return; // Malformed inbound frame: drop silently.
        }
        _frames.add(frame);
      },
      onError: (Object _) => _frames.close(),
      onDone: () => _frames.close(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final StreamController<OuterFrame> _frames = StreamController<OuterFrame>();

  @override
  Stream<OuterFrame> get frames => _frames.stream;

  @override
  void send(OuterFrame frame) => _socket.add(frame.encode());

  @override
  Future<void> close() async {
    await _socket.close(WebSocketStatus.normalClosure);
  }
}

/// The no-hammer reconnect policy (S8 intake §2): consecutive failures back
/// off exponentially and never tighten. Callers ask [nextDelay] before each
/// re-attempt and [reset] after a success; there is no automatic loop here
/// or anywhere.
class ReconnectBackoff {
  ReconnectBackoff({
    this.initial = const Duration(seconds: 2),
    this.max = const Duration(seconds: 60),
  });

  final Duration initial;
  final Duration max;

  int _failures = 0;

  /// Delay to wait before the next attempt; doubles per recorded failure,
  /// capped at [max]. First call (no failures yet) returns [initial].
  Duration nextDelay() {
    final shift = _failures > 30 ? 30 : _failures;
    final ms = initial.inMilliseconds << shift;
    _failures++;
    return ms >= max.inMilliseconds ? max : Duration(milliseconds: ms);
  }

  /// Records a successful connection; the schedule starts over.
  void reset() => _failures = 0;
}
