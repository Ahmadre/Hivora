# Microsoft Store — Store listing (Deutsch)

Copy-paste-Vorlage für Partner Center → hinata → Store listing – German.
Deutsche Entsprechung zu `en-us.md`; dieselben Windows-Korrekturen gelten.

**Dieses Listing beschreibt eine Windows-App und sonst nichts.** Die
Zertifizierung 10.1.4.3 ist einmal an Text gescheitert, der aus der
Apple-Fassung stammte. Also: keine andere Plattform, kein Gerät außer dem
Windows-Desktop und keine Formulierung „auf Windows … genauso" — ein Vergleich
nennt implizit die Plattform, mit der verglichen wird. Alles Folgende ist so
geschrieben, als gäbe es Hinata nur für Windows.

1. **Push funktioniert, aber nicht über Firebase.** `firebase_messaging` hat
   keine Windows-Implementierung; die Windows-App registriert stattdessen eine
   **WNS-Channel-URI**, der Connect-Gateway leitet an WNS weiter. Für Nutzer
   identisch — das ist ein Build-Detail und gehört nicht in den Listing-Text;
   dort steht nur, dass Benachrichtigungen funktionieren.
2. **Drei Capabilities.** Das MSIX deklariert `internetClient`, `microphone` und
   `webcam` (plus das automatische `runFullTrust`). Der Berechtigungsblock unten
   entspricht exakt der Store-Anzeige „Diese App kann" — beides synchron halten,
   sobald sich eine Capability ändert.
3. **Strg + K** statt ⌘K — im Text wie in den Screenshots.

---

## Produktname

    hinata

## Kurzbeschreibung  (≤ 270 Zeichen — aktuell 246)

    Quelloffene, selbst gehostete Projekt- und Vorgangsverwaltung. Verbinde Hinata mit deinem eigenen Server und behalte die Arbeit deines Teams auf eigener Infrastruktur — agile Boards, Sprints, Gantt, Berichte und ein integriertes Wiki, ohne Preis pro Nutzer.

## Beschreibung

**Quelle der Wahrheit: `windows/store/listing.json`** — genau dieser Text wird
hochgeladen, deshalb steht er hier nicht doppelt. Dort lesen, dort ändern.

**Keine fremde Plattform im Text.** Die Zertifizierung **10.1.4.3 App Quality –
Description** ist am 17.08.2026 in beiden Sprach-Listings an zwei Resten aus der
Apple-Fassung gescheitert:

- *„Eine App für jeden Bildschirm: Desktop, Tablet und Smartphone …"* — beschreibt
  Geräte, für die es die App hier nicht gibt; das Paket zielt nur auf
  `Windows.Desktop`.
- *„Auf Windows läuft Hinata als native Desktop-App mit dem vollen
  Funktionsumfang."* — „auf Windows … voller Funktionsumfang" liest sich als
  Vergleich mit einer anderen Plattform.

Die Neufassung sagt dasselbe ohne Vergleich: eine native Windows-Desktop-App,
die sich vom angedockten Fenster bis zum Vollbild neu anordnet. Außerdem fällt
die Vier-Leerzeichen-Einrückung weg, die der alte Text aus dem Markdown-Codeblock
mit nach Partner Center genommen hatte.

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
