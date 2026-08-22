import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Hinata: PDF-Anhänge zeigen ihre Formularfelder erst, wenn wir die
    // Annotationen vorher in die Seiten zeichnen (siehe HinataPdfChannel).
    HinataPdfChannel.register(with: flutterViewController.engine.binaryMessenger)

    // Hinata: native Splash-Animation über dem Flutter-View
    HinataSplashView.present(over: flutterViewController.view)

    super.awakeFromNib()
  }
}
