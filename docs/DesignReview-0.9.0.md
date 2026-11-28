# Designprüfung für Label Helper 0.9.0

## Zusammenfassung

**Vor der Überarbeitung bestand Verbesserungsbedarf.** Label Helper ist eine native macOS-App für wiederkehrenden Versand. Die Arbeitsfläche soll eine importierte Sendung zur Prüfung zeigen und eine eindeutige Druckaktion anbieten. Das Etikett im tatsächlichen Druckformat ist dabei das wichtigste visuelle Element.

Die Prüfung umfasst die SwiftUI-Oberflächen und ihre Aufrufpfade. Sie erfasst keine gemessenen Kontrastwerte der Systemfarben und ersetzt keinen Test mit VoiceOver oder einem physischen Drucker.

## Verbesserungen

| Priorität | Bereich und Befund | Umsetzung und Bezug |
| --- | --- | --- |
| Hoch | Versand hatte zwei Bedienmodi mit unterschiedlichen Schritten für denselben Entwurf. | Eine Arbeitsfläche je Sendung. Die Versandübersicht bietet Brief, DHL-Import und einen vorhandenen Entwurf. `design-principles.md › Simplicity` fordert „Be clear and direct“. |
| Hoch | Im Brief konkurrierten Materialwahl, Adresse, Porto und Vorschau um Aufmerksamkeit. | Empfänger und ausgewählter Portowert stehen neben dem Druckbild. Die Adressfelder und alternative Frankierung öffnen sich bei Bedarf. Material wird als Voreinstellung im Druckerbereich geführt. `layout.md › Visual hierarchy` empfiehlt „Use progressive disclosure“. |
| Hoch | Ein neuer Import konnte mit einer Druck- oder Abschlussansicht konkurrieren. | Die App schließt eine inaktive Druckvorschau, wartet auf deren Ende und bearbeitet danach den Import. Während eines Drucks bleibt die Sendung aktiv. `modality.md › Best practices` sagt „Let people dismiss a modal view before presenting another one.“ |
| Mittel | Der Verlauf wiederholte Details und Kopieraktionen in jeder Zeile. | Durchsuchbare Auswahlliste mit Detailbereich. Status, Sendungsnummer und Aktionen erscheinen zur Auswahl. `sidebars.md › Best practices` und `layout.md › Visual hierarchy` begründen Auswahl und Detail als getrennte Aufgaben. |
| Mittel | Briefmarkenbestand und Paketvorschau wiederholten dauerhafte Druckeinstellungen. | Bestand und Druckauswahl bleiben zusammen. Papier, Schnittlinien und Bluetooth-Diagnose liegen in der nativen Einstellungsansicht. `settings.md › General settings` empfiehlt dort „general, infrequently changed settings“. |
| Mittel | Die Browser-Übernahme verlangte eine Auswahl und einen separaten Bestätigungsklick. | Die Aktion „Brief vorbereiten“ oder „Paketlabel öffnen“ bestätigt die Richtung direkt. Die Einrichtung und Aktualisierung der Erweiterung bleiben unter Einstellungen und Hilfe erreichbar. `modality.md › Best practices` empfiehlt kurze, fokussierte Aufgaben. |
| Mittel | Abschluss, Kopieren und Nachdruck hatten gleich viel Gewicht. | Der nächste Versand ist die Hauptaktion. Der Nachdruck öffnet sich bei Bedarf und nutzt die vorhandenen Prüfungen der Briefmarke. `feedback.md › Best practices` empfiehlt Status im Kontext. |
| Mittel | Warteschlange, Diagnose und Designer dienten verschiedenen Aufgaben, hatten aber ähnlich dichte Standardansichten. | Druckaufträge bleiben ein eigener Einstellungstab. Diagnose und seltene Layoutregler werden aufgeklappt. Die Papieransicht zeigt weiterhin die Auswirkungen der Layoutoptionen. `settings.md › Task-specific options` und `layout.md › Visual hierarchy` begründen die Trennung. |

## Gestaltung und Plattform

Native Systemschrift und semantische Systemfarben tragen Titel, Text, Aktionen und Status. Das Druckbild selbst bleibt schwarz auf weißem Papier. Status haben ausgeschriebene Bezeichnungen. Import, Versandübersicht, Druckerverbindung und Export sind über Menübefehle erreichbar. `accessibility.md › Vision`, `typography.md › Conveying hierarchy`, `color.md › Best practices` und `toolbars.md › Desktop (macOS)`.

Die Seitenleiste enthält Versenden, Label-Verlauf und Briefmarken. Bei ausreichend Platz stehen Empfänger und Druckbild nebeneinander. Der Brief kann bei kleinerer Breite untereinander angezeigt werden. Die Arbeitsfläche kommt ohne animierte Übergänge aus. `layout.md › Adaptability` und `designing-for-macos.md › Best practices`.

Die vorhandenen Prüfungen des Druckformats, die gespeicherten Druckaufträge, die erneute Zuordnung von Entwürfen und die Regeln für Briefmarken bleiben Teil des Ablaufs.
