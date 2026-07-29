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
  - `SVGDesignSerializer` (`SimplStitch/Services/`): `[DesignObject]` ↔ `content.svg` — native SVG-Elemente (`rect`/`ellipse`/`path`/`text`) statt alles auf `<path>` zu reduzieren, per `XMLParser`. Objekt-Metadaten (Name, Z-Order, Rotation, Skew, Sichtbarkeit/Sperre) als `data-ss-*`-Attribute, Sticheinstellungen als `inkstitch:*`-Attribute — seit Phase 6c gegen echtes InkStitch verifiziert und pro Stichtyp unterschiedlich (`fill_method`/`angle`/`row_spacing_mm`/`fill_underlay` für Tatami, `zigzag_spacing_mm`/`contour_underlay`/`center_walk_underlay`/`zigzag_underlay` für Satin, `running_stitch_length_mm` für Laufstich — kein gemeinsames Schema mehr über alle Typen)
  - **Vereinfachung:** Rotation/Skew werden als rohe `data-ss-rotation`/`data-ss-skew-*`-Werte mitgeführt, nicht in eine SVG-`transform`-Matrix gebacken — reicht für verlustfreien Roundtrip von `content.svg` selbst (Canvas-Rendering in Phase 5c wendet `rotationDegrees` bereits an), muss aber für den echten InkStitch-Aufruf ggf. noch in echte Transform-Komposition überführt werden, falls Objekte rotiert/verzerrt in die Stichgenerierung eingehen sollen (Phase 6 generiert bisher unrotiert)
  - `PreviewImageRenderer`: einfacher CoreGraphics-Renderer für `preview.png` (Rechteck/Kreis gefüllt, Stern/Pfad/Text nur als Bounding-Box) — bewusst simpel vor der echten Canvas-Engine; sollte deren Renderer in Phase 5 wiederverwenden statt duplizieren
  - `DocumentPackageManager` (Protocol `DocumentPackageManaging`): reiner I/O-Service, erzeugt/liest `content.svg` + `preview.png` + `assets/<Hintergrundbild>`. Bewusst **kein** SwiftUI `DocumentGroup`/`FileDocument` und keine UTType-Registrierung fürs Finder-Package-Icon — das ist Phase 8 (UI). Reconciliation mit bereits im ModelContext existierenden `StitchProject`-Einträgen (z.B. "zuletzt geöffnet") ist Aufgabe eines künftigen `ProjectStore`
  - `StitchProject.backgroundImageFileName` ergänzt (nur Dateiname, nicht Pfad) für die Asset-Referenz
  - Tests `SimplStitchTests/DocumentPackageManagerTests.swift`: vollständiger Save/Reopen-Roundtrip mit allen 5 Objektarten (inkl. StitchSettings, Rotation/Skew, Sichtbarkeit/Sperre, Umlauten im Text), Hintergrundbild-Kopie nach `assets/`, `preview.png` ist valides PNG — grün
- [ ] Canvas-Engine (Phase 5, in Unteraufgaben)
  - [x] 5a Basis-Canvas
    - `CanvasStore` (`SimplStitch/Stores/`, `@Observable @MainActor`): Zoom (0.1×–8×, geklemmt), Pan, `zoomToFit`, Konvertierung Design-Koordinaten (mm, Ursprung oben-links — wie `content.svg`) ↔ View-Koordinaten (Punkte)
    - `CanvasView` (`SimplStitch/Views/Canvas/`): SwiftUI `Canvas`, zeichnet weisses Stickflächen-Rechteck + 10mm-Raster; Zoom per `MagnificationGesture` (Trackpad-Pinch), Pan per `DragGesture` (Klick-Drag) — beides mit Live-Feedback während der Geste, committed erst bei `onEnded`
    - **Scope-Hinweis:** Zweifinger-Scroll-Pan (bräuchte AppKit-`NSViewRepresentable` für `scrollWheel`) bewusst weggelassen — Klick-Drag ist eine vollständige, funktionierende Pan-Lösung; kann bei Bedarf später ergänzt werden
    - `ContentView` zeigt `CanvasView` bereits im Detail-Bereich (mit Platzhalter-Canvasgrösse 130×180mm, bis Phase 8 echte Projekte via `DocumentGroup` öffnet)
    - Tests `SimplStitchTests/CanvasStoreTests.swift`: Zoom-Clamping, Pan-Akkumulation, Koordinaten-Roundtrip, `zoomToFit` — grün
    - App gebaut, gestartet, läuft ohne Crash (Prozess + Log geprüft) — **kein** visueller Screenshot möglich (Sandbox ohne Bildschirmaufnahme-/Bedienungshilfen-Berechtigung), daher Canvas-Rendering/Gesten nicht visuell verifiziert
  - [x] 5b Formen (Kreis, Rechteck, Stern, Freihand-Pfad als DesignObject)
    - `CanvasTool` (`SimplStitch/Stores/`): Werkzeugauswahl (select/rectangle/circle/star/path), jedes Formwerkzeug kennt seine `DesignObjectKind` + lokalisierten Anzeigenamen
    - `CanvasStore` erweitert: `currentTool`, `objects: [DesignObject]`, `beginDraft/updateDraft/commitDraft` — Klick-Drag erzeugt bei ausreichender Grösse (`minimumShapeSize`, 1mm) ein neues DesignObject und wechselt danach zurück zum Auswahl-Werkzeug. **`objects` lebt vorerst nur im Store** (kein ModelContext-Insert) — es gibt noch kein reales `StitchProject`, an das angehängt werden könnte; die SwiftData-Synchronisation folgt mit einem `ProjectStore` in Phase 8
    - Freihand-Pfad: Punkte werden während des Ziehens akkumuliert und beim Commit zu einem einfachen `"Mx,y Lx,y …"`-Pfadstring (SVG-Syntax, absolute Design-Koordinaten) zusammengesetzt — bewusst kein Kurven-/Glättungsalgorithmus, reiner Polygonzug
    - `DesignObjectPath` (`SimplStitch/Views/Canvas/`): `DesignObject.designSpacePath()` liefert den SwiftUI-`Path` in Design-Koordinaten (mm) fürs Rendering — Rechteck/Kreis direkt über `Path(roundedRect:)`/`Path(ellipseIn:)`, Stern über dieselbe Geometrie-Formel wie `SVGDesignSerializer.starPathData` (bewusst dupliziert, da Services- und View-Schicht getrennt bleiben sollen — bei Änderungen beide Stellen synchron halten), Freihand-Pfad über einen simplen M/L/Z-Parser (kein vollständiger SVG-Pfad-Parser)
    - `CanvasView`: zeichnet `store.objects` (Rechteck/Kreis/Stern gefüllt, Pfad gestrichelt-frei als Linie) sowie eine gestrichelte Live-Vorschau während des Zeichnens; Klick-Drag ist beim Auswahl-Werkzeug Pan, bei einem Formwerkzeug Formerzeugung (`AnyGesture`-Umschaltung); Design→View-Transformation läuft direkt über `GraphicsContext.transform`, respektiert live laufende Zoom-/Pan-Gesten
    - `CGColor.fromHex` in `PreviewImageRenderer.swift` von `private` auf modulintern geöffnet, damit das Canvas-Rendering dieselbe Hex-Parsing-Logik nutzt statt sie zu duplizieren
    - `ContentView`: Platzhalter-Segmented-Picker über dem Canvas zur manuellen Werkzeugauswahl — provisorisch, bis Phase 8 die echte Toolbar (Menü + Symbolleiste) bringt
    - Tests `SimplStitchTests/CanvasStoreTests.swift` (Formerzeugung, Normalisierung bei Drag in beliebiger Richtung, Mindestgrösse, Freihand-Pfad-Akkumulation, Tool-Reset nach Commit, fortlaufende Default-Namen) und `SimplStitchTests/DesignObjectPathTests.swift` (Bounding-Rect von Rechteck/Kreis/Freihand-Pfad, Stern nicht-leer) — grün (21 Tests gesamt)
    - App gebaut, gestartet, läuft ohne Crash (Prozess geprüft) — visuelle Verifikation weiterhin nicht möglich (siehe 5a-Hinweis)
  - [x] 5c Selektion & Handles
    - `CanvasHandle.swift` (`SimplStitch/Stores/`): `CanvasHandleKind` — acht Skalier-Griffe (Ecken + Kantenmitten, mit Vorzeichen-Tupel je Achse), `.rotate`, `.cornerRadius` (nur Rechteck)
    - `CanvasStore` erweitert um `selectedObjectID`/`selectedObject`, Hit-Testing (`object(atDesignPoint:)`, oberstes sichtbares Objekt nach `zIndex`) und `beginTransformDrag/updateTransformDrag/endTransformDrag` für Verschieben (handle `nil`) sowie Skalieren/Drehen/Eckenrunden über die Griffe — alles inkl. `rotationDegrees`, damit Griffe eines gedrehten Objekts korrekt mitrotieren (Skalieren hält dabei den gegenüberliegenden Anker-Punkt im Design-Raum fest, nicht nur lokal). Neu erzeugte Objekte werden nach `commitDraft()` automatisch selektiert; Werkzeugwechsel weg von `.select` hebt die Selektion auf
    - `DesignObjectPath.rotationTransform`: `CGAffineTransform`, die den unrotierten `designSpacePath()` um die Objektmitte auf die sichtbare Ausrichtung bringt — dieselbe Rotationskonvention wie `CanvasStore`s Hit-Testing/Handle-Platzierung (mathematisch verifiziert über Testfälle, u.a. `rotatingObjectMovesHandlePositionsWithIt`). Zuvor wurde `rotationDegrees` trotz vorhandenem Modellfeld nirgends angewendet — 5c ist der erste Konsument, `CanvasView.drawObjects` wendet sie jetzt ebenfalls an, sonst hätte ein Rotations-Griff keine sichtbare Wirkung
    - `CanvasView`: eine einzige `selectionGesture` (statt der bisherigen reinen `panGesture`) deckt beim Auswahl-Werkzeug Pan (leerer Bereich), Verschieben (Objektkörper) und Griff-Drag ab — SwiftUI erlaubt nur eine statisch angehängte Geste pro View, die Verzweigung passiert zur Laufzeit beim ersten `onChanged` anhand des Trefferpunkts (`beginSelectionInteraction`), das Ergebnis steckt bis `onEnded` in einem `@Observable`-Referenztyp `SelectionDragState` (Klasse statt Enum-`@State`, da die Gesture-Closures den Modus über mehrere Aufrufe hinweg synchron lesen/schreiben müssen). Selektionsrahmen + Griffe werden gezeichnet, Griff-Marker in fester Bildschirmgrösse (nicht mit reskaliert)
    - **Scope-Hinweis:** Verzerren (Skew) hat trotz vorhandener `skewXDegrees`/`skewYDegrees`-Felder im Modell noch keinen interaktiven Griff und wird auch beim Rendering noch nicht angewendet — Interaktionsmodell dafür (z.B. Modifier-Taste auf einem Skalier-Griff) ist noch nicht entschieden, folgt als eigener Schritt
    - **Vereinfachung:** Hit-Testing für Freihand-Pfade (Strich statt Fläche) und Text (Rendering folgt erst in 5d) läuft über die Bounding-Box statt exakter Pfad-/Glyphen-Geometrie — reicht zum Selektieren
    - Gesperrte Objekte (`isLocked`) lassen sich weiterhin selektieren, aber nicht verschieben/skalieren/drehen
    - Tests `SimplStitchTests/CanvasStoreTests.swift`: Auto-Selektion nach Formerzeugung, Selektion bei Werkzeugwechsel aufgehoben, Hit-Testing (inkl. oberstes Objekt bei Überlappung), Verschieben, Skalieren über Ecken-/Kanten-Griff (inkl. Mindestgrösse), Rotations-Griff (inkl. mitrotierender Griff-Positionen), Eckenradius-Griff (inkl. Klemmung), gesperrtes Objekt ignoriert Transform-Drag, Griff-Hit-Test-Toleranz — grün (45 Tests gesamt)
    - App gebaut, gestartet, läuft ohne Crash (Prozess geprüft) — visuelle Verifikation weiterhin nicht möglich (siehe 5a-Hinweis)
  - [x] 5d Text-Objekt
    - `CanvasTool.text` neu (SF-Symbol-Auswahl folgt erst mit der echten Toolbar in Phase 8, aktuell nur im Platzhalter-Segmented-Picker sichtbar). Erzeugung läuft über dasselbe Klick-Drag-Verfahren wie die Formwerkzeuge (`CanvasStore.beginDraft/updateDraft/commitDraft`): Ziehen legt die Box wie bei einem Rechteck fest, ein blosser Klick (Drag unter `minimumShapeSize`) erzeugt stattdessen eine Box in `CanvasStore.defaultTextBoxSize` (40×12mm) an der Klickposition — reines Klicken ist der erwartete Regelfall beim Textsetzen, im Gegensatz zu den anderen Formen also *kein* verworfenes Ergebnis
    - Direkt nach `commitDraft()` wechselt ein neues Text-Objekt automatisch in den Bearbeitungsmodus (`CanvasStore.editingTextObjectID`); `CanvasView` legt dafür eine `TextField`-Overlay über die Box (View-Koordinaten, `@FocusState`). Fokusverlust (Wegklicken, Return) beendet die Bearbeitung über `endEditingText()` — bleibt der Text dabei leer (nichts eingetippt), wird das Objekt wieder verworfen statt als leere Box liegen zu bleiben. Ein Doppelklick mit dem Auswahl-Werkzeug auf ein bestehendes (ungesperrtes) Text-Objekt startet die Bearbeitung erneut (`beginEditingText`, eigene `SpatialTapGesture(count: 2)` als `simultaneousGesture` neben der bestehenden Selektionsgeste)
    - **Vereinfachung:** Die Bearbeitungs-Overlay ignoriert `rotationDegrees` (TextField liegt immer achsenparallel) — nur das fertige Rendering (`CanvasView.drawText`) berücksichtigt Rotation, über dieselbe Konvention wie Formen (`DesignObjectPath.rotationTransform`), aber in die `GraphicsContext`-Transform statt in einen Pfad gelegt, da Text über `GraphicsContext.draw(Text:at:)` statt `Path` gezeichnet wird. Die Box skaliert beim Grössenziehen weiterhin nur sich selbst, nicht die Schriftgrösse (`fontSize` ist ein unabhängiges Feld) — Hit-Testing bleibt wie zuvor Bounding-Box-basiert
    - `PreviewImageRenderer` zeichnet Text jetzt ebenfalls als echte Glyphen statt als Platzhalter-Rahmen, über rohes CoreText (`CTLine`/`CGContext`) statt über den SwiftUI-`GraphicsContext` des Canvas-Renderers — beide Stellen bleiben bewusst getrennt (unterschiedliche Zeichen-APIs)
    - Tests `SimplStitchTests/CanvasStoreTests.swift`: Drag erzeugt Text-Box mit Auto-Edit, blosser Klick nutzt Default-Grösse, Beenden der Bearbeitung verwirft leer gebliebene Objekte / behält befüllte, `beginEditingText` ignoriert Nicht-Text- und gesperrte Objekte — grün (50 Tests gesamt)
    - App gebaut, gestartet, läuft ohne Crash (Prozess geprüft) — visuelle Verifikation weiterhin nicht möglich (siehe 5a-Hinweis)
  - [x] 5e Ebenen & Z-Order
    - `CanvasStore` erweitert: `objectsFrontToBack` (Objekte nach `zIndex` absteigend, oberstes/vorderstes zuerst — löst die bisher an zwei Stellen duplizierte Sortierung ab, `object(atDesignPoint:)` nutzt sie jetzt ebenfalls), `ZOrderMove`-Enum (`toFront`/`forward`/`backward`/`toBack`) mit `moveObject(_:_:)`, sowie `reorderObjects(fromFrontToBackOffsets:toFrontToBackOffset:)` für Drag-Umsortierung im Panel (`List.onMove`-Semantik, verifiziert gegen SwiftUIs `Array.move(fromOffsets:toOffset:)`). Alle Umsortierungen laufen über einen gemeinsamen `reassignZIndices`-Schritt, der `zIndex` lückenlos 0..<count neu vergibt — neu erzeugte Objekte bekommen weiterhin `zIndex = objects.count` (unverändert seit 5b) und landen damit automatisch vorne, da dieses Invariant erhalten bleibt. `toggleVisibility(of:)`/`toggleLock(of:)` ergänzt (vorher gab es `isVisible`/`isLocked` nur als Modellfelder ohne Store-API)
    - **Vereinfachung:** Z-Order-Umsortierung ignoriert `isLocked` bewusst (Sperre verhindert nur Verschieben/Skalieren/Drehen auf dem Canvas, nicht das Umsortieren über das Panel) — anders als z.B. Verschieben/Skalieren, die gesperrte Objekte weiterhin ignorieren (5c)
    - `LayersPanelView.swift` (`SimplStitch/Views/Canvas/`): `List(selection:)` über `store.objectsFrontToBack` (oberstes Objekt oben, wie in Illustrator/Affinity), synchron mit der Canvas-Selektion; pro Zeile Sichtbarkeits-Auge und Schloss-Icon (SF Symbols `eye`/`eye.slash`, `lock.fill`/`lock.open`) sowie Drag-Umsortierung (`onMove`, macOS-Listen sortieren per Drag ohne separaten Edit-Modus); vier Z-Order-Buttons unten (`square.3.layers.3d.top/bottom.filled`, `chevron.up`/`chevron.down`) rufen `CanvasStore.moveObject` fürs selektierte Objekt auf. Bewusst kein Umbenennen der Objekte — nicht Teil des Plan-Scopes ("Objekte sortieren, Ebenen-Panel"), Name bleibt reine Anzeige
    - `ContentView`: Ebenen-Panel über `.inspector(isPresented:)` (macOS-Standardmuster für ein Seitenpanel), Toggle-Button in einer `.toolbar`-ToolbarItem — wie der Werkzeug-Picker ein Platzhalter bis Phase 8 die echte Toolbar/Menüleiste bringt
    - Elf neue Lokalisierungsschlüssel unter `layers.*` (Panel-Titel, Toggle, Leerzustand, vier Z-Order-Aktionen, Ein-/Ausblenden, Sperren/Entsperren) in `Localizable.xcstrings`, DE+EN
    - Tests `SimplStitchTests/CanvasStoreTests.swift`: `objectsFrontToBack`-Reihenfolge, alle vier `ZOrderMove`-Fälle (inkl. Grenzfall vorderstes/hinterstes Objekt bleibt bei `forward`/`backward` unverändert, inkl. gesperrtes Objekt lässt sich trotzdem verschieben), `reorderObjects` gegen die tatsächliche `Array.move(fromOffsets:toOffset:)`-Semantik verifiziert, `toggleVisibility`/`toggleLock` — grün (60 Tests gesamt)
    - App gebaut, gestartet, läuft ohne Crash (Prozess + Log geprüft) — visuelle Verifikation weiterhin nicht möglich (siehe 5a-Hinweis)
- [x] Stichgenerierung (Phase 6)
  - [x] 6a InkStitch-Vendoring & Validierung
    - InkStitchs `lib/` (GPL-3.0, Commit `e7108fdbb4a8b4175717678593d17dbd218284ed`) unverändert vendored unter `Vendor/inkstitch_lib/lib/` — **bewusst am Repo-Root, nicht unter `SimplStitch/Bridge/`**: dieselbe Begründung wie bei der Python-Runtime (Phase 2) — Xcodes File-System-Synchronized-Groups würden sonst alle 247 `.py`-Dateien einzeln als Projektmitglieder einlesen. `Scripts/bundle_python.sh` kopiert `Vendor/inkstitch_lib/lib/` bei jedem Build zusätzlich nach `Contents/Resources/inkstitch_lib/lib/` (Geschwisterordner von `python/`, wie `bridge.py`)
    - Einziger Vendor-Patch: `Vendor/inkstitch_lib/lib/tartan/palette.py` (Original importiert `wx` fürs Tartan-Fill-GUI, von SimplStitch nie genutzt) durch einen 8-zeiligen wx-freien Stub ersetzt, der bei Instanziierung `NotImplementedError` wirft — dokumentiert in `Vendor/inkstitch_lib/VENDOR_PATCHES.md`. Rest von `lib/` läuft unverändert headless (kein Inkscape, kein wx/flask/GUI-Import im von `FillStitch`/`Stroke`/`SatinColumn` genutzten Codepfad)
    - `inkex` (PyPI, `==1.4.1`, dieselbe Quelle wie InkStitchs eigener Git-Tag) wird in `Scripts/bundle_python.sh` separat mit `--no-deps` installiert — deklariert `PyGObject`/GTK als Hard-Dependency, das auf einer sauberen macOS-Maschine nicht baubar ist, im genutzten Codepfad aber nie importiert wird. Echte Laufzeit-Abhängigkeiten von `inkex` sowie von InkStitch selbst (`shapely`, `networkx`, `lxml`, `numpy`, `trimesh`, `colormath2`, `pystitch`, u.a.) in `SimplStitch/Bridge/requirements.txt`
    - Verifiziert (nicht nur recherchiert): reale `FillStitch`/`Stroke`/`SatinColumn`-Instanzen liefern echte Stichkoordinaten, sowohl in einer Wegwerf-venv als auch — entscheidend — durch die tatsächlich gebündelte App-Runtime (`Contents/Resources/python/bin/python3` + `Contents/Resources/inkstitch_lib/`)
  - [x] 6b `bridge.py`: `generate_stitches`-Befehl
    - `cmd_generate_stitches(payload)`: Payload `{canvasWidthMm, canvasHeightMm, objectSvg, stitchType}` — `objectSvg` ist dasselbe Element-Fragment, das `SVGDesignSerializer` auch für `content.svg` schreibt. Wrapped es in ein Mini-SVG nach unserer bestehenden mm-viewBox-Konvention (passt bereits exakt zu InkStitchs `get_viewbox_transform`, keine manuelle Einheiten-Umrechnung nötig), lädt via `inkex.load_svg`, dispatcht explizit von unserem `StitchType` (nicht InkStitchs eigener Auto-Erkennung) auf `FillStitch`/`Stroke`/`SatinColumn`, ruft `.embroider(None, None)` auf
    - Ergebnis `{"stitches": [[x_mm, y_mm, command], ...]}` — `command` ist dieselbe pyembroidery-Konvention wie `write_vp3`/`read_embroidery` (STITCH=0/JUMP=1/TRIM=2/STOP=3/COLOR_CHANGE=5), direkt weiterverwendbar. InkStitchs eigene Exceptions werden als `ValueError` weitergereicht, `handle_line` verpackt sie automatisch in `{"ok": false, "error": ...}`
  - [x] 6c Attribut-Schema-Abgleich `SVGDesignSerializer`
    - Die in Phase 4 offen gelassene Lücke ("unser eigenes `inkstitch:*`-Schema, nie gegen echtes InkStitch verifiziert") geschlossen: Namespace sowie `angle`/`row_spacing_mm` stimmten bereits exakt; `fill_method`-Werte (`"tatami"` → `"tatami_fill"`) und das Underlay-Modell mussten korrigiert werden
    - Kein gemeinsames Attribut-Set mehr über alle Stichtypen: Tatami (`fill_method`, `angle`, `row_spacing_mm`, `fill_underlay`-Bool), Satin (`zigzag_spacing_mm`, drei unabhängige Bools `contour_underlay`/`center_walk_underlay`/`zigzag_underlay` statt eines Typs), Laufstich (nur `running_stitch_length_mm`, kein Winkel/Unterlage)
    - **Vereinfachung:** Real InkStitch kennt für Tatami nur ein An/Aus-Bool (keinen Unterlage-*Typ*) — unser `UnderlayType`-Enum ist beim Decoden für Tatami verlustbehaftet (jeder Nicht-`.none`-Wert normalisiert sich beim Roundtrip auf `.centerWalk`). Satin behält alle drei Typen verlustfrei, da sie dort auf echte, unterscheidbare InkStitch-Attribute abbilden
  - [x] 6d `StitchGenerationService.swift`
    - `SimplStitch/Services/StitchGenerationService.swift`: Protocol `StitchGenerationServicing` + Implementierung, baut das Payload aus `SVGDesignSerializing.element(for:)` (dafür von `private` auf Protocol-Requirement geöffnet — keine zweite, parallele Attribut-Übersetzung) + `StitchSettings.stitchType`, ruft `PythonBridge` auf, parst `[StitchPoint]` zurück
    - `PythonBridge` bekommt ein schmales Protocol `PythonBridging` (nur `send(command:payload:)`) vorgeschaltet, damit Services wie dieser gegen einen Test-Double statt den echten Subprocess getestet werden können — `PythonBridge` bleibt die einzige reale Implementierung
    - `MockStitchGenerationService` für Previews/Tests ohne laufenden Python-Subprocess
  - [x] 6e Live-Vorschau-Overlay
    - `CanvasStore.refreshStitchPreview()`: debounced (250ms) und abbrechbar (Cancel-and-Relaunch über eine gespeicherte `Task`-Property) — ausgelöst bei Selektionswechsel (`selectObject`/`commitDraft`) und nach Transform-Drags (`endTransformDrag`), sowie von aussen nach Sticheinstellungs-Änderungen. `stitchPreview: [StitchPoint]?` ist nur gesetzt, solange sie zur aktuell selektierten Objekt-ID gehört (verhindert veraltete Vorschauen bei schnellem Selektionswechsel)
    - `CanvasView.drawStitchPreview`: zeichnet die Vorschau als dünne Polylinien in Design-Koordinaten — STITCH-Segmente durchgezogen, alles andere (JUMP/TRIM/STOP/COLOR_CHANGE) gestrichelt
    - `StitchDevPanelView.swift` (`SimplStitch/Views/Canvas/`) + Einbindung in `ContentView`: minimaler Dev-Bedienbereich (Stichtyp-Picker, Dichte-/Winkel-Slider) fürs selektierte Objekt — bewusst provisorisch wie der Werkzeug-Picker/Ebenen-Toggle, bis Phase 8 einen echten Settings-Inspector bringt. Acht neue Lokalisierungsschlüssel unter `stitch.dev.*`, DE+EN
  - [x] 6f Fehlersichtbarkeit & Doku-Abschluss
    - `CanvasStore.stitchPreviewError: String?` + `CanvasView.drawStitchPreviewError`: fehlgeschlagene Stichgenerierung zeigt eine kleine rote Inline-Meldung nahe der Selektion statt lautlos nichts zu tun oder abzustürzen
    - **Empirischer Befund (korrigiert eine Annahme aus der 6a-Recherche):** Satin auf einer für Satin ungeeigneten Geometrie wirft nicht zuverlässig einen Fehler — ein einfaches Rechteck erzeugte in Tests klaglos 508 Stiche (InkStitch interpretiert den geschlossenen Pfad offenbar selbst als zwei Schienen). Die Fehlerbehandlung bleibt trotzdem sinnvoll für tatsächlich entartete/ungültige Geometrie, ist aber kein Garant dafür, dass Satin auf beliebigen Formen sichtbar fehlschlägt — bewusst keine UI-Einschränkung, die Formen für Satin vorab filtert (siehe Plan-Entscheidung: best-effort statt Restriktion)
  - **Scope-Hinweis:** automatischer Stichtyp-Vorschlag (Heuristik), Format-Export über den bestehenden VP3-Testpfad hinaus, und Toolbar-/Menü-Verdrahtung des Dev-Panels bleiben spätere Phasen (7/8) — nicht Teil von Phase 6
  - Tests: `PythonBridgeTests` (`generate_stitches` gegen echtes Rechteck), `StitchGenerationServiceTests` (Payload-Aufbau/Parsing gegen gestubbte Bridge + ein echter Ende-zu-Ende-Test), `CanvasStoreTests` (Debounce/Selektionswechsel/Fehlerpfad der Live-Vorschau, alle gegen `MockStitchGenerationService`) — grün (70 Tests gesamt)
  - App gebaut, gestartet, läuft ohne Crash (Prozess + Log geprüft). Visuelle Verifikation diesmal **möglich** (siehe `run-and-screenshot`-Skill, `.claude/skills/`) — Screenshot bestätigt Fenster/Canvas/Werkzeugleiste; ein `click at {x,y}`-Klick auf den Werkzeug-Picker wurde nachweislich entgegengenommen (SwiftUI-Segmented-Picker reagiert auf koordinatenbasierte Klicks, anders als auf AXUIElement-Namenszugriff). Vollständiges Klick-Ziehen einer Form zur Live-Demo der Stichvorschau bräuchte ein echtes Drag-Event-Tool (`cliclick` o.ä., aktuell nicht installiert) — die Vorschau-Logik selbst ist stattdessen über `CanvasStoreTests` (inkl. Debounce-Timing) und die echte InkStitch-Integration in `StitchGenerationServiceTests`/`PythonBridgeTests` verifiziert
- [x] Import/Export (Phase 7)
  - `bridge.py` erweitert: `write_embroidery` — generischer Multi-Format-Export (Formatwahl über die Dateiendung von `outputPath`, `pyembroidery.write` dispatcht selbst), nimmt zusätzlich eine Garnfarben-Liste (`threads`) entgegen und fügt `add_thread` pro Farbblock ein. `read_embroidery` liefert jetzt zusätzlich `threads` (RGB + Name/Katalognummer aus `pattern.threadlist`) statt nur roher Stichkoordinaten
  - **Empirischer Befund 1 (korrigiert die in CLAUDE.md genannte Formatliste):** pyembroidery (Stand 1.5.1) hat keinen Writer **und** keinen Reader für VIP (Singer) — `EmbPattern.supported_formats()` listet dafür keinen Eintrag. VIP ist daher bewusst kein Fall von `EmbroideryFileFormat`; unterstützt werden VP3/PES/JEF/EXP/DST (alle mit echtem Writer) sowie SVG (eigener Pfad, kein pyembroidery)
  - **Empirischer Befund 2 (RGB-Rundtrip ist formatabhängig):** VP3 speichert die exakte Garnfarbe verlustfrei; PES/JEF runden dagegen beim Schreiben auf die nächstliegende Farbe der herstellereigenen Fadenkarte (z.B. `(255,0,0)` → `(237,23,31)` "Red" bei PES); EXP/DST kennen im Format gar keine Farbinformation (`threadlist` bleibt beim Zurücklesen leer, da Tajima/Melco-Maschinen Fadenwechsel manuell ohne eingebettete RGB-Angabe signalisieren)
  - **Empirischer Befund 3 (echter Bug, kein Rand-, sondern Regelfall für eine DE-first-App):** pyembroiderys VP3-Writer berechnet die Byte-Länge eines Garnnamens über Pythons `len()` (Zeichenanzahl) statt der tatsächlichen UTF-8-Byte-Länge — bei Umlauten (z.B. "Grün": 4 Zeichen, aber 5 UTF-8-Bytes) verschiebt das alle nachfolgenden Binärfelder um die Differenz, die Datei lässt sich danach nicht mehr einlesen (`ValueError: read length must be non-negative or -1`). Gefixt in `bridge.py` (`_ascii_safe_thread_text`): Garnname/Katalognummer werden vor `add_thread` transliteriert (deutsche Umlaute/ß explizit, Rest über `unicodedata`-NFKD + ASCII-Fallback) — vorsorglich für alle Zielformate, nicht nur das VP3, an dem der Fehler gefunden wurde
  - `FileExportService.swift` (Protocol `FileExportServicing`): kombiniert die pro Objekt echten, via `StitchGenerationServicing` (Phase 6) generierten Stiche zu einem einzigen Muster — sichtbare Objekte mit `stitchSettings`, sortiert nach Z-Order (wie `SVGDesignSerializer`), mit eingefügtem `COLOR_CHANGE`-Stich zwischen Objekten unterschiedlicher Garnfarbe (`threadColor` falls gesetzt, sonst aus `fillColorHex` abgeleitet über das bestehende `CGColor.fromHex`, keine zweite Hex-Parsing-Implementierung). SVG ist Sonderfall: nutzt `SVGDesignSerializer` direkt (editierbares Vektor-Schema bleibt erhalten) statt `pyembroidery.write_svg` (reine Stich-Nachzeichnung). `previewSummary(...)` teilt sich die komplette Kombinationslogik mit `export(...)` (eine gemeinsame private Methode), damit der Export-Dialog Stichzahl/Farbanzahl anzeigen kann, ohne bereits zu schreiben
  - `FileImportService.swift` (Protocol `FileImportServicing`): liest über `read_embroidery` (46 Formate) in `ImportedEmbroideryPattern` (Stiche + Garnfarben). `designObjects(from:)` rekonstruiert daraus pro Farbblock (getrennt durch `COLOR_CHANGE`) ein `.path`-`DesignObject` mit Laufstich-Sticheinstellungen (Stichlänge = mittlerer Stichabstand im Block) — der Pfad zeichnet die tatsächlichen Nadeleinstiche nach (`JUMP`-Punkte sind `M`, da dort kein Faden gelegt wird; der jeweils folgende `STITCH`-Punkt ist `L` ab der Jump-Landung). **Vereinfachung:** eine Stickdatei enthält nur fertige Stichkoordinaten, keine Vektorformen — Füllung/Satin/Unterlage der Originaldatei sind daraus nicht rekonstruierbar, Reimport ist bewusst eine Best-Effort-Nachzeichnung als Laufstich, kein verlustfreier Roundtrip
  - `GPLPaletteImporter.swift` (Protocol `GPLPaletteImporting`): reiner Swift-Parser für `.gpl` (GIMP Palette), kein Python-Bezug — "GIMP Palette"-Kopfzeile Pflicht, `Name:`/`Columns:`/`#`-Zeilen erkannt, Farbzeilen `R G B [Name]` mit beliebiger Whitespace-Trennung (kein garantiertes Tab)
  - Elf neue Lokalisierungsschlüssel unter `export.*`/`import.*`/`gpl.*` in `Localizable.xcstrings`, DE+EN
  - Provisorischer Export-Dialog (`ExportDialogView.swift`, `Views/Canvas/`) + Toolbar-Button in `ContentView` (Share-Icon, SF Symbol `square.and.arrow.up`) — Formatwahl-Picker, Live-Vorschau Stichzahl/Farbanzahl (`previewSummary`, aktualisiert bei Formatwechsel), `NSSavePanel` fürs Zielverzeichnis. Bewusst provisorisch wie Werkzeug-Picker/Ebenen-Toggle, bis Phase 8 die echte Menü-/Toolbar-Verdrahtung bringt. Eigener `PythonBridge`/`FileExportService` einmalig in `ContentView` gehalten (nicht pro Sheet-Öffnung neu erzeugt), sonst würde jedes Öffnen einen weiteren, nie beendeten Subprocess starten
  - **Scope-Hinweis:** Import ist auf Service-Ebene fertig (`FileImportService` + `designObjects(from:)`), aber noch nicht an ein Datei-Öffnen-Menü/eine Drag&Drop-Fläche angebunden — das ist Teil von Phase 8 (echte Menü-/Toolbar-Verdrahtung), ebenso die UI für den `.gpl`-Paletten-Import
  - **Scope-Hinweis 2 (echte Lücke, nicht nur Verdrahtung):** der geplante eigenständige SVG-Import ("SVG-Import (eigenständig, ohne Python)") ist NICHT umgesetzt. `SVGDesignSerializer.decode()` (Phase 4) öffnet zwar bereits jede Datei mit Standard-`<rect>`/`<ellipse>`/`<path>`/`<text>`-Elementen, auch ganz ohne unsere `data-ss-*`/`inkstitch:*`-Attribute (die werden beim Fehlen einfach auf Default-Werte gemappt) — das reicht für unser eigenes `content.svg`-Schema, aber NICHT für beliebige Illustrator/Inkscape-Exporte: keine Einheiten-Umrechnung (px/pt werden wie mm behandelt), kein `<circle>`, keine `<g>`-Gruppen/`transform`-Kompositionen, kein CSS-`style=`-Attribut statt Präsentationsattributen, keine Polygone/Polylinien. Ein robuster generischer SVG-Import ist ein eigener, nicht-trivialer Aufgabenblock und noch offen
  - Tests: `PythonBridgeTests` (write_embroidery-Roundtrip inkl. Garnfarben gegen VP3, nicht unterstützte Endung wirft), `FileExportServiceTests` (Payload-Aufbau/Farbwechsel-Einfügepunkt gegen gestubbte Services, SVG-Sonderfall ruft die Bridge nie auf, `noStitchableObjects`-Fehlerfall, echter Ende-zu-Ende-Test mit zwei Farben gegen VP3), `FileImportServiceTests` (Parsing, Farbblock-Aufteilung, Jump-Subpath-Logik, echter Roundtrip-Test gegen VP3), `GPLPaletteImporterTests` (Name-Direktive, Fallback auf Dateiname, Kommentare/`Columns:`, fehlerhafte Zeilen übersprungen, fehlender Header/leere Palette wirft) — grün (87 Tests gesamt)
  - App gebaut, gestartet, läuft ohne Crash (Prozess + Log geprüft). Visuell verifiziert (`run-and-screenshot`-Skill): Export-Button in der Toolbar per koordinatenbasiertem Klick ausgelöst, Dialog öffnet mit Formatwahl (VP3 vorausgewählt) und zeigt live die korrekte, lokalisierte Fehlermeldung "Projekt enthält keine sichtbaren Objekte mit Sticheinstellungen." (leerer Canvas) — bestätigt, dass `previewSummary` tatsächlich gegen die echte Bridge läuft, nicht nur gegen Mocks
- [ ] UI (Toolbar + Menü) (Phase 8, in Unteraufgaben wie Phase 5)
  - [x] 8a Projekt-Grundlage: `DocumentGroup` + `StitchDesignDocument`
    - Eigener `UTType` fürs `.stitchdesign`-Package (`UTType+StitchDesign.swift`, conforms to `.package`) + eigene `Info.plist` (`SimplStitch/Info.plist`, `GENERATE_INFOPLIST_FILE = NO`) mit `CFBundleDocumentTypes`/`UTExportedTypeDeclarations` — komplexe Array/Dict-Strukturen lassen sich nicht über einfache `INFOPLIST_KEY_*`-Build-Settings abbilden, das verlangt eine echte Info.plist-Datei. `ENABLE_USER_SELECTED_FILES` von `readonly` auf `readwrite` (App Sandbox muss beim Sichern schreiben dürfen). Eine `PBXFileSystemSynchronizedBuildFileExceptionSet`-Exception verhindert, dass die Synchronized-Group die Info.plist zusätzlich in "Copy Bundle Resources" einbindet (sonst Doppel-Kopie, nur eine Warnung, aber sauber vermeidbar)
    - **Empirischer Befund:** ein einzelner `xcodebuild`-Build reicht nicht zuverlässig, damit Finder/Launch Services das neu deklarierte UTType erkennt, wenn dieselbe App vorher schon (ohne das UTType) unter demselben DerivedData-Pfad registriert war — `lsregister -dump` zeigte die App zunächst gar nicht registriert, trotz "RegisterWithLaunchServices"-Schritt im Build-Log. Erst ein manuelles `lsregister -f -R -trusted <App>` brachte die Registrierung (danach als `de.daslama.simplstitch.stitchdesign` — UTIs werden von Launch Services klein-normalisiert, das ist unabhängig vom eigentlichen Problem). Bei einer regulären Installation im `/Applications`-Ordner (statt wiederholt aus demselben DerivedData-Pfad heraus) dürfte das nicht auftreten, ist aber ein Debugging-Hinweis fürs Entwickeln
    - `StitchDesignDocument: ReferenceFileDocument, ObservableObject` (`Models/StitchDesignDocument.swift`) — `ReferenceFileDocument` statt `FileDocument`, da der Inhalt (`StitchProject`/`DesignObject`, SwiftData-`@Model`-Referenztypen) kein reiner Value-Type ist. Verlangt klassisches `ObservableObject`/`@Published` (`import Combine`) statt `@Observable` — beide Observation-Systeme vertragen sich nicht auf derselben Klasse; das feingranulare Tracking von Canvas-Änderungen bleibt bei `CanvasStore` (`@Observable`), das direkt auf `project.objects` zugreift. `Snapshot` ist bewusst `(svgData: Data, previewPNGData: Data)` statt eines fertigen `FileWrapper` — `Snapshot` muss `Sendable` sein (läuft zwischen `snapshot()` auf dem MainActor und `fileWrapper(snapshot:configuration:)` ggf. auf einem Hintergrund-Thread), `FileWrapper` selbst ist es nicht. Ein vorhandenes `assets`-Verzeichnis wird beim Schreiben direkt aus `configuration.existingFile` übernommen (nicht über den Snapshot geführt), damit es bei jedem Speichern erhalten bleibt
    - **Vereinfachung:** kein eigener `ModelContext`/`ModelContainer` für {StitchProject, DesignObject, StitchSettings} — genau wie `DocumentPackageManager.read(from:)` schon seit Phase 4 erzeugt das Dokument sie als freistehende `@Model`-Instanzen ganz ohne Context (SwiftData-`@Model`-Klassen funktionieren als normale Objektgraphen auch ausserhalb eines Context, der ist nur für Queries/Persistenz relevant). Persistenz läuft für diese drei Typen weiterhin über `content.svg`, nicht über SwiftDatas SQLite-Store. `SimplStitchApp.sharedModelContainer` ist entsprechend auf {ThreadPalette, ThreadColor, AppSettings} reduziert (projektübergreifend, echt auf Disk persistiert)
    - `DocumentPackageManager` erweitert: `encodedContent(for:) -> (svgData: Data, previewPNGData: Data)` (Sendable-Kern fürs Dokument-Snapshot, teilt sich den SVGDesignSerializer/PreviewImageRenderer-Kern mit dem bestehenden URL-basierten `write(_:to:)`) und `readProject(from fileWrapper:projectName:)` (FileWrapper-Pendant zu `read(from:)`)
    - `CanvasStore` umgebaut: `objects`/`canvasSizeMillimeters` sind jetzt computed properties über ein gehaltenes `StitchProject` statt eigenem Array/Wert — Observation trackt trotz des Zwischenschritts korrekt (SwiftUI trackt zur Laufzeit den tatsächlichen Zugriffspfad, nicht nur direkt als `@Observable` markierte Properties; `project` ist ein SwiftData-`@Model`, dessen Properties selbst Teil des Tracking sind). Komfort-Initializer `init(canvasSizeMillimeters:...)` bleibt erhalten (erzeugt intern ein unbenanntes `StitchProject`) — spart die Migration von ~30 bestehenden Testzeilen, die kein eigenes Projekt brauchen; Produktivcode (`ContentView`) nutzt den neuen `init(project:...)`
    - `ContentView` nimmt jetzt `document: StitchDesignDocument` entgegen und baut `canvasStore` aus `document.project`; `SimplStitchApp` nutzt `DocumentGroup(newDocument:)` statt `WindowGroup`
    - Tests: komplette bestehende Suite (87 Tests) bleibt grün nach dem `CanvasStore`-Umbau — keine neuen Unit-Tests für `StitchDesignDocument`/Info.plist-Konfiguration selbst, das lässt sich nicht sinnvoll headless testen (SwiftUI-`DocumentGroup`-Lebenszyklus, Launch-Services-Registrierung)
    - Visuell verifiziert (`run-and-screenshot`-Skill, inkl. AppleScript-Klicks + `osascript`-Tastatureingaben): App-Start ohne offenes Dokument zeigt automatisch den macOS-Standard-Öffnen-Dialog mit "Neues Dokument"-Button (wie Pages/TextEdit) → neues Dokument → Cmd+S schlägt korrekt `<Name>.stitchdesign` vor → Sichern erzeugt ein echtes Package mit `content.svg`/`preview.png` → Finder zeigt es als Datei-Icon, nicht als Ordner → Doppelklick im Finder öffnet die Datei in SimplStitch (Fenstertitel = Dateiname). Kompletter Speichern/Öffnen-Zyklus über den echten macOS-Dokumentenmechanismus bestätigt
    - **Scope-Hinweis:** Hintergrundbild lässt sich weiterhin nur über den URL-basierten Pfad (`DocumentPackageManager.write(_:to:importingBackgroundImageFrom:)`, Phase 4) setzen — keine UI dafür über `StitchDesignDocument`. "Zuletzt geöffnet"-Menü/Undo-Integration sind SwiftUI-`DocumentGroup`-Bordmittel, aber noch nicht einzeln durchgetestet
- [ ] Apple Intelligence Integration
- [ ] Release-Pipeline (Notarisierung, GitHub Actions)
