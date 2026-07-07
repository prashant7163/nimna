/// The long-press message-actions card (S11 lane seed) — BINDING to
/// `designs/system/components.md` (message-actions, 82–90): the pressed bubble
/// stays lit, the thread dims (not a modal), and a compact card rises with the
/// six USER-locked emoji presets + a "+" disc that opens the system emoji
/// keyboard (first grapheme taken, spec §5.5), then Reply and Delete rows.
///
/// Holds no protocol state — it reports the chosen action upward via callbacks
/// (the import-direction fence). Every string is l10n; the "+" uses the SYSTEM
/// emoji keyboard (no emoji-picker dependency, architect pre-rejected).
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../model/message_view.dart';
import 'message_bubble.dart';

/// Opens the actions card for [message], dimming the thread behind it. Returns
/// when the card is dismissed (a pick / a Reply / a Delete / an outside tap).
Future<void> showMessageActions(
  BuildContext context, {
  required MessageView message,
  required void Function(String emoji) onReact,
  required VoidCallback onRemoveReaction,
  required VoidCallback onReply,
  required VoidCallback onDelete,
}) {
  final tokens = Theme.of(context).extension<NimnaTokens>()!;
  return showGeneralDialog<void>(
    context: context,
    // Dims the thread (components.md: the thread dims, the card is not a modal
    // surface — dismiss on any outside tap / swipe down).
    barrierColor: tokens.scrim,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: NimnaMotion.enter,
    pageBuilder: (context, _, _) => _ActionsBarrier(
      child: MessageActionsCard(
        message: message,
        onReact: (emoji) {
          Navigator.of(context).pop();
          onReact(emoji);
        },
        onRemoveReaction: () {
          Navigator.of(context).pop();
          onRemoveReaction();
        },
        onReply: () {
          Navigator.of(context).pop();
          onReply();
        },
        onDelete: () {
          Navigator.of(context).pop();
          onDelete();
        },
      ),
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: NimnaMotion.easeStandard),
      child: child,
    ),
  );
}

/// Swipe-down / tap-outside dismissal wrapper.
class _ActionsBarrier extends StatelessWidget {
  const _ActionsBarrier({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 0) {
          Navigator.of(context).maybePop();
        }
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          // Absorb taps on the card itself so they don't dismiss.
          child: GestureDetector(onTap: () {}, child: child),
        ),
      ),
    );
  }
}

/// The card body (public so widget tests can pump it directly).
class MessageActionsCard extends StatelessWidget {
  const MessageActionsCard({
    required this.message,
    required this.onReact,
    required this.onRemoveReaction,
    required this.onReply,
    required this.onDelete,
    super.key,
  });

  final MessageView message;
  final void Function(String emoji) onReact;
  final VoidCallback onRemoveReaction;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 332),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(NimnaRadius.large),
      ),
      padding: const EdgeInsets.all(NimnaSpacing.base * 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emojiRow(context, tokens, l10n),
          const SizedBox(height: NimnaSpacing.base * 2),
          _actionRow(
            context,
            label: l10n.chat_messageActionReply,
            color: tokens.textPrimary,
            onTap: onReply,
          ),
          _actionRow(
            context,
            label: l10n.chat_messageActionDelete,
            color: tokens.danger,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _emojiRow(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    return Semantics(
      label: l10n.chat_messageActionReact,
      container: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final preset in reactionPresets)
            _emojiDisc(
              tokens,
              child: Text(preset, style: const TextStyle(fontSize: 20)),
              selected: message.ownReaction == preset,
              onTap: () => message.ownReaction == preset
                  ? onRemoveReaction()
                  : onReact(preset),
            ),
          Semantics(
            label: l10n.chat_reactionPickMoreA11y,
            button: true,
            child: _emojiDisc(
              tokens,
              child: CustomPaint(
                size: const Size.square(18),
                painter: _PlusPainter(color: tokens.textSecondary),
              ),
              selected: false,
              onTap: () => _pickFromSystemKeyboard(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiDisc(
    NimnaTokens tokens, {
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: NimnaSpacing.touchTargetMin,
        height: NimnaSpacing.touchTargetMin,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surface3,
              shape: BoxShape.circle,
              border: selected ? Border.all(color: tokens.textSecondary) : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.touchTargetMin,
          ),
          alignment: AlignmentDirectional.centerStart,
          child: Text(label, style: NimnaText.body.copyWith(color: color)),
        ),
      ),
    );
  }

  /// Opens the system emoji keyboard via a transient hidden field and takes
  /// the first emoji grapheme cluster (spec §5.5 compose rule) — anything
  /// else is ignored. No emoji-picker dependency.
  Future<void> _pickFromSystemKeyboard(BuildContext context) async {
    final navigator = Navigator.of(context);
    final picked = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x00000000),
      pageBuilder: (context, _, _) => _SystemEmojiEntry(),
    );
    if (picked != null && picked.isNotEmpty) {
      navigator.maybePop();
      onReact(picked);
    }
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round;
    final c = size.width / 2;
    canvas.drawLine(Offset(c, 2), Offset(c, size.height - 2), paint);
    canvas.drawLine(Offset(2, c), Offset(size.width - 2, c), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => color != oldDelegate.color;
}

/// A near-invisible autofocus field that surfaces the system keyboard so the
/// user can pick any single emoji; the first grapheme cluster is taken.
class _SystemEmojiEntry extends StatefulWidget {
  @override
  State<_SystemEmojiEntry> createState() => _SystemEmojiEntryState();
}

class _SystemEmojiEntryState extends State<_SystemEmojiEntry> {
  final FocusNode _focus = FocusNode();
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      child: EditableText(
        controller: _controller,
        focusNode: _focus,
        style: const TextStyle(),
        cursorColor: const Color(0x00000000),
        backgroundCursorColor: const Color(0x00000000),
        onChanged: (value) {
          if (value.isEmpty) {
            return;
          }
          // Take the first grapheme cluster only (spec §5.5).
          final first = value.characters.first;
          Navigator.of(context).pop(first);
        },
      ),
    );
  }
}
