import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../pairing/joiner/join_controller.dart';
import '../../../../pairing/joiner/join_entry/upload_source.dart';
import '../../../../pairing/joiner/joiner_service.dart';
import '../../../../protocol/pairing_code.dart';
import '../../../theme/nimna_tokens.dart';
import '../../../widgets/nimna_back_button.dart';
import 'code_field.dart';
import 'join_scan_screen.dart';

/// The F3 joiner flow host: one route whose surface follows the controller's
/// phase (entry → handshake → safety phrase → name → done; mismatch on a
/// decline). Joining is ALWAYS free — this flow never passes through the
/// paywall (S17). Owns the controller lifecycle.
class JoinLineFlow extends StatefulWidget {
  const JoinLineFlow({required this.joiner, super.key});

  final JoinerService joiner;

  @override
  State<JoinLineFlow> createState() => _JoinLineFlowState();
}

class _JoinLineFlowState extends State<JoinLineFlow> {
  late final JoinController _controller = widget.joiner.newController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPhase);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPhase);
    _controller.dispose();
    super.dispose();
  }

  void _onPhase() {
    if (_controller.phase == JoinPhase.done && mounted) {
      // Persisted — return to the channel list (F5 chat lands in a later
      // session; the line now shows in F4).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_controller.phase) {
          JoinPhase.entry => _JoinEntryScreen(controller: _controller),
          JoinPhase.joining => const _JoinHandshakeScreen(),
          JoinPhase.verify => _JoinVerifyScreen(controller: _controller),
          JoinPhase.naming => _JoinNameScreen(controller: _controller),
          JoinPhase.done => const SizedBox.shrink(),
          JoinPhase.mismatch => _JoinMismatchScreen(controller: _controller),
        },
      ),
    );
  }
}

// ---- F3.1 / F3.6 / F3.7 / F3.8 — enter a code ------------------------

class _JoinEntryScreen extends StatefulWidget {
  const _JoinEntryScreen({required this.controller});

  final JoinController controller;

  @override
  State<_JoinEntryScreen> createState() => _JoinEntryScreenState();
}

class _JoinEntryScreenState extends State<_JoinEntryScreen> {
  final TextEditingController _field = TextEditingController();
  int _shake = 0;
  JoinEntryError _lastError = JoinEntryError.none;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerError);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerError);
    _field.dispose();
    super.dispose();
  }

  void _onControllerError() {
    // The one permitted shake fires on wrong-code only (never self-join).
    if (widget.controller.entryError == JoinEntryError.noMatch &&
        _lastError != JoinEntryError.noMatch) {
      setState(() => _shake++);
    }
    _lastError = widget.controller.entryError;
  }

  void _setField(String canonical) {
    _field.text = canonical;
    setState(() {});
  }

  Future<void> _onChanged(String canonical) async {
    if (canonical.length == pairingCodeLength) {
      await widget.controller.checkSelfJoin(
        PairingCode.canonicalize(canonical)!,
      );
    } else {
      widget.controller.clearInputState();
    }
  }

  Future<void> _submit(PairingCode code) async {
    final own = await widget.controller.checkSelfJoin(code);
    if (own) {
      _setField(code.canonical); // F3.8 shows the code, Join stays disabled.
      return;
    }
    await widget.controller.join(code);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final code = PairingCode.fromScannedPayload(data?.text ?? '');
    if (code != null) {
      _setField(code.canonical);
      await _onChanged(code.canonical);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<PairingCode>(
      MaterialPageRoute(builder: (_) => const JoinScanScreen()),
    );
    if (code != null && mounted) {
      await _submit(code); // scan/upload normalize + auto-advance (F3.2).
    }
  }

  Future<void> _upload() async {
    final result = await pickAndDecodeQr();
    if (!mounted) {
      return;
    }
    switch (result.outcome) {
      case UploadOutcome.decoded:
        await _submit(result.code!);
      case UploadOutcome.noCode:
        widget.controller.reportEntryError(JoinEntryError.noQrInFile);
      case UploadOutcome.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final controller = widget.controller;

    final blocked = controller.selfJoinBlocked;
    final err = controller.entryError;
    final complete = _field.text.length == pairingCodeLength;

    final (String? message, FieldTone tone) = switch (true) {
      _ when blocked => (l10n.pairing_selfJoinOwnCode, FieldTone.warning),
      _ when err == JoinEntryError.noMatch => (
        l10n.pairing_noMatchError,
        FieldTone.error,
      ),
      _ when err == JoinEntryError.spent => (
        l10n.pairing_joinSpentBody,
        FieldTone.error,
      ),
      _ when err == JoinEntryError.offline => (
        l10n.pairing_joinOffline,
        FieldTone.error,
      ),
      _ when err == JoinEntryError.noQrInFile => (
        l10n.pairing_joinNoQrInFile,
        FieldTone.error,
      ),
      _ when err == JoinEntryError.cameraDenied => (
        l10n.pairing_joinCameraDenied,
        FieldTone.error,
      ),
      _ => (null, FieldTone.normal),
    };

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
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          const SizedBox(height: NimnaSpacing.base * 4),
          Text(l10n.pairing_joinTitle, style: text.titleLarge),
          const SizedBox(height: NimnaSpacing.base * 3),
          Text(
            l10n.pairing_joinIntro,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
          CodeField(
            controller: _field,
            tone: tone,
            shakeTrigger: _shake,
            onChanged: (c) => unawaited(_onChanged(c)),
          ),
          const SizedBox(height: NimnaSpacing.base * 3),
          if (message != null)
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: tone == FieldTone.warning
                    ? tokens.warning
                    : tokens.danger,
              ),
            ),
          const SizedBox(height: NimnaSpacing.base * 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => unawaited(_paste()),
                child: Text(l10n.pairing_joinPaste),
              ),
              TextButton(
                onPressed: () => unawaited(_scan()),
                child: Text(l10n.pairing_joinScan),
              ),
              TextButton(
                onPressed: () => unawaited(_upload()),
                child: Text(l10n.pairing_joinUpload),
              ),
            ],
          ),
          const Spacer(),
          FilledButton(
            onPressed: (complete && !blocked)
                ? () =>
                      unawaited(_submit(PairingCode.canonicalize(_field.text)!))
                : null,
            child: Text(l10n.pairing_joinAction),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}

// ---- F3.3 — handshake ------------------------------------------------

class _JoinHandshakeScreen extends StatelessWidget {
  const _JoinHandshakeScreen();

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: NimnaSpacing.base * 24),
          Text(l10n.pairing_joinFoundThem, style: text.headlineSmall),
          const SizedBox(height: NimnaSpacing.base * 4),
          Text(
            l10n.pairing_joinSettingUp,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const Spacer(),
          Text(
            l10n.pairing_joinCodeSpentNote,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}

// ---- F3.4 — safety phrase (closing ritual) ---------------------------

class _JoinVerifyScreen extends StatelessWidget {
  const _JoinVerifyScreen({required this.controller});

  final JoinController controller;

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
            // Protocol output, one global wordlist, identical in every
            // locale (spec §3.1.4) — never localized copy.
            phrase.join(' · '),
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(
              fontFamily: 'Spline Sans Mono',
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

// ---- F3.5 — name the line --------------------------------------------

class _JoinNameScreen extends StatefulWidget {
  const _JoinNameScreen({required this.controller});

  final JoinController controller;

  @override
  State<_JoinNameScreen> createState() => _JoinNameScreenState();
}

class _JoinNameScreenState extends State<_JoinNameScreen> {
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

// ---- F2.9 / F3.4-decline — mismatch (local-only discard) -------------

class _JoinMismatchScreen extends StatelessWidget {
  const _JoinMismatchScreen({required this.controller});

  final JoinController controller;

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
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.pairing_goBack),
          ),
          const SizedBox(height: NimnaSpacing.base * 6),
        ],
      ),
    );
  }
}
