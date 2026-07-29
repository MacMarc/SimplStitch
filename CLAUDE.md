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
  ├── FileExportService        — VP3, PES, JEF, EXP, VIP, SVG
  ├── FileImportService        — alle Stickdatei-Formate + SVG
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

**Export:** VP3 (Pfaff, absolutes Muss), PES (Brother), JEF (Janome), EXP (Bernina/Melco), VIP (Singer), DST, SVG
**Import:** 46 Formate via pyembroidery + SVG
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
- Live-Stichvorschau

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

- [x] Xcode-Projekt angelegt (macOS 26+, arm64-only, SwiftUI + SwiftData)
  - Ordnerstruktur: `SimplStitch/{App,Models,Stores,Services,Bridge,Views}` (Xcode File-System-Synchronized-Groups, keine manuelle pbxproj-Pflege nötig)
  - Lokalisierung DE+EN aktiv (`Localizable.xcstrings`, `knownRegions` inkl. `de`)
  - GPL-3.0 `COPYING`, `.gitignore`, shared Scheme `SimplStitch`, GitHub-Actions-Gerüst (`.github/workflows/build.yml`) — lokaler Build via `xcodebuild` verifiziert
  - Offen: GitHub-Remote noch nicht angelegt/gepusht
- [x] Python-Backend gebündelt
  - CPython 3.12 (python-build-standalone, arm64) via `Scripts/bundle_python.sh`; Xcode Run-Script-Build-Phase "Bundle Python Runtime" kopiert die Runtime bei jedem Build nach `Contents/Resources/python/` (liegt bewusst ausserhalb von `SimplStitch/`, sonst würden Xcodes File-System-Synchronized-Groups tausende Runtime-Dateien einzeln einlesen)
  - `SimplStitch/Bridge/bridge.py` + `PythonBridge.swift` (Actor, stdin/stdout JSON, ein Request/eine Response pro Zeile) — als lose Resourcen landen `bridge.py`/`requirements.txt` flach unter `Contents/Resources/`, nicht unter `Bridge/`
  - `pyembroidery` (MIT) real installiert und getestet (Befehle `ping`, `write_vp3`, `read_embroidery`)
  - Roundtrip-Test `SimplStitchTests/PythonBridgeTests.swift` grün: Dummy-Stichkoordinaten → VP3 schreiben → zurücklesen
  - **Scope-Hinweis:** InkStitch selbst (GPL-3.0, Stichgenerierung) ist kein pip-Paket und noch NICHT gebündelt — folgt als Vendored-Library in Phase 6, wenn `StitchGenerationService` es tatsächlich aufruft
  - `ENABLE_USER_SCRIPT_SANDBOXING = NO` gesetzt (Build-Phase braucht Netzwerkzugriff für den Download)
- [x] SwiftData Models
  - `DesignObject` als **eine** konkrete `@Model`-Klasse mit `kind`-Enum-Discriminator (circle/rectangle/star/path/text) statt echter Swift-Vererbung — SwiftData-Relationships/@Query über Subklassen sind noch fehleranfällig; erfüllt denselben Zweck als gemeinsame Basis für alle Canvas-Elemente
  - `StitchSettings` (1:1 an `DesignObject`, cascade delete): `StitchType` (straight/satin/tatami), `density`, `angleDegrees`, `UnderlayType` (none/centerWalk/edgeWalk/zigzagNet)
  - `ThreadColor` (RGB 0–255 + Hersteller/Katalognummer) 1:n in `ThreadPalette` (cascade delete)
  - `StitchProject`: Wrapper-Metadaten fürs Document Package (`fileBookmarkData` statt reinem Pfad, da App Sandbox aktiv ist) + `objects: [DesignObject]` (cascade delete) — Quelle der Wahrheit für den Inhalt bleibt `content.svg` (Phase 4); die Relationship ist der In-App-Arbeitsstand
  - `AppSettings`: bewusst ohne gespeicherte "zuletzt geöffnete Projekte"-Liste (keine Logic in Persistenz-Modellen) — das leitet ein Store später per `@Query` aus `StitchProject.lastOpenedAt` ab
  - Schema in `SimplStitchApp.swift` registriert (alle 6 Typen)
  - Tests `SimplStitchTests/SwiftDataModelsTests.swift`: Roundtrip inkl. Relationships sowie Cascade-Delete-Verhalten (Projekt → DesignObjects → StitchSettings, Palette → ThreadColors) — grün
- [x] Projektformat `.stitchdesign`
  - `SVGDesignSerializer` (`SimplStitch/Services/`): `[DesignObject]` ↔ `content.svg` — native SVG-Elemente (`rect`/`ellipse`/`path`/`text`) statt alles auf `<path>` zu reduzieren, per `XMLParser`. Objekt-Metadaten (Name, Z-Order, Rotation, Skew, Sichtbarkeit/Sperre) als `data-ss-*`-Attribute, Sticheinstellungen als `inkstitch:*`-Attribute (`fill_method`, `angle`, `row_spacing_mm`, `underlay`)
  - **Vereinfachung:** Rotation/Skew werden als rohe `data-ss-rotation`/`data-ss-skew-*`-Werte mitgeführt, nicht in eine SVG-`transform`-Matrix gebacken — reicht für verlustfreien Roundtrip, muss aber für pixelgenaues Rendering (Phase 5) bzw. den echten InkStitch-Aufruf (Phase 6) noch in echte Transform-Komposition überführt werden. Ebenso sind die `inkstitch:*`-Attributnamen unser eigenes Schema, nicht zwingend 1:1 das, was echtes InkStitch erwartet — in Phase 6 gegen die reale InkStitch-Quelle verifizieren
  - `PreviewImageRenderer`: einfacher CoreGraphics-Renderer für `preview.png` (Rechteck/Kreis gefüllt, Stern/Pfad/Text nur als Bounding-Box) — bewusst simpel vor der echten Canvas-Engine; sollte deren Renderer in Phase 5 wiederverwenden statt duplizieren
  - `DocumentPackageManager` (Protocol `DocumentPackageManaging`): reiner I/O-Service, erzeugt/liest `content.svg` + `preview.png` + `assets/<Hintergrundbild>`. Bewusst **kein** SwiftUI `DocumentGroup`/`FileDocument` und keine UTType-Registrierung fürs Finder-Package-Icon — das ist Phase 8 (UI). Reconciliation mit bereits im ModelContext existierenden `StitchProject`-Einträgen (z.B. "zuletzt geöffnet") ist Aufgabe eines künftigen `ProjectStore`
  - `StitchProject.backgroundImageFileName` ergänzt (nur Dateiname, nicht Pfad) für die Asset-Referenz
  - Tests `SimplStitchTests/DocumentPackageManagerTests.swift`: vollständiger Save/Reopen-Roundtrip mit allen 5 Objektarten (inkl. StitchSettings, Rotation/Skew, Sichtbarkeit/Sperre, Umlauten im Text), Hintergrundbild-Kopie nach `assets/`, `preview.png` ist valides PNG — grün
- [ ] Canvas-Engine
- [ ] Stichgenerierung
- [ ] Import/Export
- [ ] UI (Toolbar + Menü)
- [ ] Apple Intelligence Integration
- [ ] Release-Pipeline (Notarisierung, GitHub Actions)
