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
}

private extension StubBridge {
    func updateStubbedResult(_ result: [String: Any]) {
        stubbedResult = result
    }
}
