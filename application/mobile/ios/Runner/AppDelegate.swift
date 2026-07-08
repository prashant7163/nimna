import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UNUserNotificationCenterDelegate
{
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
}
