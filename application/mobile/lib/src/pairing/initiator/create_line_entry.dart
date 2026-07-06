import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/transitions.dart';
import '../../ui/screens/pairing/create_line_flow.dart';
import 'pending_pairing.dart';

/// THE single entry point into code creation (S8 intake §4 — the G2
/// opening condition, binding design).
///
/// [startCreateLine] is the ONLY exported way to begin creating a Nimna
/// code; the F4 channel-list "+" action calls it and nothing else in the
/// tree constructs the initiator flow or its controller directly. A
/// source-scan test (test/pairing/single_call_site_test.dart) pins exactly
/// one call site outside this file.
///
/// S17 wires the paywall gate by editing exactly this function: the
/// entitlement check goes in front of the route push (F9 intercept on
/// failure). S8 ships creation ungated per the plan. Joining is never
/// gated and never passes through here.
Future<void> startCreateLine(BuildContext context) {
  final services = AppScope.of(context);
  return Navigator.of(context).push(
    NimnaPageRoute<void>(
      builder: (_) => CreateLineFlow(pairing: services.pairing),
    ),
  );
}

/// Relaunch path (F2.4/F2.8 edges): if a pending pairing survived from a
/// previous run (read once at boot by the composition root), reopen the
/// flow on it — the wait resumes after re-registration, or F2.8 if the
/// code lapsed while away. NOT a creation entry: the code already exists,
/// so no entitlement gate applies (S17).
Future<void> resumeCreateLineIfPending(BuildContext context) {
  final services = AppScope.of(context);
  final PendingPairing? entry = services.pairing.takeInitialResume();
  if (entry == null) {
    return Future<void>.value();
  }
  return Navigator.of(context).push(
    NimnaPageRoute<void>(
      builder: (_) => CreateLineFlow(pairing: services.pairing, resume: entry),
    ),
  );
}
