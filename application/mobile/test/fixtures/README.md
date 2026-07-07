# test/fixtures/

Committed expected-value fixtures for the mobile test suite.

- `qr_nimna_kr7-fm2-xq4_ecM.txt` — the exact QR module matrix (`#` dark,
  `.` light; 25×25, version 2, error-correction M) the `qr` encoder must
  produce for the §3.1.1 payload `nimna:KR7-FM2-XQ4`. Generated once from
  the pinned encoder and **verified with an independent decoder** (Apple
  Vision `VNDetectBarcodesRequest` decoded the rendered matrix back to the
  byte-exact payload, 2026-07-07 — S8 intake §7 condition). Consumed by
  `test/pairing/qr_matrix_test.dart`; any encoder/version drift that
  changes the matrix fails the test and requires re-verification with an
  independent decoder.
