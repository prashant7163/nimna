/// The chat composer (S11 lane seed) — text input with the 5000-char
/// compose-time soft cap, the disappearing-timer preset control (with voice
/// string 7 shown VERBATIM at the picker), and the reply-compose strip.
/// BINDING to `designs/system/components.md` (message-actions / quoted-reply
/// reply-compose-strip) and wireframe F5.11.
///
/// Holds no protocol state — it reports composed text (+ chosen expiry)
/// upward and pings [onTyping] as the user writes (typing is ON BY DEFAULT,
/// USER 2026-07-07; the send-side gate lives in the connection layer). Every
/// string is l10n; the timer presets are locale-aware plurals. Left/right is
/// never hardcoded.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/message_record.dart' show MessageType;
import '../../ui/theme/nimna_tokens.dart';
import '../../ui/widgets/glyphs.dart';
import '../model/message_view.dart';

/// The USER-locked disappearing presets (wireframe F5.11): Off / 1 min /
/// 15 min / 1 hr / 24 hr after read. Value is `expiry_s` (null = Off).
const List<int?> expiryPresetSeconds = [null, 60, 900, 3600, 86400];

/// Resolves a preset's locale-aware label (Off / N min / N hr).
String expiryPresetLabel(AppLocalizations l10n, int? seconds) {
  if (seconds == null) {
    return l10n.chat_timerOff;
  }
  if (seconds < 3600) {
    return l10n.chat_timerMinutes(seconds ~/ 60);
  }
  return l10n.chat_timerHours(seconds ~/ 3600);
}

class Composer extends StatefulWidget {
  const Composer({
    required this.onSend,
    required this.onTyping,
    this.replyingTo,
    this.onCancelReply,
    super.key,
  });

  /// Emits the composed text and the currently-selected expiry (null = Off).
  final void Function(String text, int? expirySeconds) onSend;

  /// Pinged as the user types (a CONTROL 0x01 typing heartbeat, spec §5.5).
  final VoidCallback onTyping;

  /// The message being replied to (drives the reply strip), or null.
  final MessageView? replyingTo;
  final VoidCallback? onCancelReply;

  static const int softCharCap = 5000;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  int? _expirySeconds;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onSend(text, _expirySeconds);
    _controller.clear();
  }

  Future<void> _openTimerPicker() async {
    final chosen = await showExpiryPicker(context, _expirySeconds);
    if (chosen.changed) {
      setState(() => _expirySeconds = chosen.seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyingTo != null)
          _replyStrip(context, tokens, l10n, widget.replyingTo!),
        Container(
          color: tokens.surface0,
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.base * 2,
            vertical: NimnaSpacing.base * 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _timerButton(tokens, l10n),
              const SizedBox(width: NimnaSpacing.base * 2),
              Expanded(
                child: Semantics(
                  label: l10n.chat_composerA11y,
                  textField: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: tokens.surface1,
                      borderRadius: BorderRadius.circular(NimnaRadius.medium),
                      border: Border.all(color: tokens.hairline),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: NimnaSpacing.base * 3,
                      vertical: NimnaSpacing.base * 2,
                    ),
                    child: EditableText(
                      controller: _controller,
                      focusNode: _focus,
                      maxLines: 6,
                      minLines: 1,
                      style: NimnaText.bodyLarge.copyWith(
                        color: tokens.textPrimary,
                      ),
                      cursorColor: tokens.accent,
                      backgroundCursorColor: tokens.hairline,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(Composer.softCharCap),
                      ],
                      onChanged: (_) => widget.onTyping(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: NimnaSpacing.base * 2),
              _sendButton(tokens, l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timerButton(NimnaTokens tokens, AppLocalizations l10n) {
    final isOff = _expirySeconds == null;
    return Semantics(
      button: true,
      label: l10n.chat_timerButtonA11y,
      child: GestureDetector(
        onTap: _openTimerPicker,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: NimnaSpacing.touchTargetMin,
          height: NimnaSpacing.touchTargetMin,
          child: Center(
            child: isOff
                ? TimerGlyph(color: tokens.textSecondary)
                : Text(
                    expiryPresetLabel(l10n, _expirySeconds),
                    style: NimnaText.caption.copyWith(color: tokens.accent),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sendButton(NimnaTokens tokens, AppLocalizations l10n) {
    return Semantics(
      button: true,
      label: l10n.chat_sendA11y,
      child: GestureDetector(
        onTap: _send,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: NimnaSpacing.touchTargetMin,
          height: NimnaSpacing.touchTargetMin,
          decoration: BoxDecoration(
            color: tokens.accent,
            shape: BoxShape.circle,
          ),
          child: Center(child: SendGlyph(color: tokens.onAccent)),
        ),
      ),
    );
  }

  Widget _replyStrip(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
    MessageView target,
  ) {
    final String quote;
    if (target.type == MessageType.text) {
      quote = target.text ?? '';
    } else {
      quote = l10n.chat_replyPreviewDocument; // TODO(S11): Photo vs Document.
    }
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.base * 4,
        vertical: NimnaSpacing.base * 2 + 2,
      ),
      child: Row(
        children: [
          Container(width: 2, height: 34, color: tokens.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.chat_replyingToLabel.toUpperCase(),
                  style: NimnaText.micro.copyWith(color: tokens.textTertiary),
                ),
                Text(
                  quote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NimnaText.caption.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: l10n.chat_replyCancelA11y,
            child: GestureDetector(
              onTap: widget.onCancelReply,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: NimnaSpacing.touchTargetMin,
                height: NimnaSpacing.touchTargetMin,
                child: Center(child: CloseGlyph(color: tokens.textSecondary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The result of the timer picker: [changed] false means dismissed with no
/// pick; else [seconds] is the chosen preset (null = Off).
class ExpiryPickerResult {
  const ExpiryPickerResult({required this.changed, this.seconds});

  final bool changed;
  final int? seconds;
}

/// Opens the disappearing-timer preset sheet. Shows voice string 7 VERBATIM
/// (never softened) as the caption beneath the presets (wireframe F5.11).
Future<ExpiryPickerResult> showExpiryPicker(
  BuildContext context,
  int? current,
) async {
  final tokens = Theme.of(context).extension<NimnaTokens>()!;
  final result = await showModalBottomSheet<ExpiryPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tokens.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NimnaRadius.sheet),
      ),
    ),
    builder: (context) => _ExpiryPickerSheet(current: current),
  );
  return result ?? const ExpiryPickerResult(changed: false);
}

class _ExpiryPickerSheet extends StatelessWidget {
  const _ExpiryPickerSheet({required this.current});

  final int? current;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NimnaSpacing.base * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: NimnaSpacing.base * 2,
              runSpacing: NimnaSpacing.base * 2,
              children: [
                for (final seconds in expiryPresetSeconds)
                  _presetChip(context, tokens, l10n, seconds),
              ],
            ),
            const SizedBox(height: NimnaSpacing.base * 4),
            // Voice string 7 — VERBATIM, never softened (components.md).
            Text(
              l10n.chat_expiryDisclaimer,
              style: NimnaText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
    int? seconds,
  ) {
    final selected = seconds == current;
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).pop(ExpiryPickerResult(changed: true, seconds: seconds)),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: NimnaSpacing.touchTargetMin,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: NimnaSpacing.base * 4,
          vertical: NimnaSpacing.base * 2,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surface3,
          borderRadius: BorderRadius.circular(NimnaRadius.full),
          border: Border.all(
            color: selected ? tokens.textSecondary : tokens.hairline,
          ),
        ),
        child: Text(
          expiryPresetLabel(l10n, seconds),
          style: NimnaText.label.copyWith(color: tokens.textPrimary),
        ),
      ),
    );
  }
}
