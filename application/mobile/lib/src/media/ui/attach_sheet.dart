/// The attach flow (S11) — BINDING to `designs/system/components.md` (attach
/// affordance + attach preview) and `tokens.json` media block. Opens the
/// photo / file pickers, runs the on-device EXIF-strip + compression, and shows
/// the preview with the metadata-strip notice (voice string 17), the
/// original-quality toggle (off by default), and the over-cap error (string
/// 17). Returns a ready-to-seal [MediaAttachment], or null if cancelled.
///
/// The picker + share are device-dependent (platform channels — S7/S18 rung);
/// the preview widgets are pure and pumpable in widget tests. Every string is
/// l10n; the sensitive-content whisper (string 14) is S14's, not added here.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../../ui/widgets/nimna_toggle.dart';
import '../model/media_attachment.dart';
import '../pipeline/attachment_picker.dart';
import '../pipeline/image_processor.dart';
import '../pipeline/media_mime.dart';
import 'media_bubble_content.dart';

/// The 5 MB attachment cap in bytes (spec §5.1; `tokens.json` media block).
const int mediaCapBytes = NimnaMedia.attachmentCapMB * 1024 * 1024;

enum _AttachIntent { photo, file }

/// Opens the attach sheet → picker → preview. Returns the chosen attachment.
Future<MediaAttachment?> showAttachSheet(BuildContext context) async {
  final tokens = Theme.of(context).extension<NimnaTokens>()!;
  final intent = await showModalBottomSheet<_AttachIntent>(
    context: context,
    backgroundColor: tokens.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NimnaRadius.sheet),
      ),
    ),
    builder: (context) => const _AttachOptionsSheet(),
  );
  if (intent == null || !context.mounted) {
    return null;
  }
  final picked = intent == _AttachIntent.photo
      ? await AttachmentPicker.pickPhoto()
      : await AttachmentPicker.pickDocument();
  if (picked == null || !context.mounted) {
    return null;
  }
  if (isImageMime(picked.mime)) {
    return showModalBottomSheet<MediaAttachment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NimnaRadius.sheet),
        ),
      ),
      builder: (context) => AttachImagePreview(rawBytes: picked.bytes),
    );
  }
  return showModalBottomSheet<MediaAttachment>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tokens.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NimnaRadius.sheet),
      ),
    ),
    builder: (context) =>
        AttachDocumentPreview(bytes: picked.bytes, mime: picked.mime),
  );
}

class _AttachOptionsSheet extends StatelessWidget {
  const _AttachOptionsSheet();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NimnaSpacing.base * 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _option(context, tokens, l10n.media_pickPhoto, _AttachIntent.photo),
            _option(context, tokens, l10n.media_pickFile, _AttachIntent.file),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    NimnaTokens tokens,
    String label,
    _AttachIntent intent,
  ) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(intent),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
            vertical: NimnaSpacing.base * 3,
          ),
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            label,
            style: NimnaText.body.copyWith(color: tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The image attach preview: thumbnail + metadata-strip notice + original-
/// quality toggle + over-cap guard + Send. Re-runs the strip/compress pipeline
/// whenever the toggle flips. Public for widget tests.
class AttachImagePreview extends StatefulWidget {
  const AttachImagePreview({required this.rawBytes, super.key});

  final Uint8List rawBytes;

  @override
  State<AttachImagePreview> createState() => _AttachImagePreviewState();
}

class _AttachImagePreviewState extends State<AttachImagePreview> {
  bool _originalQuality = false;
  bool _processing = true;
  ProcessedImage? _processed;

  @override
  void initState() {
    super.initState();
    _reprocess();
  }

  Future<void> _reprocess() async {
    setState(() => _processing = true);
    ProcessedImage? out;
    try {
      out = await ImageProcessor.process(
        widget.rawBytes,
        originalQuality: _originalQuality,
      );
    } on ImageDecodeError {
      out = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _processed = out;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final processed = _processed;
    final overCap = processed != null && processed.bytes.length > mediaCapBytes;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(NimnaSpacing.base * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(NimnaRadius.large),
              child: _processing || processed == null
                  ? AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ColoredBox(color: tokens.surface3),
                    )
                  : Image.memory(processed.bytes, fit: BoxFit.fitWidth),
            ),
            const SizedBox(height: NimnaSpacing.base * 3),
            // Voice string 17 — metadata-strip feature notice, verbatim.
            Text(
              l10n.media_metadataStripNotice,
              style: NimnaText.caption.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: NimnaSpacing.base * 3),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.media_originalQualityToggle,
                        style: NimnaText.label.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        l10n.media_compressionNote,
                        style: NimnaText.caption.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NimnaSpacing.base * 3),
                NimnaToggle(
                  value: _originalQuality,
                  onChanged: _processing
                      ? null
                      : (value) {
                          setState(() => _originalQuality = value);
                          unawaited(_reprocess());
                        },
                ),
              ],
            ),
            if (overCap) ...[
              const SizedBox(height: NimnaSpacing.base * 3),
              // Voice string 17 — over-cap error, verbatim.
              Text(
                l10n.media_overCapError,
                style: NimnaText.caption.copyWith(color: tokens.danger),
              ),
            ],
            const SizedBox(height: NimnaSpacing.base * 4),
            _SendButton(
              enabled: processed != null && !overCap && !_processing,
              onSend: () => Navigator.of(context).pop(
                MediaAttachment(
                  bytes: processed!.bytes,
                  mime: processed.mime,
                  pixelWidth: processed.width,
                  pixelHeight: processed.height,
                  originalQuality: _originalQuality,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The document attach preview: doc row + size + over-cap guard + Send. Public
/// for widget tests.
class AttachDocumentPreview extends StatelessWidget {
  const AttachDocumentPreview({
    required this.bytes,
    required this.mime,
    super.key,
  });

  final Uint8List bytes;
  final String mime;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final overCap = bytes.length > mediaCapBytes;
    final kind = mime == 'application/pdf'
        ? l10n.media_documentKindPdf
        : l10n.media_documentKindFile;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(NimnaSpacing.base * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(
                minHeight: NimnaMedia.docRowHeight,
              ),
              decoration: BoxDecoration(
                color: tokens.surface3,
                borderRadius: BorderRadius.circular(NimnaRadius.large),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.media_documentMeta(
                  kind,
                  formatMediaSize(context, l10n, bytes.length),
                ),
                style: NimnaText.caption.copyWith(color: tokens.textTertiary),
              ),
            ),
            if (overCap) ...[
              const SizedBox(height: NimnaSpacing.base * 3),
              Text(
                l10n.media_overCapError,
                style: NimnaText.caption.copyWith(color: tokens.danger),
              ),
            ],
            const SizedBox(height: NimnaSpacing.base * 4),
            _SendButton(
              enabled: !overCap,
              onSend: () => Navigator.of(
                context,
              ).pop(MediaAttachment(bytes: bytes, mime: mime)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onSend});

  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.chat_sendA11y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onSend : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.touchTargetMin,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? tokens.accent : tokens.surface3,
            borderRadius: BorderRadius.circular(NimnaRadius.medium),
          ),
          child: Text(
            l10n.chat_sendA11y,
            style: NimnaText.label.copyWith(
              color: enabled ? tokens.onAccent : tokens.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}
