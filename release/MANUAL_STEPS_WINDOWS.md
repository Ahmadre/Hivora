# Microsoft Store — was NICHT automatisierbar ist

Stand: **2026-08**. Quellen unten. Alles hier Beschriebene ist einmalig; danach
läuft jede weitere Veröffentlichung über **Actions → „Publish (button)"**.

## Zwei harte Einschränkungen, bevor du anfängst

1. **Die erste Einreichung ist immer manuell.** `msstore publish` *aktualisiert*
   eine bestehende, bereits **live** veröffentlichte App. Solange es kein
   veröffentlichtes Produkt gibt, kann die CI nichts tun. Die erste Submission
   musst du in Partner Center anlegen und durch die Zertifizierung bringen.
2. **App-Updates über GitHub Actions unterstützen derzeit nur kostenlose
   Produkte.** Kostenpflichtige Apps sind laut Microsoft „in einem künftigen
   Release" vorgesehen. Ist Hinata im Store kostenpflichtig, funktioniert der
   Publish-Button für Windows nicht — dann bleibt der Upload manuell (das MSIX
   liegt trotzdem als Run-Artefakt bereit).

## 1. Partner Center einrichten

- [x] Als Windows-App-Entwickler in [Partner Center](https://storedeveloper.microsoft.com/)
      registrieren (einmalige Gebühr, Identitätsprüfung des Publishers).
- [x] App-Namen reservieren → daraus ergeben sich **Identity Name**,
      **Publisher** und **Publisher Display Name**.
- [x] Diese drei Werte in `pubspec.yaml` → `msix_config` eintragen. **Erledigt**,
      übernommen aus **App → Produktverwaltung → Produktidentität**:

      identity_name:          4hm4dr3.hinata
      publisher:              CN=0A922060-E40D-4D55-9D1D-83B9594F60E5
      publisher_display_name: 4hm4dr3

      Store ID (= Produkt-ID für die CLI): `9N5NVNPKBBLR` — steht im Fastfile,
      da öffentlich (Teil der Store-URL). Kein Secret nötig.

      **Der Store prüft zeichengenau.** Weicht auch nur einer ab, kommt beim
      Upload: „Package acceptance validation error: The PublisherDisplayName
      element … doesn't match your publisher display name".

## 2. Erste Submission (manuell, einmalig)

- [x] MSIX bauen lassen: **Actions → „Release (button)"** ausführen und das
      Artefakt `hinata-msix` herunterladen (die CI lädt bei diesem Button
      bewusst nichts hoch).
- [x] Partner Center → App → **Neue Übermittlung** → Pakete → MSIX hochladen.
- [x] **Gerätefamilien einschränken**: auf derselben Seite unter „Device family
      availability" **nur „Windows 10/11 Desktop"** angehakt lassen. Das Paket
      deklariert `TargetDeviceFamily Name="Windows.Desktop"`; bleiben Mobile,
      Xbox, Team oder Mixed Reality angehakt, blockiert Partner Center mit
      „You must provide a package that supports each selected device family".
      „Let Microsoft decide … future device families" kann angehakt bleiben.
- [x] **Store-Eintrag** je Sprache pflegen: `en-us` und `de-de` (die App liefert
      beide Locales). Beschreibung, Screenshots, Store-Logos.
- [x] **Altersfreigabe (IARC)**-Fragebogen ausfüllen.
- [x] **Datenschutz-URL** hinterlegen — Pflicht, sobald die App auf das Netz
      zugreift.
- [x] **Deklarierte Capabilities erklären**: Der Store zeigt Nutzern
      `internetClient` und `microphone` an. Begründungen stehen in
      `release/permissions.yaml` und gehören in die Store-Beschreibung.
- [x] **`runFullTrust` begründen, falls Partner Center danach fragt.** Das MSIX
      deklariert diese *restricted capability* automatisch — jede
      Win32-Flutter-App braucht sie, um überhaupt aus einem MSIX startbar zu
      sein. Begründung: „Packaged Win32 desktop application (Flutter), not UWP."
      Verifiziert im generierten `AppxManifest.xml`.
- [x] Einreichen und Zertifizierung abwarten, bis die App **live** ist.

## 3. Automatisierung freischalten

- [x] Microsoft-Entra-Tenant mit dem Partner-Center-Konto verknüpfen (bestehenden
      verknüpfen oder neu anlegen).
- [x] In Microsoft Entra ID eine **Anwendung registrieren**
      ([App registrations → New registration](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)).
- [x] [Partner Center → Kontoeinstellungen → Benutzerverwaltung](https://partner.microsoft.com/dashboard/account/v3/usermanagement)
      → **Microsoft-Entra-Anwendungen**: die App hinzufügen und ihr die Rolle
      **Manager** geben.
- [x] Client Secret erzeugen (**Wert sofort kopieren**, er wird nur einmal gezeigt).
- [x] Folgende GitHub-Repository-Secrets anlegen
      (Settings → Secrets and variables → Actions):

      | Secret | Woher (Direktlink) |
      |---|---|
      | `AZURE_AD_TENANT_ID` | [Entra → Overview](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/TenantOverview.ReactView) → Kachel **Tenant ID** (auch unter *Properties*) |
      | `AZURE_AD_APPLICATION_CLIENT_ID` | [Entra → App registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) → die App → **Application (client) ID** |
      | `AZURE_AD_APPLICATION_SECRET` | [Entra → App → Certificates & secrets](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/CLIENT_ID) — `CLIENT_ID` am Ende durch die Client-ID von oben ersetzen → **New client secret** |
      | `SELLER_ID` | [Partner Center → Kontoeinstellungen](https://partner.microsoft.com/dashboard/account/v3/settings/accountsettings) → **Publisher IDs** → *Seller ID* (Fallback: Zahnrad ↗ → Kontoeinstellungen) |

      (`MSSTORE_PRODUCT_ID` ist **kein** Secret — die Store ID steht als Default
      im Fastfile und lässt sich per Umgebungsvariable überschreiben.)

Danach veröffentlicht **„Publish (button)"** Windows vollautomatisch mit.

## 4. Push-Benachrichtigungen (WNS) scharfschalten

Firebase hat keine Windows-Implementierung, daher registriert die Windows-App
eine **WNS-Channel-URI** statt eines FCM-Tokens. Der Versand läuft über
denselben Weg wie bisher — Server → Hinata Connect (Gateway) → Push-Dienst —,
nur wählt der Gateway anhand der Token-Form zwischen FCM und WNS.

- [x] Partner Center → App → **Produktverwaltung → WNS/MPNS**: dort stehen
      **Package SID** (`ms-app://S-1-15-2-…`) und ein **Client Secret**.
      Das Secret wird nur einmal angezeigt.
- [x] Beides im **Gateway** konfigurieren (nicht im selbst gehosteten Server —
      der besitzt bewusst keine Push-Zugangsdaten):

      gateway.wns.package-sid:    ms-app://S-1-15-2-…
      gateway.wns.client-secret:  …

      Als Umgebungsvariablen: `GATEWAY_WNS_PACKAGE_SID`,
      `GATEWAY_WNS_CLIENT_SECRET`. Leere Werte lassen Windows-Push einfach
      deaktiviert; Android/iOS/macOS bleiben unberührt.
- [x] Nach dem Start prüfen: das Gateway loggt `WNS configured; Windows push is
      active.` — andernfalls `No WNS credentials configured`.

**Push funktioniert nur in der MSIX-Version.** Die Channel-Erzeugung setzt eine
Paket-Identität voraus; ein `flutter run` ohne Paket bekommt keinen Kanal und
registriert schlicht keinen — das ist kein Fehler, sondern erwartet.

**Kanäle laufen nach 30 Tagen ab.** Die App holt bei jedem Start einen frischen
und meldet ihn; abgelaufene Kanäle antworten mit HTTP 410, woraufhin der Server
sie aus der Geräteliste entfernt (dieselbe Selbstheilung wie bei toten
FCM-Tokens).

## Wozu die CI KEIN Zertifikat braucht

Store-gebundene Pakete signiert Microsoft bei der Ingestion selbst. Ein
Code-Signing-Zertifikat wäre nur für **Direktvertrieb** (MSIX außerhalb des
Stores) nötig — dann mit OV/EV-Zertifikat aus einem Cloud-HSM (z. B. Azure
Trusted Signing), niemals mit Schlüsseldatei auf dem Build-Agent.

## Versionierung

Das 4. Feld der MSIX-Version (Revision) ist vom Store **reserviert und muss 0
sein**. Die pubspec-Buildnummer (`7.0.0+72`) kann dort also nicht hin. Die
Pipeline bildet die Version als `X.Y.Z.0`; die Eindeutigkeit jeder Einreichung
kommt aus dem Versions-Bump, den „Publish (button)" ohnehin macht. Praktische
Folge: **zwei Veröffentlichungen mit derselben X.Y.Z sind nicht möglich** —
immer bumpen.

## Quellen

- [Publish app updates to Microsoft Store with GitHub Actions](https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/github-actions)
- [Package version numbering](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/package-version-numbering)
- [msix (pub.dev)](https://pub.dev/packages/msix)
