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

- [ ] Als Windows-App-Entwickler in [Partner Center](https://storedeveloper.microsoft.com/)
      registrieren (einmalige Gebühr, Identitätsprüfung des Publishers).
- [ ] App-Namen reservieren → daraus ergeben sich **Identity Name**,
      **Publisher** und **Publisher Display Name**.
- [ ] Diese drei Werte in `pubspec.yaml` → `msix_config` eintragen.
      **Sie müssen exakt mit Partner Center übereinstimmen**, sonst weist der
      Store das Paket zurück. Aktuell stehen dort Platzhalter:

      identity_name:          com.ahmadre.hinata
      publisher:              CN=com.ahmadre
      publisher_display_name: com.ahmadre

      Die echten Werte stehen unter **App → Produktidentität**.

## 2. Erste Submission (manuell, einmalig)

- [ ] MSIX bauen lassen: **Actions → „Release (button)"** ausführen und das
      Artefakt `hinata-msix` herunterladen (die CI lädt bei diesem Button
      bewusst nichts hoch).
- [ ] Partner Center → App → **Neue Übermittlung** → Pakete → MSIX hochladen.
- [ ] **Store-Eintrag** je Sprache pflegen: `en-us` und `de-de` (die App liefert
      beide Locales). Beschreibung, Screenshots, Store-Logos.
- [ ] **Altersfreigabe (IARC)**-Fragebogen ausfüllen.
- [ ] **Datenschutz-URL** hinterlegen — Pflicht, sobald die App auf das Netz
      zugreift.
- [ ] **Deklarierte Capabilities erklären**: Der Store zeigt Nutzern
      `internetClient` und `microphone` an. Begründungen stehen in
      `release/permissions.yaml` und gehören in die Store-Beschreibung.
- [ ] **`runFullTrust` begründen, falls Partner Center danach fragt.** Das MSIX
      deklariert diese *restricted capability* automatisch — jede
      Win32-Flutter-App braucht sie, um überhaupt aus einem MSIX startbar zu
      sein. Begründung: „Packaged Win32 desktop application (Flutter), not UWP."
      Verifiziert im generierten `AppxManifest.xml`.
- [ ] Einreichen und Zertifizierung abwarten, bis die App **live** ist.

## 3. Automatisierung freischalten

- [ ] Microsoft-Entra-Tenant mit dem Partner-Center-Konto verknüpfen (bestehenden
      verknüpfen oder neu anlegen).
- [ ] In Microsoft Entra ID eine **Anwendung registrieren**.
- [ ] Partner Center → Kontoeinstellungen → Benutzerverwaltung → **Microsoft-Entra-
      Anwendungen**: die App hinzufügen und ihr die Rolle **Manager** geben.
- [ ] Client Secret erzeugen (**Wert sofort kopieren**, er wird nur einmal gezeigt).
- [ ] Folgende GitHub-Repository-Secrets anlegen
      (Settings → Secrets and variables → Actions):

      | Secret | Woher |
      |---|---|
      | `AZURE_AD_TENANT_ID` | Entra → Identity → Overview → Tenant ID |
      | `AZURE_AD_APPLICATION_CLIENT_ID` | Entra → App registrations → Application (client) ID |
      | `AZURE_AD_APPLICATION_SECRET` | Entra → App registration → Certificates & secrets |
      | `SELLER_ID` | Partner Center → Account settings → Publisher/Seller ID |
      | `MSSTORE_PRODUCT_ID` | Partner Center → App → Produktidentität → Store-Produkt-ID |

Danach veröffentlicht **„Publish (button)"** Windows vollautomatisch mit.

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
