import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var timezoneChannel: FlutterMethodChannel?
  private var timezoneObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SystemTimezoneBridge") else { return }
    let channel = FlutterMethodChannel(name: "eatwise/system_timezone", binaryMessenger: registrar.messenger())
    timezoneChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "getIdentifier" {
        result(TimeZone.autoupdatingCurrent.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    if let observer = timezoneObserver { NotificationCenter.default.removeObserver(observer) }
    timezoneObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      self?.timezoneChannel?.invokeMethod("timezoneChanged", arguments: nil)
    }
  }
  deinit {
    if let observer = timezoneObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
