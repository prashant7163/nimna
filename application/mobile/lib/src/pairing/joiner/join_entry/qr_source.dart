/// The SOLE `mobile_scanner` call site (SESSION-9 dependency fence): the
/// live QR scanner (F3.2) and the still-image decode used by the upload path
/// (F3.1 method iv). Pinned to the BUNDLED on-device MLKit variant — no
/// play-services telemetry, zero network (SESSION-9 deps audit). Every
/// decoded payload converges through [PairingCode.fromScannedPayload]
/// (spec §3.1.1), so all four join methods produce the same canonical bytes.
///
/// Camera glue is device-only and is exercised on-device (QA device pass),
/// not under `flutter test`; the canonicalization it feeds is unit-tested.
library;

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../protocol/pairing_code.dart';

/// Live camera scanner. Calls [onCode] exactly once with the first frame
/// that decodes to a valid Nimna code; a foreign/unreadable QR is ignored
/// (no error state — the brackets just keep looking, F3.2).
class JoinScannerView extends StatefulWidget {
  const JoinScannerView({required this.onCode, super.key});

  final void Function(PairingCode code) onCode;

  @override
  State<JoinScannerView> createState() => _JoinScannerViewState();
}

class _JoinScannerViewState extends State<JoinScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) {
        continue;
      }
      final code = PairingCode.fromScannedPayload(raw);
      if (code != null) {
        _handled = true;
        widget.onCode(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      MobileScanner(controller: _controller, onDetect: _onDetect);
}

/// Decodes a Nimna code from a QR in the image at [path] (a photo or a
/// rasterized PDF page). Returns null when no readable Nimna QR is present.
Future<PairingCode?> decodeQrFromImage(String path) async {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  try {
    final capture = await controller.analyzeImage(path);
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final raw = barcode.rawValue;
      if (raw == null) {
        continue;
      }
      final code = PairingCode.fromScannedPayload(raw);
      if (code != null) {
        return code;
      }
    }
    return null;
  } finally {
    await controller.dispose();
  }
}
