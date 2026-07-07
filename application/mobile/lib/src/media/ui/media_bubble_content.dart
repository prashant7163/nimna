/// The media bubble body (S11) — BINDING to `designs/system/components.md`
/// (media bubbles: images edge-to-edge, documents as a row, the 2 px transfer
/// progress line) and `tokens.json` media block. Consumed BY the chat lane's
/// `message_bubble.dart` through a content hook: S11 renders up to the loaded
/// state; the S14 sensitive-content blur veil layers ON TOP later.
///
/// Holds no transport/store state — it renders an immutable [MessageView] and
/// decrypts-to-memory via the [loadBytes] callback the chat screen supplies
/// (which routes through the session controller). Every string is l10n;
/// left/right is never hardcoded.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../session/model/message_view.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../model/media_transfer_state.dart';

/// Formats a byte length as a locale-aware size string (MB ≥ 1 MB, else KB).
String formatMediaSize(BuildContext context, AppLocalizations l10n, int bytes) {
  final locale = Localizations.localeOf(context).toString();
  if (bytes >= 1024 * 1024) {
    final mb = NumberFormat('0.0', locale).format(bytes / (1024 * 1024));
    return l10n.media_sizeMegabytes(mb);
  }
  final kb = NumberFormat('0', locale).format(bytes / 1024);
  return l10n.media_sizeKilobytes(kb);
}

/// The media bubble content. For images: edge-to-edge, clipped to the bubble
/// radius. For documents: a `surface2` row with a doc glyph, kind, and size.
class MediaBubbleContent extends StatelessWidget {
  const MediaBubbleContent({
    required this.message,
    required this.loadBytes,
    this.onTap,
    super.key,
  });

  final MessageView message;

  /// Decrypts the blob to memory (image bubbles only); null for documents or
  /// when bytes are not yet available.
  final Future<Uint8List> Function()? loadBytes;

  /// Opens the full-bleed viewer (components.md media viewer).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final transfer = message.mediaTransfer ?? MediaTransferState.loaded;
    return Semantics(
      label: _a11y(l10n, transfer),
      button: onTap != null,
      child: message.isMediaImage
          ? _image(context, tokens, transfer)
          : _document(context, tokens, l10n),
    );
  }

  String _a11y(AppLocalizations l10n, MediaTransferState transfer) {
    switch (transfer.phase) {
      case MediaTransferPhase.sending:
        return l10n.media_sendingA11y;
      case MediaTransferPhase.receiving:
        return l10n.media_receivingA11y;
      case MediaTransferPhase.loaded:
      case MediaTransferPhase.failed:
        return message.isMediaImage
            ? l10n.media_imageA11y
            : l10n.media_documentA11y;
    }
  }

  Widget _image(
    BuildContext context,
    NimnaTokens tokens,
    MediaTransferState transfer,
  ) {
    final radius = BorderRadius.circular(NimnaRadius.large);
    final receiving = transfer.phase == MediaTransferPhase.receiving;
    final sending = transfer.phase == MediaTransferPhase.sending;
    Widget picture;
    if (receiving || loadBytes == null) {
      // Receiving placeholder at a neutral aspect (components.md).
      picture = AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(color: tokens.surface2),
      );
    } else {
      picture = FutureBuilder<Uint8List>(
        future: loadBytes!(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(color: tokens.surface2),
            );
          }
          return Image.memory(data, fit: BoxFit.fitWidth);
        },
      );
    }
    // Sending: the image at 60% opacity while it moves (components.md).
    if (sending) {
      picture = Opacity(opacity: 0.6, child: picture);
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            picture,
            if (transfer.inFlight)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: _TransferProgressLine(color: tokens.accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _document(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    final kind = message.mediaMime == 'application/pdf'
        ? l10n.media_documentKindPdf
        : l10n.media_documentKindFile;
    final meta = l10n.media_documentMeta(
      kind,
      formatMediaSize(context, l10n, message.mediaByteLength ?? 0),
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: NimnaMedia.docRowHeight),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(NimnaRadius.large),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DocGlyph(color: tokens.textSecondary, size: 24),
            const SizedBox(width: NimnaSpacing.base * 3),
            Flexible(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NimnaText.caption.copyWith(color: tokens.textTertiary),
              ),
            ),
            if ((message.mediaTransfer ?? MediaTransferState.loaded).inFlight)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: SizedBox(
                  width: 40,
                  child: _TransferProgressLine(color: tokens.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 2 px `accent` progress line — the line motif carrying the transfer
/// (components.md: "reassurance, not a meter"; no percentage text). Renders
/// indeterminately (a sweeping fill) while bytes move.
class _TransferProgressLine extends StatefulWidget {
  const _TransferProgressLine({required this.color});

  final Color color;

  @override
  State<_TransferProgressLine> createState() => _TransferProgressLineState();
}

class _TransferProgressLineState extends State<_TransferProgressLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NimnaMedia.transferProgressThickness,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ProgressLinePainter(
            color: widget.color,
            t: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _ProgressLinePainter extends CustomPainter {
  _ProgressLinePainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // A sweeping segment ~40% of the width, left→right (LTR-agnostic fill).
    const fraction = 0.4;
    final segWidth = size.width * fraction;
    final x = (size.width + segWidth) * t - segWidth;
    canvas.drawRect(
      Rect.fromLTWH(x.clamp(0, size.width), 0, segWidth, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressLinePainter old) => old.t != t;
}

/// A minimal document glyph (a page with a folded corner). Symmetric enough to
/// not require RTL mirroring.
class _DocGlyph extends StatelessWidget {
  const _DocGlyph({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _DocPainter(color: color),
  );
}

class _DocPainter extends CustomPainter {
  const _DocPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(6 * s, 3 * s)
      ..lineTo(14 * s, 3 * s)
      ..lineTo(19 * s, 8 * s)
      ..lineTo(19 * s, 21 * s)
      ..lineTo(6 * s, 21 * s)
      ..close()
      ..moveTo(14 * s, 3 * s)
      ..lineTo(14 * s, 8 * s)
      ..lineTo(19 * s, 8 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DocPainter old) => color != old.color;
}
