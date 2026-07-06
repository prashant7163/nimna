import 'dart:async';

import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/transport/relay_socket.dart';

/// In-memory relay transport fake: records sent frames, lets tests deliver
/// inbound frames and kill the "socket".
class FakeRelayConnection implements RelayConnection {
  final StreamController<OuterFrame> _inbound = StreamController<OuterFrame>();

  /// Frames the client sent, in order.
  final List<OuterFrame> sent = [];

  bool closedByClient = false;

  @override
  Stream<OuterFrame> get frames => _inbound.stream;

  @override
  void send(OuterFrame frame) => sent.add(frame);

  @override
  Future<void> close() async {
    closedByClient = true;
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }

  /// Test side: deliver an inbound frame.
  void deliver(OuterFrame frame) => _inbound.add(frame);

  /// Test side: the connection drops (implicit TEARDOWN).
  Future<void> drop() async {
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }
}

/// Connector fake: counts attempts, can fail the next N attempts.
class FakeRelayConnector implements RelayConnector {
  final List<FakeRelayConnection> connections = [];
  int attempts = 0;

  /// Number of upcoming attempts that throw [RelayUnreachableError].
  int failNextAttempts = 0;

  FakeRelayConnection get latest => connections.last;

  @override
  Future<RelayConnection> connect() async {
    attempts++;
    if (failNextAttempts > 0) {
      failNextAttempts--;
      throw RelayUnreachableError();
    }
    final conn = FakeRelayConnection();
    connections.add(conn);
    return conn;
  }
}
