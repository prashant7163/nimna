/// THE ONE share_plus CALL-SITE MODULE (S8 intake §7 — scoped sign-off).
/// Platform share only: the code as text, or the QR as a PNG image. The
/// QR PNG is rendered to a temp file for the OS handoff and deleted
/// immediately afterwards (the decrypt-to-temp-for-share cleanup pattern,
/// app-architecture.md §5). Either form travels alone (F2.3): the briefing
/// line is the SHEET's caption, never payload.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:share_plus/share_plus.dart';

import '../../protocol/pairing_code.dart';
import 'qr_matrix.dart';

/// Shares the code as plain text (`XXX-XXX-XXX`).
Future<void> shareCodeAsText(PairingCode code) async {
  await SharePlus.instance.share(ShareParams(text: code.display));
}

/// Renders the code's QR to a PNG (black modules on true white, quiet
/// zone included), hands it to the OS share sheet, then deletes the temp
/// file.
Future<void> shareCodeAsQrImage(PairingCode code) async {
  final png = await renderQrPng(code);
  final dir = await Directory.systemTemp.createTemp('nimna-share-');
  final file = File('${dir.path}/nimna-code.png');
  try {
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
  } finally {
    // Cleanup after handoff — the receiving app holds its own copy.
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// Rasterizes the QR matrix for [code] as a PNG: 8 px per module, 4-module
/// quiet zone, `#FFFFFF` background (QR needs true white — components.md).
Future<Uint8List> renderQrPng(PairingCode code, {int scale = 8}) async {
  final matrix = QrMatrix.forCode(code);
  const quiet = 4;
  final size = (matrix.moduleCount + 2 * quiet) * scale;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final white = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    white,
  );
  for (var y = 0; y < matrix.moduleCount; y++) {
    for (var x = 0; x < matrix.moduleCount; x++) {
      if (matrix.isDark(x, y)) {
        canvas.drawRect(
          ui.Rect.fromLTWH(
            ((quiet + x) * scale).toDouble(),
            ((quiet + y) * scale).toDouble(),
            scale.toDouble(),
            scale.toDouble(),
          ),
          black,
        );
      }
    }
  }
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
