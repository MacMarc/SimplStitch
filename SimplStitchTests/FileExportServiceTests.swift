//
//  FileExportServiceTests.swift
//  SimplStitchTests
//
//  Phase 7: Payload-Aufbau (kombinierte Stiche + Farbwechsel zwischen Objekten,
//  SVG-Sonderfall) gegen gestubbte Services, sowie ein echter Ende-zu-Ende-Test
//  gegen die reale Bridge (analog zu StitchGenerationServiceTests).
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

private actor StubBridge: PythonBridging {
    private(set) var lastCommand: String?
    private(set) var lastPayload: [String: Any]?
    var stubbedResult: [String: Any] = [:]

    func send(command: String, payload: [String: Any]) async throws -> [String: Any] {
        lastCommand = command
        lastPayload = payload
        return stubbedResult
    }

    func updateStubbedResult(_ result: [String: Any]) {
        stubbedResult = result
    }
}

/// Liefert pro Objekt-Identität unterschiedliche Stiche (anders als
/// MockStitchGenerationService, das immer dasselbe Ergebnis zurückgibt) — damit
/// die Kombinationslogik (Reihenfolge, Farbwechsel-Einfügepunkt) prüfbar ist.
private final class RecordingStitchGenerationService: StitchGenerationServicing {
    var stitchesByObjectID: [UUID: [StitchPoint]] = [:]
    private(set) var requestedObjectIDsInOrder: [UUID] = []

    func generateStitches(for object: DesignObject, canvasSize: CGSize) async throws -> [StitchPoint] {
        requestedObjectIDsInOrder.append(object.id)
        guard object.stitchSettings != nil else {
            throw StitchGenerationError.missingStitchSettings
        }
        return stitchesByObjectID[object.id] ?? []
    }
}

struct FileExportServiceTests {

    private func makeObject(name: String, zIndex: Int, isVisible: Bool = true, hasStitchSettings: Bool = true, fillColorHex: String = "#FF0000") -> DesignObject {
        let object = DesignObject(name: name, kind: .rectangle, positionX: 0, positionY: 0, width: 10, height: 10)
        object.zIndex = zIndex
        object.isVisible = isVisible
        object.fillColorHex = fillColorHex
        if hasStitchSettings {
            object.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 0, underlayType: .none)
        }
        return object
    }

    @Test func combinesStitchesAcrossObjectsWithColorChangeBetweenBlocks() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult(["stitchCount": 5, "colorCount": 2])

        let first = makeObject(name: "A", zIndex: 0)
        let second = makeObject(name: "B", zIndex: 1)

        let generation = RecordingStitchGenerationService()
        generation.stitchesByObjectID[first.id] = [StitchPoint(x: 0, y: 0, command: .stitch), StitchPoint(x: 1, y: 1, command: .stitch)]
        generation.stitchesByObjectID[second.id] = [StitchPoint(x: 5, y: 5, command: .stitch)]

        let service = FileExportService(bridge: stub, stitchGenerationService: generation)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("vp3")

        let summary = try await service.export(objects: [second, first], canvasSize: CGSize(width: 50, height: 50), to: outputURL, format: .vp3)

        #expect(generation.requestedObjectIDsInOrder == [first.id, second.id]) // Z-Order, nicht Übergabereihenfolge
        #expect(summary == ExportSummary(stitchCount: 5, colorCount: 2))

        let payload = try #require(await stub.lastPayload)
        #expect(await stub.lastCommand == "write_embroidery")
        let stitches = try #require(payload["stitches"] as? [[Any]])
        // A(2 Stiche) + Farbwechsel an letzter Position von A + B(1 Stich) = 4
        #expect(stitches.count == 4)
        #expect((stitches[2][2] as? Int) == StitchPoint.Command.colorChange.rawValue)
        #expect((stitches[2][0] as? Double) == 1)
        #expect((stitches[2][1] as? Double) == 1)

        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect(threads.count == 2)
    }

    @Test func throwsWhenNoVisibleObjectHasStitchSettings() async throws {
        let stub = StubBridge()
        let generation = RecordingStitchGenerationService()
        let service = FileExportService(bridge: stub, stitchGenerationService: generation)

        let hidden = makeObject(name: "Hidden", zIndex: 0, isVisible: false)
        let noSettings = makeObject(name: "NoSettings", zIndex: 1, hasStitchSettings: false)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("vp3")

        await #expect(throws: FileExportError.self) {
            try await service.export(objects: [hidden, noSettings], canvasSize: CGSize(width: 50, height: 50), to: outputURL, format: .vp3)
        }
    }

    @Test func exportsSVGViaRealSerializerWithoutTouchingBridge() async throws {
        let stub = StubBridge()
        let generation = RecordingStitchGenerationService()
        let service = FileExportService(bridge: stub, stitchGenerationService: generation)

        let object = makeObject(name: "Rechteck", zIndex: 0, fillColorHex: "#00FF00")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("svg")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let summary = try await service.export(objects: [object], canvasSize: CGSize(width: 50, height: 50), to: outputURL, format: .svg)

        #expect(summary.stitchCount == 0)
        #expect(summary.colorCount == 1)
        #expect(await stub.lastCommand == nil) // SVG-Export ruft die Bridge nie auf
        #expect(generation.requestedObjectIDsInOrder.isEmpty)

        let written = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(written.contains("<rect"))
        #expect(written.contains("fill=\"#00FF00\""))
    }

    // Ende-zu-Ende gegen die echte Bridge (Subprocess + vendored InkStitch + pyembroidery).
    @Test func realBridgeExportsCombinedVP3WithTwoColors() async throws {
        let bridge = PythonBridge()
        let service = FileExportService(bridge: bridge)

        let red = makeObject(name: "Rot", zIndex: 0, fillColorHex: "#FF0000")
        red.width = 20
        red.height = 15
        let green = makeObject(name: "Grün", zIndex: 1, fillColorHex: "#00FF00")
        green.positionX = 25
        green.width = 15
        green.height = 15

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("vp3")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let summary = try await service.export(objects: [red, green], canvasSize: CGSize(width: 50, height: 50), to: outputURL, format: .vp3)

        #expect(summary.stitchCount > 0)
        #expect(summary.colorCount == 2)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        await bridge.stop()
    }
}
