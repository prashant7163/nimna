import Flutter
import SensitiveContentAnalysis
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UNUserNotificationCenterDelegate
{
  /// The screenshot channel and its notification observer (S14, spec §5.2).
  private var screenshotChannel: FlutterMethodChannel?
  private var screenshotObserver: NSObjectProtocol?
  /// app.nimna/push — the S15 push glue channel. Held so the OS-side
  /// callbacks (token registration, rotation, tap) can push events to Dart.
  private var pushChannel: FlutterMethodChannel?
  /// The pending `registerForToken` reply, fulfilled by the APNs
  /// registration delegate callback (async round-trip).
  private var pendingTokenResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Own the notification-center delegate so foreground banners are
    // suppressed (in-app suppression) and taps route to Dart.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerStorageChannel(with: engineBridge.pluginRegistry)
    registerScreenshotChannel(with: engineBridge.pluginRegistry)
    registerSensitiveChannel(with: engineBridge.pluginRegistry)
    registerPushChannel(with: engineBridge.pluginRegistry)
  }

  /// app.nimna/push — NATIVE APNs, no SDK (USER decision 1, SESSION-15):
  /// `UNUserNotificationCenter` + `registerForRemoteNotifications`, pure
  /// Apple. `registerForToken` asks the OS for permission then registers,
  /// replying with the RAW 32-byte device token (the relay hex-encodes it
  /// into `/3/device/<hex>`), or nil on denial/failure (the line then rides
  /// burner mode). No notification content is ever read — the only body that
  /// ships is the OS-localised "New activity" from NEW_ACTIVITY.
  private func registerPushChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "app.nimna.push") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.nimna/push",
      binaryMessenger: registrar.messenger()
    )
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "registerForToken":
        self.requestAndRegister(result: result)
      case "setForeground":
        // Foreground state is informational; suppression is enforced in
        // willPresent regardless. Acknowledge and move on.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestAndRegister(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, _ in
      guard granted else {
        result(nil)
        return
      }
      DispatchQueue.main.async {
        self.pendingTokenResult = result
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let payload = FlutterStandardTypedData(bytes: deviceToken)
    if let pending = pendingTokenResult {
      pendingTokenResult = nil
      pending(payload)
    } else {
      // An OS-initiated rotation (no pending acquire) — hand it up so the
      // live session re-announces the fresh address.
      pushChannel?.invokeMethod("onTokenRotated", arguments: payload)
    }
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    if let pending = pendingTokenResult {
      pendingTokenResult = nil
      pending(nil)  // burner mode: registration failed, no token
    }
  }

  // Foreground: show NO OS banner — in-app suppression (§3.2.1). The body is
  // only "New activity"; there is nothing to surface while the app is open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  // Tap → content-free open event (tap → open → reconnect). No payload read.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    pushChannel?.invokeMethod("onNotificationTap", arguments: nil)
    completionHandler()
  }

  /// app.nimna/storage — hand-written platform glue (app-architecture.md §7):
  /// no dependency exists for a URLResourceValues write. Sets/reads/clears
  /// `isExcludedFromBackup` on the store root; set at store-root creation and
  /// re-asserted every launch, because the attribute is filesystem metadata
  /// that restores/migrations can drop. `clear` exists only for the §7.3
  /// re-assert integration proof.
  private func registerStorageChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "app.nimna.storage") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.nimna/storage",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "expected {path: String}",
            details: nil
          )
        )
        return
      }
      var url = URL(fileURLWithPath: path)
      do {
        switch call.method {
        case "setExcludedFromBackup":
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          result(true)
        case "clearExcludedFromBackup":
          var values = URLResourceValues()
          values.isExcludedFromBackup = false
          try url.setResourceValues(values)
          result(true)
        case "isExcludedFromBackup":
          let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
          result(values.isExcludedFromBackup ?? false)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(
          FlutterError(
            code: "resource_values_failed",
            message: "URLResourceValues operation failed",
            details: nil
          )
        )
      }
    }
  }

  /// app.nimna/screenshot — detect-and-notify (spec §5.2). Observes
  /// `UIApplication.userDidTakeScreenshotNotification` (iOS ≥ 17 floor per
  /// USER 2026-07-07; the notification predates 17 but Nimna gates the feature
  /// there) ONLY between `start` and `stop`, which Dart calls as the chat
  /// screen mounts/unmounts — spec §5.2's "content on screen inside the app".
  /// No FLAG_SECURE analog, no prevention: the OS event is a system signal, not
  /// a file, so ZERO permissions are needed. Each capture invokes `onScreenshot`
  /// back on the channel.
  private func registerScreenshotChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "app.nimna.screenshot") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.nimna/screenshot",
      binaryMessenger: registrar.messenger()
    )
    screenshotChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.startScreenshotObserver()
        result(nil)
      case "stop":
        self?.stopScreenshotObserver()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startScreenshotObserver() {
    guard screenshotObserver == nil else { return }
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenshotChannel?.invokeMethod("onScreenshot", arguments: nil)
    }
  }

  private func stopScreenshotObserver() {
    if let observer = screenshotObserver {
      NotificationCenter.default.removeObserver(observer)
      screenshotObserver = nil
    }
  }

  /// app.nimna/sensitive — on-device sensitive-content analysis (spec §5.3),
  /// iOS-17-only (CODE decision 2026-07-07). `analyze` runs
  /// `SCSensitivityAnalyzer` LOCALLY on the passed image bytes and returns a
  /// single Bool. HARD BOUNDARY §5.3: nothing is blocked, logged, reported, or
  /// transmitted — the bytes never leave the device and the result is a local
  /// display decision only. FAIL-OPEN: a decode miss, a disabled analysis
  /// policy (the framework throws), any error, or < iOS 17 all return `false`
  /// (no blur / no whisper). No special entitlement is required.
  private func registerSensitiveChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "app.nimna.sensitive") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.nimna/sensitive",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "analyze" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let data = (args["bytes"] as? FlutterStandardTypedData)?.data
      else {
        result(false)  // Malformed call — fail open (display sugar, §5.3).
        return
      }
      if #available(iOS 17.0, *) {
        guard let image = UIImage(data: data)?.cgImage else {
          result(false)
          return
        }
        Task {
          let analyzer = SCSensitivityAnalyzer()
          do {
            let response = try await analyzer.analyzeImage(image)
            result(response.isSensitive)
          } catch {
            // Analysis disabled by the user's policy, or any failure —
            // fail open to no blur (§5.3: this is display sugar, not security).
            result(false)
          }
        }
      } else {
        result(false)  // < iOS 17: no analysis available (iOS-only-at-launch).
      }
    }
  }
}
