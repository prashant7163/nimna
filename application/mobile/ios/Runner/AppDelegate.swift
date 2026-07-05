import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerStorageChannel(with: engineBridge.pluginRegistry)
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
