<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="Label Helper App-Icon">
</p>

<h1 align="center">Label Helper</h1>

<p align="center">
  Etiketten für Briefe und Pakete auf dem Mac vorbereiten, prüfen und direkt
  auf einem MUNBYN RW403B drucken.
</p>

<p align="center">
  <a href="https://github.com/ni920/LabelHelper/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_Release-2ea44f" alt="Aktuelles Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer">
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/Universal_2-arm64_%2B_x86__64-3572A5" alt="Apple Silicon und Intel">
</p>

**Label Helper** ist eine native macOS-App für Adressetiketten, DHL-Paketlabel
und Internetmarken. Sie verbindet sich per Bluetooth direkt mit dem
**MUNBYN RW403B**, zeigt vor jedem Druck die tatsächlichen 203-dpi-Rasterdaten
und verarbeitet alle Versanddaten lokal auf dem Mac.

> [!IMPORTANT]
> Label Helper ist ein privates, unabhängiges Projekt und kein offizielles
> Produkt von MUNBYN, Etsy, DHL oder der Deutschen Post. Bitte Adresse, Porto,
> Barcode, Format und Druckbild vor dem Versand immer selbst kontrollieren.

## Auf einen Blick

- **Direkter Bluetooth-Druck** ohne Cloud-Dienst oder Zwischenserver
- **Geführter Modus** für Briefe, Paketlabel und Briefmarken
- **Exakte Vorschau** der später übertragenen Schwarz-Weiß-Druckdaten
- **Etsy-Übernahme** per Browser-Erweiterung oder CSV-Import
- **Vorgestanzte Etiketten und 100-mm-Endlosrollen**
- **Universal-2-App** für Apple Silicon und Intel-Macs
- **Automatische Updates** über den integrierten Sparkle-Updater

## Installation

**Voraussetzungen:** macOS 14 oder neuer, Bluetooth und ein MUNBYN RW403B.

1. Im [aktuellen GitHub Release](https://github.com/ni920/LabelHelper/releases/latest)
   `LabelHelper-universal.zip` herunterladen.
2. Das Archiv entpacken und **Label Helper.app** nach **Programme** ziehen.
3. Die App öffnen und beim ersten Druckerversuch den Bluetooth-Zugriff erlauben.

Die App benötigt keinen Installer und richtet keine Systemerweiterung oder
Hintergrunddienste ein.

<details>
<summary><strong>macOS blockiert den ersten Start?</strong></summary>

Die Release-App ist derzeit nicht von Apple notarisiert. Wenn sie aus einer
vertrauenswürdigen Quelle stammt:

1. Einmal versuchen, **Label Helper.app** zu öffnen.
2. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen.
3. Im Abschnitt **Sicherheit** bei Label Helper auf **Dennoch öffnen** klicken.
4. Die Rückfrage mit **Öffnen** bestätigen.

Apple beschreibt den Vorgang unter
[Sicher Apps auf dem Mac öffnen](https://support.apple.com/de-de/102445).

</details>

### Updates und Deinstallation

Neue Versionen installiert die App über **Label Helper → Nach Updates suchen …**.
Falls ein manuelles Update nötig ist, die neue App einfach über die vorhandene
Version im Programme-Ordner kopieren. Einstellungen, Briefmarkenbestand und
Druckhistorie bleiben erhalten.

Zum Deinstallieren **Label Helper.app** in den Papierkorb verschieben. Lokale
App-Daten bleiben dabei unter
`~/Library/Application Support/MunbynLabeler/` gespeichert und können bei
Bedarf separat gelöscht werden.

## Erster Druck

1. Den RW403B einschalten und in die Nähe des Macs stellen.
2. In Label Helper **Drucken → Geräte suchen** öffnen.
3. Den Drucker auswählen und auf **Drucker verbunden** warten.
4. Material und Etikettenformat wählen.
5. Mit **Testetikett** Druckbild und Papiererkennung prüfen.

Nach der ersten erfolgreichen Verbindung merkt sich die App den Drucker und
verbindet ihn nach Neustarts oder kurzen Unterbrechungen automatisch wieder.

## Versand vorbereiten

Beim ersten Start ist der geführte Modus aktiv. Unter **Versenden** lässt sich
jederzeit zwischen **Geführt** und **Direkt** wechseln.

| Aufgabe | Ablauf |
| --- | --- |
| **Brief** | Empfänger eingeben oder aus Etsy übernehmen, optional eine Internetmarke wählen, Vorschau prüfen und drucken |
| **Paket** | Gekauftes DHL-PDF importieren, den automatisch erkannten 100 × 150-mm-Ausschnitt prüfen und drucken |
| **Briefmarken** | PDF-Bündel importieren, verfügbare Marken auswählen, platzsparendes Layout prüfen und drucken |
| **Eigene Datei** | PDF, PNG oder JPEG importieren und proportional in das gewählte Format einpassen |

Gedruckt wird erst nach der Vorschau. Bereits vorbereitete Aufträge behalten ihr
gespeichertes Format, auch wenn die Voreinstellung später geändert wird.

### Etiketten und Endlosrollen

| Material | Verhalten |
| --- | --- |
| **Vorgestanzte Etiketten** | Voreinstellungen für 100 × 150, 100 × 50, 89 × 36, 70 × 36 und 50 × 50 mm sowie eigene Formate von 20–108 mm Breite und 15–300 mm Höhe |
| **100-mm-Endlosrolle** | Adressen und Briefmarken erhalten automatisch die passende Länge; Paketlabel bleiben 100 × 150 mm |

Endlosetiketten erhalten unter dem Inhalt eine gestrichelte Schnittlinie auf
2 mm zusätzlichem Rand. Der RW403B besitzt keinen automatischen Schneider.
Adress- und Briefmarkenetiketten werden unabhängig voneinander gekürzt, ohne
Text, Porto oder Barcodes zu skalieren oder abzuschneiden.

Bluetooth-Druck auf Endlosmaterial benötigt eine vom Drucker gemeldete Firmware
ab **1.1.49**. Bei älterer Firmware bleibt der macOS-Systemdruck über USB die
Alternative. Die normale FEED-Kalibrierung für Lückenetiketten darf nicht mit
einer unmarkierten Endlosrolle gestartet werden.

### Briefmarken und Briefverlauf

Mehrseitige Internetmarken-PDFs der Deutschen Post können als Bündel importiert
werden. Label Helper:

- druckt Marken in Originalgröße und verteilt sie platzsparend auf Etiketten,
- erkennt erneut importierte Marken und behält ihren lokalen Druckstatus,
- zeigt die vollständige Sendungsnummer mit Kopierfunktion,
- markiert unterbrochene Drucke zur manuellen Prüfung und
- verwaltet verfügbare, gedruckte und nach Fehldruck freigegebene Marken.

Bei **Adresse + Briefmarke** druckt die App zuerst die Adresse und danach die
reservierte Marke. Der Briefverlauf speichert Empfänger, Etsy-Bestellnummer,
Marke, Sendungsnummer und Druckfortschritt. Abgeschlossene Briefe können mit
**Nur Adresse**, **Nur Briefmarke** oder **Adresse und Briefmarke** erneut
geöffnet werden.

> [!WARNING]
> Eine Briefmarke darf nur für eine Sendung verwendet werden. Vor einem
> Markennachdruck muss der unbrauchbare Ausdruck vernichtet werden.

## Etsy-Browser-Erweiterung

Die Erweiterung ergänzt geöffnete Etsy-Bestellungen um **An Label Helper
senden**. Übertragen werden nur Bestellnummer und Empfängeradresse – lokal über
den App-Link `munbyn-labeler://etsy-order`. Artikeldaten werden nicht gelesen
und es wird niemals automatisch gedruckt.

Am einfachsten erfolgt die Einrichtung direkt in der App:

1. **Label Helper → Einstellungen → Allgemein** öffnen.
2. Unter **Etsy-Browser-Erweiterung** auf
   **Browser-Erweiterung einrichten …** klicken.
3. Chrome oder Safari wählen und den angezeigten Schritten folgen.

Alternativ kann `LabelHelper-Browser-Extension.zip` aus dem aktuellen Release
manuell installiert werden. Safari lädt die Erweiterung ohne Xcode nur temporär
für 24 Stunden beziehungsweise bis zum Beenden.

Die [vollständige Anleitung](BrowserExtension/README.md) erklärt Installation,
Updates und Fehlerbehebung für Chrome und Safari.

## Fehlerbehebung

### „Papier wird nicht erkannt“

Die Bluetooth-Verbindung funktioniert bereits; die Meldung stammt vom
Papierstatus des Druckers.

1. Drucker ausschalten und Etiketten entfernen.
2. **FEED** gedrückt halten, Drucker einschalten und die Taste nach dem Signalton
   loslassen.
3. Die automatische Kalibrierung vollständig abwarten und den Drucker neu starten.
4. Mindestens acht zusammenhängende Etiketten gerade einlegen und den Deckel schließen.
5. **FEED** bis zum Signalton halten, damit der Drucker die Etikettenlücke lernt.

Offizielle Hinweise:
[Sensorkalibrierung](https://support.munbyn.com/hc/en-us/articles/52525254689043-How-to-Fix-Red-Light-Paper-Recognition-Failure-via-Printer-Sensor-Calibration)
und
[Etikettengröße/Papiererkennung](https://support.munbyn.com/hc/en-us/articles/41520136801299-How-to-create-a-new-customized-label-size).

### Drucker wird nicht gefunden

- Bluetooth in macOS einschalten und den Zugriff für Label Helper erlauben.
- Den Drucker nah am Mac einschalten und erneut **Geräte suchen** wählen.
- Unter **Label Helper → Einstellungen → Bluetooth** den Verbindungsstatus und
  das kopierbare Diagnoseprotokoll prüfen.

## Entwicklung

Das Projekt ist ein Swift Package mit einer nativen SwiftUI-App. Der
vollständige Build erzeugt eine Universal-2-App inklusive Sparkle und
Browser-Erweiterung.

```bash
# App bauen und starten
./script/build_and_run.sh

# App nur bauen
./script/build_and_run.sh build

# Architekturen, Signatur und lokalen Start prüfen
./script/build_and_run.sh verify

# Protokoll- und Core-Selbsttests
swift run LabelCoreSelfTest

# Gerenderte Adress-, Briefmarken- und Payload-Geometrie prüfen
bash script/test_print_layout.sh
```

Die fertige App liegt unter `dist/Label Helper.app`. Für einen einfachen
SwiftPM-Entwicklungsstart stehen außerdem `swift build --product LabelHelper`
und `swift run LabelHelper` zur Verfügung.

Lokale Builds werden standardmäßig ad hoc signiert. Eine vorhandene feste
Signieridentität kann so verwendet werden:

```bash
LABEL_HELPER_CODE_SIGN_IDENTITY='Name der Signieridentität' \
  ./script/build_and_run.sh build
```

Die GitHub-Actions-Workflows bauen und prüfen die Universal-App, testen die
Drucklayouts und paketieren App sowie Browser-Erweiterung. Ein `v*`-Tag erzeugt
ein GitHub Release mit ZIP-Archiven, Prüfsummen und signiertem Update-Feed.

<details>
<summary><strong>Kompatibilitätskennungen für Mitwirkende</strong></summary>

Für bestehende Installationen bleiben einige historische Kennungen absichtlich
unverändert:

- Bundle-ID: `de.nicosaia.MunbynLabeler`
- Datenspeicher: `~/Library/Application Support/MunbynLabeler/`
- App-Link: `munbyn-labeler://etsy-order`
- Safari-Erweiterung: `de.nicosaia.MunbynLabeler.EtsyExtension`

Diese Werte sollten nur zusammen mit einer vollständigen Migration geändert
werden. Repository, Swift-Package, Target und ausführbare Datei heißen
**LabelHelper**; das App-Paket heißt **Label Helper.app**.

</details>

## Haftungsausschluss

Die Software wird unentgeltlich und ohne Zusicherung bestimmter Eigenschaften
bereitgestellt. Die Nutzung erfolgt auf eigene Gefahr. Es wird insbesondere
keine Gewähr für Fehlerfreiheit, dauerhafte Verfügbarkeit,
Gerätekompatibilität, korrekte Adressübernahme, passende Etikettenmaße,
ausreichende Druckqualität oder die Annahme und Zustellung einer Sendung
übernommen.

Soweit gesetzlich zulässig, ist die Haftung des Autors für Schäden aus Nutzung
oder Nichtverfügbarkeit ausgeschlossen. Das gilt nicht bei Vorsatz oder grober
Fahrlässigkeit, Schäden an Leben, Körper oder Gesundheit, der Verletzung
wesentlicher Vertragspflichten, zwingender gesetzlicher Haftung oder einer
ausdrücklich übernommenen Garantie. Bei leicht fahrlässiger Verletzung
wesentlicher Vertragspflichten ist die Haftung auf den vertragstypischen,
vorhersehbaren Schaden begrenzt.

Dieser Hinweis ersetzt keine individuelle Rechtsberatung.
