import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';
import 'package:nimna/src/protocol/outer_frame.dart';

/// §18-C property/random-bytes fuzz of the §5.4 outer-frame and §5.5–§5.8
/// inner-envelope decoders. Existing coverage is entirely hand-enumerated
/// negatives; this feeds large batches of random + structured-random bytes and
/// asserts two invariants the frozen codec must uphold on arbitrary input:
///
///   1. decode NEVER throws anything but its own typed error
///      ([OuterFrameError] / [InnerEnvelopeError]) — no RangeError, no
///      FormatException, no StateError, no hang/unbounded allocation;
///   2. anything ACCEPTED round-trips byte-identically through encode
///      (the decoder canonicalizes nothing it later re-emits differently).
///
/// Deterministic: a fixed SEED is recorded so any failure reproduces exactly.
void main() {
  // Recorded seed — change only to widen the search; a failure prints it.
  const seed = 0x0DDF00D;
  const iterations = 20000;

  /// A byte length skewed toward the small sizes where the header/optional
  /// fields live, with an occasional larger draw to exercise bodies.
  int drawLen(Random rng) {
    final r = rng.nextInt(100);
    if (r < 70) return rng.nextInt(48); // around the headers
    if (r < 95) return rng.nextInt(300);
    return rng.nextInt(70000); // large bodies (also > outer header, < absurd)
  }

  Uint8List randomBytes(Random rng, int len) {
    final b = Uint8List(len);
    for (var i = 0; i < len; i++) {
      b[i] = rng.nextInt(256);
    }
    return b;
  }

  test('outer-frame decode: only OuterFrameError, and accepted ⇒ '
      'byte-identical round trip', () {
    final rng = Random(seed);
    var accepted = 0;
    for (var it = 0; it < iterations; it++) {
      final bytes = randomBytes(rng, drawLen(rng));
      // Bias a good fraction toward structurally-plausible frames so the
      // fuzzer reaches past the header gate (valid version + valid type byte).
      if (rng.nextBool() && bytes.length >= outerHeaderBytes) {
        bytes[0] = protocolVersion;
        bytes[1] = FrameType.values[rng.nextInt(FrameType.values.length)].wire;
      }
      OuterFrame decoded;
      try {
        decoded = OuterFrame.decode(bytes);
      } on OuterFrameError {
        continue; // the only permitted rejection
      } catch (e, st) {
        fail(
          'outer decode threw ${e.runtimeType} (seed=$seed it=$it): $e\n$st',
        );
      }
      accepted++;
      expect(
        decoded.encode(),
        bytes,
        reason: 'accepted frame must re-encode identically (seed=$seed it=$it)',
      );
    }
    // The biased stream must actually reach the accept path (guards a fuzzer
    // that only ever hits the reject gate — a vacuous pass).
    expect(accepted, greaterThan(0));
  });

  test('inner-envelope decode: only InnerEnvelopeError, and accepted ⇒ '
      'byte-identical round trip', () {
    final rng = Random(seed ^ 0x5155);
    var accepted = 0;
    for (var it = 0; it < iterations; it++) {
      final bytes = randomBytes(rng, drawLen(rng));
      if (rng.nextBool() && bytes.length >= baseHeaderBytes) {
        // Plausible header: valid version, a real type, low/zeroed flags.
        bytes[0] = innerVersion;
        bytes[1] = InnerType.values[rng.nextInt(InnerType.values.length)].wire;
        bytes[2] = rng.nextInt(8); // only the three defined flag bits
      }
      InnerEnvelope decoded;
      try {
        decoded = InnerEnvelope.decode(bytes);
      } on InnerEnvelopeError {
        continue; // the only permitted rejection
      } catch (e, st) {
        fail(
          'inner decode threw ${e.runtimeType} (seed=$seed it=$it): $e\n$st',
        );
      }
      accepted++;
      expect(
        decoded.encode(),
        bytes,
        reason:
            'accepted envelope must re-encode identically (seed=$seed '
            'it=$it)',
      );
    }
    expect(accepted, greaterThan(0));
  });
}
