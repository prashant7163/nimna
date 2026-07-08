/// On-device sensitive-content analysis (spec §5.3; S14). Runs the platform's
/// LOCAL nudity check to make a purely LOCAL display decision — recipient-side
/// blur and sender-side whisper. It has a hard boundary: nothing is ever
/// blocked, logged, reported, or transmitted; the sender is NEVER told of
/// recipient-side flags; there are NO network calls. Our safety features can't
/// phone home — they have nowhere to call.
///
/// Platform floor (CODE decision, 2026-07-07): iOS 17 `SensitiveContentAnalysis`
/// only. Android has no first-party on-device equivalent and bundling an ML
/// model is rejected on minimal-deps grounds — so Android returns `false`
/// (no blur, no whisper) at launch, the pre-approved iOS-only fallback (spec
/// §5.3, plan S14).
///
/// FAIL-OPEN by contract: a miss, an unavailable framework, a non-iOS platform,
/// or ANY error means [isSensitive] returns `false` (no blur). This is display
/// sugar, not security — a false negative shows an un-blurred image, never a
/// leak. The interface is injectable so the recipient-blur and whisper wiring
/// is provable headlessly (a real analysis needs a device — the S18 rung).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Decides whether a decoded image looks sensitive. Returns `true` ONLY on a
/// positive on-device flag; every other outcome is `false` (fail-open).
abstract class SensitiveContentAnalyzer {
  Future<bool> isSensitive(Uint8List imageBytes);
}

/// The always-`false` analyzer — the Android-at-launch behaviour and a safe
/// default anywhere the platform check is unavailable. No blur, no whisper.
class NoOpSensitiveContentAnalyzer implements SensitiveContentAnalyzer {
  const NoOpSensitiveContentAnalyzer();

  @override
  Future<bool> isSensitive(Uint8List imageBytes) async => false;
}

/// The production analyzer: an iOS-17-only [MethodChannel] to the
/// `SensitiveContentAnalysis` bridge in `AppDelegate.swift`. On any non-iOS
/// platform it never touches the channel and returns `false`; on iOS an
/// unavailable framework, a decode miss, or a thrown error also returns
/// `false` (fail-open, §5.3). The image bytes stay on-device — the bridge
/// analyses locally and returns only a boolean; nothing leaves the phone.
class PlatformSensitiveContentAnalyzer implements SensitiveContentAnalyzer {
  PlatformSensitiveContentAnalyzer({MethodChannel? channel, bool? isIOS})
    : _channel = channel ?? const MethodChannel('app.nimna/sensitive'),
      _isIOS = isIOS ?? Platform.isIOS;

  final MethodChannel _channel;
  final bool _isIOS;

  @override
  Future<bool> isSensitive(Uint8List imageBytes) async {
    // iOS-only at launch (CODE decision): Android has no analysis, so never
    // touch the channel there — it returns false = no blur, no whisper.
    if (!_isIOS) {
      return false;
    }
    try {
      final flagged = await _channel.invokeMethod<bool>('analyze', {
        'bytes': imageBytes,
      });
      return flagged ?? false;
    } on PlatformException {
      // Framework unavailable (< iOS 17), a decode miss, or an analysis error
      // — fail open to no blur. This is display sugar, not security.
      return false;
    } on MissingPluginException {
      // No native handler on this build — no analysis available.
      return false;
    }
  }
}
