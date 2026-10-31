# Label Helper Etsy-Erweiterung

Die Erweiterung ergänzt Etsy-Bestellseiten um **An Label Helper senden**.
Sie liest die aktuell geöffnete Bestellung erst nach einem Klick und öffnet die
lokal installierte Label-Helper-App. Es werden keine Bestelldaten an einen
Server übertragen.

## Einrichtung direkt in Label Helper

In App-Versionen mit **Browser-Erweiterung einrichten …**:

1. **Label Helper → Einstellungen → Allgemein → Etsy-Browser-Erweiterung** öffnen.
2. **Browser-Erweiterung einrichten …** anklicken und **Chrome** oder **Safari**
   auswählen.
3. **Einrichtung starten** wählen. Die App bereitet ihre mitgelieferten Dateien
   ohne zusätzlichen Download vor, kopiert den Ordnerpfad und öffnet Chrome mit
   `chrome://extensions` beziehungsweise Safari.
4. Die drei eingeblendeten Schritte im Browser abschließen. Im Dateidialog mit
   **⇧⌘G** den kopierten Pfad einfügen und den Ordner auswählen.

**Ordner anzeigen** öffnet den Speicherort im Finder; **Pfad kopieren** kopiert
ihn erneut. Der feste Speicherort ist
`~/Library/Application Support/MunbynLabeler/BrowserExtension`.
Diesen Ordner nicht löschen oder verschieben, solange der Browser ihn verwendet.
Bei erneuter Einrichtung werden die Dateien am selben Ort aktualisiert.
Wenn du zuvor eine Kopie aus einem anderen Ordner geladen hast, entferne oder
deaktiviere diese alte Erweiterung im Browser, bevor du die neue Kopie hinzufügst.

Die App meldet **Dateien vorbereitet**, nicht **Installiert**. Das Aktivieren,
die Website-Berechtigungen und das Neuladen bleiben im Browser. Für Safari gilt
auch hier die temporäre Installation mit ihrer Begrenzung auf 24 Stunden oder
bis zum nächsten Beenden.

Fehlt der Einrichtungsbutton in deiner App, nutze die manuelle Installation:

## Manuelle Vorbereitung

1. [Das aktuelle Release öffnen](https://github.com/ni920/LabelHelper/releases/latest).
2. `LabelHelper-universal.zip` herunterladen, entpacken und **Label Helper.app**
   nach **Programme** verschieben. Die App einmal öffnen, bevor du eine Bestellung
   überträgst.
3. Aus demselben Release **LabelHelper-Browser-Extension.zip** herunterladen und
   entpacken. Im Ordner **BrowserExtension** liegt die Datei `manifest.json`.
   Nicht das App-ZIP oder den Unterordner `icons` als Erweiterung auswählen.

Die Erweiterung ist nicht im Chrome Web Store oder Safari-Erweiterungsstore
veröffentlicht. Das ZIP enthält die gemeinsamen WebExtension-Dateien, keine
fertige Safari-Container-App.

## Chrome hinzufügen

1. Den Ordner **BrowserExtension** an einen festen Ort verschieben, zum Beispiel
   in **Dokumente/Label Helper**. Chrome verwendet diesen Ordner weiterhin.
2. `chrome://extensions` in die Adressleiste eingeben.
3. Oben rechts **Entwicklermodus** einschalten.
4. **Entpackte Erweiterung laden** anklicken und genau den Ordner
   **BrowserExtension** mit der `manifest.json` auswählen.
5. Prüfen, dass **Label Helper für Etsy** eingeschaltet ist.
6. Bereits geöffnete Etsy-Tabs neu laden. Im Shop-Manager eine Bestellung
   öffnen, sodass **Versand an** und die vollständige Adresse sichtbar sind.

Der Button **An Label Helper senden** erscheint unten rechts auf der
Bestellseite, nicht als eigenes Popup in der Browser-Symbolleiste.

## Safari hinzufügen

### Schnellstart ohne Xcode: temporär laden

In Safari-Versionen mit **Add Temporary Extension …** /
**Temporäre Erweiterung hinzufügen …**:

1. **Safari → Einstellungen → Erweitert** öffnen und **Funktionen für
   Webentwickler anzeigen** aktivieren.
2. Zum nun sichtbaren Reiter **Entwickler** wechseln.
3. **Temporäre Erweiterung hinzufügen …** wählen. Die Rückfrage zum Laden
   unsignierter Erweiterungen nur für die selbst heruntergeladene Erweiterung
   bestätigen.
4. Den entpackten Ordner **BrowserExtension** mit der `manifest.json` auswählen.
5. Unter **Safari → Einstellungen → Erweiterungen** die Erweiterung
   **Label Helper für Etsy** aktivieren und den Website-Zugriff auf **etsy.com**
   erlauben. Bei Safari-Profilen die Erweiterung auch für das verwendete Profil
   aktivieren.
6. Den Etsy-Tab neu laden und eine Bestellung mit sichtbarer Versandadresse öffnen.

**Wichtig:** Safari entfernt temporäre Erweiterungen nach **24 Stunden oder beim
Beenden von Safari**. Dann musst du den Ordner erneut hinzufügen. Auch die
Einstellung für unsignierte Erweiterungen wird beim Beenden zurückgesetzt.
Fehlt der Menüpunkt für temporäre Erweiterungen, nutze eine neuere Safari-Version
oder den Xcode-Weg unten.

### Lokale Container-App mit Xcode

Hierfür ist **vollständiges Xcode** nötig; die Command Line Tools allein reichen
nicht. Lade zusätzlich den Quellcode dieses Repositorys herunter und führe in
seinem Hauptordner aus:

```bash
./script/create_safari_extension_project.sh
```

1. Das erzeugte `.xcodeproj` im Ordner **SafariExtension** mit Xcode öffnen.
2. Das macOS-App-Schema und **My Mac** wählen. Die Signierung bei Bedarf in
   **Signing & Capabilities** konfigurieren.
3. **Product → Run** ausführen, damit die Container-App gestartet und die
   Erweiterung für Safari registriert wird. Nur **Build** reicht für die
   erstmalige Installation nicht.
4. Die Erweiterung in Safari aktivieren und Etsy-Zugriff erlauben wie oben.

Eine unsignierte lokale Container-App benötigt in Safari weiterhin
**Entwickler → Unsignierte Erweiterungen erlauben**, nach jedem Safari-Neustart.
Für regulär signierte Weitergabe ist eine Apple-Developer-Mitgliedschaft nötig.
Die Container-App installiert nur die Erweiterung; **Label Helper.app** wird
zusätzlich für die Übernahme und den Druck benötigt.

Quelle: [Apple: Running your Safari web extension](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension).

## Verwendung

1. Etsy-Shop-Manager öffnen und eine Bestellung mit Versandadresse anzeigen.
2. **An Label Helper senden** anklicken.
3. Den Browserdialog zum Öffnen von Label Helper bestätigen.
4. In der App **Brief** oder **Paket** wählen und die Daten prüfen.

Es wird nichts automatisch gedruckt. Prüfe vor der Übernahme insbesondere
Bestellnummer, Empfänger und Adresse.

## Aktualisieren

- **Chrome:** Dateien im bisherigen Erweiterungsordner durch die neue Version
  ersetzen, bei `chrome://extensions` an der Erweiterung **Neu laden** anklicken
  und danach Etsy neu laden.
- **Safari, temporär:** Unter **Einstellungen → Erweiterungen** die Erweiterung
  neu laden oder den aktualisierten Ordner erneut hinzufügen; anschließend Etsy
  neu laden.
- **Safari, Xcode:** Die kopierten WebExtension-Dateien im erzeugten Projekt
  aktualisieren und die Container-App erneut bauen/starten. Das Script verwendet
  `--copy-resources`; Änderungen im ursprünglichen Ordner werden deshalb nicht
  automatisch ins Xcode-Projekt übernommen.

Der Sparkle-Updater aktualisiert **nur Label Helper**, nicht eine manuell
installierte Browser-Erweiterung. Bei Einrichtung über die App: Nach einem
App-Update die Einrichtungshilfe erneut öffnen und **Einrichtung starten**
wählen, dann die Erweiterung im Browser neu laden. Die App enthält die zu ihrer
Version passenden Erweiterungsdateien; sie ändert Browserprofile oder
Erweiterungsberechtigungen nicht selbst.

## Wenn es nicht klappt

| Problem | Abhilfe |
|---|---|
| Kein Button auf Etsy | Erweiterung aktivieren, Etsy-Zugriff und Browser-Profil prüfen, Bestellseite vollständig neu laden. Unterstützt sind `www.etsy.com/your/orders/…`, `www.etsy.com/your/shops/…/orders/…` und `www.etsy.com/shop-manager/orders/…`. |
| „Empfängeradresse nicht gefunden“ | Die Details einer einzelnen Bestellung öffnen, bis die vollständige Versandadresse sichtbar ist. Nicht nur die Bestellübersicht anzeigen. |
| Label Helper öffnet sich nicht | App aus dem Release installieren und einmal öffnen. Den Browserdialog zum Öffnen der externen App zulassen. |
| Safari-Erweiterung nach Neustart verschwunden | Temporäre Erweiterung erneut hinzufügen; sie ist nicht dauerhaft installiert. |
| Safari-Packager nicht gefunden | Vollständiges Xcode installieren und als aktive Entwicklerumgebung auswählen oder den temporären Safari-Weg verwenden. |
| Einrichtungsbutton meldet fehlende Dateien | Die vollständige `.app` aus dem Release verwenden. Ein reines SwiftPM-Executable enthält die vom Packaging-Script beigefügten Browserdateien nicht. |
| Etsy zeigt ein anderes Layout | Adresse und Bestellnummer nicht ungeprüft übernehmen. Als Alternative den Etsy-CSV-Import in Label Helper verwenden. |

## Funktionsprüfung

Die automatischen Tests laufen mit `node --test BrowserExtension/tests/*.test.js`
im Repository-Hauptordner und beim Verpacken der Erweiterung. Sie prüfen unter
anderem Adresserkennung, Umlaute im App-Link, den Klickablauf, Fehlerhinweise und
das Wiederherstellen des Buttons nach Seitenänderungen.

Zusätzlich wurde die gemeinsame Skriptlogik in Chrome und in WebKit mit
synthetischen Bestellseiten ausgeführt. Der dabei erzeugte Link ließ sich mit
dem nativen Swift-Decoder lesen. Das ersetzt keine Prüfung einer tatsächlich
installierten Erweiterung auf der aktuellen Etsy-Seite: Website-Berechtigungen,
der Browserdialog zum Öffnen der App und abweichende Etsy-Layouts müssen dort
geprüft werden. Eine Safari-Container-App wurde hier mangels vollständigem
Xcode nicht gebaut.
