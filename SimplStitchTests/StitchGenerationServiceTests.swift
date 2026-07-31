//
//  StitchGenerationServiceTests.swift
//  SimplStitchTests
//
//  Phase 6d: Payload-Aufbau und Ergebnis-Parsing gegen einen gestubbten
//  PythonBridging-Double (kein Subprocess) sowie ein echter Ende-zu-Ende-Test
//  gegen die reale Bridge (analog zu PythonBridgeTests.vp3Roundtrip).
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
}

struct StitchGenerationServiceTests {

    private func makeRectangle(stitchSettings: StitchSettings? = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 45, underlayType: .centerWalk)) -> DesignObject {
        let object = DesignObject(name: "Rechteck", kind: .rectangle, positionX: 10, positionY: 10, width: 30, height: 20)
        object.stitchSettings = stitchSettings
        return object
    }

    @Test func buildsPayloadFromObjectAndCanvasSize() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult(["stitches": [[11.0, 12.0, 0], [13.0, 14.0, 1]]])
        let service = StitchGenerationService(bridge: stub)

        _ = try await service.generateStitches(for: makeRectangle(), canvasSize: CGSize(width: 130, height: 180))

        let command = await stub.lastCommand
        let payload = try #require(await stub.lastPayload)
        #expect(command == "generate_stitches")
        #expect(payload["stitchType"] as? String == "tatami")
        #expect(payload["canvasWidthMm"] as? Double == 130)
        #expect(payload["canvasHeightMm"] as? Double == 180)
        let objectSvg = try #require(payload["objectSvg"] as? String)
        #expect(objectSvg.contains("<rect"))
        #expect(objectSvg.contains("inkstitch:fill_method=\"tatami_fill\""))
    }

    @Test func parsesStitchesFromResult() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult(["stitches": [[1.5, 2.5, 0], [3.5, 4.5, 2], [5.5, 6.5, 5]]])
        let service = StitchGenerationService(bridge: stub)

        let stitches = try await service.generateStitches(for: makeRectangle(), canvasSize: CGSize(width: 50, height: 50))

        #expect(stitches == [
            StitchPoint(x: 1.5, y: 2.5, command: .stitch),
            StitchPoint(x: 3.5, y: 4.5, command: .trim),
            StitchPoint(x: 5.5, y: 6.5, command: .colorChange),
        ])
    }

    @Test func throwsWhenObjectHasNoStitchSettings() async throws {
        let stub = StubBridge()
        let service = StitchGenerationService(bridge: stub)

        await #expect(throws: StitchGenerationError.self) {
            try await service.generateStitches(for: makeRectangle(stitchSettings: nil), canvasSize: CGSize(width: 50, height: 50))
        }
        let command = await stub.lastCommand
        #expect(command == nil) // Bridge wird gar nicht erst aufgerufen
    }

    // Ende-zu-Ende gegen die echte Bridge (Subprocess + vendored InkStitch, siehe 6a/6b).
    @Test func realBridgeGeneratesTatamiStitchesForRectangle() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)

        let stitches = try await service.generateStitches(for: makeRectangle(), canvasSize: CGSize(width: 50, height: 50))

        #expect(!stitches.isEmpty)
        #expect(stitches.allSatisfy { $0.command == .stitch })

        await bridge.stop()
    }

    /// Text embroiderable: die echte Glyphen-Umriss-Pipeline (`GlyphOutlineService` ->
    /// `SVGDesignSerializer.generationElement(for:)`) erreicht InkStitch tatsächlich und erzeugt
    /// Stiche — nicht nur ein durchkompiliertes Payload.
    @Test func realBridgeGeneratesStitchesForTextObject() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)
        let text = DesignObject(name: "Text", kind: .text, positionX: 10, positionY: 10, width: 40, height: 12)
        text.text = "Hi"
        text.fontSize = 8
        text.fontName = "Helvetica"
        text.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 0, underlayType: .centerWalk)

        let stitches = try await service.generateStitches(for: text, canvasSize: CGSize(width: 50, height: 50))

        #expect(!stitches.isEmpty)

        await bridge.stop()
    }

    // MARK: Issue #30 — Rand-Ausrichtung (borderWidthMm/borderAlignment im Payload, echtes Offsetting)

    private func makeRectangleWithBorder(widthMm: Double = 2, alignment: BorderAlignment) -> DesignObject {
        let object = DesignObject(name: "Rechteck", kind: .rectangle, positionX: 10, positionY: 10, width: 30, height: 20)
        object.hasBorder = true
        object.borderWidthMillimeters = widthMm
        object.borderAlignment = alignment
        let settings = StitchSettings(stitchType: .straight, density: 0.4, angleDegrees: 0, underlayType: .none)
        settings.borderOwner = object
        object.borderStitchSettings = settings
        return object
    }

    @Test func buildsPayloadWithBorderWidthAndAlignmentForBorderStitches() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult(["stitches": [[10.0, 10.0, 0]]])
        let service = StitchGenerationService(bridge: stub)

        _ = try await service.generateBorderStitches(for: makeRectangleWithBorder(alignment: .inside), canvasSize: CGSize(width: 50, height: 50))

        let payload = try #require(await stub.lastPayload)
        #expect(payload["borderWidthMm"] as? Double == 2)
        #expect(payload["borderAlignment"] as? String == "inside")
    }

    @Test func buildsPayloadWithoutBorderFieldsForFillStitches() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult(["stitches": [[10.0, 10.0, 0]]])
        let service = StitchGenerationService(bridge: stub)

        _ = try await service.generateStitches(for: makeRectangle(), canvasSize: CGSize(width: 50, height: 50))

        let payload = try #require(await stub.lastPayload)
        #expect(payload["borderWidthMm"] == nil)
        #expect(payload["borderAlignment"] == nil)
    }

    /// Kernverhalten von Issue #30: `.inside` muss die tatsächliche Stichgeometrie nach innen
    /// versetzen (bridge.py, `_offset_border_node`, Shapely `buffer(-distance)`) — nicht nur die
    /// Canvas-Vorschau. Verifiziert über die tatsächliche Bounding-Box der generierten Stiche:
    /// bei 2mm Randdicke sollte sie ca. 1mm (halbe Breite) innerhalb der Rechteck-Grenzen liegen.
    @Test func realBridgeInsideAlignmentShrinksStitchBounds() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)
        let object = makeRectangleWithBorder(widthMm: 2, alignment: .inside)

        let stitches = try await service.generateBorderStitches(for: object, canvasSize: CGSize(width: 50, height: 50))
        #expect(!stitches.isEmpty)

        let minX = stitches.map(\.x).min()!
        let minY = stitches.map(\.y).min()!
        let maxX = stitches.map(\.x).max()!
        let maxY = stitches.map(\.y).max()!

        // Original-Rechteck: (10,10)-(40,30). Bei "innen" muss der Stichpfad klar INNERHALB dieser
        // Grenzen liegen (nicht auf ihnen, wie bei "zentriert" der Fall wäre).
        #expect(minX > 10.3)
        #expect(minY > 10.3)
        #expect(maxX < 39.7)
        #expect(maxY < 29.7)

        await bridge.stop()
    }

    /// Gegenstück: `.outside` muss die Stichgeometrie über die Rechteck-Grenzen hinaus wachsen
    /// lassen (Shapely `buffer(+distance)`).
    @Test func realBridgeOutsideAlignmentGrowsStitchBounds() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)
        let object = makeRectangleWithBorder(widthMm: 2, alignment: .outside)

        let stitches = try await service.generateBorderStitches(for: object, canvasSize: CGSize(width: 50, height: 50))
        #expect(!stitches.isEmpty)

        let minX = stitches.map(\.x).min()!
        let minY = stitches.map(\.y).min()!
        let maxX = stitches.map(\.x).max()!
        let maxY = stitches.map(\.y).max()!

        #expect(minX < 9.7)
        #expect(minY < 9.7)
        #expect(maxX > 40.3)
        #expect(maxY > 30.3)

        await bridge.stop()
    }

    /// `.centered` (Default) bleibt das native, unversetzte Verhalten — Stichpfad folgt exakt der
    /// Rechteck-Kontur, keine Offset-Berechnung wird angestossen.
    @Test func realBridgeCenteredAlignmentMatchesOriginalBounds() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)
        let object = makeRectangleWithBorder(widthMm: 2, alignment: .centered)

        let stitches = try await service.generateBorderStitches(for: object, canvasSize: CGSize(width: 50, height: 50))
        #expect(!stitches.isEmpty)

        let minX = stitches.map(\.x).min()!
        let maxX = stitches.map(\.x).max()!

        #expect(abs(minX - 10) < 0.3)
        #expect(abs(maxX - 40) < 0.3)

        await bridge.stop()
    }

    /// Issue #30 (stroke-width-Bug): Satin-Rand ist am direktesten von `borderWidthMillimeters`
    /// abhängig (bestimmt die Schienenbreite) — vor dem Fix nutzte InkStitch dafür immer seinen
    /// eigenen Default (~0.26mm), unabhängig von der UI-Einstellung. Reiner Regressionstest, dass
    /// das jetzt geschriebene `style="stroke-width:…mm"` nicht zu einem Absturz/Fehler führt.
    @Test func realBridgeGeneratesSatinBorderStitchesWithConfiguredWidth() async throws {
        let bridge = PythonBridge()
        let service = StitchGenerationService(bridge: bridge)
        let object = DesignObject(name: "Rechteck", kind: .rectangle, positionX: 10, positionY: 10, width: 30, height: 20)
        object.hasBorder = true
        object.borderWidthMillimeters = 1
        object.borderAlignment = .centered
        let settings = StitchSettings(stitchType: .satin, density: 0.4, angleDegrees: 0, underlayType: .none)
        settings.borderOwner = object
        object.borderStitchSettings = settings

        let stitches = try await service.generateBorderStitches(for: object, canvasSize: CGSize(width: 50, height: 50))

        #expect(!stitches.isEmpty)

        await bridge.stop()
    }
}

private extension StubBridge {
    func updateStubbedResult(_ result: [String: Any]) {
        stubbedResult = result
    }
}
