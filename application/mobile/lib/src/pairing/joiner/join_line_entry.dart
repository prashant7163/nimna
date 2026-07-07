import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/transitions.dart';
import '../../ui/screens/pairing/join/join_line_flow.dart';

/// THE entry point into the joiner flow (F3). Joining is ALWAYS free and
/// NEVER passes through the paywall (S17 gates creation only, via
/// `create_line_entry.dart` — a separate door). The F4 channel-list "Enter a
/// code" action calls this and nothing else constructs the flow.
Future<void> startJoinLine(BuildContext context) {
  final services = AppScope.of(context);
  return Navigator.of(context).push(
    NimnaPageRoute<void>(builder: (_) => JoinLineFlow(joiner: services.joiner)),
  );
}
