# Label Helper v0.8.4

Sichtbare Sammelauswahl für Briefmarken und eine geführte Einrichtung der Browser-Erweiterung.

## Neu und verbessert

- **Alle verfügbaren auswählen** steht wieder direkt über der Markenliste. Die Checkbox zeigt auch eine Teilauswahl an; das Menü **Aktionen** bündelt gemeinsames Kopieren, Als-genutzt-Markieren und Löschen.
- Unter **Einstellungen → Allgemein → Etsy-Browser-Erweiterung** startet **Browser-Erweiterung einrichten …** die Einrichtung für Chrome oder Safari.
- Die App enthält die Erweiterungsdateien, bereitet einen festen Ordner vor, kopiert dessen Pfad und öffnet den gewählten Browser. Drei kurze Schritte führen durch das Hinzufügen und die Freigabe für Etsy.
- Die Anleitung erklärt auch manuelle Installation, Aktualisierung und Fehlerbehebung. Zusätzliche Tests sichern den Klickablauf, die Adresserkennung und die Dateivorbereitung ab.

## Hinweise zur Browser-Erweiterung

Das Aktivieren erfolgt weiterhin im Browser. **Dateien vorbereitet** bedeutet nicht **Installiert**; die App verändert keine Browserprofile oder Website-Berechtigungen.

Safari entfernt temporäre Erweiterungen beim Beenden oder nach 24 Stunden. Für eine dauerhafte Safari-Installation ist eine separate Container-App erforderlich.

Nach einem App-Update die Einrichtung erneut starten und die Erweiterung anschließend im Browser neu laden. Bereits aus einem anderen Ordner geladene Kopien zuvor deaktivieren oder entfernen.

## Installation

`LabelHelper-universal.zip` herunterladen, entpacken und **Label Helper.app** in **Programme** verschieben. Die App enthält Intel- und Apple-Silicon-Code und benötigt macOS 14 oder neuer. Bestehende Installationen erhalten das Update über den integrierten Sparkle-Updater.

Die App ist derzeit ad hoc signiert und nicht von Apple notarisiert. macOS kann beim ersten Öffnen eine Freigabe unter **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** verlangen. Ohne feste Apple-Signieridentität kann macOS nach dem Update erneut um Bluetooth-Zugriff bitten.

## Prüfung

Der Release-Workflow prüft Core-Selbsttests, zehn Erweiterungstests, Universal-Build, Signatur und eingebettete Erweiterungsdateien. Sammelauswahl und Einrichtungsdialog wurden mit isolierten Daten an der gerenderten Oberfläche geprüft. Die Erweiterungsskripte wurden mit synthetischen Bestellseiten in Chrome und WebKit sowie mit dem nativen App-Link-Decoder geprüft; eine vollständig installierte Safari-Erweiterung auf einer echten Etsy-Seite wurde nicht verifiziert.
