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
    }

    private let packageManager: DocumentPackageManaging

    @Published private(set) var project: StitchProject

    /// Neues, leeres Dokument (`DocumentGroup(newDocument:)`) — Default-Massangabe wie bisher der
    /// Platzhalter in ContentView, bis der Nutzer eine andere Zeichenflächengrösse wählt.
    init(packageManager: DocumentPackageManaging = DocumentPackageManager()) {
        self.packageManager = packageManager
        self.project = StitchProject(name: "Unbenannt", lastKnownPath: "", canvasWidthMillimeters: 130, canvasHeightMillimeters: 180)
    }

    required init(configuration: ReadConfiguration) throws {
        self.packageManager = DocumentPackageManager()
        let projectName = (configuration.file.filename ?? "Unbenannt")
        self.project = try packageManager.readProject(from: configuration.file, projectName: projectName)
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        let encoded = try packageManager.encodedContent(for: project)
        return Snapshot(svgData: encoded.svgData, previewPNGData: encoded.previewPNGData)
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
        if let existingAssets = configuration.existingFile?.fileWrappers?["assets"] {
            children["assets"] = existingAssets
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
