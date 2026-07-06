import 'package:qr/qr.dart';

import '../../protocol/pairing_code.dart';

/// The one place the `qr` encoder is invoked. Encodes exactly the §3.1.1
/// QR payload (`nimna:XXX-XXX-XXX` — nothing else: no expiry hint, no
/// version, no metadata) at error-correction level M — the ISO/IEC 18004
/// default for screen-to-camera use; the payload is 17 ASCII bytes, so the
/// symbol stays at version 1–2 and scans at arm's length. Correctness is
/// pinned by the committed expected-matrix fixture
/// (test/ui/qr_matrix_test.dart), whose bits were verified once with an
/// independent decoder (Apple Vision `VNDetectBarcodesRequest`).
class QrMatrix {
  QrMatrix._(this._image);

  final QrImage _image;

  factory QrMatrix.forCode(PairingCode code) {
    final qrCode = QrCode.fromData(
      data: code.qrPayload,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return QrMatrix._(QrImage(qrCode));
  }

  int get moduleCount => _image.moduleCount;

  /// Whether the module at column [x], row [y] is dark.
  bool isDark(int x, int y) => _image.isDark(y, x);
}
