# Manual Steps Report — Release 7.0.0+72 (2026-08-02)
Erkannte Plattformen: android, ios, macos, windows
App-Locales: nicht erkannt — prüfen!

## Pipeline-Status (automatisiert)
- Android Fastlane: ✅ vorhanden
- iOS Fastlane: ✅ vorhanden
- macOS Fastlane: ✅ vorhanden
- Permission-Register: ✅
- ⚠️ Berechtigungen seit letztem Release geändert: associated_domains, camera, files_read, internet, media_location, microphone, network_client, notifications, photo_library, run_full_trust, secure_storage — Data-Safety-Formular & Privacy Labels MÜSSEN aktualisiert werden (Items unten).

## Google Play (Play Console) — manuell
- [ ] **Data-Safety-Formular prüfen/aktualisieren** — Play Console → Richtlinie → App-Inhalte → Datensicherheit
      _Warum:_ Muss exakt zu erhobenen Daten & Berechtigungen passen; Abweichung = Ablehnung/Sperrung.
- [ ] **Formular zur Erklärung sensibler Berechtigungen (falls zutreffend)** — Play Console → Release-Review nach AAB-Upload
      _Warum:_ SMS/Anrufliste/All-Files/Accessibility usw. erfordern genehmigte Begründung.
- [ ] **IARC-Altersfreigabe-Fragebogen aktuell halten** — Play Console → App-Inhalte → Altersfreigaben
      _Warum:_ Ohne Einstufung droht Entfernung; bei Inhaltsänderungen erneut ausfüllen.
- [ ] **Zielgruppe-, Werbe-, ggf. News-/Finanz-Erklärungen** — Play Console → App-Inhalte
      _Warum:_ Pflichtdeklarationen; falsche Angaben sind Policy-Verstöße.
- [ ] **App-Zugriff: Test-Credentials hinterlegen (bei Login-Gate)** — Play Console → App-Inhalte → App-Zugriff
      _Warum:_ Reviewer müssen alle Bereiche erreichen, sonst Ablehnung.
- [ ] **Produktions-Rollout final freigeben (Release ist als Draft hochgeladen)** — Play Console → Produktion → Release bearbeiten → Einführen
      _Warum:_ Bewusstes Vier-Augen-Gate: supply lädt als Draft, Mensch veröffentlicht.

## Apple (App Store Connect) — manuell
- [ ] **Privacy Nutrition Labels bestätigen/aktualisieren** — App Store Connect → App → App-Datenschutz
      _Warum:_ Nicht per deliver setzbar; muss Netzwerk-/Datenrealität entsprechen (Guideline 5.1).
- [ ] **Altersfreigabe-Fragebogen** — App Store Connect → App-Informationen
      _Warum:_ Pflicht bei Erstrelease und Inhaltsänderungen.
- [ ] **Preis & Verfügbarkeit, ggf. IAP/Abos konfigurieren** — App Store Connect → Preise und Verfügbarkeit / In-App-Käufe
      _Warum:_ IAP-Setup ist nicht sinnvoll automatisierbar; Review verlangt eingereichte IAPs.
- [ ] **Review-Notizen & Demo-Account verifizieren** — App Store Connect → Version → App-Review-Informationen
      _Warum:_ Login-Gates ohne funktionierende Demo-Credentials = Guideline-2.1-Ablehnung.
- [ ] **Export-Compliance-Status prüfen** — App Store Connect → Version
      _Warum:_ Nur nötig falls ITSAppUsesNonExemptEncryption nicht im Info.plist gesetzt ist.
- [ ] **Zur Prüfung einreichen (submit_for_review ist bewusst false)** — App Store Connect → Version → Zur Prüfung senden
      _Warum:_ Menschliches Freigabe-Gate nach Sichtung von Metadaten/Screenshots.

## Microsoft Store (Partner Center) — manuell
- [ ] **Store-Listing pro Sprache pflegen + Submission anstoßen** — Partner Center → App → Store-Eintrag / Neue Übermittlung
      _Warum:_ Solange die Submission API nicht angebunden ist, ist der Upload manuell.
- [ ] **Altersfreigaben (IARC) & Datenschutz-URL** — Partner Center → Eigenschaften
      _Warum:_ Pflichtangaben; Capabilities werden Nutzern angezeigt und müssen erklärbar sein.

## Abschluss
- [ ] **Nach Veröffentlichung: Berechtigungs-Snapshot aktualisieren** — `python3 scripts/release_readiness_report.py --snapshot` bzw. Snapshot-Datei committen
      _Warum:_ Damit der nächste Report Berechtigungsänderungen korrekt erkennt.

