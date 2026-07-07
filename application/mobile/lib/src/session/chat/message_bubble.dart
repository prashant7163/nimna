/// Chat bubbles (S11 lane seed) — the text bubble with delivery ticks, the
/// quoted-reply preview + tombstone, reaction chips (ownership by STROKE
/// weight, never color, never amber), the long-press message-actions card,
/// and the silent peer-typing three-dot glyph. BINDING to
/// `designs/system/components.md` (chat bubbles ~37–47, reaction chip 63–80,
/// message-actions 82–90, quoted-reply-preview 92–105).
///
/// This lane holds NO NoiseTransport / key / counter / message store — it only
/// renders immutable [MessageView]s and reports gestures upward (the
/// import-direction fence, test/session/import_direction_test.dart). Every
/// user-facing string comes from l10n; left/right is never hardcoded
/// (directional alignment + logical insets).
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/message_record.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../model/message_view.dart';

/// The six USER-locked reaction presets (components.md message-actions;
/// USER 2026-07-05 03:30 +0200). Order is fixed.
const List<String> reactionPresets = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Sanitizes a peer emoji before it is substituted into any a11y label
/// (REQUIRED, designs/handoff/arb-stubs-reply-reactions.md). The wire
/// guarantees only 1–64 bytes of valid UTF-8 (spec §5.5); a modified client
/// can pack control characters, newlines, or bidi/format marks into the
/// field. We enforce the 64-byte bound (a longer field is a §3.3.1 structural
/// error and never reaches here) and strip C0/C1 controls plus Unicode
/// bidi/format controls — but keep the joiners that legitimate emoji
/// sequences need (ZWJ, variation selectors, skin-tone modifiers). Never feed
/// raw wire bytes to a formatter.
String sanitizeEmojiForA11y(String raw) {
  var source = raw;
  final bytes = utf8.encode(raw);
  if (bytes.length > 64) {
    // Defensive only — a >64-byte field is already a structural violation.
    source = utf8.decode(bytes.sublist(0, 64), allowMalformed: true);
  }
  final out = StringBuffer();
  for (final rune in source.runes) {
    if (_isStrippableControl(rune)) {
      continue;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}

bool _isStrippableControl(int r) {
  // C0 controls + DEL + C1 controls.
  if (r <= 0x1F || r == 0x7F || (r >= 0x80 && r <= 0x9F)) {
    return true;
  }
  // Bidi marks / embeddings / overrides / isolates (spoofing surface).
  if (r == 0x200E || r == 0x200F || r == 0x061C) {
    return true;
  }
  if (r >= 0x202A && r <= 0x202E) {
    return true;
  }
  if (r >= 0x2066 && r <= 0x2069) {
    return true;
  }
  // Other invisible format controls (ZWSP, ZWNJ, WJ, BOM/ZWNBSP). ZWJ
  // (0x200D), variation selectors (0xFE00–0xFE0F), and skin-tone modifiers
  // are deliberately KEPT — they carry legitimate emoji meaning.
  if (r == 0x200B || r == 0x200C || r == 0x2060 || r == 0xFEFF) {
    return true;
  }
  return false;
}

/// One text bubble (sent or received) with its optional quoted-reply preview,
/// delivery chrome, and reaction chips.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    this.onLongPress,
    this.onTapQuote,
    super.key,
  });

  final MessageView message;

  /// Long-press opens the message-actions card (react / reply / delete).
  final VoidCallback? onLongPress;

  /// Tap on the quote block scrolls the thread to the referent.
  final VoidCallback? onTapQuote;

  static const double _maxWidthFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final outbound = message.outbound;
    final align = outbound ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final waiting = outbound && message.deliveryState == DeliveryState.waiting;

    return Padding(
      padding: EdgeInsets.only(
        top: NimnaSpacing.base,
        bottom: message.hasReactions ? 14 : NimnaSpacing.base,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                l10n.chat_waitingHeader,
                style: NimnaText.micro.copyWith(color: tokens.textTertiary),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * _maxWidthFraction,
                ),
                child: _bubbleWithChips(context, tokens, l10n, outbound),
              );
            },
          ),
          _footer(context, tokens, l10n),
        ],
      ),
    );
  }

  Widget _bubbleWithChips(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
    bool outbound,
  ) {
    final chips = _chips(context, tokens, l10n);
    final bubble = GestureDetector(
      onLongPress: message.isReferentEligible ? onLongPress : null,
      child: _bubbleBody(context, tokens, outbound),
    );
    if (chips.isEmpty) {
      return bubble;
    }
    // The chip overlaps the bubble's bottom edge (components.md); Stack lets it
    // protrude into the 14 px clearance added above.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bubble,
        PositionedDirectional(
          bottom: -12,
          start: outbound ? 10 : null,
          end: outbound ? null : 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                chips[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubbleBody(BuildContext context, NimnaTokens tokens, bool outbound) {
    final waiting = outbound && message.deliveryState == DeliveryState.waiting;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(NimnaRadius.large),
      topRight: const Radius.circular(NimnaRadius.large),
      bottomLeft: Radius.circular(
        outbound ? NimnaRadius.large : NimnaRadius.bubbleTail,
      ),
      bottomRight: Radius.circular(
        outbound ? NimnaRadius.bubbleTail : NimnaRadius.large,
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.reply != null) _quoteBlock(context, tokens, message.reply!),
        if (message.text != null)
          Text(
            message.text!,
            style: NimnaText.bodyLarge.copyWith(color: tokens.textPrimary),
          ),
      ],
    );
    if (waiting) {
      // Waiting: transparent fill, 1 px dashed border (components.md; §3.4).
      return CustomPaint(
        painter: _DashedBorderPainter(
          color: tokens.lineIdle,
          radius: NimnaRadius.large,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: content,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: outbound ? tokens.bubbleSent : tokens.bubbleReceived,
        borderRadius: radius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: content,
    );
  }

  /// The in-bubble quote block (components.md quoted-reply-preview): a 2 px
  /// vertical rule at the reading edge, referent excerpt or the neutral
  /// tombstone. Tap scrolls to the referent (never for a tombstone).
  Widget _quoteBlock(
    BuildContext context,
    NimnaTokens tokens,
    ReplyPreview reply,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final String label;
    if (reply.tombstone) {
      label = l10n.chat_replyTombstone;
    } else if (reply.kind == ReplyReferentKind.photo) {
      label = l10n.chat_replyPreviewPhoto;
    } else if (reply.kind == ReplyReferentKind.document) {
      label = l10n.chat_replyPreviewDocument;
    } else {
      label = reply.excerpt ?? '';
    }
    final block = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2, color: tokens.textTertiary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NimnaText.caption.copyWith(
                  color: reply.tombstone
                      ? tokens.textTertiary
                      : tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (reply.tombstone) {
      return block; // History, not an affordance — tap does nothing.
    }
    return GestureDetector(onTap: onTapQuote, child: block);
  }

  List<Widget> _chips(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    // The peer's chip takes the center-facing slot; yours sits beside it
    // toward the authored edge (components.md, one rule both directions).
    final chips = <Widget>[];
    if (message.peerReaction != null) {
      chips.add(
        _ReactionChip(
          emoji: message.peerReaction!,
          own: false,
          semanticsLabel: l10n.chat_reactionPeerA11y(
            sanitizeEmojiForA11y(message.peerReaction!),
          ),
        ),
      );
    }
    if (message.ownReaction != null) {
      chips.add(
        _ReactionChip(
          emoji: message.ownReaction!,
          own: true,
          semanticsLabel: l10n.chat_reactionOwnA11y(
            sanitizeEmojiForA11y(message.ownReaction!),
          ),
        ),
      );
    }
    return chips;
  }

  Widget _footer(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    if (!message.outbound) {
      return const SizedBox.shrink();
    }
    final String a11y;
    switch (message.deliveryState) {
      case DeliveryState.waiting:
        a11y = l10n.chat_deliveryWaitingA11y;
      case DeliveryState.sent:
        a11y = l10n.chat_deliverySentA11y;
      case DeliveryState.delivered:
        a11y = l10n.chat_deliveryDeliveredA11y;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Semantics(
        label: a11y,
        child: SizedBox(
          height: 14,
          // Delivered adds a check glyph (components.md); no double-ticks, no
          // read receipts unless the channel opts in (deferred).
          child: message.deliveryState == DeliveryState.delivered
              ? CheckGlyph(color: tokens.textTertiary, size: 12)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A single reaction chip — ownership is a STROKE, never a color, never amber
/// (components.md). One line, bidi-isolated, bounded window; a hostile field
/// can at worst look odd inside its own clamp, never break the thread.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.own,
    required this.semanticsLabel,
  });

  final String emoji;
  final bool own;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 60, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tokens.surface3,
          borderRadius: BorderRadius.circular(NimnaRadius.full),
          border: Border.all(
            color: own ? tokens.textSecondary : tokens.hairline,
          ),
        ),
        // Bidi-isolated so a hostile field cannot set the row's direction; the
        // raw emoji is excluded from a11y (the sanitized label names it).
        child: ExcludeSemantics(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 40),
              child: Text(
                emoji,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: NimnaText.caption.copyWith(
                  color: tokens.textPrimary,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The silent peer-typing indicator: an animated three-dot glyph in the
/// received-bubble position, NO text string (USER, 2026-07-07).
class PeerTypingBubble extends StatefulWidget {
  const PeerTypingBubble({super.key});

  @override
  State<PeerTypingBubble> createState() => _PeerTypingBubbleState();
}

class _PeerTypingBubbleState extends State<PeerTypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: NimnaSpacing.base),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.bubbleReceived,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(NimnaRadius.large),
            topRight: Radius.circular(NimnaRadius.large),
            bottomRight: Radius.circular(NimnaRadius.large),
            bottomLeft: Radius.circular(NimnaRadius.bubbleTail),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: const Size(28, 6),
            painter: _TypingDotsPainter(
              color: tokens.textTertiary,
              t: _controller.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDotsPainter extends CustomPainter {
  _TypingDotsPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const count = 3;
    for (var i = 0; i < count; i++) {
      final phase = (t + i / count) % 1.0;
      final opacity = 0.3 + 0.7 * (0.5 - (phase - 0.5).abs()) * 2;
      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(Offset(3 + i * 11, size.height / 2), 3, paint);
    }
  }

  @override
  bool shouldRepaint(_TypingDotsPainter oldDelegate) => oldDelegate.t != t;
}

/// A small delivery check tick (components.md: 12 px check glyph beside the
/// timestamp on a delivered message).
class CheckGlyph extends StatelessWidget {
  const CheckGlyph({required this.color, this.size = 12, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _CheckPainter(color: color),
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(5 * s, 12.5 * s)
      ..lineTo(10 * s, 17.5 * s)
      ..lineTo(19 * s, 6.5 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color;
}
