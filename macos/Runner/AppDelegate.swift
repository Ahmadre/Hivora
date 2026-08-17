import Cocoa
import FlutterMacOS
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Universal Links (`https://connect.hinata.ahmadre.com/l/…` aus einer E-Mail).
  ///
  /// app_links 6.4.1 hat seine macOS-Implementierung dieser Methode auskommentiert
  /// (siehe `AppLinksMacosPlugin.swift`) — auf dem Mac kam ein Universal Link
  /// deshalb NIE in Dart an, weder beim Kaltstart noch bei laufender App. Nur das
  /// eigene Schema `hinata://` funktionierte, das geht über den AppleEvent-Handler
  /// des Plugins.
  ///
  /// Wir nehmen den Link also selbst entgegen und geben ihn an das Plugin weiter.
  /// `handleLink` ist genau dafür öffentlich: läuft die App schon, feuert es das
  /// Stream-Event; beim Kaltstart (noch kein EventSink) merkt es sich den Link als
  /// `initialLink`, den Dart dann über `getInitialLink()` abholt.
  ///
  /// `FlutterAppDelegate` implementiert diese Methode nicht (es leitet nur die
  /// Callbacks aus `FlutterAppLifecycleDelegate` weiter, und `continueUserActivity`
  /// gehört nicht dazu) — deshalb steht hier kein `override`.
  func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return false
    }
    AppLinks.shared.handleLink(link: url.absoluteString)
    return true
  }
}
