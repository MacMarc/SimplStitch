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
  - `SVGDesignSerializer` (`SimplStitch/Services/`): `[DesignObject]` ↔ `content.svg` — native SVG-Elemente (`rect`/`ellipse`/`path`/`text`) statt alles auf `<path>` zu reduzieren, per `XMLParser`. Objekt-Metadaten (Name, Z-Order, Rotation, Skew, Sichtbarkeit/Sperre) als `data-ss-*`-Attribute, Sticheinstellungen als `inkstitch:*`-Attribute (`fill_method`, `angle`, `row_spacing_mm`, `underlay`)
  - **Vereinfachung:** Rotation/Skew werden als rohe `data-ss-rotation`/`data-ss-skew-*`-Werte mitgeführt, nicht in eine SVG-`transform`-Matrix gebacken — reicht für verlustfreien Roundtrip, muss aber für pixelgenaues Rendering (Phase 5) bzw. den echten InkStitch-Aufruf (Phase 6) noch in echte Transform-Komposition überführt werden. Ebenso sind die `inkstitch:*`-Attributnamen unser eigenes Schema, nicht zwingend 1:1 das, was echtes InkStitch erwartet — in Phase 6 gegen die reale InkStitch-Quelle verifizieren
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
- [ ] Stichgenerierung
- [ ] Import/Export
- [ ] UI (Toolbar + Menü)
- [ ] Apple Intelligence Integration
- [ ] Release-Pipeline (Notarisierung, GitHub Actions)
