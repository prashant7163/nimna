import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/routes.dart';
import '../../app/transitions.dart';
import '../../../l10n/app_localizations.dart';
import '../../ui/screens/pairing/create_line_flow.dart';
import '../../ui/screens/paywall/paywall_screen.dart';
import '../../ui/widgets/nimna_toast.dart';
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
/// S17 wires the paywall gate INSIDE this function (the single entry point,
/// so no second ungated creation door can appear — single_call_site_test):
/// the entitlement check runs at creation intent, on this device only, once
/// (spec §10). Not entitled (or unresolved → fail-closed) opens F9; the
/// paywall pops a non-dismissed [PaywallResult] only once the subscription
/// is active (purchase or restore), and creation continues. Dismiss stops
/// here — nothing was created. Joining is never gated and never passes
/// through here; [resumeCreateLineIfPending] stays UNGATED (the code already
/// exists).
Future<void> startCreateLine(BuildContext context) async {
  final services = AppScope.of(context);
  final navigator = Navigator.of(context);

  if (!await services.billing.hasActiveCreationEntitlement()) {
    final result = await navigator.pushNamed<PaywallResult>(Routes.paywall);
    if (result == null || result == PaywallResult.dismissed) {
      return; // F9.2 ✕ / declined — no creation, nothing follows the user.
    }
    if (context.mounted) {
      // F9.4 (purchase) / F9.5 (restore): one calm toast, then straight on
      // to creating — no celebration screen.
      showNimnaToast(
        context,
        result == PaywallResult.restored
            ? AppLocalizations.of(context)!.billing_restoreSuccessToast
            : AppLocalizations.of(context)!.billing_subscriptionStartedToast,
      );
    }
  }

  await navigator.push(
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
