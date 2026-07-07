/// The SOLE `file_picker` + `pdfrx` call site (SESSION-9 dependency fence):
/// the "upload a QR image or PDF" join method (F3.1 method iv, spec §3.1).
/// An image is decoded directly; a PDF's first page is rasterized to a
/// short-lived temp PNG, decoded, then deleted. Every path converges through
/// [decodeQrFromImage] → [PairingCode.fromScannedPayload], so it produces the
/// same canonical bytes as the other three methods.
///
/// Device-only glue (pickers, native PDF raster), exercised on-device (QA
/// device pass), not under `flutter test`.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../protocol/pairing_code.dart';
import 'qr_source.dart';

/// The outcome of an upload attempt (F3.1 edge copy is chosen by the caller).
enum UploadOutcome {
  /// The user dismissed the picker — no change, no error.
  cancelled,

  /// A file was chosen but held no readable Nimna QR ("No code in that file.").
  noCode,

  /// A valid code was decoded.
  decoded,
}

class UploadResult {
  const UploadResult._(this.outcome, this.code);

  const UploadResult.cancelled() : this._(UploadOutcome.cancelled, null);
  const UploadResult.noCode() : this._(UploadOutcome.noCode, null);
  const UploadResult.decoded(PairingCode code)
    : this._(UploadOutcome.decoded, code);

  final UploadOutcome outcome;
  final PairingCode? code;
}

bool _pdfrxInitialized = false;

/// Opens the OS picker (image or PDF), decodes a Nimna QR, and cleans up any
/// temp raster.
Future<UploadResult> pickAndDecodeQr() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'png',
      'jpg',
      'jpeg',
      'webp',
      'bmp',
      'gif',
      'heic',
      'heif',
      'pdf',
    ],
  );
  if (picked == null || picked.files.isEmpty) {
    return const UploadResult.cancelled();
  }
  final path = picked.files.single.path;
  if (path == null) {
    return const UploadResult.noCode();
  }

  String? tempPng;
  try {
    final String imagePath;
    if (p.extension(path).toLowerCase() == '.pdf') {
      tempPng = await _rasterizePdfFirstPage(path);
      if (tempPng == null) {
        return const UploadResult.noCode();
      }
      imagePath = tempPng;
    } else {
      imagePath = path;
    }
    final code = await decodeQrFromImage(imagePath);
    return code == null
        ? const UploadResult.noCode()
        : UploadResult.decoded(code);
  } finally {
    if (tempPng != null) {
      try {
        await File(tempPng).delete();
      } on FileSystemException {
        // Best-effort cleanup; the temp holds only a rendered QR of a
        // single-use rendezvous code, never channel key material.
      }
    }
  }
}

/// Rasterizes page 1 of the PDF at [path] to a temp PNG at 2× and returns its
/// path (null if the PDF is empty or unrenderable).
Future<String?> _rasterizePdfFirstPage(String path) async {
  if (!_pdfrxInitialized) {
    await pdfrxFlutterInitialize();
    _pdfrxInitialized = true;
  }
  final doc = await PdfDocument.openFile(path);
  try {
    if (doc.pages.isEmpty) {
      return null;
    }
    final page = doc.pages.first;
    final pdfImage = await page.render(
      width: (page.width * 2).toInt(),
      height: (page.height * 2).toInt(),
    );
    if (pdfImage == null) {
      return null;
    }
    try {
      final uiImage = await pdfImage.createImage();
      final png = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (png == null) {
        return null;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'nimna_qr_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      return file.path;
    } finally {
      pdfImage.dispose();
    }
  } finally {
    await doc.dispose();
  }
}
