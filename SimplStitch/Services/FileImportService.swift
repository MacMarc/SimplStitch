//
//  FileImportService.swift
//  SimplStitch
//
//  Liest Stickdateien (46 Formate über pyembroidery, siehe bridge.py
//  "read_embroidery") als rohe Stich-/Farbdaten (`ImportedEmbroideryPattern`)
//  ein. `designObjects(from:)` rekonstruiert daraus Canvas-Objekte: pro
//  Farbblock (durch COLOR_CHANGE getrennt) ein `.path`-DesignObject, dessen
//  Pfad die tatsächlichen Nadeleinstiche als Polygonzug nachzeichnet
//  (JUMP-Stiche starten ein neues Teilstück statt eine durchgezogene Linie),
//  mit Laufstich-Sticheinstellungen (Stichlänge = mittlerer Stichabstand im
//  Block).
//
//  Vereinfachung: eine Stickdatei enthält nur die fertigen Stichkoordinaten,
//  keine Vektorformen — die Original-Stichart (Füllung/Satin/Unterlage) lässt
//  sich daraus nicht zurückgewinnen. Reimport ist daher bewusst eine
//  Best-Effort-Nachzeichnung als Laufstich, kein verlustfreier Roundtrip.
//

import Foundation
import CoreGraphics

struct ImportedThread: Equatable {
    var red: Int
    var green: Int
    var blue: Int
    var name: String?
    var catalogNumber: String?
}

struct ImportedEmbroideryPattern {
    var stitches: [StitchPoint]
    var threads: [ImportedThread]
}

protocol FileImportServicing {
    func importEmbroideryFile(at url: URL) async throws -> ImportedEmbroideryPattern
    func designObjects(from pattern: ImportedEmbroideryPattern) -> [DesignObject]
}

final class FileImportService: FileImportServicing {
    private let bridge: PythonBridging

    init(bridge: PythonBridging) {
        self.bridge = bridge
    }

    func importEmbroideryFile(at url: URL) async throws -> ImportedEmbroideryPattern {
        let result = try await bridge.send(command: "read_embroidery", payload: ["inputPath": url.path])

        guard let rawStitches = result["stitches"] as? [[Any]] else {
            throw PythonBridgeError.invalidResponse("Antwort enthält kein 'stitches'-Feld")
        }
        let stitches = rawStitches.compactMap { entry -> StitchPoint? in
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

        let rawThreads = result["threads"] as? [[String: Any]] ?? []
        let threads = rawThreads.map { entry in
            ImportedThread(
                red: (entry["red"] as? NSNumber)?.intValue ?? 0,
                green: (entry["green"] as? NSNumber)?.intValue ?? 0,
                blue: (entry["blue"] as? NSNumber)?.intValue ?? 0,
                name: entry["name"] as? String,
                catalogNumber: entry["catalogNumber"] as? String
            )
        }

        return ImportedEmbroideryPattern(stitches: stitches, threads: threads)
    }

    func designObjects(from pattern: ImportedEmbroideryPattern) -> [DesignObject] {
        var objects: [DesignObject] = []
        var blockIndex = 0
        var currentBlock: [StitchPoint] = []

        func finalizeBlock() {
            defer {
                blockIndex += 1
                currentBlock = []
            }
            guard let object = makeObject(from: currentBlock, thread: pattern.threads[safe: blockIndex], zIndex: objects.count) else {
                return
            }
            objects.append(object)
        }

        // Issue #30 (Punkt 3): TRIM/STOP schneiden den Faden — der nachfolgende Punkt darf daher
        // nicht per "L" mit der Nadelposition davor verbunden werden. Manche Stickdateien fügen nach
        // einem TRIM keinen eigenen JUMP-Stich ein (die neue Startposition steht direkt im nächsten
        // STITCH), ohne dieses Flag würde makeObject() dann fälschlich eine durchgezogene Linie quer
        // über den Fadenschnitt zeichnen. `pendingBreak` erzwingt für genau den nächsten Stich/Jump
        // dieselbe "M"-Behandlung wie einen echten JUMP (siehe makeObject-Kommentar).
        var pendingBreak = false
        for stitch in pattern.stitches {
            switch stitch.command {
            case .stitch, .jump:
                if pendingBreak {
                    var breakPoint = stitch
                    breakPoint.command = .jump
                    currentBlock.append(breakPoint)
                    pendingBreak = false
                } else {
                    currentBlock.append(stitch)
                }
            case .colorChange:
                currentBlock.append(stitch)
                finalizeBlock()
                pendingBreak = false
            case .trim, .stop:
                pendingBreak = true
            case .end:
                continue
            }
        }
        finalizeBlock()

        return objects
    }

    private func makeObject(from points: [StitchPoint], thread: ImportedThread?, zIndex: Int) -> DesignObject? {
        guard !points.isEmpty else { return nil }

        let minX = points.map(\.x).min() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        // Ein JUMP-Stich selbst legt keinen Faden (Nadel bewegt sich im Leerlauf dorthin) —
        // sein eigener Punkt ist daher ein "M" (kein verbindender Strich zum vorherigen Punkt),
        // während der nächste STITCH-Punkt danach wieder eine echte Linie ab der Jump-Landung ist.
        var pathData = ""
        var isFirstPoint = true
        for point in points {
            let isMove = isFirstPoint || point.command == .jump
            pathData += "\(isMove ? "M" : "L")\(String(format: "%.4f", point.x)),\(String(format: "%.4f", point.y)) "
            isFirstPoint = false
        }

        let object = DesignObject(
            name: thread?.name?.isEmpty == false ? thread!.name! : String(localized: "import.object.defaultName"),
            kind: .path,
            positionX: minX,
            positionY: minY,
            width: max(maxX - minX, 0.01),
            height: max(maxY - minY, 0.01)
        )
        object.pathData = pathData.trimmingCharacters(in: .whitespaces)
        object.zIndex = zIndex

        if let thread {
            object.fillColorHex = String(format: "#%02X%02X%02X", thread.red, thread.green, thread.blue)
            object.threadColor = ThreadColor(name: thread.name ?? "", red: thread.red, green: thread.green, blue: thread.blue, catalogNumber: thread.catalogNumber)
        }

        let settings = StitchSettings(stitchType: .straight, density: averageStitchLength(points), angleDegrees: 0, underlayType: .none)
        settings.designObject = object
        object.stitchSettings = settings

        return object
    }

    private func averageStitchLength(_ points: [StitchPoint]) -> Double {
        guard points.count > 1 else { return 2.5 }
        var totalLength = 0.0
        var count = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            totalLength += length
            count += 1
        }
        guard count > 0 else { return 2.5 }
        return min(max(totalLength / Double(count), 0.1), 12.0)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
