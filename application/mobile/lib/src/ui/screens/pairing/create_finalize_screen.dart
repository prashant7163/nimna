import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../pairing/initiator/initiator_controller.dart';
import '../../theme/nimna_tokens.dart';

/// The creator-side finalize screens (F2.6 safety phrase · F2.7 channel ready ·
/// F2.9 mismatch) — the S16 build of the PM's core gap: today the creator
/// completes the handshake but never sees the safety phrase. These mirror the
/// joiner's F3.4/F3.5 screens exactly (same voice-guide copy, same two-button
/// pattern, NO skip — USER 2026-07-04) and reuse the same `pairing_*` ARB keys.
///
/// The safety phrase is protocol output (one global wordlist, identical in
/// every locale — spec §3.1.4), rendered mono, never localized copy. A
/// mismatch is a LOCAL-ONLY silent discard: the copy never implies the peer is
/// told (honesty doctrine).

/// F2.6 — the safety phrase, the closing ritual of pairing (spec §3.1.5).
class CreateVerifyScreen extends StatelessWidget {
  const CreateVerifyScreen({required this.controller, super.key});

  final CreateLineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final phrase = controller.safetyPhrase ?? const [];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.screenMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NimnaSpacing.base * 14),
          Text(
            l10n.pairing_verifyTitle,
            textAlign: TextAlign.center,
            style: text.titleLarge,
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
          Text(
            phrase.join(' · '),
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(
              fontFamily: NimnaText.fontFamilyMono,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
          Text(
            l10n.pairing_verifyBody,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const Spacer(),
          FilledButton(
            onPressed: controller.confirmMatch,
            child: Text(l10n.pairing_verifyMatch),
          ),
          // Spaced below the primary, never adjacent (no skip affordance).
          const SizedBox(height: NimnaSpacing.base * 4),
          TextButton(
            onPressed: () => unawaited(controller.declineMismatch()),
            child: Text(l10n.pairing_verifyMismatch),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}

/// F2.7 — channel ready: name the line (label is local-only), then Done
/// persists and the code is spent.
class CreateNameScreen extends StatefulWidget {
  const CreateNameScreen({required this.controller, super.key});

  final CreateLineController controller;

  @override
  State<CreateNameScreen> createState() => _CreateNameScreenState();
}

class _CreateNameScreenState extends State<CreateNameScreen> {
  final TextEditingController _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.screenMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NimnaSpacing.base * 16),
          Text(l10n.pairing_readyTitle, style: text.headlineSmall),
          const SizedBox(height: NimnaSpacing.base * 6),
          Text(
            l10n.pairing_nameLineLabel,
            style: text.labelLarge?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: NimnaSpacing.base * 2),
          TextField(controller: _label, autofocus: true),
          const SizedBox(height: NimnaSpacing.base * 2),
          Text(
            l10n.pairing_nameLineCaption,
            style: text.bodySmall?.copyWith(color: tokens.textTertiary),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => unawaited(widget.controller.finish(_label.text)),
            child: Text(l10n.pairing_doneAction),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}

/// F2.9 — safety-phrase mismatch (edge). The MITM defense working as designed
/// (spec §3.1.5): the pairing was thrown away LOCALLY, nothing was kept, and
/// the copy never says the peer was notified (there is no wire signal).
class CreateMismatchScreen extends StatelessWidget {
  const CreateMismatchScreen({required this.onMakeNewCode, super.key});

  /// F2.9 "Make a new code" → F2.1 with a fresh keypair and code.
  final VoidCallback onMakeNewCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.screenMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NimnaSpacing.base * 16),
          Text(l10n.pairing_mismatchTitle, style: text.headlineSmall),
          const SizedBox(height: NimnaSpacing.base * 4),
          Text(
            l10n.pairing_mismatchBody,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: NimnaSpacing.base * 3),
          Text(
            l10n.pairing_mismatchShareSafer,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onMakeNewCode,
            child: Text(l10n.pairing_makeNewCode),
          ),
          const SizedBox(height: NimnaSpacing.base * 2),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.pairing_notNow),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}
