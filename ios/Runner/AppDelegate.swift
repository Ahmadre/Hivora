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

    // Hinata: PDF-Anhänge zeigen ihre Formularfelder erst, wenn wir die
    // Annotationen vorher in die Seiten zeichnen (siehe HinataPdfChannel).
    HinataPdfChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }
}
