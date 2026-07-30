# SimplStitch — CLAUDE.md

Dieses Dokument beschreibt die Architektur, Konventionen und den aktuellen Stand von SimplStitch. Lies es vollständig bevor du Code schreibst.

---

## Was ist SimplStitch?

**SimplStitch** ist eine macOS-App zum Erstellen von Stichdateien für Heim-Stickmaschinen.
Kernbotschaft: „Du malst. Es wird eine Stichdatei." — kein Nutzer soll je über Stiche nachdenken müssen.

Maskottchen: **Bobbi the Twister** (kleines Bobbin-Männchen, dreht Faden).

---

## Tech Stack

- **Sprache:** Swift, SwiftUI, SwiftData
- **Platform:** macOS 26+, Apple Silicon only (kein Intel)
- **Lizenz:** GPL-3.0 (Open Source, GitHub)
- **Lokalisierung:** Deutsch + Englisch von Tag 1 — `Localizable.xcstrings`, nie hardcodierte Strings
- **Python-Backend:** CPython gebündelt in `App.app/Contents/Resources/python/` — kein System-Python
- **Vertrieb:** GitHub Releases (DMG), Apple-notarisiert — kein App Store (GPL-3.0 inkompatibel)

---

## Architektur: Layered Architecture mit @Observable Stores

**Kein MVVM.** SwiftData's `@Query` lässt Views Daten direkt beobachten — kein ViewModel dazwischen.

### Die vier Schichten

```
Views (SwiftUI)
  └── @Query direkt für Datenzugriff, kein Business Logic

Stores / Feature Controllers (@Observable)
  ├── CanvasStore        — Zeichenfläche, Selektion, Handles
  ├── ProjectStore       — aktives Projekt, Speichern/Laden
  └── ThreadPaletteStore — Garnlisten-Verwaltung

Services (Business Logic, hinter Protocols)
  ├── StitchGenerationService  — Bridge zu InkStitch
  ├── FileExportService        — VP3, PES, JEF, EXP, DST, SVG (kein VIP, siehe Phase 7)
  ├── FileImportService        — alle Stickdatei-Formate (pyembroidery), kein separater SVG-Import
  ├── GPLPaletteImporter        — .gpl-Garnlisten, reines Swift
  └── ImageTraceService        — KI: Vision + Foundation Models

SwiftData Models (@Model)
  └── Reine Persistenz, kein Logic
```

### Swift ↔ Python Kommunikation
- Python läuft als Subprocess im Hintergrund
- Kommunikation via stdin/stdout (JSON)
- Einstiegspunkt Python-seitig: `bridge.py`
- Einstiegspunkt Swift-seitig: `PythonBridge.swift`

---

## Python-Backend

Zwei Bibliotheken, eine Python-Umgebung:

| Bibliothek | Zweck | Lizenz |
|---|---|---|
| InkStitch | Stichgenerierung (Vektorpfad → Stichkoordinaten) | GPL-3.0 |
| pyembroidery | Format I/O: liest 46, schreibt 20 Formate inkl. VP3 | MIT |

Python-Runtime gebündelt in `App.app/Contents/Resources/python/`.

---

## SwiftData Models

- `StitchProject` — Wrapper für `.stitchdesign` Document Package
- `DesignObject` — Basisklasse für alle Canvas-Elemente (Formen, Text)
- `StitchSettings` — Stichtyp, Dichte, Winkel, Unterlagentyp pro Objekt
- `ThreadColor` — Garnfarbe mit RGB + Herstellerinfo
- `ThreadPalette` — Garnlisten-Bibliothek
- `AppSettings` — Preferences, zuletzt geöffnete Projekte

---

## Projektformat: `.stitchdesign`

macOS Document Package (Ordner der wie eine Datei aussieht):

```
MeinDesign.stitchdesign/
├── content.svg     ← Design (InkStitch-Namespace-Attribute)
├── preview.png     ← Finder-Vorschau via QuickLook
└── assets/         ← Hintergrundbilder (kein base64-Bloat)
```

SVG nutzt InkStitch-kompatible Namespace-Attribute:
```xml
<path inkstitch:fill_method="tatami" inkstitch:angle="45" … />
```

Text bleibt als `<text>`-Element im SVG erhalten (editierbar). Konvertierung zu Pfaden nur beim Export/Stichberechnung.

---

## Import / Export

**Export:** VP3 (Pfaff, absolutes Muss), PES (Brother), JEF (Janome), EXP (Bernina/Melco), DST, SVG. VIP (Singer) ist **nicht** umsetzbar — pyembroidery (Stand 1.5.1) hat dafür weder Writer noch Reader (siehe Phase 7 in "Aktueller Stand")
**Import:** 46 Formate via pyembroidery, rekonstruiert als Laufstich-Best-Effort (siehe Phase 7). Eigenständiger SVG-Import (beliebige Illustrator/Inkscape-Dateien, nicht nur unser eigenes content.svg-Schema) ist noch offen — siehe Scope-Hinweis in Phase 7
**Garnlisten:** `.gpl` Format (GIMP Palette, kompatibel mit InkStitch/Inkscape)

---

## Canvas & Objekte

- Alle Objekte (Formen + Text) haben dieselben Handles: skalieren, drehen, verzerren, runden
- Handles wie PowerPoint-Rechteck-Handles
- Sticharten pro Objekt zuweisbar: Laufstich, Satinstich, Füllung (Tatami)
- Live-Vorschau der Stiche als Overlay auf dem Canvas

---

## UI-Anforderungen

- Jede Funktion erreichbar über: macOS Menüleiste UND Toolbar
- Toolbar: Icon + Text-Label (kein "Icon-Raten")
  - **Bewusste, vom Nutzer entschiedene Ausnahme (Issue #26, Nachbesserung 2):** die Werkzeug-/Exportieren-/Inspektor-Icons in der Haupt-Toolbar sind reine Icons mit Mouseover-Tooltip (`.help(_:)`) statt permanent sichtbarem Text — auf ausdrückliche Nutzerentscheidung nach einer Opus-Konsultation, da mehrere Anläufe mit sichtbarem Text (nebeneinander, dann übereinander) optisch "nicht aus einem Guss" wirkten. Menüleiste (Werkzeug-Menü) bleibt textbeschriftet und deckt dieselbe Funktion vollständig ab — die Regel gilt unverändert für alle anderen Toolbars/Panels (z.B. Ebenen-Panel-Buttons), nur die Haupt-Toolbar ist betroffen
- Live-Stichvorschau
- Icons wo immer möglich aus **SF Symbols** — kein selbstgebautes Icon, solange SF Symbols etwas Passendes hergibt. Nur wenn SF Symbols wirklich nichts Passendes hat, darf ein eigenes Icon gebaut werden. Betrifft v.a. Phase 8 (Toolbar + Menü), gilt aber für jedes Icon in der App

---

## KI-Funktion: Bild → Stichdatei

1. `VNDetectContoursRequest` (Vision Framework) → `CGPath` aus Foto
2. Foundation Models Framework (multimodal, WWDC26) → Stichtyp-Vorschläge pro Bereich
3. Vollständig on-device, kein Internet, keine API

---

## Konventionen

- Keine hardcodierten Strings — immer `String(localized:)` oder `LocalizedStringKey`
- Alle Services hinter Protocol (→ Testbarkeit, Mock-Implementierungen)
- `@Query` direkt in Views, kein ViewModel
- Nicht re-lesen was gerade editiert wurde
- Haiku für Boilerplate, Sonnet für Implementation, Opus nur bei echten Blockern

---

## Aktueller Stand

Kurzstatus: Canvas-Engine, Stichgenerierung, Import/Export und die grundlegende UI (Toolbar, Menüleiste, Inspector, Einstellungen) sind funktionsfähig und aktiv weiterentwickelt. Offene grössere Themen: Apple-Intelligence-Bildimport, Release-Pipeline (Notarisierung/automatisierte Releases).

Die vollständige, phasenweise Entwicklungshistorie (jede abgeschlossene Phase/jedes Issue mit Bug-Ursachen, bewussten Vereinfachungen und Verifikationsdetails) ist in den Skill `project-history` ausgelagert (`.claude/skills/project-history/SKILL.md`) — lädt bei Bedarf, nicht bei jeder Session. Frag danach oder lies die Datei direkt, wenn du wissen musst, warum ein bestehender Teil der App so gebaut ist wie er ist.
