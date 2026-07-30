//
//  FileExportService.swift
//  SimplStitch
//
//  Kombiniert die pro Objekt echte, via InkStitch generierten Stiche
//  (StitchGenerationServicing, Phase 6) zu einem einzigen Stickmuster und
//  schreibt es über den PythonBridge-Befehl "write_embroidery" (Phase 7,
//  bridge.py) in ein Maschinenformat. Formatwahl läuft über die Dateiendung
//  von `url` — pyembroidery.write dispatcht selbst, siehe bridge.py-Kommentar.
//
//  SVG ist ein Sonderfall: nutzt SVGDesignSerializer direkt statt der Bridge,
//  da unser eigenes content.svg-Schema (editierbare Vektorformen) erhalten
//  bleiben soll — pyembroidery kennt nur write_svg als Stich-Nachzeichnung,
//  das würde die Vektor-Editierbarkeit zerstören.
//
//  Empirischer Befund: pyembroidery (Stand 1.5.1) hat trotz der in CLAUDE.md
//  genannten Format-Liste keinen Writer (und keinen Reader) für VIP (Singer) —
//  `EmbPattern.supported_formats()` listet dafür keinen Eintrag. VIP ist daher
//  bewusst kein Fall von `EmbroideryFileFormat`.
//

import Foundation
import CoreGraphics

enum EmbroideryFileFormat: String, CaseIterable, Identifiable {
    case vp3
    case pes
    case jef
    case exp
    case dst
    case svg

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .vp3: return String(localized: "export.format.vp3")
        case .pes: return String(localized: "export.format.pes")
        case .jef: return String(localized: "export.format.jef")
        case .exp: return String(localized: "export.format.exp")
        case .dst: return String(localized: "export.format.dst")
        case .svg: return String(localized: "export.format.svg")
        }
    }
}

struct ExportSummary: Equatable {
    var stitchCount: Int
    var colorCount: Int
}

enum FileExportError: Error, LocalizedError {
    case noStitchableObjects

    var errorDescription: String? {
        switch self {
        case .noStitchableObjects:
            return String(localized: "export.error.noStitchableObjects")
        }
    }
}

protocol FileExportServicing {
    func export(objects: [DesignObject], canvasSize: CGSize, to url: URL, format: EmbroideryFileFormat) async throws -> ExportSummary
    /// Stichgenerierung ohne Datei-Schreiben — fürs Export-Dialog-Vorschaufeld
    /// (Stichzahl/Farbanzahl), bevor der Nutzer den Zielort bestätigt.
    func previewSummary(objects: [DesignObject], canvasSize: CGSize, format: EmbroideryFileFormat) async throws -> ExportSummary
}

final class FileExportService: FileExportServicing {
    private let bridge: PythonBridging
    private let stitchGenerationService: StitchGenerationServicing
    private let svgSerializer: SVGDesignSerializing

    init(
        bridge: PythonBridging,
        stitchGenerationService: StitchGenerationServicing? = nil,
        svgSerializer: SVGDesignSerializing = SVGDesignSerializer()
    ) {
        self.bridge = bridge
        self.stitchGenerationService = stitchGenerationService ?? StitchGenerationService(bridge: bridge, svgSerializer: svgSerializer)
        self.svgSerializer = svgSerializer
    }

    func export(objects: [DesignObject], canvasSize: CGSize, to url: URL, format: EmbroideryFileFormat) async throws -> ExportSummary {
        if format == .svg {
            return try exportSVG(objects: objects, canvasSize: canvasSize, to: url)
        }
        let combined = try await combinedStitchesAndThreads(objects: objects, canvasSize: canvasSize)

        let payload: [String: Any] = [
            "stitches": combined.stitches.map { [$0.x, $0.y, $0.command.rawValue] },
            "threads": combined.threads,
            "outputPath": url.path,
        ]
        let result = try await bridge.send(command: "write_embroidery", payload: payload)

        let stitchCount = (result["stitchCount"] as? NSNumber)?.intValue ?? combined.stitches.count
        let colorCount = (result["colorCount"] as? NSNumber)?.intValue ?? combined.threads.count
        return ExportSummary(stitchCount: stitchCount, colorCount: colorCount)
    }

    func previewSummary(objects: [DesignObject], canvasSize: CGSize, format: EmbroideryFileFormat) async throws -> ExportSummary {
        if format == .svg {
            let stitchableObjects = stitchableObjects(from: objects)
            return ExportSummary(stitchCount: 0, colorCount: countDistinctColors(stitchableObjects))
        }
        let combined = try await combinedStitchesAndThreads(objects: objects, canvasSize: canvasSize)
        return ExportSummary(stitchCount: combined.stitches.count, colorCount: combined.threads.count)
    }

    private func exportSVG(objects: [DesignObject], canvasSize: CGSize, to url: URL) throws -> ExportSummary {
        let svg = svgSerializer.encode(
            objects: objects,
            canvasSize: canvasSize,
            backgroundImageFileName: nil,
            backgroundImageOpacity: 1.0,
            isBackgroundImageVisible: true,
            defaultThreadPaletteID: nil
        )
        try svg.write(to: url, atomically: true, encoding: .utf8)

        let stitchableObjects = stitchableObjects(from: objects)
        return ExportSummary(stitchCount: 0, colorCount: countDistinctColors(stitchableObjects))
    }

    private func combinedStitchesAndThreads(
        objects: [DesignObject],
        canvasSize: CGSize
    ) async throws -> (stitches: [StitchPoint], threads: [[String: Any]]) {
        let stitchableObjects = stitchableObjects(from: objects)
        guard !stitchableObjects.isEmpty else {
            throw FileExportError.noStitchableObjects
        }

        var combinedStitches: [StitchPoint] = []
        var threads: [[String: Any]] = []

        // Issue #18: Füllung und Rand sind unabhängige Stichpässe pro Objekt — beide werden (falls
        // aktiv) nacheinander angehängt. Wie schon bisher zwischen Objekten (unabhängig davon, ob
        // sich die Farbe tatsächlich unterscheidet — siehe bestehender Test
        // `combinesStitchesAcrossObjectsWithColorChangeBetweenBlocks`) wird zwischen JEDEM Paar
        // aufeinanderfolgender Pässe ein COLOR_CHANGE eingefügt, jetzt auch zwischen Füll- und
        // Randpass desselben Objekts.
        func appendPass(stitches: [StitchPoint]?, threadPayload: [String: Any]) {
            guard let stitches, !stitches.isEmpty else { return }
            if let last = combinedStitches.last {
                combinedStitches.append(StitchPoint(x: last.x, y: last.y, command: .colorChange))
            }
            combinedStitches.append(contentsOf: stitches)
            threads.append(threadPayload)
        }

        for object in stitchableObjects {
            // Ein einzelnes Objekt mit fehlerhafter Geometrie/Sticheinstellung soll nicht den
            // gesamten Export zum Absturz bringen — übersprungen statt den kompletten Export
            // abzubrechen (analog zum bereits bestehenden Überspringen leerer Stichfolgen unten).
            if object.hasFill, object.stitchSettings != nil {
                let stitches = try? await stitchGenerationService.generateStitches(for: object, canvasSize: canvasSize)
                appendPass(stitches: stitches, threadPayload: threadPayload(for: object))
            }
            if object.hasBorder, object.borderStitchSettings != nil {
                let stitches = try? await stitchGenerationService.generateBorderStitches(for: object, canvasSize: canvasSize)
                appendPass(stitches: stitches, threadPayload: borderThreadPayload(for: object))
            }
        }

        return (combinedStitches, threads)
    }

    /// Nur sichtbare Objekte mit einer aktiven, eingestellten Füllung ODER einem aktiven,
    /// eingestellten Rand können gestickt werden — beides fehlt (z.B. neu erzeugtes Text-Objekt),
    /// wird das Objekt beim Export stillschweigend übersprungen statt den gesamten Export
    /// fehlschlagen zu lassen. Reihenfolge folgt der Z-Order (wie SVGDesignSerializer).
    private func stitchableObjects(from objects: [DesignObject]) -> [DesignObject] {
        objects
            .filter { $0.isVisible && (($0.hasFill && $0.stitchSettings != nil) || ($0.hasBorder && $0.borderStitchSettings != nil)) }
            .sorted { $0.zIndex < $1.zIndex }
    }

    private func countDistinctColors(_ objects: [DesignObject]) -> Int {
        var keys = Set<String>()
        for object in objects {
            if object.hasFill, object.stitchSettings != nil {
                keys.insert(fillColorKey(for: object))
            }
            if object.hasBorder, object.borderStitchSettings != nil {
                keys.insert(borderColorKey(for: object))
            }
        }
        return keys.count
    }

    private func fillColorKey(for object: DesignObject) -> String {
        object.threadColor.map(colorKey) ?? object.fillColorHex.lowercased()
    }

    private func borderColorKey(for object: DesignObject) -> String {
        object.borderThreadColor.map(colorKey) ?? (object.borderColorHex ?? object.fillColorHex).lowercased()
    }

    private func colorKey(_ threadColor: ThreadColor) -> String {
        "\(threadColor.red),\(threadColor.green),\(threadColor.blue)"
    }

    private func threadPayload(for object: DesignObject) -> [String: Any] {
        if let threadColor = object.threadColor {
            var payload: [String: Any] = [
                "red": threadColor.red,
                "green": threadColor.green,
                "blue": threadColor.blue,
                "name": threadColor.name,
            ]
            if let catalogNumber = threadColor.catalogNumber {
                payload["catalogNumber"] = catalogNumber
            }
            return payload
        }
        let (red, green, blue) = Self.rgb(fromHex: object.fillColorHex)
        return ["red": red, "green": green, "blue": blue, "name": object.name]
    }

    private func borderThreadPayload(for object: DesignObject) -> [String: Any] {
        if let threadColor = object.borderThreadColor {
            var payload: [String: Any] = [
                "red": threadColor.red,
                "green": threadColor.green,
                "blue": threadColor.blue,
                "name": threadColor.name,
            ]
            if let catalogNumber = threadColor.catalogNumber {
                payload["catalogNumber"] = catalogNumber
            }
            return payload
        }
        let (red, green, blue) = Self.rgb(fromHex: object.borderColorHex ?? object.fillColorHex)
        return ["red": red, "green": green, "blue": blue, "name": object.name]
    }

    /// Nutzt `CGColor.fromHex` (PreviewImageRenderer.swift) statt Hex-Parsing zu duplizieren.
    private static func rgb(fromHex hex: String) -> (Int, Int, Int) {
        guard let color = CGColor.fromHex(hex), let components = color.components, components.count >= 3 else {
            return (0, 0, 0)
        }
        return (Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }
}

/// Nutzt keine echte Bridge — für Previews und UI-Arbeit ohne laufenden Python-Subprocess
/// (analog zu MockStitchGenerationService, Phase 6d).
final class MockFileExportService: FileExportServicing {
    var summaryToReturn = ExportSummary(stitchCount: 0, colorCount: 0)
    var errorToThrow: Error?

    func export(objects: [DesignObject], canvasSize: CGSize, to url: URL, format: EmbroideryFileFormat) async throws -> ExportSummary {
        if let errorToThrow { throw errorToThrow }
        return summaryToReturn
    }

    func previewSummary(objects: [DesignObject], canvasSize: CGSize, format: EmbroideryFileFormat) async throws -> ExportSummary {
        if let errorToThrow { throw errorToThrow }
        return summaryToReturn
    }
}
