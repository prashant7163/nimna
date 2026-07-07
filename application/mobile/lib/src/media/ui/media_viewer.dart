/// The full-bleed media viewer (S11) — BINDING to `designs/system/components.md`
/// (media viewer): full-bleed on `surface0`, top bar = local label + received
/// time, bottom bar = Export (the single deliberate act that moves a file out
/// of Nimna's store, spec §5.1). Pushed on-the-fly from the bubble tap (no
/// named route — SESSION-11 intake §6), so `routes.dart` stays untouched.
///
/// Holds no store/transport state: it decrypts-to-memory via [loadBytes] and
/// delegates the export to [onExport] (which the chat screen routes through the
/// pipeline). Every string is l10n; left/right is never hardcoded.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../../ui/widgets/glyphs.dart';

class MediaViewer extends StatefulWidget {
  const MediaViewer({
    required this.loadBytes,
    required this.isImage,
    required this.label,
    required this.timestampMs,
    required this.onExport,
    super.key,
  });

  final Future<Uint8List> Function() loadBytes;
  final bool isImage;

  /// The channel's local label (components.md: "local label + received time").
  final String label;

  /// The message timestamp (Unix ms) — rendered locale-aware.
  final int timestampMs;

  /// Runs the deliberate export (decrypt-to-temp → share → cleanup).
  final Future<void> Function() onExport;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  bool _chromeVisible = true;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: tokens.surface0,
      body: GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: SafeArea(
          child: Stack(
            children: [
              Center(child: _content(tokens)),
              if (_chromeVisible) _topBar(context, tokens, l10n),
              if (_chromeVisible) _bottomBar(context, tokens, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(NimnaTokens tokens) {
    if (!widget.isImage) {
      return _DocGlyphLarge(color: tokens.textSecondary);
    }
    return FutureBuilder<Uint8List>(
      future: widget.loadBytes(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const SizedBox.shrink();
        }
        return InteractiveViewer(child: Image.memory(data));
      },
    );
  }

  Widget _topBar(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.yMMMd(
      locale,
    ).add_jm().format(DateTime.fromMillisecondsSinceEpoch(widget.timestampMs));
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: Container(
        color: tokens.scrim,
        padding: const EdgeInsets.symmetric(
          horizontal: NimnaSpacing.screenMargin,
          vertical: NimnaSpacing.base * 2,
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: NimnaSpacing.touchTargetMin,
                  height: NimnaSpacing.touchTargetMin,
                  child: Center(child: BackGlyph(color: tokens.textPrimary)),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: NimnaText.label.copyWith(color: tokens.textPrimary),
                  ),
                  Text(
                    l10n.media_viewerReceivedTime(time),
                    style: NimnaText.caption.copyWith(
                      color: tokens.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    return PositionedDirectional(
      bottom: 0,
      start: 0,
      end: 0,
      child: Container(
        color: tokens.scrim,
        padding: const EdgeInsets.symmetric(
          horizontal: NimnaSpacing.screenMargin,
          vertical: NimnaSpacing.base * 3,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _confirmExport(context, tokens, l10n),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: NimnaSpacing.touchTargetMin,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.base * 4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.hairline),
                  borderRadius: BorderRadius.circular(NimnaRadius.medium),
                ),
                child: Text(
                  l10n.media_exportAction,
                  style: NimnaText.label.copyWith(color: tokens.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExport(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: tokens.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NimnaRadius.sheet),
        ),
      ),
      builder: (context) => _ExportConfirmSheet(tokens: tokens, l10n: l10n),
    );
    if (confirmed ?? false) {
      await widget.onExport();
    }
  }
}

class _ExportConfirmSheet extends StatelessWidget {
  const _ExportConfirmSheet({required this.tokens, required this.l10n});

  final NimnaTokens tokens;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(NimnaSpacing.base * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.media_exportConfirm,
              style: NimnaText.body.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: NimnaSpacing.base * 2),
            Text(
              l10n.media_exportRollNote,
              style: NimnaText.caption.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: NimnaSpacing.base * 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _sheetButton(
                  context,
                  label: l10n.media_exportCancel,
                  color: tokens.textSecondary,
                  value: false,
                ),
                const SizedBox(width: NimnaSpacing.base * 3),
                _sheetButton(
                  context,
                  label: l10n.media_exportAction,
                  color: tokens.accent,
                  value: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetButton(
    BuildContext context, {
    required String label,
    required Color color,
    required bool value,
  }) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.base * 3,
          ),
          alignment: Alignment.center,
          child: Text(label, style: NimnaText.label.copyWith(color: color)),
        ),
      ),
    );
  }
}

class _DocGlyphLarge extends StatelessWidget {
  const _DocGlyphLarge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(96),
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
      ..strokeWidth = 1.5 * s
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
