# Microsoft Store — Store listing (Deutsch)

Copy-paste-Vorlage für Partner Center → hinata → Store listing – German.
Deutsche Entsprechung zu `en-us.md`; dieselben Windows-Korrekturen gelten.

**Funktionsgleich zu macOS/iOS, technisch anders gelöst — Wortlaut so lassen:**

1. **Push funktioniert, aber nicht über Firebase.** `firebase_messaging` hat
   keine Windows-Implementierung; die Windows-App registriert stattdessen eine
   **WNS-Channel-URI**, der Connect-Gateway leitet an WNS weiter. Für Nutzer
   identisch — die Formulierung der Apple-Fassung stimmt hier also.
2. **Drei Capabilities.** Das MSIX deklariert `internetClient`, `microphone` und
   `webcam` (plus das automatische `runFullTrust`). Der Berechtigungsblock unten
   entspricht exakt der Store-Anzeige „Diese App kann" — beides synchron halten,
   sobald sich eine Capability ändert.
3. **Strg + K** statt ⌘K, und **„Auf Windows"** statt „Auf dem Mac".

---

## Produktname

    hinata

## Kurzbeschreibung  (≤ 270 Zeichen — aktuell 246)

    Quelloffene, selbst gehostete Projekt- und Vorgangsverwaltung. Verbinde Hinata mit deinem eigenen Server und behalte die Arbeit deines Teams auf eigener Infrastruktur — agile Boards, Sprints, Gantt, Berichte und ein integriertes Wiki, ohne Preis pro Nutzer.

## Beschreibung

    Hinata ist ein quelloffener, selbst gehosteter Client für Projekt- und Vorgangsverwaltung. Du verbindest ihn mit deinem eigenen Hinata-Server – so bleibt die Arbeit deines Teams auf einer Infrastruktur, die du kontrollierst: ohne Preis pro Nutzer und ohne Board-Limit.

    Eine App für jeden Bildschirm: Desktop, Tablet und Smartphone teilen sich eine vollständig responsive Oberfläche, die sich über Breakpoints nach dem Goldenen Schnitt anpasst – im hellen oder dunklen Design.

    DAS KANNST DU TUN
    • Agile Boards – Drag & Drop über Spalten, WIP-Limits sowie Board-, Backlog- und Timeline-Ansicht
    • Sprints – planen, durchführen und auswerten mit Kapazität, Story Points und Burndown
    • Vorgänge – Hierarchie aus Epic → Story → Unteraufgabe, Abhängigkeiten, Labels und Archivierung
    • Gantt & Timeline – Start-/Fälligkeitsdaten, Abhängigkeiten und Live-Fortschritt
    • Berichte – Burndown, Velocity, Durchlaufzeit und Verteilungen
    • Zeiterfassung – wöchentliche Zeiten je Aktivität
    • Kommentare – Antwort-Threads, Emoji-Reaktionen und Sprachnotizen, live aktualisiert
    • Anhänge – Dateien, Fotos und Videos per Drag & Drop mit Glass-Lightbox
    • Wissensdatenbank – ein integriertes, hierarchisches Markdown-Wiki mit Smart Links
    • Befehlspalette – Strg + K-Suche über alles
    • Benachrichtigungen – in der App, per E-Mail und Push für Zuweisungen, @Erwähnungen und Fälligkeiten

    FÜR TEAMS GEMACHT
    • Projekte & Teams mit projektbezogenen Workflows, Schlüsseln und Mitgliedern
    • Anmeldung mit lokalen Zugangsdaten und optionaler Zwei-Faktor-Authentifizierung (TOTP) oder SSO (OpenID Connect, OAuth 2.0, SAML, LDAP)
    • Selbstregistrierung mit E-Mail-Bestätigung und Passwort-vergessen
    • Multi-Server: mehrere Server speichern und wechseln, jeder mit eigener sicherer Sitzung

    DEINE DATEN, DEIN SERVER
    Hinata sammelt selbst nichts. Alle Inhalte liegen auf dem Hinata-Server, mit dem du dich verbindest. Kein Tracking, keine Analyse.

    Auf Windows läuft Hinata als native Desktop-App mit dem vollen Funktionsumfang.

    Zur Anmeldung wird ein Hinata-Server benötigt. Wie du selbst hostest, erfährst du auf hinata.ahmadre.com.

    BERECHTIGUNGEN & WARUM WIR SIE BENÖTIGEN
    • Internet – um den Hinata-Server zu erreichen, mit dem du dich verbindest
    • Mikrofon – Sprachkommentare und Ton für Videos, die du anhängst
    • Kamera – ein Foto aufnehmen oder ein Video aufzeichnen, um es an einen Vorgang anzuhängen
    Wir fragen jede Berechtigung erst ab, wenn du die zugehörige Funktion zum ersten Mal nutzt.

## Neuerungen in dieser Version

Microsoft empfiehlt, das Feld bei der **ersten** Einreichung leer zu lassen.
Falls du etwas eintragen willst:

    Erste Windows-Version.

## Produktfeatures  (Aufzählung, max. 20)

    Agile Boards mit Drag & Drop und WIP-Limits
    Sprint-Planung mit Kapazität, Story Points und Burndown
    Hierarchie aus Epic → Story → Unteraufgabe mit Abhängigkeiten
    Gantt- und Timeline-Ansicht mit Live-Fortschritt
    Berichte: Burndown, Velocity, Durchlaufzeit und Verteilungen
    Wöchentliche Zeiterfassung je Aktivität
    Kommentar-Threads mit Reaktionen und Sprachnotizen
    Dateien, Fotos und Videos per Drag & Drop anhängen
    Integriertes, hierarchisches Markdown-Wiki
    Befehlspalette mit globaler Suche (Strg + K)
    Single Sign-on: OpenID Connect, OAuth 2.0, SAML, LDAP
    Zwei-Faktor-Authentifizierung (TOTP)
    Multi-Server mit getrennten sicheren Sitzungen
    Helles und dunkles Design
    Selbst gehostet – deine Daten verlassen deinen Server nicht

## Keywords  (max. 7, ≤ 40 Zeichen, ≤ 21 Wörter gesamt — hier 9)

    Projektmanagement
    Aufgabenverwaltung
    self-hosted
    agile Boards
    Sprint-Planung
    Kanban
    Open Source

## Copyright- und Markenangaben

    © 2026 com.ahmadre. Hinata ist quelloffene Software.

Wie in der englischen Fassung: bitte prüfen, ob dort dein rechtlicher Name
stehen soll — die Angabe ist öffentlich sichtbar.

## Entwickelt von

    com.ahmadre

## Felder, die LEER bleiben

| Feld | Grund |
|---|---|
| Kurztitel | nur Xbox |
| Sprachtitel | nur Xbox/Kinect |
| Xbox-Bilder | Produkt ist Desktop-only |
| Zusätzliche Lizenzbedingungen | nur bei Abweichung von den Standardbedingungen |
| Trailer | optional; benötigt zusätzlich das 16:9-Hero-Bild |

## Bilder

Identisch zur englischen Fassung — Store-Grafiken sind sprachunabhängig und
liegen in `windows/store/images/`. Auch die sechs Screenshots aus
`windows/store/screenshots/` sind für beide Listings dieselben; **deutsch ist
nur die Bildunterschrift** (`captions.json`), die App-Oberfläche auf den Bildern
ist englisch.

Hochgeladen werden sie über **Actions → „Windows listing (screenshots)"** — das
schreibt sie per Store-Submission-API in beide Sprach-Listings der offenen
Übermittlung.

**Warum die Bilder so aussehen:** Die Einreichung vom 16.08.2026 wurde nach
Richtlinie **10.1.1.3 Inaccurate Representation** abgelehnt — hochgeladen waren
die Apple-Store-Kompositionen mit MacBook-Rahmen und macOS-Ampelknöpfen.
Store-Metadaten dürfen keine fremde Plattform-UI und keine fremden Geräte
zeigen. Der aktuelle Satz zeigt die App in einem schlichten Windows-11-Fenster
(Titelleiste mit Minimieren / Maximieren / Schließen), ohne Zusatz-Logos und
ohne Werbetext — auch das verlangt Microsofts Leitfaden für die Screenshot-Slots.
Die Suchleiste muss dabei **Ctrl K** zeigen, nicht ⌘K.
