//
//  StitchDesignDocument.swift
//  SimplStitch
//
//  `ReferenceFileDocument`-Wrapper fürs `.stitchdesign` Document Package
//  (Phase 8a) — macht `DocumentGroup` (SimplStitchApp.swift) möglich: Öffnen/
//  Sichern über den macOS-Standardweg (NSOpenPanel/NSSavePanel intern über
//  SwiftUI, Doppelklick im Finder öffnet die App, "Zuletzt geöffnet"-Menü,
//  Autosave, Fenstertitel mit Änderungspunkt).
//
//  `ReferenceFileDocument` statt `FileDocument`, weil der Inhalt
//  (`StitchProject`/`DesignObject`, beides SwiftData-`@Model`-Referenztypen)
//  kein reiner Value-Type ist. `ReferenceFileDocument` verlangt
//  `ObservableObject` (altes Combine-Pattern) — bewusst NICHT `@Observable`
//  (Swift Observation), die beiden Systeme vertragen sich nicht auf derselben
//  Klasse. Das feingranulare Tracking von Canvas-Änderungen übernimmt weiterhin
//  `CanvasStore` (`@Observable`), das direkt auf `project.objects` zugreift —
//  `@Published` hier feuert nur, wenn `project` als Ganzes ausgetauscht wird.
//
//  Kein eigener ModelContext/Container für {StitchProject, DesignObject,
//  StitchSettings} nötig — genau wie DocumentPackageManager.read(from:) schon
//  seit Phase 4 erzeugt dieses Dokument sie als freistehende `@Model`-Instanzen
//  ganz ohne ModelContext (SwiftData-`@Model`-Klassen funktionieren als
//  normale Objektgraphen auch ausserhalb eines Contexts, der ist nur für
//  Queries/Persistenz relevant). Persistenz läuft für diese drei Typen
//  weiterhin über content.svg (Phase 4/8a), nicht über SwiftDatas SQLite-
//  Store. Der globale `sharedModelContainer` (SimplStitchApp.swift) bleibt für
//  {ThreadPalette, ThreadColor, AppSettings} zuständig (projektübergreifend,
//  echt auf Disk persistiert, über einen echten Context/Container).
//
//  Snapshot ist bewusst (svgData, previewPNGData) statt eines fertigen
//  FileWrapper: `Snapshot` muss `Sendable` sein (läuft zwischen `snapshot()`
//  auf dem MainActor und `fileWrapper(snapshot:configuration:)` ggf. auf
//  einem Hintergrund-Thread), `FileWrapper` selbst ist das nicht. Ein
//  vorhandenes `assets`-Verzeichnis (Hintergrundbild) wird beim Schreiben
//  direkt aus `configuration.existingFile` übernommen, nicht über den
//  Snapshot geführt.
//
//  Scope-Hinweis: Hintergrundbild lässt sich aktuell nur beim ursprünglichen
//  Import über `DocumentPackageManager.write(_:to:importingBackgroundImageFrom:)`
//  setzen (Phase 4) — eine UI zum nachträglichen Setzen/Ändern über dieses
//  Dokument gibt es noch nicht, `assets/` wird beim Speichern nur 1:1 erhalten.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class StitchDesignDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.stitchDesign] }

    struct Snapshot: Sendable {
        var svgData: Data
        var previewPNGData: Data
        var backgroundImageChange: BackgroundImageChange
    }

    /// Issue #10: `fileWrapper(snapshot:configuration:)` kann `assets/` nicht mehr einfach immer
    /// 1:1 aus `configuration.existingFile` übernehmen, sobald ein NEUES Hintergrundbild gewählt
    /// oder das bestehende entfernt wurde — dieselben drei Fälle wie zuvor implizit (unverändert
    /// durchreichen), jetzt aber explizit unterscheidbar.
    enum BackgroundImageChange: Sendable {
        case unchanged
        case set(fileName: String, data: Data)
        case removed
    }

    private let packageManager: DocumentPackageManaging

    @Published private(set) var project: StitchProject
    /// Issue #10: rohe Bild-Bytes fürs Canvas-Rendering — bewusst NICHT in `StitchProject`/SwiftData
    /// gehalten (kein base64-Bloat, siehe CLAUDE.md), sondern hier direkt aus dem geöffneten
    /// `FileWrapper` bzw. einer frischen Bildauswahl gelesen. `nil`, wenn kein Hintergrundbild
    /// gesetzt ist. `ContentView` spiegelt das nach `CanvasStore` für die eigentliche Zeichnung.
    @Published private(set) var backgroundImageData: Data?

    private var pendingBackgroundImageChange: BackgroundImageChange = .unchanged

    /// Issue #29 (Punkt 7): unterscheidet "gerade frisch via `DocumentGroup(newDocument:)` erzeugt"
    /// von "aus einer bestehenden .stitchdesign-Datei geöffnet" — zuverlässiger als ein blosser
    /// `defaultThreadPaletteID == nil`-Check, der ein absichtlich leer gelassenes Feld eines
    /// bereits gespeicherten alten Projekts nicht von einem wirklich neuen Dokument unterscheiden
    /// könnte. Nur für dieses eine Seeding gebraucht (siehe `ContentView.onAppear`).
    let isNewDocument: Bool

    /// Neues, leeres Dokument (`DocumentGroup(newDocument:)`) — Default-Massangabe wie bisher der
    /// Platzhalter in ContentView, bis der Nutzer eine andere Zeichenflächengrösse wählt.
    init(packageManager: DocumentPackageManaging = DocumentPackageManager()) {
        self.packageManager = packageManager
        self.project = StitchProject(name: "Unbenannt", lastKnownPath: "", canvasWidthMillimeters: 130, canvasHeightMillimeters: 180)
        self.isNewDocument = true
        self.backgroundImageData = nil
    }

    required init(configuration: ReadConfiguration) throws {
        self.packageManager = DocumentPackageManager()
        let projectName = (configuration.file.filename ?? "Unbenannt")
        self.project = try packageManager.readProject(from: configuration.file, projectName: projectName)
        self.isNewDocument = false
        if let fileName = project.backgroundImageFileName {
            self.backgroundImageData = configuration.file.fileWrappers?["assets"]?.fileWrappers?[fileName]?.regularFileContents
        } else {
            self.backgroundImageData = nil
        }
    }

    /// Issue #10: setzt ein neues Hintergrundbild — die Bytes werden bis zum nächsten Speichern in
    /// `pendingBackgroundImageChange` gehalten, `fileWrapper(snapshot:configuration:)` schreibt sie
    /// dann tatsächlich unter `assets/`. `project.backgroundImageFileName` wird sofort gesetzt,
    /// damit SVG-Encode/Canvas-Rendering/Inspector-UI schon vor dem nächsten Save konsistent sind.
    func setBackgroundImage(fileName: String, data: Data) {
        project.backgroundImageFileName = fileName
        pendingBackgroundImageChange = .set(fileName: fileName, data: data)
        backgroundImageData = data
    }

    /// Entfernt das Hintergrundbild wieder — Deckkraft/Sichtbarkeit bleiben als Werte im Modell
    /// erhalten (nur `backgroundImageFileName` wird `nil`), falls der Nutzer später ein neues Bild
    /// wählt und dieselbe Einstellung erwartet.
    func removeBackgroundImage() {
        project.backgroundImageFileName = nil
        pendingBackgroundImageChange = .removed
        backgroundImageData = nil
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        let encoded = try packageManager.encodedContent(for: project)
        let change = pendingBackgroundImageChange
        pendingBackgroundImageChange = .unchanged
        return Snapshot(svgData: encoded.svgData, previewPNGData: encoded.previewPNGData, backgroundImageChange: change)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let contentWrapper = FileWrapper(regularFileWithContents: snapshot.svgData)
        contentWrapper.preferredFilename = "content.svg"
        let previewWrapper = FileWrapper(regularFileWithContents: snapshot.previewPNGData)
        previewWrapper.preferredFilename = "preview.png"

        var children: [String: FileWrapper] = [
            "content.svg": contentWrapper,
            "preview.png": previewWrapper,
        ]
        switch snapshot.backgroundImageChange {
        case .unchanged:
            if let existingAssets = configuration.existingFile?.fileWrappers?["assets"] {
                children["assets"] = existingAssets
            }
        case .set(let fileName, let data):
            let imageWrapper = FileWrapper(regularFileWithContents: data)
            imageWrapper.preferredFilename = fileName
            let assetsWrapper = FileWrapper(directoryWithFileWrappers: [fileName: imageWrapper])
            assetsWrapper.preferredFilename = "assets"
            children["assets"] = assetsWrapper
        case .removed:
            break // kein assets-Eintrag -> Hintergrundbild verschwindet aus dem Package.
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
