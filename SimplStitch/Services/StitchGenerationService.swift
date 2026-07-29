//
//  StitchGenerationService.swift
//  SimplStitch
//
//  Ruft echte InkStitch-Stichgenerierung (vendored, siehe Vendor/inkstitch_lib/)
//  über den PythonBridge-Befehl "generate_stitches" auf (bridge.py, Phase 6b).
//  Das Payload wird aus demselben Element-Markup gebaut, das SVGDesignSerializer
//  auch für content.svg schreibt (SVGDesignSerializing.element(for:), Phase 6c) —
//  keine zweite, parallele Attribut-Übersetzung.
//

import Foundation
import CoreGraphics

/// Ein einzelner Stich in Design-Koordinaten (mm, Ursprung oben-links — wie CanvasStore/
/// content.svg). `command` folgt derselben pyembroidery-Konvention wie write_vp3/read_embroidery.
struct StitchPoint: Equatable {
    enum Command: Int {
        case stitch = 0
        case jump = 1
        case trim = 2
        case stop = 3
        case end = 4
        case colorChange = 5
    }

    var x: Double
    var y: Double
    var command: Command
}

enum StitchGenerationError: Error, LocalizedError {
    case missingStitchSettings

    var errorDescription: String? {
        switch self {
        case .missingStitchSettings:
            return "Objekt hat keine Sticheinstellungen."
        }
    }
}

protocol StitchGenerationServicing {
    func generateStitches(for object: DesignObject, canvasSize: CGSize) async throws -> [StitchPoint]
}

final class StitchGenerationService: StitchGenerationServicing {
    private let bridge: PythonBridging
    private let svgSerializer: SVGDesignSerializing

    init(bridge: PythonBridging, svgSerializer: SVGDesignSerializing = SVGDesignSerializer()) {
        self.bridge = bridge
        self.svgSerializer = svgSerializer
    }

    func generateStitches(for object: DesignObject, canvasSize: CGSize) async throws -> [StitchPoint] {
        guard let stitchType = object.stitchSettings?.stitchType else {
            throw StitchGenerationError.missingStitchSettings
        }

        let objectSvg = svgSerializer.element(for: object)
        let result = try await bridge.send(
            command: "generate_stitches",
            payload: [
                "canvasWidthMm": Double(canvasSize.width),
                "canvasHeightMm": Double(canvasSize.height),
                "objectSvg": objectSvg,
                "stitchType": stitchType.rawValue,
            ]
        )

        guard let rawStitches = result["stitches"] as? [[Any]] else {
            throw PythonBridgeError.invalidResponse("Antwort enthält kein 'stitches'-Feld")
        }

        return rawStitches.compactMap { entry in
            guard entry.count == 3,
                  let x = (entry[0] as? NSNumber)?.doubleValue,
                  let y = (entry[1] as? NSNumber)?.doubleValue,
                  let commandRaw = (entry[2] as? NSNumber)?.intValue,
                  let command = StitchPoint.Command(rawValue: commandRaw)
            else {
                return nil
            }
            return StitchPoint(x: x, y: y, command: command)
        }
    }
}

/// Nutzt keine echte Bridge — für Previews und UI-Arbeit ohne laufenden Python-Subprocess.
final class MockStitchGenerationService: StitchGenerationServicing {
    var stitchesToReturn: [StitchPoint]
    /// Wenn gesetzt, wirft `generateStitches` diesen Fehler statt `stitchesToReturn`
    /// zurückzugeben — simuliert z.B. einen InkStitch-Fehler (siehe 6f, Fehlersichtbarkeit).
    var errorToThrow: Error?

    init(stitchesToReturn: [StitchPoint] = [], errorToThrow: Error? = nil) {
        self.stitchesToReturn = stitchesToReturn
        self.errorToThrow = errorToThrow
    }

    func generateStitches(for object: DesignObject, canvasSize: CGSize) async throws -> [StitchPoint] {
        guard object.stitchSettings != nil else {
            throw StitchGenerationError.missingStitchSettings
        }
        if let errorToThrow {
            throw errorToThrow
        }
        return stitchesToReturn
    }
}
