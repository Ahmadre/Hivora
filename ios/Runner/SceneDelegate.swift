import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {

  private var didPresentSplash = false

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Hinata: den Link, mit dem die App GESTARTET wurde, an app_links übergeben.
    //
    // Diese App läuft im UIScene-Lebenszyklus (UIApplicationSceneManifest in der
    // Info.plist). Damit stellt iOS einen Kaltstart-Link NICHT über
    // `application(_:continue:restorationHandler:)` bzw. `application(_:open:options:)`
    // zu, sondern ausschließlich hier in den ConnectionOptions der Szene.
    // app_links (6.4.1) implementiert nur die alten UIApplicationDelegate-Methoden:
    // Universal Links aus E-Mails kamen deshalb an, solange die App schon lief
    // (`scene(_:continue:)`), beim Kaltstart aber nie — `getInitialLink()` lieferte
    // null und die App blieb auf dem Dashboard stehen.
    //
    // `handleLink` ist genau dafür öffentlich (siehe `getLink(launchOptions:)` im
    // Plugin: "Allow to capture links when apps also override application
    // callbacks"). Es setzt nur `initialLink`; ein Event kann es hier nicht
    // doppelt feuern, weil der Dart-Isolate noch gar nicht läuft und damit noch
    // kein EventSink registriert ist. Die warmen Pfade fasst diese Klasse
    // bewusst nicht an — die funktionieren bereits über Flutters Fallback auf die
    // alten Delegate-Methoden, und ein zweiter Aufruf würde dort doppelt routen.
    captureLaunchLink(connectionOptions)

    // Hinata: native Splash-Animation über dem Flutter-View starten.
    // WICHTIG: Unter Flutter 3.44 ist self.window in willConnectTo noch versteckt
    // (hidden = YES) und wird erst danach key & visible gemacht. Hängt man das
    // Overlay sofort an dieses Fenster, bleibt es unsichtbar (man sieht nur das
    // statische LaunchScreen-Storyboard). Deshalb warten wir per Runloop auf ein
    // sichtbares Fenster und präsentieren erst dann.
    presentSplashWhenWindowVisible(scene, attempt: 0)
  }

  /// Reicht den Link weiter, mit dem die Szene verbunden wurde: einen Universal
  /// Link (`https://connect.hinata.ahmadre.com/l/…` aus einer E-Mail) oder ein
  /// eigenes Schema (`hinata://…`). Nur der erste zählt — die App kann nur an
  /// eine Stelle springen.
  private func captureLaunchLink(_ options: UIScene.ConnectionOptions) {
    for activity in options.userActivities
    where activity.activityType == NSUserActivityTypeBrowsingWeb {
      if let url = activity.webpageURL {
        AppLinks.shared.handleLink(url: url)
        return
      }
    }
    if let context = options.urlContexts.first {
      AppLinks.shared.handleLink(url: context.url)
    }
  }

  private func presentSplashWhenWindowVisible(_ scene: UIScene, attempt: Int) {
    guard !didPresentSplash else { return }
    let windowScene = scene as? UIWindowScene
    let candidates = windowScene?.windows ?? []
    // Nur ein wirklich sichtbares Fenster akzeptieren (keyWindow allein genügt nicht –
    // es kann hidden = YES sein).
    let host = candidates.first(where: { $0.isKeyWindow && !$0.isHidden })
      ?? candidates.first(where: { !$0.isHidden })

    if let host = host {
      didPresentSplash = true
      HinataSplashView.present(in: host)
    } else if attempt < 240 {
      // Noch kein sichtbares Fenster – im nächsten Runloop-Durchlauf erneut versuchen.
      DispatchQueue.main.async { [weak self] in
        self?.presentSplashWhenWindowVisible(scene, attempt: attempt + 1)
      }
    }
  }
}
