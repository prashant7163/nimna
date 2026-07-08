/// Local screenshot detection (spec §5.2, §5.5; S14). Detect-and-notify only:
/// Nimna cannot PREVENT a screenshot and never pretends to (no FLAG_SECURE, no
/// blocking) — it only NOTICES one taken while session content is on screen
/// inside the app, so the peer can always be told (voice string 11/12).
///
/// Platform floor (USER, 2026-07-07):
///   • iOS 17     — `UIApplicationUserDidTakeScreenshotNotification`.
///   • Android 14+ — `Activity.registerScreenCaptureCallback` (SDK_INT ≥ 34).
///   • Android 10–13 — NO notice, disclosed honestly (voice caveat string).
/// ZERO extra permissions: no media-read grant, no ContentObserver, no
/// screenshots-folder watching — a screenshot is a system event, not a file we
/// read.
///
/// The "content on screen inside the app" gate is a UI-lifecycle concern: the
/// chat screen [start]s the observer only while it is mounted and [stop]s it on
/// dispose, and the session controller additionally gates emission on liveness.
/// Detection is HEADLESS-untestable (a real capture needs a device — the S18
/// rung); the interface is injectable so the Dart wiring is provable with a
/// fake.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Emits an event each time the OS reports a screenshot while [start]ed.
/// Injectable (a fake drives the widget/controller wiring headlessly).
abstract class ScreenshotDetector {
  /// Fires once per detected screenshot. Broadcast: the chat screen is the
  /// only subscriber and it (dis)connects with its own lifecycle.
  Stream<void> get onScreenshot;

  /// Begins native observation (adds the notification observer / registers the
  /// capture callback). Idempotent. Called when session content comes on
  /// screen.
  Future<void> start();

  /// Ends native observation (removes the observer / unregisters the callback).
  /// Idempotent. Called when session content leaves the screen.
  Future<void> stop();

  /// Releases the stream. After this the detector is inert.
  Future<void> dispose();
}

/// The production detector: a [MethodChannel] to the native shims
/// (`AppDelegate.swift` on iOS, `MainActivity.kt` on Android). Native invokes
/// `onScreenshot` on this channel; Dart invokes `start`/`stop` to (un)register.
/// On a platform with no detection floor (Android 10–13) the native `start` is
/// a no-op and `onScreenshot` simply never fires — the honest gap.
class PlatformScreenshotDetector implements ScreenshotDetector {
  PlatformScreenshotDetector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.nimna/screenshot') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get onScreenshot => _controller.stream;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onScreenshot' && !_controller.isClosed) {
      _controller.add(null);
    }
    return null;
  }

  @override
  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on PlatformException {
      // A platform without the observer (or a transient failure) simply yields
      // no notices — never surfaced, never an error to the user (silence).
    } on MissingPluginException {
      // No native handler on this platform/build — detection is unavailable.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Best-effort teardown; nothing to surface.
    } on MissingPluginException {
      // No native handler — nothing to stop.
    }
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }
}
