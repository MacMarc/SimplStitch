# SimplStitch

![Lizenz](https://img.shields.io/badge/Lizenz-GPL--3.0-blue) ![Plattform](https://img.shields.io/badge/Plattform-macOS%2026%2B%20(Apple%20Silicon)-lightgrey) ![Status](https://img.shields.io/badge/Status-in%20aktiver%20Entwicklung-orange)

🇩🇪 Deutsch · [🇬🇧 English](README.en.md)

**Du malst. Es wird eine Stichdatei.**

SimplStitch ist eine macOS-App, mit der du direkt am Bildschirm zeichnest — Formen, Text, Linien — und daraus automatisch eine fertige Stichdatei für deine Heim-Stickmaschine entsteht. Kein Stickerei-Fachwissen nötig: Sticharten, Dichte und Unterlage werden sinnvoll vorbelegt, du kannst sie aber jederzeit selbst anpassen.

Maskottchen des Projekts: **Bobbi the Twister**, ein kleines Bobbin-Männchen, das ständig Faden dreht.

> ⚠️ **Früher Entwicklungsstand.** SimplStitch ist noch nicht veröffentlicht und kann sich jederzeit ändern. Feedback ist ausdrücklich erwünscht — siehe [Feedback & Issues](#feedback--issues).

---

## Inhalt

- [Über dieses Projekt](#über-dieses-projekt)
- [Warum nicht im Mac App Store?](#warum-nicht-im-mac-app-store)
- [Was SimplStitch kann](#was-simplstitch-kann)
- [Wie es funktioniert](#wie-es-funktioniert)
- [Verwendete Bibliotheken](#verwendete-bibliotheken)
- [Voraussetzungen & Installation](#voraussetzungen--installation)
- [Aus dem Quellcode bauen](#aus-dem-quellcode-bauen)
- [Projektstatus](#projektstatus)
- [Lizenz](#lizenz)
- [Feedback & Issues](#feedback--issues)

---

## Über dieses Projekt

SimplStitch ist ein **Vibe-Coding-Projekt**: Der weitaus grösste Teil des Codes wurde nicht klassisch Zeile für Zeile von Hand geschrieben, sondern gemeinsam mit einem KI-Assistenten ([Claude Code](https://claude.com/claude-code)) entwickelt — der Autor beschreibt in natürlicher Sprache, was gebraucht wird, prüft und lenkt das Ergebnis, die KI schreibt den grössten Teil der eigentlichen Implementierung.

Das bedeutet konkret:

- Es ist ein **Hobby-/Lernprojekt** eines einzelnen Autors, kein kommerzielles Produkt eines Teams.
- Die Entwicklungsgeschichte (inklusive Design-Entscheidungen, gefundener Bugs und bewusster Vereinfachungen) ist offen in [`CLAUDE.md`](CLAUDE.md) dokumentiert — das ist die technische Arbeitsgrundlage für die KI-Unterstützung, gleichzeitig aber auch das ehrlichste verfügbare Änderungsprotokoll des Projekts.
- Code-Qualität und Testabdeckung werden ernst genommen (automatisierte Tests laufen bei jeder Änderung mit), aber wie bei jedem Open-Source-Projekt gilt: **keine Garantie, Nutzung auf eigene Verantwortung** (siehe [Lizenz](#lizenz)).
- Wer Ungereimtheiten, Bugs oder unklaren Code findet — das ist bei diesem Entwicklungsstil nicht auszuschliessen. Bitte melden statt stillschweigend hinnehmen, siehe [Feedback & Issues](#feedback--issues).

## Warum nicht im Mac App Store?

SimplStitch nutzt [InkStitch](https://inkstitch.org/) für die eigentliche Stichberechnung, eine unter **GPL-3.0** lizenzierte Bibliothek. Damit steht SimplStitch selbst zwangsläufig ebenfalls unter GPL-3.0 (siehe [Lizenz](#lizenz)).

Die Nutzungsbedingungen des Mac App Store (u.a. zusätzliche Vertriebs- und Nutzungseinschränkungen, DRM-Vorgaben) stehen im Widerspruch zu den Bedingungen der GPL-3.0, die genau solche zusätzlichen Einschränkungen für Empfänger der Software ausdrücklich verbietet. Dieser Konflikt ist kein Einzelfall von SimplStitch — bekanntestes Beispiel ist VLC, das aus demselben Grund lange nicht im App Store verfügbar war.

SimplStitch wird deshalb **ausschliesslich über [GitHub Releases](https://github.com/MacMarc/SimplStitch/releases)** als notarisiertes DMG vertrieben, nicht über den App Store.

## Was SimplStitch kann

- **Zeichnen:** Formen (Rechteck, Kreis, Stern, Linie, Freihand-Pfad) und Text direkt auf dem Canvas, alle mit denselben Handles zum Skalieren, Drehen, Verzerren und Eckenrunden (wie in PowerPoint/Keynote)
- **Automatische Stichtyp-Vorschläge:** schmale, lange Formen bekommen automatisch Satinstich vorgeschlagen, Flächen Füllung (Tatami) — jederzeit manuell überschreibbar
- **Sticharten pro Objekt:** Laufstich, Satinstich, Füllung (Tatami), inklusive Dichte, Winkel und Unterlage
- **Unabhängige Füllung & Rand:** jedes Objekt kann Füllung und/oder Rand haben, mit eigenen Sticheinstellungen und Garnfarben
- **Live-Stichvorschau** direkt auf dem Canvas, während du Einstellungen änderst
- **Garnlisten:** 74 mitgelieferte Standard-Garnlisten (u.a. Madeira, Isacord, DMC, Robison-Anton) plus Import eigener `.gpl`-Paletten
- **Mehrfachauswahl & Gruppierung** von Objekten
- **Export** als VP3 (Pfaff), PES (Brother), JEF (Janome), EXP (Bernina/Melco), DST (Tajima) oder SVG
- **Import** von 46 Stickdatei-Formaten (Best-Effort-Rekonstruktion als Laufstich)
- Vollständig **lokalisiert in Deutsch und Englisch**
- Geplant: KI-gestützte Bild-zu-Stichdatei-Umwandlung, vollständig on-device (kein Internet, keine externe API)

## Wie es funktioniert

SimplStitch besteht aus zwei Teilen, die in derselben App zusammenlaufen:

1. **Die SwiftUI/SwiftData-App** (macOS, Apple Silicon) — Canvas, Objektverwaltung, Projektdateien, gesamte Benutzeroberfläche.
2. **Ein gebündeltes Python-Backend** — läuft als Hintergrundprozess innerhalb der App (kein System-Python nötig, kein Internetzugriff), zuständig für die eigentliche Stickerei-Fachlogik:
   - **[InkStitch](https://inkstitch.org/)** rechnet aus einer gezeichneten Form die tatsächlichen Stichkoordinaten aus (Vektorpfad → Nadeleinstiche)
   - **[pyembroidery](https://github.com/EmbroidePy/pyembroidery)** liest und schreibt die Stickdatei-Formate (VP3, PES, JEF, EXP, DST, …)

Swift und Python kommunizieren über eine schlanke JSON-Schnittstelle via stdin/stdout — die App schickt eine Anfrage ("berechne die Stiche für dieses Objekt"), das Backend antwortet mit den Ergebniskoordinaten.

Dein Design wird als `.stitchdesign`-Dokument gespeichert — ein macOS Document Package (sieht im Finder aus wie eine einzelne Datei, ist intern aber ein Ordner) mit einer editierbaren `content.svg` als Quelle der Wahrheit, einer `preview.png` fürs Finder-Vorschaubild und einem `assets/`-Ordner für Hintergrundbilder.

Mehr technische Details (Architektur, Datenmodell, Entwicklungsverlauf) stehen in [`CLAUDE.md`](CLAUDE.md).

## Verwendete Bibliotheken

| Bibliothek | Zweck | Lizenz |
|---|---|---|
| [InkStitch](https://inkstitch.org/) | Stichgenerierung (Vektorpfad → Stichkoordinaten); vendored unter [`Vendor/inkstitch_lib/`](Vendor/inkstitch_lib/), inkl. der 74 mitgelieferten Garnlisten unter [`Vendor/inkstitch_palettes/`](Vendor/inkstitch_palettes/) | GPL-3.0 |
| [pyembroidery](https://github.com/EmbroidePy/pyembroidery) | Format-I/O: liest 46, schreibt 20 Stickformate (u.a. VP3, PES, JEF, EXP, DST) | MIT |
| [inkex](https://pypi.org/project/inkex/) | Inkscape-SVG-Grundlagen, von InkStitch verwendet | GPL-2.0-or-later |
| [Shapely](https://pypi.org/project/shapely/), [NumPy](https://pypi.org/project/numpy/), [NetworkX](https://pypi.org/project/networkx/), [lxml](https://pypi.org/project/lxml/) | Geometrie-, Numerik- und XML-Verarbeitung, von InkStitch verwendet | BSD-3-Clause |
| [trimesh](https://pypi.org/project/trimesh/) | 3D-/Mesh-Hilfsfunktionen, von InkStitch verwendet | MIT |
| [colormath2](https://pypi.org/project/colormath2/) | Farbraum-Umrechnung, von InkStitch verwendet | BSD-3-Clause |
| CPython | Gebündelte Python-Laufzeit, keine System-Python-Abhängigkeit | PSF License |

Die vollständige Liste der transitiven Python-Abhängigkeiten (inkl. weniger zentraler Pakete wie Pillow, cssselect, pyparsing, scour, tinycss2 — allesamt permissiv lizenziert, MIT/BSD/Apache-2.0) steht in [`SimplStitch/Bridge/requirements.txt`](SimplStitch/Bridge/requirements.txt). Details zum InkStitch-Vendoring (Commit-Referenz, der eine notwendige Patch) stehen in [`Vendor/inkstitch_lib/VENDOR_PATCHES.md`](Vendor/inkstitch_lib/VENDOR_PATCHES.md).

## Voraussetzungen & Installation

- **macOS 26 oder neuer**
- **Apple Silicon (arm64)** — Intel-Macs werden nicht unterstützt

Fertige Builds gibt es (sobald verfügbar) unter [GitHub Releases](https://github.com/MacMarc/SimplStitch/releases) als notarisiertes DMG — einfach herunterladen, öffnen, in den Programme-Ordner ziehen.

## Aus dem Quellcode bauen

```bash
git clone https://github.com/MacMarc/SimplStitch.git
cd SimplStitch
open SimplStitch.xcodeproj
```

Beim Bauen in Xcode lädt eine Run-Script-Build-Phase automatisch eine passende CPython-Laufzeit herunter und bündelt sie zusammen mit den Python-Abhängigkeiten (InkStitch, pyembroidery, …) in `Contents/Resources/`. Dafür ist beim ersten Build eine Internetverbindung nötig (`ENABLE_USER_SCRIPT_SANDBOXING = NO`).

## Projektstatus

SimplStitch befindet sich in aktiver Entwicklung. Canvas-Engine, Stichgenerierung, Import/Export sowie die grundlegende UI (Toolbar, Menüleiste, Seitenleiste, Einstellungen) sind funktionsfähig. Offene grössere Themen:

- Apple-Intelligence-Integration (Bild → Stichdatei per Vision/Foundation Models)
- Release-Pipeline (Notarisierung, automatisierte GitHub-Releases)

Den detaillierten, laufend aktualisierten Fortschritt siehe Abschnitt „Aktueller Stand" in [`CLAUDE.md`](CLAUDE.md).

## Lizenz

SimplStitch steht unter der **GNU General Public License v3.0** — siehe [`LICENSE`](LICENSE) bzw. [`COPYING`](COPYING) für den vollständigen Lizenztext.

Kurz zusammengefasst (keine Rechtsberatung, es gilt der Lizenztext): Du darfst SimplStitch frei nutzen, verändern und weitergeben, auch kommerziell — musst abgeleitete Werke aber ebenfalls unter GPL-3.0 mit vollständigem Quellcode weitergeben. Die Software wird **ohne jede Gewährleistung** bereitgestellt.

## Feedback & Issues

Fehler gefunden, eine Idee für ein Feature, oder etwas ist einfach unklar? Bitte direkt als [GitHub Issue](https://github.com/MacMarc/SimplStitch/issues) melden — das ist der zentrale und bevorzugte Weg für Feedback zu diesem Projekt.
