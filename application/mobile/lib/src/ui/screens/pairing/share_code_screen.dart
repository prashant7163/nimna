import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../pairing/initiator/initiator_controller.dart';
import '../../../pairing/initiator/share.dart' as code_share;
import '../../../protocol/pairing_code.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/idle_line.dart';
import '../../widgets/nimna_back_button.dart';
import '../../widgets/nimna_toast.dart';
import '../../widgets/qr_card.dart';
import 'create_code_setup_screen.dart' show SheetGrabHandle;

/// F2.2/F2.4 — ONE screen (wireframe annotation): the text code and its QR
/// simultaneously (spec §3.1.1), Copy/Share acting on either form, and the
/// patient waiting state beneath — dotted idle line, "nothing yet". The
/// bridged hold (S8's terminal success) keeps this surface unchanged: the
/// S9 engine attaches at the F2.4→F2.5 boundary.
///
/// Back → confirm-discard ("Stop waiting? The code stops working.");
/// Cancel this code → discards code and keypair → F4.
class ShareCodeScreen extends StatelessWidget {
  const ShareCodeScreen({required this.controller, super.key});

  final CreateLineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmStopWaiting(context));
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final code = controller.code;
              if (code == null) {
                return const SizedBox.shrink(); // Terminal swap in flight.
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: NimnaSpacing.listRowSettings,
                      child: Row(
                        children: [
                          NimnaBackButton(
                            onPressed: () =>
                                unawaited(_confirmStopWaiting(context)),
                          ),
                          const SizedBox(width: NimnaSpacing.base * 2),
                          Expanded(
                            child: Text(
                              l10n.pairing_createTitle,
                              style: text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: NimnaSpacing.base * 5),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                child: QrCard(code: code),
                              ),
                            ),
                            const SizedBox(height: NimnaSpacing.base * 6),
                            Text(
                              code.display,
                              style: NimnaText.codeDisplay.copyWith(
                                color: tokens.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: NimnaSpacing.base * 3),
                            Text(
                              l10n.pairing_shareBriefing,
                              style: text.bodySmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              l10n.pairing_eitherFormPairs,
                              style: text.bodySmall?.copyWith(
                                color: tokens.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: NimnaSpacing.base * 6),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _copy(context, code),
                                    child: Text(l10n.pairing_copyAction),
                                  ),
                                ),
                                const SizedBox(width: NimnaSpacing.base * 3),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => unawaited(
                                      _openShareSheet(context, code),
                                    ),
                                    child: Text(l10n.pairing_shareAction),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: NimnaSpacing.base * 6),
                          ],
                        ),
                      ),
                    ),
                    const IdleLine(),
                    const SizedBox(height: NimnaSpacing.base * 2),
                    Text(
                      l10n.pairing_waitingForJoin,
                      style: text.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: NimnaSpacing.base),
                    Text(
                      l10n.pairing_waitLifetime(controller.ttl.inHours),
                      style: text.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: NimnaSpacing.base * 2),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.textSecondary,
                      ),
                      onPressed: () => unawaited(controller.cancel()),
                      child: Text(l10n.pairing_cancelCode),
                    ),
                    const SizedBox(height: NimnaSpacing.base * 2),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context, PairingCode code) {
    unawaited(Clipboard.setData(ClipboardData(text: code.display)));
    showNimnaToast(
      context,
      AppLocalizations.of(context)!.pairing_codeCopiedToast,
    );
  }

  /// Back-confirm (F2.2 exit annotation). Actions from the designed
  /// vocabulary: ghost "Not now" keeps waiting; "Cancel this code"
  /// confirms the discard.
  Future<void> _confirmStopWaiting(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: tokens.scrim,
      builder: (dialogContext) => Dialog(
        backgroundColor: tokens.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NimnaRadius.large),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NimnaSpacing.base * 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pairing_stopWaitingConfirm,
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.pairing_notNow),
                  ),
                  const SizedBox(width: NimnaSpacing.base * 2),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l10n.pairing_cancelCode),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed ?? false) {
      await controller.cancel();
    }
  }

  /// F2.3 — the in-app share sheet: the §3.1 one-liner (string 13,
  /// verbatim) as the header caption; either form travels alone.
  Future<void> _openShareSheet(BuildContext context, PairingCode code) async {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface2,
      barrierColor: tokens.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NimnaRadius.sheet),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetGrabHandle(),
              Text(
                l10n.pairing_shareBriefing,
                style: Theme.of(
                  sheetContext,
                ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NimnaSpacing.base * 4),
              OutlinedButton(
                onPressed: () => unawaited(code_share.shareCodeAsText(code)),
                child: Text(l10n.pairing_shareAsText),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              OutlinedButton(
                onPressed: () => unawaited(code_share.shareCodeAsQrImage(code)),
                child: Text(l10n.pairing_shareQrAsImage),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _copy(context, code);
                },
                child: Text(l10n.pairing_copyCode),
              ),
              const SizedBox(height: NimnaSpacing.base * 4),
            ],
          ),
        ),
      ),
    );
  }
}
