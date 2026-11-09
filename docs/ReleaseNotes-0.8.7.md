# Label Helper v0.8.7

Etiketten selbst gestalten, Adresse und Briefmarke auf einem Etikett drucken und alle Sendungen samt Paketen in einem Verlauf.

## Neu und verbessert

- **Etikett-Designer** unter Einstellungen → **Etikett**: Absender, Empfänger, Schrift, Rand und Position der Briefmarke lassen sich mit Live-Vorschau anpassen.
- **Adresse und Briefmarke auf einem Etikett** als zusätzliche Einstellung im Designer. Die Marke muss nicht mehr ausgeschnitten werden und behält ihre Originalgröße.
- **Label-Verlauf** statt Briefverlauf: Briefe und Paketlabel stehen zusammen in einer Liste. Aus DHL-PDFs werden Empfänger, Adresse, Produkt, Sendungsnummer und Warenkorb-Nr. automatisch ausgelesen.
- **Verlauf exportieren** speichert den gesamten Verlauf als CSV-Datei für Excel oder Numbers.
- **Druckaufträge** liegen jetzt unter Einstellungen → **Druckaufträge**. „Erledigte entfernen“ lässt den Label-Verlauf unberührt.
- Nach dem Druck führt **Zurück zum Anfang** zur Aufgabenauswahl und leert die Empfängeradresse.

## Geändertes Verhalten

Adressen, die nicht vollständig auf ein Etikett passen, werden nicht mehr abgeschnitten. Stattdessen erscheint eine Fehlermeldung mit dem Hinweis auf ein größeres Format oder ein angepasstes Design.

## Endlosrollen

Unter Einstellungen → **Allgemein** → **Etikettenmaterial** gibt es eine optionale **Papierzugabe nach der Schnittlinie**. Sie kann helfen, falls der Drucker das Papier beim Start zu weit einzieht, und ist standardmäßig aus. Die Wirkung hängt vom Verhalten der Drucker-Firmware ab.

## Aktualisierung

Label Helper aktualisiert sich über **Nach Updates suchen …**. Alternativ `LabelHelper-universal.zip` entpacken und die App nach **Programme** kopieren. Vorhandene Aufträge werden beim ersten Start in den Label-Verlauf übernommen. Pakete, die bereits früher aus den Druckaufträgen entfernt wurden, lassen sich nicht wiederherstellen.

Die App läuft ab macOS 14 auf Intel und Apple Silicon, ist ad hoc signiert und nicht von Apple notarisiert.
