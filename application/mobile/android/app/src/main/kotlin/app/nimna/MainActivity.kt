package app.nimna

import android.app.Activity
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity): BiometricPrompt — the S13
// app-lock biometric path via local_auth — requires a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    // app.nimna/screenshot — the FIRST custom Android channel (S14, spec §5.2).
    // Detect-and-notify only: NO FLAG_SECURE (USER-settled, DECISIONS
    // 2026-07-07 — the promise stays identical on both platforms), NO extra
    // permissions, NO ContentObserver, NO screenshots-folder watching. A
    // screenshot is a system event, not a file we read.
    //
    // Floor (USER 2026-07-07): Android 14+ (SDK_INT >= 34) via
    // Activity.registerScreenCaptureCallback. On Android 10–13 there is NO
    // notice — the honest gap, disclosed in onboarding copy. Registered only
    // between Dart `start`/`stop` (chat screen mounted = content on screen) AND
    // unregistered on pause / re-registered on resume, per USER.
    private var screenshotChannel: MethodChannel? = null
    private var captureWanted = false

    // Typed Any? so the API-34-only ScreenCaptureCallback class is never
    // referenced in a field descriptor loaded on older devices.
    private var captureCallback: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.nimna/screenshot",
        )
        screenshotChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    captureWanted = true
                    registerCaptureCallback()
                    result.success(null)
                }
                "stop" -> {
                    captureWanted = false
                    unregisterCaptureCallback()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Re-arm if the chat screen still wants detection (unregister-on-pause).
        if (captureWanted) {
            registerCaptureCallback()
        }
    }

    override fun onPause() {
        // Unregister on pause (USER 2026-07-07): a screenshot taken while Nimna
        // is not foreground is not "content on screen inside the app".
        unregisterCaptureCallback()
        super.onPause()
    }

    private fun registerCaptureCallback() {
        // Android 10–13: NO detection floor — silently do nothing (the honest
        // gap, disclosed in copy).
        if (Build.VERSION.SDK_INT < 34) {
            return
        }
        if (captureCallback != null) {
            return
        }
        val callback = Activity.ScreenCaptureCallback {
            screenshotChannel?.invokeMethod("onScreenshot", null)
        }
        captureCallback = callback
        registerScreenCaptureCallback(mainExecutor, callback)
    }

    private fun unregisterCaptureCallback() {
        if (Build.VERSION.SDK_INT < 34) {
            return
        }
        val callback = captureCallback as? Activity.ScreenCaptureCallback ?: return
        unregisterScreenCaptureCallback(callback)
        captureCallback = null
    }
}
