import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../pairing/initiator/initiator_controller.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nimna_back_button.dart';

/// F2.1 · Generate code — one calm decision (the TTL, default 24 h) and
/// one action. Nothing exists until Create succeeds against a live relay
/// registration (no phantom codes); the offline edge renders the
/// wireframe's line and stays here.
class CreateCodeSetupScreen extends StatelessWidget {
  const CreateCodeSetupScreen({required this.controller, super.key});

  final CreateLineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final generating = controller.phase == CreateLinePhase.generating;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NimnaSpacing.screenMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: NimnaSpacing.listRowSettings,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NimnaBackButton(
                        onPressed: generating
                            ? null
                            : () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  const SizedBox(height: NimnaSpacing.base * 6),
                  Text(l10n.pairing_createTitle, style: text.titleLarge),
                  const SizedBox(height: NimnaSpacing.base * 3),
                  Text(
                    l10n.pairing_createIntro,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: NimnaSpacing.base * 3),
                  _TtlRow(controller: controller, enabled: !generating),
                  const Spacer(),
                  if (controller.offline) ...[
                    Text(
                      l10n.pairing_offlineError,
                      style: text.bodySmall?.copyWith(color: tokens.danger),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: NimnaSpacing.base * 3),
                  ],
                  FilledButton(
                    onPressed: generating
                        ? null
                        : () => unawaited(controller.createCode()),
                    child: Text(l10n.pairing_createTitle),
                  ),
                  const SizedBox(height: NimnaSpacing.base * 6),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The F2.1 setting row: "Code works for" + the safety hint, value +
/// disclosure on the trailing edge; tap opens the preset sheet
/// (1 h · 8 h · 24 h — S8 intake §5).
class _TtlRow extends StatelessWidget {
  const _TtlRow({required this.controller, required this.enabled});

  final CreateLineController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: enabled ? () => _pickTtl(context) : null,
      borderRadius: BorderRadius.circular(NimnaRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NimnaSpacing.base * 3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.pairing_ttlLabel, style: text.labelLarge),
                  const SizedBox(height: NimnaSpacing.base),
                  Text(
                    l10n.pairing_ttlHint,
                    style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NimnaSpacing.base * 3),
            Text(
              l10n.pairing_ttlHours(controller.ttl.inHours),
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTtl(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: tokens.surface2,
      barrierColor: tokens.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NimnaRadius.sheet),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrabHandle(),
            for (final preset in ttlPresets)
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop(preset),
                child: Container(
                  height: NimnaSpacing.listRowSettings,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NimnaSpacing.screenMargin,
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.pairing_ttlHours(preset.inHours),
                    style: Theme.of(sheetContext).textTheme.bodyLarge,
                  ),
                ),
              ),
            const SizedBox(height: NimnaSpacing.base * 2),
          ],
        ),
      ),
    );
    if (picked != null) {
      controller.ttl = picked;
    }
  }
}

/// The sheet grab handle (components.md: 32×4, `hairline`).
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NimnaSpacing.base * 2),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: tokens.hairline,
            borderRadius: BorderRadius.circular(NimnaRadius.full),
          ),
        ),
      ),
    );
  }
}
