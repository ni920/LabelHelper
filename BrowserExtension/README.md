# Etsy mit Label Helper verbinden

Die Erweiterung setzt unten rechts auf die Etsy-Bestellseite den Button
**An Label Helper senden**. Er überträgt Bestellnummer und Empfängeradresse an
die App auf deinem Mac. Du wählst dort Brief oder Paket und prüfst die Adresse.
Artikeldaten werden nicht übertragen. Es wird nichts automatisch gedruckt.

## Welchen Weg soll ich nehmen?

| Du verwendest … | So gehst du vor |
| --- | --- |
| **Chrome und Label Helper ab 0.8.6** | Die Einrichtung in der App verwenden. Kein zusätzlicher Download nötig. |
| **Safari mit „Temporäre Erweiterung hinzufügen“** | Die Safari-Einrichtung in der App verwenden. Sie gilt nur bis zum Beenden von Safari oder maximal 24 Stunden. |
| **Eine ältere App ohne Einrichtungshilfe** | App aktualisieren oder unten die manuelle ZIP-Anleitung verwenden. |
| **Safari ohne temporäre Erweiterungen / dauerhafte Safari-Verteilung** | Den Abschnitt „Safari mit Container-App“ lesen. Das Erweiterungs-ZIP ist keine signierte Safari-App. |

## Am einfachsten: direkt in der App

1. **Label Helper** aus **Programme** öffnen. Bei Bedarf das
   [aktuelle App-Release](https://github.com/ni920/LabelHelper/releases/latest)
   installieren: `LabelHelper-universal.zip` entpacken und **Label Helper.app**
   nach **Programme** ziehen. **Source code** ist dafür nicht nötig.
2. Oben in der Menüleiste **Hilfe → Browser-Erweiterung einrichten …** wählen.
   Du findest denselben Einstieg unter **Importieren** und unter
   **Label Helper → Einstellungen → Allgemein → Etsy-Browser-Erweiterung**.
3. **Chrome** oder **Safari** wählen. Die Hilfe zeigt immer nur den aktuellen
   Schritt. Mit **Zurück** kannst du ihn wiederholen.
4. **Dateien vorbereiten** anklicken. Die App legt die mitgelieferte Erweiterung
   in einem festen Ordner ab. Es wird noch nichts im Browser installiert.
5. Den folgenden Abschnitt für deinen Browser abschließen. Setze die Häkchen
   in der Hilfe jeweils erst, wenn du den Schritt im Browser erledigt hast.
   Sie sind deine Bestätigung; die App erkennt den Installationszustand nicht
   automatisch.

### Chrome: einmal einrichten

1. Im Schritt **Browser vorbereiten** auf **Chrome-Erweiterungen öffnen** klicken.
   Falls Chrome die Seite nicht öffnet: **Browseradresse kopieren** anklicken,
   in die Chrome-Adressleiste einfügen und Return drücken. Die Adresse lautet
   `chrome://extensions/`.
2. Auf dieser Seite oben rechts **Entwicklermodus** einschalten. In Label Helper
   **Entwicklermodus ist eingeschaltet** anhaken und **Weiter** wählen.
3. In Chrome **Entpackte Erweiterung laden** anklicken.
4. In Label Helper **Ordnerpfad kopieren** wählen. Zum Chrome-Dateidialog
   zurückwechseln, **⇧⌘G** drücken, den Pfad mit **⌘V** einfügen und Return drücken.
   Danach **Auswählen** bestätigen. Du wählst den **Ordner BrowserExtension**,
   in dem `manifest.json` liegt; nicht die Datei selbst und nicht `icons`.
5. Prüfen, dass **Label Helper für Etsy** in Chrome erscheint. Dies in der Hilfe
   bestätigen und **Weiter** wählen.
6. Die Erweiterung einschalten. Unter **Details → Websitezugriff** prüfen,
   dass der Zugriff auf `etsy.com` für die unterstützten Bestellseiten erlaubt
   ist. Bei Firmen-Macs kann eine Browserrichtlinie das Laden verhindern;
   dann die zuständige Administration kontaktieren.
7. In der Hilfe den erlaubten Zugriff bestätigen und zum Funktionstest gehen.

Chrome verwendet den vorbereiteten Ordner dauerhaft. **Nicht löschen oder
verschieben**, solange du die Erweiterung nutzt. Ein Symbol in der
Chrome-Symbolleiste musst du nicht anheften: Der Senden-Button steht direkt
auf der Etsy-Seite.

### Safari: temporär einrichten

Dieser Weg benötigt kein Xcode, aber einen Safari-Menüpunkt **Temporäre
Erweiterung hinzufügen …** / **Add Temporary Extension …**. Fehlt er, helfen
die Schritte unter „Safari mit Container-App“ oder die Chrome-Einrichtung.

1. In der Hilfe **Safari** wählen und **Dateien vorbereiten** anklicken.
2. **Safari öffnen**, dann in Safari **⌘,** drücken.
3. **Erweitert** öffnen und **Funktionen für Webentwickler anzeigen** einschalten.
   In der Hilfe den Schritt bestätigen und **Weiter** wählen.
4. In Safari zum nun sichtbaren Reiter **Entwickler** wechseln und
   **Temporäre Erweiterung hinzufügen …** anklicken. Safari kann dabei eine
   Bestätigung für das Laden unsignierter Erweiterungen verlangen.
5. In Label Helper **Ordnerpfad kopieren** anklicken. Im Safari-Dateidialog
   **⇧⌘G**, dann **⌘V** und Return drücken. Den vorbereiteten Ordner
   **BrowserExtension** mit **Auswählen** bestätigen.
6. Unter **Safari → Einstellungen → Erweiterungen** **Label Helper für Etsy**
   aktivieren und den Zugriff auf **etsy.com** erlauben. Falls du Safari-Profile
   verwendest, die Erweiterung auch für das verwendete Profil aktivieren.
7. Die Häkchen in der Hilfe erst nach diesen Schritten setzen und zum Test gehen.

**Safari entfernt temporäre Erweiterungen beim Beenden oder nach 24 Stunden.**
Dann die Hilfe erneut öffnen und den aktualisierten Ordner wieder hinzufügen.
Auch **Unsignierte Erweiterungen erlauben** wird beim Beenden zurückgesetzt.

## Funktionstest: eine Bestellung übernehmen

1. In der Hilfe **Etsy-Bestellungen öffnen** wählen oder den Etsy-Shop-Manager
   im eingerichteten Browser öffnen.
2. Den Etsy-Tab nach der Installation **neu laden (⌘R)**.
3. Die Details **einer einzelnen Bestellung** öffnen. Unter **Versand an** müssen
   Name, Straße, Postleitzahl, Ort und Land vollständig sichtbar sein.
4. Unten rechts auf der Seite **An Label Helper senden** anklicken.
5. Den Browserdialog zum Öffnen von **Label Helper** bestätigen. Falls du wählen
   kannst, nimm die bereits nach **Programme** kopierte App.
6. In Label Helper **Brief** oder **Paket** wählen und die übernommene Adresse
   und Bestellnummer kontrollieren. Für den Einrichtungstest musst du kein
   Porto kaufen und nichts drucken.
7. Ist die richtige Adresse angekommen, das letzte Häkchen in der Hilfe setzen
   und **Fertig** wählen. Andernfalls **Es klappt noch nicht?** öffnen.

## Manuell aus dem ZIP installieren

Nur nötig, wenn du die App-Einrichtung nicht verwenden möchtest:

1. [Aktuelles Release öffnen](https://github.com/ni920/LabelHelper/releases/latest).
2. Für die **App** `LabelHelper-universal.zip` herunterladen, entpacken,
   **Label Helper.app** nach **Programme** ziehen und einmal öffnen.
3. Für die **Erweiterung** aus demselben Release
   `LabelHelper-Browser-Extension.zip` herunterladen und doppelt anklicken.
4. Den entpackten Ordner **BrowserExtension** an einen festen Ort verschieben,
   zum Beispiel **Dokumente/Label Helper**. Darin muss `manifest.json` liegen
   (der Finder kann die Dateiendung ausblenden).
5. Die Schritte oben für Chrome bzw. Safari ausführen. Im Browser-Dateidialog
   diesen Ordner auswählen. Beim manuellen Weg gibt es keinen von der App
   kopierten Ordnerpfad; du kannst den Ordner im Dateidialog direkt suchen.

Nicht das App-ZIP, **Source code**, die `.app` oder den Unterordner `icons` als
Erweiterung auswählen. Das Erweiterungs-ZIP enthält WebExtension-Dateien,
keine separat signierte Safari-Container-App. Es gibt derzeit keinen Eintrag
im Chrome Web Store oder Safari-Erweiterungsstore.

## Safari mit Container-App: Entwicklung und Verteilung

Für eine gewöhnlich installierbare Safari-Erweiterung müssen die
WebExtension-Dateien in einer macOS-Container-App verpackt sein.
**Eine solche signierte Safari-App wird hier noch nicht als Download geliefert.**
Die native Druck-App allein installiert deshalb keine dauerhafte Safari-Erweiterung.

Für lokale Entwicklung ist **vollständiges Xcode** erforderlich; die Command
Line Tools allein reichen nicht:

1. Den Quellcode des Repositorys laden und im Projektordner im Terminal
   `./script/create_safari_extension_project.sh` ausführen.
2. Das erzeugte `.xcodeproj` unter **SafariExtension** mit Xcode öffnen.
3. Das macOS-App-Schema und **My Mac** auswählen. Unter **Signing & Capabilities**
   die für den eigenen Entwicklungsaufbau benötigte Signierung konfigurieren.
4. **Product → Run (⌘R)** ausführen: Erst der Start der Container-App registriert
   die Erweiterung. Nur **Build** genügt bei der Erstinstallation nicht.
5. In Safari die Erweiterung aktivieren und Etsy-Zugriff erlauben wie oben.

Ein unsignierter lokaler Aufbau benötigt **Unsignierte Erweiterungen erlauben**
in Safaris Entwicklereinstellungen erneut nach jedem Safari-Neustart. Er ist
kein dauerhafter Ein-Klick-Installationsweg für andere Nutzer. Für reguläre
Verteilung sind Apple-Developer-Mitgliedschaft, passende Signierung und je nach
Vertriebsweg App-Store-Verteilung bzw. Notarisierung erforderlich.

Das Skript kopiert die Dateien ins erzeugte Projekt. Nach einem Update müssen
diese dort aktualisiert und die Container-App erneut gebaut/gestartet werden.
Die Druck-App **Label Helper** wird zusätzlich benötigt.

## Aktualisieren

- **Über die App eingerichtet:** Nach einem App-Update dieselbe Einrichtungshilfe
  erneut öffnen und **Dateien vorbereiten** bzw. **Dateien aktualisieren** wählen.
  Die Dateien werden am selben festen Ort ersetzt. In Chrome anschließend bei
  `chrome://extensions/` an der Erweiterung auf **Neu laden** klicken; in Safari
  die temporäre Erweiterung neu laden oder erneut hinzufügen. Dann Etsy neu laden.
- **Manuell eingerichtet:** Den Inhalt des bisherigen Erweiterungsordners durch
  die neue Version ersetzen und im Browser wie oben neu laden.
- Falls du vorher einen anderen Ordner verwendet hast: Die alte Erweiterung
  entfernen oder deaktivieren und die neue Kopie einmal hinzufügen. Verhindere,
  dass zwei Kopien denselben Senden-Button einfügen.

Sparkle aktualisiert die App, aber keine eigenständig im Browser installierte
Erweiterung. Der vorbereitete Ordner liegt unter
`~/Library/Application Support/LabelHelper/BrowserExtension`.
Ein vorhandener alter Pfad unter `MunbynLabeler/BrowserExtension` bleibt als
Kompatibilitätslink erreichbar. Der Ordner wird weiter gebraucht und gehört
nicht zu den entbehrlichen Build-Caches.

## Wenn etwas nicht klappt

| Problem | Nächster Schritt |
| --- | --- |
| „Manifest fehlt“ | Den entpackten Ordner mit `manifest.json` auswählen, nicht das ZIP oder `icons`. Im App-Weg **Ordnerpfad kopieren** verwenden. |
| Chrome öffnet keine Erweiterungsseite | `chrome://extensions/` manuell in die Chrome-Adressleiste eingeben. Diese internen Adressen sind auf Webseiten keine normalen Links. |
| Browser wird nicht gefunden | Den gewünschten Browser installieren oder in der Hilfe den anderen auswählen. |
| Safari hat keinen temporären Menüpunkt | Safari-Version prüfen; Chrome oder den Xcode-Weg verwenden. Das ZIP lässt sich nicht als dauerhafte Safari-App installieren. |
| Kein Senden-Button | Etsy neu laden, Erweiterung einschalten, Website-Zugriff und Browser-Profil prüfen. |
| „Empfängeradresse nicht gefunden“ | Einzelne Bestellung mit vollständiger Adresse unter **Versand an** öffnen, nicht nur die Bestellübersicht. |
| App öffnet sich nicht | App aus **Programme** einmal starten und den Dialog zum Öffnen der externen App im Browser bestätigen. |
| Safari-Erweiterung ist verschwunden | Temporäre Erweiterung erneut hinzufügen; Safari entfernt sie beim Beenden oder nach 24 Stunden. |
| Hilfe kann keine Dateien vorbereiten | Die vollständige App aus dem Release installieren. Ein loses SwiftPM-Executable enthält die Erweiterungsdateien nicht. |

Unterstützte Etsy-Bestellseiten: `www.etsy.com/your/orders/…`,
`www.etsy.com/your/shops/…/orders/…` und `www.etsy.com/shop-manager/orders/…`.

## Quellen und Prüfgrenzen

Anforderungen geprüft am **02.11.2026** anhand der Primärquellen:

- [Google: Erweiterungen verteilen](https://developer.chrome.com/docs/extensions/how-to/distribute)
- [Apple: Einrichtung ohne Xcode](https://developer.apple.com/documentation/safariservices/building-and-testing-a-safari-web-extension)
- [Google: Unpacked-Erweiterung laden und neu laden](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked)
- [Apple: Safari-Erweiterung ausführen und temporär installieren](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)
- [Apple: Safari-Erweiterung verteilen](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)

`node --test BrowserExtension/tests/*.test.js` prüft die Adresserkennung, App-Links
und den Klickablauf mit synthetischen Bestellungen. Die Core-Tests prüfen die
Vorbereitung im festen Ordner, Fehlererholung und den geführten Ablauf. Ein
vorbereitetes Verzeichnis oder ein bestandenes Skripttest-Ergebnis belegt noch
keine erteilte Browser-Berechtigung. Eine signierte Safari-Container-App und
physischer Druck sind nicht Bestandteil dieser Einrichtungsprüfung.
