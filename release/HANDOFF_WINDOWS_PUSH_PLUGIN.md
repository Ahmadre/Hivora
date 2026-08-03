# Windows-Push als eigenständiges Flutter-Plugin auslösen

## Ausgangslage

In `hinata-app` ist WNS-Push für Windows vollständig implementiert und im Betrieb
verifiziert: Kanal-Registrierung, Versand über den Connect-Gateway, Toast-Klick
mit Deep-Link-Routing (warm und kalt). Der plattformnahe Teil davon ist nicht
Hinata-spezifisch — er löst ein Problem, das **jede** Flutter-Windows-App mit
serverseitig ausgelösten Benachrichtigungen hat.

Auf pub.dev existiert dafür **kein** Paket. Vorhanden sind nur
`flutter_local_notifications_windows` und `windows_notification`; beide zeigen
**lokale**, von der App selbst ausgelöste Toasts an. Keines holt einen
WNS-Kanal oder empfängt serverseitig ausgelöste Nachrichten.

`firebase_messaging` deklariert android/ios/macos/web — Windows fehlt, und das
ist der Grund, warum es diesen Weg überhaupt braucht.

## Ziel

Den plattformnahen Teil als wiederverwendbares Plugin herauslösen und auf
pub.dev veröffentlichen. Hinata konsumiert es danach wie jedes andere Paket.

## Was ins Plugin gehört

| Heute in hinata-app | Zweck |
|---|---|
| `windows/cmake/WindowsAppSDK.cmake` | Windows App SDK per NuGet holen, C++/WinRT-Projektion aus den `.winmd` erzeugen, als CMake-Target bereitstellen |
| `windows/runner/wns_channel.cpp/.h` | Kanal anfordern, Aktivierung empfangen, Deep-Link an Dart reichen |
| `tool/patch_msix_manifest.dart` | COM-Aktivatoren + Framework-Abhängigkeit ins generierte AppxManifest injizieren |
| `lib/core/notifications/wns_channel.dart` | Dart-API: `getChannelUri`, `listenForDeepLinks`, `initialDeepLink` |

## Was Anwendungssache bleibt

- Registrierung der Kanal-URI beim eigenen Backend
- Der Versand selbst (bei uns: `WnsService` im `hinata-gateway`)
- Routing des Deep-Links in der App
- Das Toast-XML-Format

## Erkenntnisse, die Zeit gekostet haben

Diese Punkte sind der eigentliche Wert des Vorhabens — sie stehen in keiner
zusammenhängenden Anleitung.

**cppwinrt-Version muss zur Windows-SDK-Version passen.** Wir erzeugen nur die
App-SDK-Namespaces, nicht die ganze Projektion; `winrt/base.h` kommt daher aus
dem Windows SDK. Ein neuerer Generator erzeugt Header, deren `static_assert`
die ältere `base.h` mit „Mismatched C++/WinRT headers" ablehnt. Windows Kits
10.0.26100.0 liefert `CPPWINRT_VERSION 2.0.250303.1`. Ein Plugin sollte die
SDK-Version **auslesen**, nicht pinnen.

**Nicht den ganzen Metadaten-Ordner an cppwinrt geben.**
`Microsoft.Security.Authentication.OAuth` verweist auf `Microsoft.UI.WindowId`
aus dem WinUI-Paket. Nur die benötigten Namespaces als `-input`, den Rest als
`-reference`.

**Zwei COM-Aktivatoren, nicht einer.** `----WindowsAppRuntimePushServer:` lässt
WNS die App zum **Zustellen** starten. Für den **Klick** braucht es zusätzlich
`windows.toastNotificationActivation` mit einer `ToastActivatorCLSID` und einen
zweiten COM-Server mit `----AppNotificationActivated:` und derselben CLSID.
`AppNotificationManager.Register()` im Code genügt **nicht** — die Zuordnung
Shell → App passiert ausschließlich über die Manifest-CLSID.

**Reihenfolge in `<Dependencies>` ist schema-fest.** `TargetDeviceFamily` vor
`PackageDependency`, sonst lehnt `makeappx` mit `0x80080204` ab. `MinVersion`
muss eine echte Version sein; `0.0.0.0` wird abgelehnt.

**Kaltstart braucht Pufferung.** Die Aktivierung feuert, bevor die Dart-Engine
läuft. Der Puffer darf erst geleert werden, wenn Dart die Zustellung
**quittiert** — eine Engine ohne Handler antwortet `NotImplemented`, dann holt
`getInitialDeepLink` den Link nach. Wird der Puffer beim Senden geleert, geht
genau der Kaltstart verloren, also der häufigste Fall.

**`Argument()`, nicht `Arguments()`.** Das `launch`-Attribut ist ein roher
String. `Arguments()` parst ihn als `key=value` und liefert bei einem Pfad den
ganzen Pfad als Schlüssel mit leerem Wert.

**`MethodResult` darf nicht vom Hintergrund-Thread abgeschlossen werden.** Die
WinRT-Callbacks laufen off-thread; wir marshalen über eine `WM_APP`-Nachricht
zurück auf den Platform-Thread.

**Das `msix`-Paket hat keinen Hook für eigenes Manifest-XML** — aber es trennt
`msix:build` und `msix:pack`. Dazwischen lässt sich die generierte
`AppxManifest.xml` patchen. Ohne diese Trennung müsste man das Paket forken.

**Stale-Build-Falle.** Wechselt man im selben Build-Verzeichnis zwischen
`--debug` und `--release`, kann der Dart-AOT-Snapshot neu erzeugt, aber **nicht
ins Release-Verzeichnis kopiert** werden. Der C++-Runner ist dann frisch, der
Dart-Code stundenalt. Symptom: native Änderungen wirken, Dart-Änderungen nicht.
Prüfen mit einem Zeitstempel-Vergleich von `Release/data/app.so` gegen die
Quelldateien.

## Voraussetzungen auf Betreiberseite

- Ein **Entra-Verzeichnis**. Ein reines Microsoft-Konto ohne Verzeichnis kann
  seit 2026 keine App-Registrierung mehr anlegen.
- App-Registrierung als **multi-tenant**. Eine MSA-only-Registrierung bekommt
  nie ein WNS-Token: die Tenant-Endpunkte lehnen sie ab (`AADSTS9002331`), und
  `/consumers` lehnt WNS als Ziel ab (`AADSTS9002332`).
- Der klassische Package-SID-Flow ist **tot**:
  `login.live.com/accesstoken.srf` antwortet „Client credential flows against
  login.live.com are no longer supported."
- Das in Microsofts Doku beschriebene **PFN-Mapping per E-Mail war nicht
  nötig** — Push funktionierte ohne. Die Adresse
  `Win_App_SDK_Push@microsoft.com` weist externe Absender zudem mit
  `550 5.4.1 Access denied` ab.

## Offene Punkte vor einer Veröffentlichung

- [ ] Auf einer **zweiten Maschine** verifizieren (bisher nur eine Konstellation)
- [ ] Verhalten **ohne Paket-Identität** definieren (aktuell: liefert `null`)
- [ ] Abhängigkeit vom `msix`-Paket klären — der Manifest-Patcher setzt dessen
      `build`/`pack`-Trennung voraus. Alternativen für andere Packaging-Wege?
- [ ] **Framework-abhängig vs. self-contained** entscheiden und dokumentieren
- [ ] cppwinrt-Version zur Laufzeit aus dem installierten Windows SDK ermitteln
      statt sie zu pinnen
- [ ] Beispiel-App mit minimalem Server-Stub
- [ ] Namensfindung und Abgrenzung zu `flutter_local_notifications_windows`

## Abnahmekriterien

- [ ] Eine frische Flutter-Windows-App bekommt mit dem Plugin eine Kanal-URI
- [ ] Toast-Klick routet bei **laufender und geschlossener** App
- [ ] Unverpackter Build startet und meldet sauber „nicht verfügbar"
- [ ] MSIX besteht die Store-Validierung

## Referenzen

- Umsetzung: `hinata-app`, Commits zum Windows-Push (August 2026)
- [WNS overview](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/wns-overview)
- [Push notifications quickstart (Windows App SDK)](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/push-quickstart)
- [App notifications quickstart](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-quickstart)
