# Windows-Push: PFN-Mapping bei Microsoft beantragen

**Sofort abschicken.** Microsoft bearbeitet diese Anfragen **wöchentlich**, und
ohne das Mapping liefert `CreateChannelAsync` bei einer verpackten App keinen
Kanal — der Runner-Umbau nützt bis dahin nichts. Die Wartezeit läuft am besten
parallel zur Entwicklung.

## Warum das nötig ist

Windows App SDK Push verknüpft die **Paket-Identität** der App (Package Family
Name) mit einer **Entra-Identität** (Azure AppId). Diese Verknüpfung kann man
nicht selbst setzen; sie wird von Microsoft eingetragen. Erst danach akzeptiert
WNS eine Kanal-Anforderung aus dem verpackten Prozess.

Quelle: [Push notifications quickstart, Step 4](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/push-quickstart)

## Die Werte

| Feld | Wert | Herkunft |
|---|---|---|
| **PFN** | `4hm4dr3.hinata_06f1m0fr9531r` | Partner Center → Produktidentität → Package Family Name |
| **AppId** | `e89a5a67-af01-4c79-98a7-09e609f0c831` | Entra → hinata-wns → Application (client) ID |
| **ObjectId** | `33fa840e-5c3b-4cc0-8308-227acbecdf0d` | Entra → hinata-wns → **Managed application in local directory** → Object ID |

> Die ObjectId ist **nicht** die `09b9d64b-…` von der Essentials-Seite der
> App-Registrierung. Gebraucht wird die des **Service Principals** — erreichbar
> über den Link „Managed application in local directory". Dieselbe GUID geht
> später in `PushNotificationManager::Default().CreateChannelAsync(...)`.

## Die Mail

**An:** Win_App_SDK_Push@microsoft.com
**Betreff:** Windows App SDK Push Notifications Mapping Request

```
PFN: 4hm4dr3.hinata_06f1m0fr9531r
AppId: e89a5a67-af01-4c79-98a7-09e609f0c831
ObjectId: <ObjectId des Service Principals eintragen>
```

Mehr erwartet Microsoft nicht — genau diese drei Zeilen. Eine Bestätigung kommt,
sobald das Mapping eingetragen ist.

## Danach prüfen

Sobald die Bestätigung da ist und der Runner umgebaut wurde: Die MSIX-Version
installieren und starten. Der Kanal kommt über den Method-Channel `hinata/wns`
in Dart an und wird beim Anmelden an `/api/v1/me/devices` gemeldet. Kommt dort
eine `https://…notify.windows.com/?token=…`-URI an, steht die Client-Seite.

Ein echter Zustellversuch ist erst danach sinnvoll — dafür muss der Gateway mit
den `GATEWAY_WNS_*`-Secrets laufen (bereits gesetzt) und beim Start
`WNS configured; Windows push is active.` loggen.
