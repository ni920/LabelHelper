# Label Helper v0.8.5

Kürzere Endlosetiketten, sichere Nachdrucke aus dem Briefverlauf und ein einheitlicher Name für App und Projekt.

## Neu und verbessert

- Adressetiketten auf 100-mm-Endlosrollen verwenden jetzt automatisch nur die für den vollständigen Inhalt benötigte Länge. Lange Adressen wachsen mit, statt abgeschnitten zu werden.
- Auch Briefmarken-Bündel und kombinierte Briefabläufe entfernen ungenutzte Leerzeilen. Adresse und Briefmarke behalten dabei jeweils ihre eigene passende Länge.
- Im Briefverlauf können abgeschlossene Sendungen als **Nur Adresse**, **Nur Briefmarke** oder **Adresse und Briefmarke** erneut gedruckt werden.
- Briefmarken-Nachdrucke bleiben an den ursprünglichen Brief gebunden. Bestätigungen, gespeicherte Zwischenstände und Wiederanlaufprüfungen verhindern eine versehentliche Mehrfachverwendung.
- Beim Start prüft Label Helper nun direkt im Hintergrund den signierten Update-Feed. Die manuelle Funktion **Nach Updates suchen …** bleibt verfügbar.
- App-Paket, Repository und Dokumentation verwenden nun durchgehend den Namen **Label Helper**. Die README wurde deutlich vereinfacht und neu strukturiert.

## Hinweise zu Endlosrollen

Endlosetiketten bleiben 100 mm breit und erhalten weiterhin 2 mm Schnittzugabe. Adressen, Porto und Barcodes werden nicht verkleinert oder beschnitten.

Der direkte Bluetooth-Druck auf Endlosmaterial benötigt beim RW403B Firmware **1.1.49 oder neuer**. Bestehende vorbereitete Druckaufträge behalten ihre gespeicherten Maße.

## Aktualisierung

`LabelHelper-universal.zip` herunterladen, entpacken und **Label Helper.app** in **Programme** verschieben. Beim Wechsel von einer älteren **Munbyn Labeler**-Version die alte App beenden und anschließend entfernen.

Einstellungen, Briefmarkenbestand, Briefverlauf und Druckhistorie werden weiterverwendet. Die dafür notwendigen technischen Kennungen und der vorhandene Datenordner unter `~/Library/Application Support/MunbynLabeler/` bleiben aus Kompatibilitätsgründen unverändert.

Die App enthält Intel- und Apple-Silicon-Code und benötigt macOS 14 oder neuer. Sie ist derzeit ad hoc signiert und nicht von Apple notarisiert. macOS kann deshalb eine Freigabe unter **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** und erneut Bluetooth-Zugriff verlangen.

## Prüfung

Der Release-Workflow prüft Core- und Nachdruck-Selbsttests, echte PDF-/Raster-Layouts, vollständige Adressinhalte, unveränderte Briefmarkenpixel, Bluetooth-Payload-Längen, beide Universal-2-Architekturen, Signatur und App-Start.
